import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';

/// SyncStatus for tracking bill sync state
enum SyncStatus {
  pending,    // Waiting to sync
  syncing,    // Currently syncing
  synced,     // Successfully synced
  failed,     // Failed to sync (will retry)
}

/// Represents a bill pending sync
class PendingBill {
  final String localId;
  final String oderId;
  final List<Map<String, dynamic>> items;
  final double total;
  final DateTime createdAt;
  SyncStatus status;
  int retryCount;
  String? remoteBillId;
  String? errorMessage;

  PendingBill({
    required this.localId,
    required this.oderId,
    required this.items,
    required this.total,
    required this.createdAt,
    this.status = SyncStatus.pending,
    this.retryCount = 0,
    this.remoteBillId,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() => {
    'localId': localId,
    'userId': oderId,
    'items': items,
    'total': total,
    'createdAt': createdAt.toIso8601String(),
    'status': status.index,
    'retryCount': retryCount,
    'remoteBillId': remoteBillId,
    'errorMessage': errorMessage,
  };

  factory PendingBill.fromJson(Map<String, dynamic> json) => PendingBill(
    localId: json['localId'] as String,
    oderId: json['userId'] as String,
    items: List<Map<String, dynamic>>.from(
      (json['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    ),
    total: (json['total'] as num).toDouble(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    status: SyncStatus.values[json['status'] as int],
    retryCount: json['retryCount'] as int? ?? 0,
    remoteBillId: json['remoteBillId'] as String?,
    errorMessage: json['errorMessage'] as String?,
  );
}

/// SyncQueueService manages offline-first bill syncing
class SyncQueueService {
  static final SyncQueueService _instance = SyncQueueService._internal();
  factory SyncQueueService() => _instance;
  SyncQueueService._internal();

  // Hive box for pending bills
  static const String _pendingBillsBoxName = 'pending_bills';
  static const String _syncedBillsBoxName = 'synced_bills';
  
  late Box<String> _pendingBillsBox;
  late Box<String> _syncedBillsBox;
  
  // Sync configuration
  static const int _maxRetries = 5;
  static const Duration _retryDelay = Duration(seconds: 5);
  static const Duration _syncInterval = Duration(seconds: 10);
  
  // State
  bool _isInitialized = false;
  bool _isSyncing = false;
  Timer? _syncTimer;
  StreamSubscription? _connectivitySubscription;
  
  // Callbacks for UI updates
  final _syncStatusController = StreamController<SyncQueueStatus>.broadcast();
  Stream<SyncQueueStatus> get syncStatusStream => _syncStatusController.stream;
  
  // Connectivity status
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  /// Initialize the sync queue service
  Future<void> init() async {
    if (_isInitialized) return;

    _pendingBillsBox = await Hive.openBox<String>(_pendingBillsBoxName);
    _syncedBillsBox = await Hive.openBox<String>(_syncedBillsBoxName);

    _isInitialized = true;

    // Start listening to connectivity changes
    _startConnectivityMonitoring();

    // Start periodic sync
    _startPeriodicSync();

    // Initial sync attempt
    _attemptSync();
    
    debugPrint('🔄 SyncQueueService initialized with ${pendingCount} pending bills');
  }

  /// Start monitoring connectivity
  void _startConnectivityMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final wasOffline = !_isOnline;
      _isOnline = !results.contains(ConnectivityResult.none);
      
      debugPrint('📶 Connectivity changed: ${_isOnline ? "Online" : "Offline"}');
      
      // If we just came online, try to sync immediately
      if (_isOnline && wasOffline) {
        debugPrint('🔄 Back online! Starting sync...');
        _attemptSync();
      }
      
      _emitStatus();
    });
    
    // Check initial connectivity
    Connectivity().checkConnectivity().then((results) {
      _isOnline = !results.contains(ConnectivityResult.none);
      _emitStatus();
    });
  }

  /// Start periodic sync timer
  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) {
      if (_isOnline && pendingCount > 0) {
        _attemptSync();
      }
    });
  }

  /// Get count of pending bills
  int get pendingCount => _pendingBillsBox.length;
  
  /// Get count of synced bills
  int get syncedCount => _syncedBillsBox.length;

  /// Get all pending bills
  List<PendingBill> get pendingBills {
    return _pendingBillsBox.values
        .map((json) => PendingBill.fromJson(jsonDecode(json)))
        .toList();
  }

  /// Add a bill to the sync queue
  /// Returns a local bill ID immediately
  Future<String> queueBill({
    required String oderId,
    required List<Map<String, dynamic>> items,
    required double total,
  }) async {
    if (!_isInitialized) await init();

    final localId = const Uuid().v4();
    
    final pendingBill = PendingBill(
      localId: localId,
      oderId: oderId,
      items: items,
      total: total,
      createdAt: DateTime.now(),
      status: SyncStatus.pending,
    );

    // Save to local queue
    await _pendingBillsBox.put(localId, jsonEncode(pendingBill.toJson()));
    
    debugPrint('📝 Bill queued: $localId (${items.length} items, total: $total)');
    
    _emitStatus();

    // Try to sync immediately if online
    if (_isOnline) {
      _attemptSync();
    }

    return localId;
  }

  /// Attempt to sync all pending bills
  Future<void> _attemptSync() async {
    if (_isSyncing || !_isOnline || pendingCount == 0) return;

    _isSyncing = true;
    _emitStatus();

    debugPrint('🔄 Starting sync of ${pendingCount} pending bills...');

    final pendingList = pendingBills
        .where((b) => b.status == SyncStatus.pending || b.status == SyncStatus.failed)
        .toList();

    for (final bill in pendingList) {
      if (!_isOnline) {
        debugPrint('📶 Lost connection, pausing sync');
        break;
      }

      await _syncBill(bill);
    }

    _isSyncing = false;
    _emitStatus();
    
    debugPrint('✅ Sync complete. Remaining: ${pendingCount} pending');
  }

  /// Sync a single bill to Supabase
  Future<void> _syncBill(PendingBill bill) async {
    try {
      // Update status to syncing
      bill.status = SyncStatus.syncing;
      await _pendingBillsBox.put(bill.localId, jsonEncode(bill.toJson()));
      _emitStatus();

      debugPrint('🔄 Syncing bill: ${bill.localId}');

      final supabase = Supabase.instance.client;

      // Prepare items for the RPC call
      final itemsJson = bill.items.map((item) {
        return {
          'product_id': item['product_id'],
          'quantity': item['quantity'],
          'unit_price': item['unit_price'],
        };
      }).toList();

      // Call the create_bill RPC with timeout
      final remoteBillId = await supabase.rpc('create_bill', params: {
        'p_user_id': bill.oderId,
        'p_items': itemsJson,
        'p_total': bill.total,
      }).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Sync timeout'),
      );

      // Success! Update the bill status
      bill.status = SyncStatus.synced;
      bill.remoteBillId = remoteBillId.toString();
      bill.errorMessage = null;

      // Move to synced bills box
      await _syncedBillsBox.put(bill.localId, jsonEncode(bill.toJson()));
      await _pendingBillsBox.delete(bill.localId);

      debugPrint('✅ Bill synced: ${bill.localId} -> ${bill.remoteBillId}');
      
    } catch (e) {
      debugPrint('❌ Sync failed for ${bill.localId}: $e');

      bill.status = SyncStatus.failed;
      bill.retryCount++;
      bill.errorMessage = e.toString();

      // If max retries exceeded, keep in queue but log warning
      if (bill.retryCount >= _maxRetries) {
        debugPrint('⚠️ Bill ${bill.localId} reached max retries ($_maxRetries)');
      }

      await _pendingBillsBox.put(bill.localId, jsonEncode(bill.toJson()));
    }

    _emitStatus();
  }

  /// Force sync all pending bills
  Future<void> forceSync() async {
    if (!_isOnline) {
      debugPrint('📶 Cannot force sync: offline');
      return;
    }
    
    // Reset retry counts for failed bills
    for (final bill in pendingBills.where((b) => b.status == SyncStatus.failed)) {
      bill.retryCount = 0;
      bill.status = SyncStatus.pending;
      await _pendingBillsBox.put(bill.localId, jsonEncode(bill.toJson()));
    }
    
    await _attemptSync();
  }

  /// Get sync queue status
  SyncQueueStatus get status => SyncQueueStatus(
    isOnline: _isOnline,
    isSyncing: _isSyncing,
    pendingCount: pendingCount,
    syncedCount: syncedCount,
    failedCount: pendingBills.where((b) => b.status == SyncStatus.failed).length,
  );

  /// Emit current status to listeners
  void _emitStatus() {
    if (!_syncStatusController.isClosed) {
      _syncStatusController.add(status);
    }
  }

  /// Get a specific pending bill by local ID
  PendingBill? getPendingBill(String localId) {
    final json = _pendingBillsBox.get(localId);
    if (json == null) return null;
    return PendingBill.fromJson(jsonDecode(json));
  }

  /// Check if a bill was synced and get remote ID
  String? getRemoteBillId(String localId) {
    final json = _syncedBillsBox.get(localId);
    if (json == null) return null;
    final bill = PendingBill.fromJson(jsonDecode(json));
    return bill.remoteBillId;
  }

  /// Clear synced bills (cleanup)
  Future<void> clearSyncedBills() async {
    await _syncedBillsBox.clear();
    _emitStatus();
  }

  /// Dispose resources
  void dispose() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _syncStatusController.close();
  }
}

/// Status object for UI updates
class SyncQueueStatus {
  final bool isOnline;
  final bool isSyncing;
  final int pendingCount;
  final int syncedCount;
  final int failedCount;

  SyncQueueStatus({
    required this.isOnline,
    required this.isSyncing,
    required this.pendingCount,
    required this.syncedCount,
    required this.failedCount,
  });

  bool get hasPending => pendingCount > 0;
  bool get hasFailed => failedCount > 0;
}

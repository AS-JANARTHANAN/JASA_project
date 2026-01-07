import 'package:flutter/material.dart';
import 'package:JASA/services/sync_queue_service.dart';

/// A widget that displays the current sync queue status
class SyncStatusWidget extends StatelessWidget {
  final SyncQueueStatus status;
  final VoidCallback? onRetry;
  final bool compact;

  const SyncStatusWidget({
    super.key,
    required this.status,
    this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompact(context);
    }
    return _buildFull(context);
  }

  Widget _buildCompact(BuildContext context) {
    final theme = Theme.of(context);
    
    // If everything is synced and online, show nothing
    if (!status.hasPending && status.isOnline) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildIcon(),
          const SizedBox(width: 6),
          Text(
            _getCompactText(),
            style: TextStyle(
              color: _getTextColor(),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFull(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getBorderColor(),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          _buildIcon(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _getTitle(),
                  style: TextStyle(
                    color: _getTextColor(),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getSubtitle(),
                  style: TextStyle(
                    color: _getTextColor().withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (status.hasFailed && onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh, size: 16, color: _getTextColor()),
              label: Text('Retry', style: TextStyle(color: _getTextColor())),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIcon() {
    if (!status.isOnline) {
      return const Icon(Icons.cloud_off, color: Colors.white, size: 20);
    }
    
    if (status.isSyncing) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }
    
    if (status.hasFailed) {
      return const Icon(Icons.error_outline, color: Colors.white, size: 20);
    }
    
    if (status.hasPending) {
      return const Icon(Icons.schedule, color: Colors.white, size: 20);
    }
    
    return const Icon(Icons.cloud_done, color: Colors.white, size: 20);
  }

  Color _getBackgroundColor() {
    if (!status.isOnline) {
      return Colors.grey.shade700;
    }
    if (status.hasFailed) {
      return Colors.red.shade400;
    }
    if (status.isSyncing) {
      return Colors.blue.shade400;
    }
    if (status.hasPending) {
      return Colors.orange.shade400;
    }
    return Colors.green.shade400;
  }

  Color _getBorderColor() {
    return _getBackgroundColor().withOpacity(0.3);
  }

  Color _getTextColor() {
    return Colors.white;
  }

  String _getCompactText() {
    if (!status.isOnline) {
      return 'Offline${status.hasPending ? ' (${status.pendingCount})' : ''}';
    }
    if (status.isSyncing) {
      return 'Syncing...';
    }
    if (status.hasFailed) {
      return '${status.failedCount} failed';
    }
    if (status.hasPending) {
      return '${status.pendingCount} pending';
    }
    return 'Synced';
  }

  String _getTitle() {
    if (!status.isOnline) {
      return 'Offline Mode';
    }
    if (status.isSyncing) {
      return 'Syncing Bills...';
    }
    if (status.hasFailed) {
      return 'Sync Failed';
    }
    if (status.hasPending) {
      return 'Pending Sync';
    }
    return 'All Synced';
  }

  String _getSubtitle() {
    if (!status.isOnline) {
      return status.hasPending
          ? '${status.pendingCount} bills will sync when online'
          : 'Bills will be saved locally';
    }
    if (status.isSyncing) {
      return '${status.pendingCount} bills remaining';
    }
    if (status.hasFailed) {
      return '${status.failedCount} bills failed to sync. Tap retry.';
    }
    if (status.hasPending) {
      return '${status.pendingCount} bills waiting to sync';
    }
    return 'All bills are synced to server';
  }
}

/// A banner that shows sync status at the top of the screen
class SyncStatusBanner extends StatefulWidget {
  const SyncStatusBanner({super.key});

  @override
  State<SyncStatusBanner> createState() => _SyncStatusBannerState();
}

class _SyncStatusBannerState extends State<SyncStatusBanner> {
  final SyncQueueService _syncService = SyncQueueService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncQueueStatus>(
      stream: _syncService.syncStatusStream,
      initialData: _syncService.status,
      builder: (context, snapshot) {
        final status = snapshot.data!;
        
        // Only show if there's something to show
        if (status.isOnline && !status.hasPending && !status.hasFailed) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SyncStatusWidget(
            status: status,
            onRetry: status.hasFailed ? () => _syncService.forceSync() : null,
          ),
        );
      },
    );
  }
}

/// An indicator chip that shows sync status in the app bar
class SyncStatusChip extends StatefulWidget {
  const SyncStatusChip({super.key});

  @override
  State<SyncStatusChip> createState() => _SyncStatusChipState();
}

class _SyncStatusChipState extends State<SyncStatusChip> {
  final SyncQueueService _syncService = SyncQueueService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncQueueStatus>(
      stream: _syncService.syncStatusStream,
      initialData: _syncService.status,
      builder: (context, snapshot) {
        final status = snapshot.data!;
        
        return SyncStatusWidget(
          status: status,
          compact: true,
        );
      },
    );
  }
}

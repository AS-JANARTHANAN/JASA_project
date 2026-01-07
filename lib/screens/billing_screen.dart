import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:JASA/services/cache_service.dart';
import 'package:JASA/services/sync_queue_service.dart';
import 'package:JASA/widgets/cached_product_image.dart';
import 'package:JASA/widgets/bill_success_popup.dart';
import 'package:JASA/widgets/sync_status_widget.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final CacheService _cacheService = CacheService();
  final SyncQueueService _syncService = SyncQueueService();
  
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _categories = [];
  Map<String, int> _cart = {}; // product_id -> quantity
  bool _isLoading = true;
  String? _selectedCategoryCode;
  bool _isBillingInProgress = false;

  @override
  void initState() {
    super.initState();
    _loadCachedData();
  }

  /// Load data from cache (instant) or fetch if cache is empty
  Future<void> _loadCachedData() async {
    setState(() => _isLoading = true);
    
    try {
      // Check if cache has data
      if (_cacheService.products.isNotEmpty) {
        // Use cached data - instant loading!
        setState(() {
          _products = List.from(_cacheService.products);
          _categories = List.from(_cacheService.categories);
          _isLoading = false;
        });
      } else {
        // Cache is empty, need to fetch from server
        await _fetchFromServer();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading data: $e")),
      );
      setState(() => _isLoading = false);
    }
  }

  /// Fetch data from server (fallback if cache is empty)
  Future<void> _fetchFromServer() async {
    try {
      await _cacheService.refreshAllData(
        forceRefresh: true,
        onProgress: (message, progress) {
          // Optional: show progress in UI
        },
      );
      
      setState(() {
        _products = List.from(_cacheService.products);
        _categories = List.from(_cacheService.categories);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching data: $e")),
      );
      setState(() => _isLoading = false);
    }
  }

  /// Refresh data from server
  Future<void> _refreshData() async {
    await _fetchFromServer();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Data refreshed!"),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _addToCart(String productId) {
    final product = _products.firstWhere((p) => p['product_id'] == productId);
    final int currentStock = product['stock'] as int;
    final int currentCartQuantity = _cart[productId] ?? 0;

    if (currentCartQuantity < currentStock) {
      setState(() {
        _cart[productId] = currentCartQuantity + 1;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Cannot add more ${product['name']}. Only $currentStock available."),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _removeFromCart(String productId) {
    setState(() {
      if (_cart.containsKey(productId)) {
        _cart[productId] = _cart[productId]! - 1;
        if (_cart[productId] == 0) {
          _cart.remove(productId);
        }
      }
    });
  }

  double get _totalPrice {
    double total = 0;
    _cart.forEach((productId, quantity) {
      final product = _products.firstWhere((p) => p['product_id'] == productId);
      total += (product['price'] as num) * quantity;
    });
    return total;
  }

  int get _totalItems {
    return _cart.values.fold(0, (a, b) => a + b);
  }

  void _showBillConfirmationDialog() {
    final cartItems = _cart.entries.map((entry) {
      final product = _products.firstWhere((p) => p['product_id'] == entry.key);
      return {
        'product': product,
        'quantity': entry.value,
        'subtotal': (product['price'] as num) * entry.value,
      };
    }).toList();

    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Confirm Bill', style: theme.textTheme.headlineSmall),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Show sync status
                StreamBuilder<SyncQueueStatus>(
                  stream: _syncService.syncStatusStream,
                  initialData: _syncService.status,
                  builder: (context, snapshot) {
                    final status = snapshot.data!;
                    if (!status.isOnline) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.wifi_off, color: Colors.orange.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Offline mode: Bill will sync when connected',
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                
                ...cartItems.map((item) {
                  final product = item['product'] as Map<String, dynamic>;
                  final imageUrl = _cacheService.getProductImageUrl(product);
                  final imagePath = _cacheService.getProductImagePath(product);
                  
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CachedProductImage(
                      imageUrl: imageUrl,
                      imagePath: imagePath,
                      width: 50,
                      height: 50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    title: Text(product['name']),
                    subtitle: Text('${item['quantity']} x ₹${product['price']} = ₹${item['subtotal']}'),
                  );
                }),
                const Divider(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Grand Total:', style: theme.textTheme.titleMedium),
                      Text(
                        '₹${_totalPrice.toStringAsFixed(2)}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: _isBillingInProgress ? null : () => _confirmBill(cartItems),
              icon: _isBillingInProgress
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_isBillingInProgress ? 'Processing...' : 'Confirm Bill'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmBill(List<Map<String, dynamic>> cartItems) async {
    setState(() => _isBillingInProgress = true);
    
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;

      // Prepare items for the queue
      final itemsJson = cartItems.map((item) {
        final product = item['product'] as Map<String, dynamic>;
        return {
          'product_id': product['product_id'],
          'quantity': item['quantity'],
          'unit_price': product['price'],
          'product_name': product['name'], // For display in pending bills
        };
      }).toList();

      // Validate stock before creating the bill
      for (var item in cartItems) {
        final product = item['product'] as Map<String, dynamic>;
        final int requestedQuantity = item['quantity'] as int;
        final int availableStock = product['stock'] as int;

        if (requestedQuantity > availableStock) {
          if (!mounted) return;
          Navigator.pop(context); // Close the confirmation dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  "Not enough stock for ${product['name']}. Available: $availableStock, Requested: $requestedQuantity"),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isBillingInProgress = false);
          return;
        }
      }

      // Queue the bill (saves locally first, syncs in background)
      final localBillId = await _syncService.queueBill(
        oderId: userId,
        items: itemsJson,
        total: _totalPrice,
      );

      // Update local cache with new stock values (optimistic update)
      for (var item in cartItems) {
        final product = item['product'] as Map<String, dynamic>;
        final int quantity = item['quantity'] as int;
        final newStock = (product['stock'] as int) - quantity;
        _cacheService.updateProductStock(product['product_id'], newStock);
      }

      if (!mounted) return;
      Navigator.pop(context); // Close the confirmation dialog

      // Show beautiful success popup!
      await showBillSuccessPopup(
        context,
        billId: localBillId,
        totalAmount: _totalPrice,
        itemCount: cartItems.length,
        onNewBill: () {
          // Reset cart and stay on billing screen
          setState(() {
            _cart = {};
            _products = List.from(_cacheService.products); // Refresh with updated stock
          });
        },
        onViewBill: () {
          // Navigate to bill success screen with details
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => BillingSuccessScreen(
                billId: localBillId,
                items: cartItems,
                total: _totalPrice,
                isPending: !_syncService.isOnline,
              ),
            ),
          );
        },
      );

      // Reset cart after successful billing
      setState(() {
        _cart = {};
        _products = List.from(_cacheService.products); // Refresh with updated stock
        _isBillingInProgress = false;
      });

    } catch (e) {
      if (!mounted) return;
      setState(() => _isBillingInProgress = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error creating bill: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showImagePreview(String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: InteractiveViewer(
              child: CachedProductImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredProducts = _selectedCategoryCode == null
        ? _products
        : _products.where((p) => p['category_code'] == _selectedCategoryCode).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 1,
        actions: [
          // Sync status chip
          const Center(child: SyncStatusChip()),
          const SizedBox(width: 8),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh data',
            onPressed: _refreshData,
          ),
          // Category filter
          PopupMenuButton<String?>(
            onSelected: (String? newCategoryCode) {
              setState(() {
                _selectedCategoryCode = newCategoryCode;
              });
            },
            itemBuilder: (BuildContext context) {
              final menuItems = <PopupMenuEntry<String?>>[
                const PopupMenuItem<String?>(
                  value: null,
                  child: Text('All Categories'),
                ),
              ];
              menuItems.addAll(_categories.map((category) {
                return PopupMenuItem<String?>(
                  value: category['code'],
                  child: Text(category['name']),
                );
              }));
              return menuItems;
            },
            icon: const Icon(Icons.filter_list_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          // Sync status banner (only shows if offline or pending)
          const SyncStatusBanner(),
          
          // Product grid
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _refreshData,
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16.0),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.75,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = filteredProducts[index];
                        final quantity = _cart[product['product_id']] ?? 0;
                        final imageUrl = _cacheService.getProductImageUrl(product);
                        final imagePath = _cacheService.getProductImagePath(product);

                        return _buildProductCard(product, quantity, imageUrl, imagePath, theme);
                      },
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _cart.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_totalItems items',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        Text(
                          '₹${_totalPrice.toStringAsFixed(2)}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: _showBillConfirmationDialog,
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Generate Bill'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildProductCard(
    Map<String, dynamic> product,
    int quantity,
    String? imageUrl,
    String? imagePath,
    ThemeData theme,
  ) {
    final stock = product['stock'] as int;
    
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (imageUrl != null) {
                  _showImagePreview(imageUrl);
                }
              },
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedProductImage(
                      imageUrl: imageUrl,
                      imagePath: imagePath,
                      fit: BoxFit.cover,
                    ),
                    // Out of stock overlay
                    if (stock == 0)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: Text(
                            'OUT OF STOCK',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['name'],
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '₹${product['price']}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: stock > 0
                            ? Colors.green.withOpacity(0.1)
                            : Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        stock > 0 ? 'Stock: $stock' : 'Out',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: stock > 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: quantity > 0
                  ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                  : theme.colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.remove_circle_outline,
                    color: quantity > 0 ? theme.colorScheme.primary : Colors.grey,
                  ),
                  onPressed: quantity > 0 ? () => _removeFromCart(product['product_id']) : null,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: quantity > 0 ? theme.colorScheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    quantity.toString(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: quantity > 0 ? Colors.white : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.add_circle_outline,
                    color: stock > quantity ? theme.colorScheme.primary : Colors.grey,
                  ),
                  onPressed: stock > quantity ? () => _addToCart(product['product_id']) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BillingSuccessScreen extends StatelessWidget {
  final String billId;
  final List<Map<String, dynamic>> items;
  final double total;
  final bool isPending;

  const BillingSuccessScreen({
    super.key,
    required this.billId,
    required this.items,
    required this.total,
    this.isPending = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cacheService = CacheService();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill Generated'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Success Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPending ? Icons.schedule : Icons.check_circle,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPending ? 'Bill Saved!' : 'Thank you!',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Bill ID: #${billId.substring(0, 8).toUpperCase()}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        if (isPending) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Will sync when online',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Sync Status
            if (isPending) ...[
              const SizedBox(height: 16),
              const SyncStatusBanner(),
            ],
            
            const SizedBox(height: 24),
            Text('Billed Items:', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            
            // Items List
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final product = item['product'] as Map<String, dynamic>;
                  final imageUrl = cacheService.getProductImageUrl(product);
                  final imagePath = cacheService.getProductImagePath(product);
                  
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: CachedProductImage(
                        imageUrl: imageUrl,
                        imagePath: imagePath,
                        width: 50,
                        height: 50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      title: Text(
                        product['name'],
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text('${item['quantity']} x ₹${product['price']}'),
                      trailing: Text(
                        '₹${item['subtotal']}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            const Divider(height: 24),
            
            // Grand Total
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Grand Total:', style: theme.textTheme.titleLarge),
                  Text(
                    '₹${total.toStringAsFixed(2)}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // New Bill Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('New Bill'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
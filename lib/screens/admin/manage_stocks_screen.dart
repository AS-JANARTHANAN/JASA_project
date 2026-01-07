import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:JASA/services/cache_service.dart';
import 'package:JASA/widgets/cached_product_image.dart';

class ManageStocksScreen extends StatefulWidget {
  const ManageStocksScreen({super.key});

  @override
  State<ManageStocksScreen> createState() => _ManageStocksScreenState();
}

class _ManageStocksScreenState extends State<ManageStocksScreen> {
  final CacheService _cacheService = CacheService();
  
  List<Map<String, dynamic>> _products = [];
  bool _isLoading = true;
  String? _selectedCategory;
  final List<String> _categories = ['All', 'own products', 'sudam'];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    
    try {
      // Use cached data for instant loading
      List<Map<String, dynamic>> products;
      
      if (_cacheService.products.isNotEmpty) {
        if (_selectedCategory != null && _selectedCategory != 'All') {
          final categoryCode = _selectedCategory == 'own products' ? 'OWN' : 'SUD';
          products = _cacheService.getProductsByCategory(categoryCode);
        } else {
          products = List.from(_cacheService.products);
        }
      } else {
        // Fallback to server fetch
        products = await _fetchFromServer();
      }
      
      // Sort by name
      products.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      
      setState(() {
        _products = products;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading products: $e")),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _fetchFromServer() async {
    final supabase = Supabase.instance.client;
    var query = supabase.from('products').select();

    if (_selectedCategory != null && _selectedCategory != 'All') {
      final categoryCode = _selectedCategory == 'own products' ? 'OWN' : 'SUD';
      query = query.eq('category_code', categoryCode);
    }

    final response = await query.order('name', ascending: true);
    return List<Map<String, dynamic>>.from(response as List);
  }

  void _onCategoryChanged(String? newValue) {
    setState(() {
      _selectedCategory = newValue;
    });
    _loadProducts();
  }

  Future<void> _updateStock(String productId, int newStock, int change, String note) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('products').update({'stock': newStock}).eq('product_id', productId);
      await supabase.from('inventory_logs').insert({
        'product_id': productId,
        'change': change,
        'note': note,
      });
      
      // Update local cache
      _cacheService.updateProductStock(productId, newStock);
      
      // Update local list
      setState(() {
        final index = _products.indexWhere((p) => p['product_id'] == productId);
        if (index != -1) {
          _products[index]['stock'] = newStock;
        }
      });
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stock updated successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error updating stock: $e")),
      );
    }
  }

  void _showAddStockDialog(Map<String, dynamic> product) {
    final stockController = TextEditingController();
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Add Stock for ${product['name']}', style: theme.textTheme.headlineSmall),
          content: TextField(
            controller: stockController,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Quantity to add',
              prefixIcon: const Icon(Icons.add),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final quantity = int.tryParse(stockController.text);
                if (quantity != null && quantity > 0) {
                  final newStock = (product['stock'] as int) + quantity;
                  _updateStock(product['product_id'], newStock, quantity, 'Manual stock addition');
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Stock'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
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

  void _showReduceStockDialog(Map<String, dynamic> product) {
    final stockController = TextEditingController();
    final theme = Theme.of(context);
    final currentStock = product['stock'] as int;
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Reduce Stock for ${product['name']}', style: theme.textTheme.headlineSmall),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Current stock: $currentStock'),
              const SizedBox(height: 16),
              TextField(
                controller: stockController,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Quantity to reduce',
                  prefixIcon: const Icon(Icons.remove),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final quantity = int.tryParse(stockController.text);
                if (quantity != null && quantity > 0 && quantity <= currentStock) {
                  final newStock = currentStock - quantity;
                  _updateStock(product['product_id'], newStock, -quantity, 'Manual stock reduction');
                  Navigator.pop(context);
                } else if (quantity != null && quantity > currentStock) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Cannot reduce more than current stock ($currentStock)'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.remove),
              label: const Text('Reduce'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
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

  void _showClearStockDialog(Map<String, dynamic> product) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              const Text('Clear Stock'),
            ],
          ),
          content: Text('Are you sure you want to clear all stock for "${product['name']}"?\n\nCurrent stock: ${product['stock']}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final currentStock = product['stock'] as int;
                _updateStock(product['product_id'], 0, -currentStock, 'Stock cleared manually');
                Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Clear All'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
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

  Future<void> _refreshProducts() async {
    await _cacheService.forceRefresh();
    await _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Stocks'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshProducts,
            tooltip: 'Refresh',
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: DropdownButton<String>(
              value: _selectedCategory ?? 'All',
              items: _categories.map((String category) {
                return DropdownMenuItem<String>(
                  value: category,
                  child: Text(category),
                );
              }).toList(),
              onChanged: _onCategoryChanged,
              underline: Container(),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 64,
                        color: theme.colorScheme.onSurface.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No products found.',
                        style: TextStyle(
                          fontSize: 16,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshProducts,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _products.length,
                    itemBuilder: (context, index) {
                      final product = _products[index];
                      final imageUrl = _cacheService.getProductImageUrl(product);
                      final imagePath = _cacheService.getProductImagePath(product);
                      final stock = product['stock'] as int;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              // Product Image
                              CachedProductImage(
                                imageUrl: imageUrl,
                                imagePath: imagePath,
                                width: 64,
                                height: 64,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              const SizedBox(width: 16),
                              
                              // Product Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product['name'],
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: stock > 10
                                            ? Colors.green.withOpacity(0.1)
                                            : stock > 0
                                                ? Colors.orange.withOpacity(0.1)
                                                : Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Stock: $stock',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: stock > 10
                                              ? Colors.green
                                              : stock > 0
                                                  ? Colors.orange
                                                  : Colors.red,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              // Action Buttons
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.add_circle, color: Colors.green),
                                    onPressed: () => _showAddStockDialog(product),
                                    tooltip: 'Add Stock',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle, color: Colors.orange),
                                    onPressed: stock > 0 ? () => _showReduceStockDialog(product) : null,
                                    tooltip: 'Reduce Stock',
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_sweep,
                                      color: stock > 0 ? Colors.red : Colors.grey,
                                    ),
                                    onPressed: stock > 0 ? () => _showClearStockDialog(product) : null,
                                    tooltip: 'Clear Stock',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
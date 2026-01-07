import 'package:flutter/material.dart';
import 'package:JASA/screens/add_product_screen.dart';
import 'package:JASA/services/cache_service.dart';
import 'package:JASA/widgets/cached_product_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ViewProductScreen extends StatefulWidget {
  const ViewProductScreen({super.key});

  @override
  State<ViewProductScreen> createState() => _ViewProductScreenState();
}

class _ViewProductScreenState extends State<ViewProductScreen> {
  final CacheService _cacheService = CacheService();
  
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  bool _isLoading = true;
  String? _selectedCategory;
  final List<String> _categories = ['All', 'own products', 'sudam'];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCachedProducts();
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Load products from cache (instant loading!)
  Future<void> _loadCachedProducts() async {
    setState(() => _isLoading = true);
    
    try {
      // Check if cache has data
      if (_cacheService.products.isNotEmpty) {
        // Apply category filter to cached data
        List<Map<String, dynamic>> products;
        
        if (_selectedCategory != null && _selectedCategory != 'All') {
          final categoryCode = _selectedCategory == 'own products' ? 'OWN' : 'SUD';
          products = _cacheService.getProductsByCategory(categoryCode);
        } else {
          products = List.from(_cacheService.products);
        }
        
        setState(() {
          _products = products;
          _filterProducts();
          _isLoading = false;
        });
      } else {
        // Cache is empty, fetch from server
        await _fetchFromServer();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading products: $e")),
      );
      setState(() => _isLoading = false);
    }
  }

  /// Fetch from server (fallback)
  Future<void> _fetchFromServer() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      var query = supabase.from('products').select();

      if (_selectedCategory != null && _selectedCategory != 'All') {
        final categoryCode = _selectedCategory == 'own products' ? 'OWN' : 'SUD';
        query = query.eq('category_code', categoryCode);
      }

      final response = await query.order('sort_order', ascending: true);

      setState(() {
        _products = List<Map<String, dynamic>>.from(response as List);
        _filterProducts();
        _isLoading = false;
      });
      
      // Update cache with fresh data
      await _cacheService.forceRefresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching products: $e")),
      );
      setState(() => _isLoading = false);
    }
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProducts = _products.where((product) {
        final name = product['name'].toString().toLowerCase();
        return name.contains(query);
      }).toList();
    });
  }

  void _onCategoryChanged(String? newValue) {
    setState(() {
      _selectedCategory = newValue;
      _loadCachedProducts();
    });
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final product = _filteredProducts.removeAt(oldIndex);
    _filteredProducts.insert(newIndex, product);

    // Update the main products list as well
    final mainIndex = _products.indexWhere((p) => p['product_id'] == product['product_id']);
    if (mainIndex != -1) {
      _products.removeAt(mainIndex);
      // Find the correct insertion point in the main list
      if (newIndex < _filteredProducts.length - 1) {
        final nextProductId = _filteredProducts[newIndex + 1]['product_id'];
        final insertBeforeIndex = _products.indexWhere((p) => p['product_id'] == nextProductId);
        if (insertBeforeIndex != -1) {
          _products.insert(insertBeforeIndex, product);
        } else {
          _products.add(product);
        }
      } else {
        _products.add(product);
      }
    }

    setState(() {});

    try {
      final supabase = Supabase.instance.client;
      for (int i = 0; i < _products.length; i++) {
        await supabase
            .from('products')
            .update({'sort_order': i})
            .eq('product_id', _products[i]['product_id']);
      }
      
      // Update cache
      await _cacheService.forceRefresh();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product order updated successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error updating order: $e")),
      );
      // Revert order on failure
      _loadCachedProducts();
    }
  }

  void _editProduct(Map<String, dynamic> product) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddProductScreen(product: product),
      ),
    );

    if (result == true) {
      // Refresh cache and reload
      await _cacheService.forceRefresh();
      _loadCachedProducts();
    }
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete "${product['name']}"? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        final supabase = Supabase.instance.client;

        // 1. Delete the image from storage if it exists
        if (product['image_path'] != null) {
          await supabase.storage
              .from('product-images')
              .remove([product['image_path']]);
        }

        // 2. Delete the product from the database
        await supabase
            .from('products')
            .delete()
            .eq('product_id', product['product_id']);

        // 3. Remove from cache
        _cacheService.removeProduct(product['product_id']);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product deleted successfully!')),
        );

        // 4. Refresh the product list from cache
        _loadCachedProducts();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting product: $e')),
        );
      }
    }
  }

  Future<void> _refreshProducts() async {
    await _cacheService.forceRefresh();
    await _loadCachedProducts();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Products refreshed!'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('View Products'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refreshProducts,
          ),
          DropdownButton<String>(
            value: _selectedCategory ?? 'All',
            items: _categories.map((String category) {
              return DropdownMenuItem<String>(
                value: category,
                child: Text(category),
              );
            }).toList(),
            onChanged: _onCategoryChanged,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search products...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
              ),
            ),
          ),
          // Product List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
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
                              _products.isEmpty
                                  ? 'No products found.'
                                  : 'No products match your search.',
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
                        child: ReorderableListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = _filteredProducts[index];
                            final imageUrl = _cacheService.getProductImageUrl(product);
                            final imagePath = _cacheService.getProductImagePath(product);
                            
                            return Card(
                              key: ValueKey(product['product_id']),
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: CachedProductImage(
                                  imageUrl: imageUrl,
                                  imagePath: imagePath,
                                  width: 56,
                                  height: 56,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                title: Text(
                                  product['name'],
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Row(
                                  children: [
                                    Text('₹${product['price']}'),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: (product['stock'] as int) > 0
                                            ? Colors.green.withOpacity(0.1)
                                            : Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Stock: ${product['stock']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: (product['stock'] as int) > 0
                                              ? Colors.green
                                              : Colors.red,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline,
                                        color: Colors.red.withOpacity(0.7),
                                      ),
                                      onPressed: () => _deleteProduct(product),
                                      tooltip: 'Delete',
                                    ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Icon(
                                        Icons.drag_handle,
                                        color: theme.colorScheme.onSurface.withOpacity(0.4),
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () => _editProduct(product),
                              ),
                            );
                          },
                          onReorder: _onReorder,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:JASA/screens/add_product_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ViewProductScreen extends StatefulWidget {
  const ViewProductScreen({super.key});

  @override
  State<ViewProductScreen> createState() => _ViewProductScreenState();
}

class _ViewProductScreenState extends State<ViewProductScreen> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  bool _isLoading = true;
  String? _selectedCategory;
  final List<String> _categories = ['All', 'own products', 'sudam'];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchProducts() async {
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
      _fetchProducts();
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
      _fetchProducts();
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
      _fetchProducts(); // Refresh the list if a change was made
    }
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
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

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product deleted successfully!')),
        );

        // 3. Refresh the product list
        _fetchProducts();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting product: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('View Products'),
        actions: [
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[200],
              ),
            ),
          ),
          // Product List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                    ? Center(
                        child: Text(
                          _products.isEmpty
                              ? 'No products found.'
                              : 'No products match your search.',
                          style: const TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
                          return Card(
                            key: ValueKey(product['product_id']),
                            elevation: 4,
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: product['image_path'] != null
                                    ? Image.network(
                                        Supabase.instance.client.storage
                                            .from('product-images')
                                            .getPublicUrl(product['image_path']),
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) =>
                                            const Icon(Icons.broken_image, size: 50),
                                      )
                                    : const Icon(Icons.image_not_supported, size: 50),
                              ),
                              title: Text(product['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  'Price: ${product['price']} | Stock: ${product['stock']}'),
                              trailing: ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle, color: Colors.grey),
                              ),
                              onTap: () => _editProduct(product),
                              onLongPress: () => _deleteProduct(product), // Alternative delete action
                            ),
                          );
                        },
                        onReorder: _onReorder,
                      ),
          ),
        ],
      ),
    );
  }
}

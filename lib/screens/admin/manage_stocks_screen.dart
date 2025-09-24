import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageStocksScreen extends StatefulWidget {
  const ManageStocksScreen({super.key});

  @override
  State<ManageStocksScreen> createState() => _ManageStocksScreenState();
}

class _ManageStocksScreenState extends State<ManageStocksScreen> {
  late Future<List<Map<String, dynamic>>> _productsFuture;
  String? _selectedCategory;
  final List<String> _categories = ['All', 'own products', 'sudam'];

  @override
  void initState() {
    super.initState();
    _productsFuture = _fetchProducts();
  }

  Future<List<Map<String, dynamic>>> _fetchProducts() async {
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
      _productsFuture = _fetchProducts();
    });
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
      setState(() {
        _productsFuture = _fetchProducts();
      });
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
            decoration: const InputDecoration(labelText: 'Quantity to add'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final quantity = int.tryParse(stockController.text);
                if (quantity != null && quantity > 0) {
                  final newStock = (product['stock'] as int) + quantity;
                  _updateStock(product['product_id'], newStock, quantity, 'Manual stock addition');
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Add'),
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
          title: Text('Clear Stock for ${product['name']}', style: theme.textTheme.headlineSmall),
          content: const Text('Are you sure you want to clear the stock for this product?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final currentStock = product['stock'] as int;
                _updateStock(product['product_id'], 0, -currentStock, 'Stock cleared manually');
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );
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
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No products found.'));
          }

          final products = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              final imageUrl = product['image_path'] != null
                  ? Supabase.instance.client.storage
                      .from('product-images')
                      .getPublicUrl(product['image_path'])
                  : null;
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      if (imageUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            imageUrl,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: theme.disabledColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.image_outlined, size: 32, color: Colors.grey),
                        ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product['name'], style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('Current Stock: ${product['stock']}', style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                        onPressed: () => _showAddStockDialog(product),
                        tooltip: 'Add Stock',
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                        onPressed: () => _showClearStockDialog(product),
                        tooltip: 'Clear Stock',
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _categories = [];
  Map<String, int> _cart = {}; // product_id -> quantity
  bool _isLoading = true;
  String? _selectedCategoryCode;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final productsResponse = await supabase.from('products').select().order('name');
      final categoriesResponse = await supabase.from('categories').select().order('name');

      setState(() {
        _products = List<Map<String, dynamic>>.from(productsResponse as List);
        _categories = List<Map<String, dynamic>>.from(categoriesResponse as List);
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
                ...cartItems.map((item) {
                  final product = item['product'] as Map<String, dynamic>;
                  return ListTile(
                    leading: product['image_path'] != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              Supabase.instance.client.storage
                                  .from('product-images')
                                  .getPublicUrl(product['image_path']),
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(Icons.image, size: 50),
                    title: Text(product['name']),
                    subtitle: Text('${item['quantity']} x ${product['price']} = ${item['subtotal']}'),
                  );
                }),
                const Divider(height: 24),
                Text('Grand Total: $_totalPrice', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => _confirmBill(cartItems),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Confirm Bill'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmBill(List<Map<String, dynamic>> cartItems) async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;

      final itemsJson = cartItems.map((item) {
        return {
          'product_id': item['product']['product_id'],
          'quantity': item['quantity'],
          'unit_price': item['product']['price'],
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
          return; // Stop the billing process
        }
      }

      final billId = await supabase.rpc('create_bill', params: {
        'p_user_id': userId,
        'p_items': itemsJson,
        'p_total': _totalPrice,
      });

      if (!mounted) return;
      Navigator.pop(context); // Close the dialog
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BillingSuccessScreen(billId: billId.toString(), items: cartItems, total: _totalPrice),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error creating bill: $e")),
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
              child: Image.network(
                imageUrl,
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
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
                final imageUrl = product['image_path'] != null
                    ? Supabase.instance.client.storage
                        .from('product-images')
                        .getPublicUrl(product['image_path'])
                    : null;

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
                            child: imageUrl != null
                                ? Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                  )
                                : const Icon(Icons.image_outlined, size: 80, color: Colors.grey),
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
                                Text('Price: ${product['price']}', style: theme.textTheme.bodyMedium),
                                Text('Stock: ${product['stock']}', style: theme.textTheme.bodyMedium),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(24),
                            bottomRight: Radius.circular(24),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => _removeFromCart(product['product_id']),
                            ),
                            Text(quantity.toString(), style: theme.textTheme.titleMedium),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => _addToCart(product['product_id']),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: _cart.isNotEmpty
          ? BottomAppBar(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total: $_totalPrice', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    ElevatedButton.icon(
                      onPressed: _showBillConfirmationDialog,
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Generate Bill'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
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
}

class BillingSuccessScreen extends StatelessWidget {
  final String billId;
  final List<Map<String, dynamic>> items;
  final double total;

  const BillingSuccessScreen({super.key, required this.billId, required this.items, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill Generated Successfully'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Thank you for your purchase!',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Bill ID: $billId',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Billed Items:', style: theme.textTheme.titleLarge),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final product = item['product'] as Map<String, dynamic>;
                  return ListTile(
                    leading: product['image_path'] != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              Supabase.instance.client.storage
                                  .from('product-images')
                                  .getPublicUrl(product['image_path']),
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(Icons.image, size: 50),
                    title: Text(product['name']),
                    subtitle: Text('${item['quantity']} x ${product['price']} = ${item['subtotal']}'),
                  );
                },
              ),
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Grand Total:', style: theme.textTheme.titleLarge),
                Text('$total', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('New Bill'),
              ),
            )
          ],
        ),
      ),
    );
  }
}
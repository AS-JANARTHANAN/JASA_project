import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class AddProductScreen extends StatefulWidget {
  final Map<String, dynamic>? product;

  const AddProductScreen({super.key, this.product});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  String? _selectedCategory;
  final List<String> _categories = ["own products", "sudam"];

  File? _imageFile;
  bool _loading = false;
  bool get _isEditMode => widget.product != null;
  String? _initialImageUrl;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      final product = widget.product!;
      _nameController.text = product['name'];
      _priceController.text = product['price'].toString();
      _stockController.text = product['stock'].toString();
      _selectedCategory = product['category_code'] == 'OWN' ? 'own products' : 'sudam';
      if (product['image_path'] != null) {
        _initialImageUrl = Supabase.instance.client.storage
            .from('product-images')
            .getPublicUrl(product['image_path']);
      }
    } else {
      if (_categories.isNotEmpty) {
        _selectedCategory = _categories.first;
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source);

      if (pickedFile != null) {
        File file = File(pickedFile.path);
        final fileSize = await file.length();
        if (fileSize > 1.5 * 1024 * 1024) {
          final dir = await getTemporaryDirectory();
          final targetPath = "${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg";
          final result = await FlutterImageCompress.compressWithFile(
            file.absolute.path,
            quality: 70,
          );
          if (result != null) {
            final compressedFile = File(targetPath);
            await compressedFile.writeAsBytes(result);
            file = compressedFile;
          }
        }
        setState(() => _imageFile = file);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error picking image: $e")));
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!_isEditMode && _imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select an image for a new product")),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      if (_isEditMode) {
        await _updateProduct();
      } else {
        await _addProduct();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Product ${(_isEditMode ? 'updated' : 'added')} successfully")),
      );
      Navigator.pop(context, true); // Return true to indicate success
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addProduct() async {
    final supabase = Supabase.instance.client;
    final productId = const Uuid().v4();
    final fileExt = _imageFile!.path.split('.').last;
    final filePath = "$productId.$fileExt";

    await supabase.storage.from('product-images').upload(filePath, _imageFile!);

    final categoryCode = _selectedCategory == "own products" ? "OWN" : "SUD";

    await supabase.from('products').insert({
      'name': _nameController.text.trim(),
      'price': double.parse(_priceController.text.trim()),
      'stock': int.parse(_stockController.text.trim()),
      'category_code': categoryCode,
      'image_path': filePath,
    });
  }

  Future<void> _updateProduct() async {
    final supabase = Supabase.instance.client;
    String? filePath = widget.product!['image_path'];

    if (_imageFile != null) {
      // Delete old image
      if (filePath != null) {
        await supabase.storage.from('product-images').remove([filePath]);
      }
      // Upload new image
      final fileExt = _imageFile!.path.split('.').last;
      filePath = "${const Uuid().v4()}.$fileExt";
      await supabase.storage.from('product-images').upload(filePath, _imageFile!);
    }

    final categoryCode = _selectedCategory == "own products" ? "OWN" : "SUD";

    await supabase.from('products').update({
      'name': _nameController.text.trim(),
      'price': double.parse(_priceController.text.trim()),
      'stock': int.parse(_stockController.text.trim()),
      'category_code': categoryCode,
      'image_path': filePath,
    }).eq('product_id', widget.product!['product_id']);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? "Edit Product" : "Add Product"),
        backgroundColor: theme.colorScheme.surface,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Product Details", style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: "Product Name"),
                      validator: (value) => (value == null || value.isEmpty) ? 'Please enter a name' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Price"),
                      validator: (value) => (value == null || value.isEmpty) ? 'Please enter a price' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _stockController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Stock"),
                      validator: (value) => (value == null || value.isEmpty) ? 'Please enter the stock' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      items: _categories.map((String category) {
                        return DropdownMenuItem<String>(
                          value: category,
                          child: Text(category),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => _selectedCategory = value);
                      },
                      decoration: const InputDecoration(labelText: "Category"),
                      validator: (value) => (value == null) ? 'Please select a category' : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(24),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Product Image", style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () => _pickImage(ImageSource.gallery),
                      child: Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.dividerColor),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _imageFile != null
                            ? Image.file(_imageFile!, fit: BoxFit.cover)
                            : (_initialImageUrl != null
                                ? Image.network(_initialImageUrl!, fit: BoxFit.cover)
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_a_photo_outlined, size: 48, color: theme.disabledColor),
                                      const SizedBox(height: 8),
                                      const Text("Tap to select an image"),
                                    ],
                                  )),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text("Gallery"),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text("Camera"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _loading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(_isEditMode ? "Update Product" : "Add Product"),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

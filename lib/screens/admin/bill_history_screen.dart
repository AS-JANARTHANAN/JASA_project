import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';

/// Enhanced Bill History Screen with advanced filtering and PDF generation
class BillHistoryScreen extends StatefulWidget {
  const BillHistoryScreen({super.key});

  @override
  State<BillHistoryScreen> createState() => _BillHistoryScreenState();
}

class _BillHistoryScreenState extends State<BillHistoryScreen> {
  // Data
  List<Map<String, dynamic>> _bills = [];
  List<Map<String, dynamic>> _filteredBillItems = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  
  bool _isLoading = true;
  bool _isGeneratingPdf = false;

  // Filter state
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCategoryCode;
  String? _selectedProductId;
  String? _selectedBillId;
  DateTimeRange? _selectedDateRange;
  String _filterMode = 'all'; // all, today, date_range, bill_wise, product_wise, category_wise

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    
    try {
      final supabase = Supabase.instance.client;
      
      // Load categories
      final categoriesResponse = await supabase
          .from('categories')
          .select('code, name')
          .order('name');
      
      // Load products
      final productsResponse = await supabase
          .from('products')
          .select('product_id, name, category_code')
          .order('name');
      
      setState(() {
        _categories = List<Map<String, dynamic>>.from(categoriesResponse as List);
        _products = List<Map<String, dynamic>>.from(productsResponse as List);
        _filteredProducts = _products;
      });
      
      // Load bills with default filter (today)
      await _applyFilters();
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
    
    setState(() => _isLoading = false);
  }

  /// Apply all active filters and fetch bills
  Future<void> _applyFilters() async {
    setState(() => _isLoading = true);
    
    try {
      final supabase = Supabase.instance.client;
      
      // Build bill items query based on filters
      var query = supabase.from('bill_items').select('''
        id,
        bill_id,
        product_id,
        product_name,
        category_code,
        quantity,
        unit_price,
        total,
        bills!inner (
          id,
          bill_number,
          user_id,
          total_amount,
          created_at
        )
      ''');
      
      // Apply category filter
      if (_selectedCategoryCode != null) {
        query = query.eq('category_code', _selectedCategoryCode!);
      }
      
      // Apply product filter
      if (_selectedProductId != null) {
        query = query.eq('product_id', _selectedProductId!);
      }
      
      // Apply bill filter
      if (_selectedBillId != null) {
        query = query.eq('bill_id', _selectedBillId!);
      }
      
      // Execute query
      final response = await query.order('bill_id', ascending: false);
      var items = List<Map<String, dynamic>>.from(response as List);
      
      // Apply date range filter (client-side for nested data)
      if (_filterMode == 'today') {
        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        
        items = items.where((item) {
          final billData = item['bills'] as Map<String, dynamic>?;
          if (billData == null) return false;
          final createdAt = DateTime.parse(billData['created_at'] as String);
          return createdAt.isAfter(startOfToday.subtract(const Duration(seconds: 1))) &&
                 createdAt.isBefore(endOfToday.add(const Duration(seconds: 1)));
        }).toList();
      } else if (_selectedDateRange != null) {
        final startDate = _selectedDateRange!.start;
        final endDate = DateTime(
          _selectedDateRange!.end.year,
          _selectedDateRange!.end.month,
          _selectedDateRange!.end.day,
          23, 59, 59, 999,
        );
        
        items = items.where((item) {
          final billData = item['bills'] as Map<String, dynamic>?;
          if (billData == null) return false;
          final createdAt = DateTime.parse(billData['created_at'] as String);
          return createdAt.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
                 createdAt.isBefore(endDate.add(const Duration(seconds: 1)));
        }).toList();
      }
      
      // Apply search filter
      if (_searchController.text.isNotEmpty) {
        final searchLower = _searchController.text.toLowerCase();
        items = items.where((item) {
          final productName = (item['product_name'] as String? ?? '').toLowerCase();
          final billNumber = (item['bills']?['bill_number'] as String? ?? '').toLowerCase();
          return productName.contains(searchLower) || billNumber.contains(searchLower);
        }).toList();
      }
      
      // Group by bills
      final billsMap = <String, Map<String, dynamic>>{};
      for (final item in items) {
        final billData = item['bills'] as Map<String, dynamic>?;
        if (billData == null) continue;
        
        final billId = billData['id'].toString();
        if (!billsMap.containsKey(billId)) {
          billsMap[billId] = {
            ...billData,
            'items': <Map<String, dynamic>>[],
          };
        }
        (billsMap[billId]!['items'] as List<Map<String, dynamic>>).add({
          'id': item['id'],
          'product_id': item['product_id'],
          'product_name': item['product_name'],
          'category_code': item['category_code'],
          'quantity': item['quantity'],
          'unit_price': item['unit_price'],
          'total': item['total'],
        });
      }
      
      // Convert to list and sort by date
      final bills = billsMap.values.toList();
      bills.sort((a, b) {
        final dateA = DateTime.parse(a['created_at'] as String);
        final dateB = DateTime.parse(b['created_at'] as String);
        return dateB.compareTo(dateA);
      });
      
      setState(() {
        _bills = bills;
        _filteredBillItems = items;
      });
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error applying filters: $e')),
        );
      }
    }
    
    setState(() => _isLoading = false);
  }

  /// Update products dropdown when category changes
  void _onCategoryChanged(String? categoryCode) {
    setState(() {
      _selectedCategoryCode = categoryCode;
      _selectedProductId = null; // Reset product selection
      
      if (categoryCode == null) {
        _filteredProducts = _products;
      } else {
        _filteredProducts = _products
            .where((p) => p['category_code'] == categoryCode)
            .toList();
      }
    });
    _applyFilters();
  }

  /// Quick filter: Today's bills
  void _filterToday() {
    setState(() {
      _filterMode = 'today';
      _selectedDateRange = null;
    });
    _applyFilters();
  }

  /// Quick filter: Date range
  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      currentDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
    );
    
    if (picked != null) {
      setState(() {
        _filterMode = 'date_range';
        _selectedDateRange = picked;
      });
      _applyFilters();
    }
  }

  /// Reset all filters
  void _resetFilters() {
    setState(() {
      _filterMode = 'all';
      _selectedCategoryCode = null;
      _selectedProductId = null;
      _selectedBillId = null;
      _selectedDateRange = null;
      _searchController.clear();
      _filteredProducts = _products;
    });
    _applyFilters();
  }

  /// Calculate totals for summary
  Map<String, dynamic> _calculateSummary() {
    // Category-wise totals
    final categoryTotals = <String, double>{};
    final productTotals = <String, Map<String, dynamic>>{};
    double grandTotal = 0;
    int totalQuantity = 0;
    
    for (final bill in _bills) {
      final items = bill['items'] as List<Map<String, dynamic>>;
      for (final item in items) {
        final categoryCode = item['category_code'] as String? ?? 'Unknown';
        final productName = item['product_name'] as String? ?? 'Unknown';
        final total = (item['total'] as num?)?.toDouble() ?? 0;
        final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
        
        // Category totals
        categoryTotals[categoryCode] = (categoryTotals[categoryCode] ?? 0) + total;
        
        // Product totals
        if (!productTotals.containsKey(productName)) {
          productTotals[productName] = {
            'name': productName,
            'category_code': categoryCode,
            'quantity': 0,
            'total': 0.0,
          };
        }
        productTotals[productName]!['quantity'] = 
            (productTotals[productName]!['quantity'] as int) + quantity;
        productTotals[productName]!['total'] = 
            (productTotals[productName]!['total'] as double) + total;
        
        grandTotal += total;
        totalQuantity += quantity;
      }
    }
    
    // Get category names
    final categoryTotalsWithNames = <String, Map<String, dynamic>>{};
    for (final entry in categoryTotals.entries) {
      final category = _categories.firstWhere(
        (c) => c['code'] == entry.key,
        orElse: () => {'code': entry.key, 'name': entry.key},
      );
      categoryTotalsWithNames[entry.key] = {
        'code': entry.key,
        'name': category['name'] ?? entry.key,
        'total': entry.value,
      };
    }
    
    return {
      'categoryTotals': categoryTotalsWithNames,
      'productTotals': productTotals,
      'grandTotal': grandTotal,
      'totalQuantity': totalQuantity,
      'totalBills': _bills.length,
    };
  }

  /// Generate and preview PDF
  Future<void> _generatePdf() async {
    if (_bills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No bills to generate PDF for.')),
      );
      return;
    }

    setState(() => _isGeneratingPdf = true);

    try {
      final summary = _calculateSummary();
      final pdf = pw.Document();
      
      // PDF styling
      final headerStyle = pw.TextStyle(
        fontSize: 18,
        fontWeight: pw.FontWeight.bold,
      );
      final titleStyle = pw.TextStyle(
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
      );
      final normalStyle = const pw.TextStyle(fontSize: 10);
      final boldStyle = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
      
      // Get filter description
      String filterDesc = _getFilterDescription();
      
      // Build all bill widgets first
      List<pw.Widget> allBillWidgets = [];
      double runningTotal = 0;
      
      for (int billIndex = 0; billIndex < _bills.length; billIndex++) {
        final bill = _bills[billIndex];
        final items = bill['items'] as List<Map<String, dynamic>>;
        final billDate = DateTime.parse(bill['created_at'] as String).toLocal();
        
        // Bill header
        allBillWidgets.add(
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            margin: const pw.EdgeInsets.only(bottom: 4),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue100,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Bill #${bill['bill_number'] ?? bill['id'].toString().substring(0, 8).toUpperCase()}', style: titleStyle),
                pw.Text(DateFormat('dd MMM yyyy, hh:mm a').format(billDate), style: normalStyle),
              ],
            ),
          ),
        );
        
        // Items table
        allBillWidgets.add(
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1.5),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1.5),
              4: const pw.FlexColumnWidth(1.5),
            },
            children: [
              // Header row
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Product', style: boldStyle)),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Category', style: boldStyle)),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Qty', style: boldStyle)),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Price', style: boldStyle)),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Total', style: boldStyle)),
                ],
              ),
              // Item rows
              ...items.map((item) {
                final category = _categories.firstWhere(
                  (c) => c['code'] == item['category_code'],
                  orElse: () => {'name': item['category_code']},
                );
                return pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(item['product_name'] ?? '', style: normalStyle)),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(category['name'] ?? '', style: normalStyle)),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${item['quantity']}', style: normalStyle)),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('₹${item['unit_price']}', style: normalStyle)),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('₹${item['total']}', style: normalStyle)),
                  ],
                );
              }),
            ],
          ),
        );
        
        // Bill total
        double billTotal = items.fold(0.0, (sum, item) => sum + ((item['total'] as num?)?.toDouble() ?? 0));
        runningTotal += billTotal;
        
        allBillWidgets.add(
          pw.Container(
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            margin: const pw.EdgeInsets.only(bottom: 16),
            child: pw.Text('Bill Total: ₹${billTotal.toStringAsFixed(2)}', style: boldStyle),
          ),
        );
      }
      
      // Add bills using MultiPage for automatic pagination
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('JASA - Bill History Report', style: headerStyle),
                    pw.Text('Page ${context.pageNumber}', style: normalStyle),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Text(filterDesc, style: normalStyle),
                pw.Text('Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}', style: normalStyle),
                pw.Divider(),
                pw.SizedBox(height: 8),
              ],
            );
          },
          footer: (pw.Context context) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: normalStyle,
              ),
            );
          },
          build: (pw.Context context) => allBillWidgets,
        ),
      );
      
      // Summary page
      final categoryTotals = summary['categoryTotals'] as Map<String, Map<String, dynamic>>;
      final productTotals = summary['productTotals'] as Map<String, Map<String, dynamic>>;
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(child: pw.Text('SUMMARY REPORT', style: headerStyle)),
                pw.SizedBox(height: 8),
                pw.Center(child: pw.Text(filterDesc, style: normalStyle)),
                pw.Divider(),
                pw.SizedBox(height: 16),
                
                // Overview
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue50,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                    children: [
                      pw.Column(
                        children: [
                          pw.Text('${summary['totalBills']}', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                          pw.Text('Total Bills', style: normalStyle),
                        ],
                      ),
                      pw.Column(
                        children: [
                          pw.Text('${summary['totalQuantity']}', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                          pw.Text('Items Sold', style: normalStyle),
                        ],
                      ),
                      pw.Column(
                        children: [
                          pw.Text('₹${(summary['grandTotal'] as double).toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
                          pw.Text('Grand Total', style: normalStyle),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 24),
                
                // Category-wise summary
                pw.Text('CATEGORY-WISE SUMMARY', style: titleStyle),
                pw.SizedBox(height: 8),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FlexColumnWidth(2),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Category', style: boldStyle)),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Total Amount', style: boldStyle)),
                      ],
                    ),
                    ...categoryTotals.values.map((cat) => pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(cat['name'] ?? '', style: normalStyle)),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('₹${(cat['total'] as double).toStringAsFixed(2)}', style: normalStyle)),
                      ],
                    )),
                  ],
                ),
                pw.SizedBox(height: 24),
                
                // Product-wise summary
                pw.Text('PRODUCT-WISE SUMMARY', style: titleStyle),
                pw.SizedBox(height: 8),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FlexColumnWidth(1),
                    2: const pw.FlexColumnWidth(2),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Product', style: boldStyle)),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Qty', style: boldStyle)),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Total Amount', style: boldStyle)),
                      ],
                    ),
                    ...productTotals.values.map((prod) => pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(prod['name'] ?? '', style: normalStyle)),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${prod['quantity']}', style: normalStyle)),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('₹${(prod['total'] as double).toStringAsFixed(2)}', style: normalStyle)),
                      ],
                    )),
                  ],
                ),
                
                pw.Spacer(),
                
                // Grand total
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Text('GRAND TOTAL: ', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    pw.Text('₹${(summary['grandTotal'] as double).toStringAsFixed(2)}', 
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Center(
                  child: pw.Text('--- End of Report ---', style: normalStyle),
                ),
              ],
            );
          },
        ),
      );

      // Save PDF to temp file
      final output = await getTemporaryDirectory();
      final fileName = 'bill_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final file = File('${output.path}/$fileName');
      final pdfBytes = await pdf.save();
      await file.writeAsBytes(pdfBytes);

      if (!mounted) return;
      
      // Navigate to PDF preview screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PdfPreviewScreen(
            pdfBytes: pdfBytes,
            fileName: fileName,
            title: 'Bill History Report',
          ),
        ),
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating PDF: $e')),
        );
      }
    }

    setState(() => _isGeneratingPdf = false);
  }

  String _getFilterDescription() {
    List<String> filters = [];
    
    if (_filterMode == 'today') {
      filters.add('Date: Today (${DateFormat('dd MMM yyyy').format(DateTime.now())})');
    } else if (_selectedDateRange != null) {
      filters.add('Date: ${DateFormat('dd MMM').format(_selectedDateRange!.start)} - ${DateFormat('dd MMM yyyy').format(_selectedDateRange!.end)}');
    }
    
    if (_selectedCategoryCode != null) {
      final category = _categories.firstWhere(
        (c) => c['code'] == _selectedCategoryCode,
        orElse: () => {'name': _selectedCategoryCode},
      );
      filters.add('Category: ${category['name']}');
    }
    
    if (_selectedProductId != null) {
      final product = _products.firstWhere(
        (p) => p['product_id'] == _selectedProductId,
        orElse: () => {'name': _selectedProductId},
      );
      filters.add('Product: ${product['name']}');
    }
    
    if (filters.isEmpty) {
      return 'Filter: All Bills';
    }
    
    return 'Filter: ${filters.join(' | ')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _calculateSummary();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill History'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 1,
        actions: [
          // PDF button
          IconButton(
            icon: _isGeneratingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Generate PDF Report',
            onPressed: _isGeneratingPdf ? null : _generatePdf,
          ),
          // Reset filters
          IconButton(
            icon: const Icon(Icons.filter_alt_off),
            tooltip: 'Reset Filters',
            onPressed: _resetFilters,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter section
          _buildFilterSection(theme),
          
          // Summary bar
          if (!_isLoading && _bills.isNotEmpty)
            _buildSummaryBar(theme, summary),
          
          // Bills list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _bills.isEmpty
                    ? _buildEmptyState(theme)
                    : _buildBillsList(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search and quick filters row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by product or bill number...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _applyFilters();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (_) => _applyFilters(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Quick filter chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Today chip
              FilterChip(
                label: const Text('Today'),
                selected: _filterMode == 'today',
                onSelected: (_) => _filterToday(),
                avatar: const Icon(Icons.today, size: 18),
              ),
              // Date range chip
              FilterChip(
                label: Text(_selectedDateRange != null
                    ? '${DateFormat('dd/MM').format(_selectedDateRange!.start)} - ${DateFormat('dd/MM').format(_selectedDateRange!.end)}'
                    : 'Date Range'),
                selected: _filterMode == 'date_range' && _selectedDateRange != null,
                onSelected: (_) => _selectDateRange(),
                avatar: const Icon(Icons.date_range, size: 18),
              ),
              // All bills chip
              FilterChip(
                label: const Text('All Bills'),
                selected: _filterMode == 'all',
                onSelected: (_) => _resetFilters(),
                avatar: const Icon(Icons.receipt_long, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Category and Product dropdowns
          Row(
            children: [
              // Category dropdown
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: _selectedCategoryCode,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    prefixIcon: const Icon(Icons.category_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Categories'),
                    ),
                    ..._categories.map((cat) => DropdownMenuItem<String?>(
                      value: cat['code'] as String?,
                      child: Text(cat['name'] as String? ?? ''),
                    )),
                  ],
                  onChanged: _onCategoryChanged,
                  isExpanded: true,
                ),
              ),
              const SizedBox(width: 12),
              // Product dropdown
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: _selectedProductId,
                  decoration: InputDecoration(
                    labelText: 'Product',
                    prefixIcon: const Icon(Icons.inventory_2_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Products'),
                    ),
                    ..._filteredProducts.map((prod) => DropdownMenuItem<String?>(
                      value: prod['product_id'] as String?,
                      child: Text(
                        prod['name'] as String? ?? '',
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedProductId = value);
                    _applyFilters();
                  },
                  isExpanded: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar(ThemeData theme, Map<String, dynamic> summary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: theme.colorScheme.primaryContainer.withOpacity(0.3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem(theme, Icons.receipt_outlined, '${summary['totalBills']}', 'Bills'),
          _buildSummaryItem(theme, Icons.shopping_cart_outlined, '${summary['totalQuantity']}', 'Items'),
          _buildSummaryItem(
            theme,
            Icons.currency_rupee,
            '${(summary['grandTotal'] as double).toStringAsFixed(0)}',
            'Total',
            isHighlighted: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(ThemeData theme, IconData icon, String value, String label, {bool isHighlighted = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isHighlighted ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.6)),
            const SizedBox(width: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isHighlighted ? theme.colorScheme.primary : null,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 80,
            color: theme.colorScheme.onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No bills found',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _resetFilters,
            icon: const Icon(Icons.refresh),
            label: const Text('Reset Filters'),
          ),
        ],
      ),
    );
  }

  Widget _buildBillsList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _bills.length,
      itemBuilder: (context, index) {
        final bill = _bills[index];
        final items = bill['items'] as List<Map<String, dynamic>>;
        final billDate = DateTime.parse(bill['created_at'] as String).toLocal();
        final billTotal = items.fold(0.0, (sum, item) => sum + ((item['total'] as num?)?.toDouble() ?? 0));

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.receipt, color: theme.colorScheme.primary),
            ),
            title: Text(
              'Bill #${bill['bill_number'] ?? bill['id'].toString().substring(0, 8)}',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  DateFormat('dd MMM yyyy, hh:mm a').format(billDate),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${items.length} items',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${billTotal.toStringAsFixed(2)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            children: [
              const Divider(height: 1),
              ...items.map((item) {
                final category = _categories.firstWhere(
                  (c) => c['code'] == item['category_code'],
                  orElse: () => {'name': item['category_code']},
                );
                return ListTile(
                  dense: true,
                  leading: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(item['product_name'] ?? 'Unknown'),
                  subtitle: Text(
                    '${category['name']} • ${item['quantity']} x ₹${item['unit_price']}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: Text(
                    '₹${item['total']}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// PDF Preview Screen - View PDF in app with download option
class PdfPreviewScreen extends StatelessWidget {
  final List<int> pdfBytes;
  final String fileName;
  final String title;

  const PdfPreviewScreen({
    super.key,
    required this.pdfBytes,
    required this.fileName,
    required this.title,
  });

  Future<void> _downloadPdf(BuildContext context) async {
    try {
      // Use printing package to share/save
      await Printing.sharePdf(
        bytes: Uint8List.fromList(pdfBytes),
        filename: fileName,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing PDF: $e')),
      );
    }
  }

  Future<void> _printPdf(BuildContext context) async {
    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => Uint8List.fromList(pdfBytes),
        name: fileName,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error printing PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: theme.colorScheme.surface,
        elevation: 1,
        actions: [
          // Download/Share button
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download / Share',
            onPressed: () => _downloadPdf(context),
          ),
          // Print button
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print',
            onPressed: () => _printPdf(context),
          ),
        ],
      ),
      body: PdfPreview(
        build: (format) => Uint8List.fromList(pdfBytes),
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName: fileName,
        actions: [
          PdfPreviewAction(
            icon: Icon(Icons.download, color: theme.colorScheme.primary),
            onPressed: (context, build, format) => _downloadPdf(context),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
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
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () => _downloadPdf(context),
                  icon: const Icon(Icons.download),
                  label: const Text('Download PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
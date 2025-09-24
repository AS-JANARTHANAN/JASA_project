import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';

class BillHistoryScreen extends StatefulWidget {
  const BillHistoryScreen({super.key});

  @override
  State<BillHistoryScreen> createState() => _BillHistoryScreenState();
}

class _BillHistoryScreenState extends State<BillHistoryScreen> {
  List<Map<String, dynamic>> _bills = [];
  bool _isLoading = true;

  // Filter state
  final _searchController = TextEditingController();
  String? _selectedCategory;
  DateTimeRange? _selectedDateRange;
  List<Map<String, dynamic>> _categories = [];

  @override
  void initState() {
    super.initState();
    _fetchCategories();
    _fetchBills();
  }

  Future<void> _fetchCategories() async {
    final supabase = Supabase.instance.client;
    final response = await supabase.from('categories').select('code, name');
    setState(() {
      _categories = List<Map<String, dynamic>>.from(response as List);
    });
  }

  Future<void> _fetchBills() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      var billsQuery = supabase.from('bills').select();

      // Date filter
      if (_selectedDateRange != null) {
        final startDate = _selectedDateRange!.start;
        final endDate = DateTime(
          _selectedDateRange!.end.year,
          _selectedDateRange!.end.month,
          _selectedDateRange!.end.day,
          23,
          59,
          59,
          999);

        billsQuery = billsQuery
            .gte('created_at', startDate.toIso8601String())
            .lte('created_at', endDate.toIso8601String());
      }

      // Category and Product search filters (complex)
      if (_selectedCategory != null || _searchController.text.isNotEmpty) {
        var billItemsQuery = supabase.from('bill_items').select('bill_id');
        if (_selectedCategory != null) {
          billItemsQuery = billItemsQuery.eq(
            'category_code',
            _selectedCategory!,
          );
        }
        if (_searchController.text.isNotEmpty) {
          billItemsQuery = billItemsQuery.ilike(
            'product_name',
            '%${_searchController.text}%',
          );
        }
        final billItemsResponse = await billItemsQuery;
        final billIds = (billItemsResponse as List)
            .map((item) => item['bill_id'].toString())
            .toSet()
            .toList();
        if (billIds.isEmpty) {
          setState(() {
            _bills = [];
            _isLoading = false;
          });
          return;
        }
        billsQuery = billsQuery.filter('id', 'in', billIds);
      }

      final billsResponse = await billsQuery.order(
        'created_at',
        ascending: false,
      );
      final bills = List<Map<String, dynamic>>.from(billsResponse as List);

      // Fetch all bill items for the fetched bills in one go
      final fetchedBillIds = bills
          .map((bill) => bill['id'].toString())
          .toList();
      if (fetchedBillIds.isEmpty) {
        setState(() {
          _bills = [];
          _isLoading = false;
        });
        return;
      }
      final allBillItemsResponse = await supabase
          .from('bill_items')
          .select()
          .filter('bill_id', 'in', fetchedBillIds);
      final allBillItems = List<Map<String, dynamic>>.from(
        allBillItemsResponse as List,
      );

      // Map bill items to their respective bills
      for (var bill in bills) {
        var itemsForBill = allBillItems
            .where(
              (item) => item['bill_id'].toString() == bill['id'].toString(),
            );

        // If a category is selected, further filter the items to only show those from the selected category
        if (_selectedCategory != null) {
          itemsForBill = itemsForBill.where(
            (item) => item['category_code'] == _selectedCategory,
          );
        }
        
        bill['items'] = itemsForBill.toList();
      }

      setState(() {
        _bills = bills;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error fetching bills: $e")));
      setState(() => _isLoading = false);
    }
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _selectedCategory = null;
      _selectedDateRange = null;
    });
    _fetchBills();
  }

  Future<void> _generatePdf() async {
    if (_bills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No bills to generate PDF for.')),
      );
      return;
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Text(
              'Bill History Report',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Generated on: ${DateFormat.yMd().add_jm().format(DateTime.now())}',
          ),
          pw.SizedBox(height: 20),
          ..._bills.map((bill) {
            final items = bill['items'] as List<Map<String, dynamic>>;
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Bill ID: ${bill['id']}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text('Total Amount: ${bill['total_amount']}'),
                pw.Text(
                  'Date: ${bill['created_at'] != null ? DateFormat.yMd().add_jm().format(DateTime.parse(bill['created_at']).toLocal()) : 'N/A'}',
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'Items:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                ...items.map(
                  (item) => pw.Text(
                    '- ${item['product_name']} x ${item['quantity']} @ ${item['unit_price']} = ${item['total']}',
                  ),
                ),
                pw.Divider(),
                pw.SizedBox(height: 10),
              ],
            );
          }),
          pw.SizedBox(height: 20),
          pw.Text(
            'Grand Total of Filtered Bills: ${_bills.fold(0.0, (double sum, bill) {
              final items = bill['items'] as List<Map<String, dynamic>>;
              final billTotal = items.fold(0.0, (double itemSum, item) => itemSum + (item['total'] as num).toDouble());
              return sum + billTotal;
            }).toStringAsFixed(2)}',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File("${output.path}/bill_history.pdf");
    await file.writeAsBytes(await pdf.save());

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('PDF generated and saved to ${file.path}'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () {
            // This requires a package like open_filex or url_launcher
            // For now, just show the path
            // open_filex.OpenFilex.open(file.path);
          },
        ),
      ),
    );
    // You might want to use Printing.sharePdf or Printing.layoutPdf here
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'bill_history.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill History'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _generatePdf,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(theme),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _bills.isEmpty
                ? const Center(child: Text('No bills found.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _bills.length,
                    itemBuilder: (context, index) {
                      final bill = _bills[index];
                      final items = bill['items'] as List<Map<String, dynamic>>;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 4,
                        child: ExpansionTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          title: Text('Bill ID: ${bill['id']}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            'Total: ${bill['total_amount']} - Date: ${bill['created_at'] != null ? DateFormat.yMd().add_jm().format(DateTime.parse(bill['created_at']).toLocal()) : 'N/A'}',
                          ),
                          children: items.map((item) {
                            return ListTile(
                              title: Text(item['product_name'] ?? 'N/A'),
                              subtitle: Text(
                                '${item['quantity']} x ${item['unit_price']} = ${item['total']}',
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          // Search Field
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search by Product',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
              ),
              onSubmitted: (_) => _fetchBills(),
            ),
          ),

          // Category Dropdown
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: DropdownButtonFormField<String?>(
              value: _selectedCategory,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All Categories'),
                ),
                ..._categories.map(
                  (cat) => DropdownMenuItem<String?>(
                    value: cat['code'] as String?,
                    child: Text(cat['name'] as String),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => _selectedCategory = value);
                _fetchBills();
              },
              decoration: InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
              ),
            ),
          ),

          // Date Range Picker
          ActionChip(
            avatar: const Icon(Icons.calendar_today_outlined),
            label: Text(
              _selectedDateRange == null
                  ? 'Select Date Range'
                  : '${DateFormat.yMd().format(_selectedDateRange!.start)} - ${DateFormat.yMd().format(_selectedDateRange!.end)}',
            ),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                currentDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() => _selectedDateRange = picked);
                _fetchBills();
              }
            },
          ),

          // Today Button
          TextButton(
            onPressed: () {
              final now = DateTime.now();
              final startOfToday = DateTime(now.year, now.month, now.day);
              final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
              setState(
                () => _selectedDateRange = DateTimeRange(
                  start: startOfToday,
                  end: endOfToday,
                ),
              );
              _fetchBills();
            },
            child: const Text('Today'),
          ),

          // Reset Button
          TextButton(
            onPressed: _resetFilters,
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
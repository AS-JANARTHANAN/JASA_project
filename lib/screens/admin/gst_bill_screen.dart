import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// GST Bill Generator Screen
/// Generates professional tax invoices with SGST and CGST calculation
class GSTBillScreen extends StatefulWidget {
  const GSTBillScreen({super.key});

  @override
  State<GSTBillScreen> createState() => _GSTBillScreenState();
}

class _GSTBillScreenState extends State<GSTBillScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _toNameController = TextEditingController();
  final _toAddressController = TextEditingController();
  final _toPhoneController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _invoiceNumberController = TextEditingController();

  bool _isGenerating = false;

  // From Address (Fixed)
  static const String _brandName = 'JASA';
  static const String _fromContact = '6379984759, 7598465053';
  static const String _fromAddress = 'M. Ashokkumar, Office Street, Kallakudi, Lalgudi, Trichy';

  // GST Rates
  static const double _sgstRate = 9.0;
  static const double _cgstRate = 9.0;
  static const double _totalGstRate = _sgstRate + _cgstRate; // 18%

  @override
  void initState() {
    super.initState();
    // Generate default invoice number
    _invoiceNumberController.text = 'JASA-${DateFormat('yyyyMMdd').format(DateTime.now())}-${DateTime.now().millisecond}';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _toNameController.dispose();
    _toAddressController.dispose();
    _toPhoneController.dispose();
    _descriptionController.dispose();
    _invoiceNumberController.dispose();
    super.dispose();
  }

  // Calculate amounts from total (inclusive of GST)
  Map<String, double> _calculateFromTotal(double totalAmount) {
    // Total = Base + SGST + CGST
    // Total = Base + (Base * 0.09) + (Base * 0.09)
    // Total = Base * 1.18
    // Base = Total / 1.18
    final baseAmount = totalAmount / (1 + _totalGstRate / 100);
    final sgstAmount = baseAmount * (_sgstRate / 100);
    final cgstAmount = baseAmount * (_cgstRate / 100);

    return {
      'base': baseAmount,
      'sgst': sgstAmount,
      'cgst': cgstAmount,
      'total': totalAmount,
    };
  }

  // Calculate amounts from base (exclusive of GST)
  Map<String, double> _calculateFromBase(double baseAmount) {
    final sgstAmount = baseAmount * (_sgstRate / 100);
    final cgstAmount = baseAmount * (_cgstRate / 100);
    final totalAmount = baseAmount + sgstAmount + cgstAmount;

    return {
      'base': baseAmount,
      'sgst': sgstAmount,
      'cgst': cgstAmount,
      'total': totalAmount,
    };
  }

  Future<void> _generateGSTBill() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isGenerating = true);

    try {
      final totalAmount = double.parse(_amountController.text.replaceAll(',', ''));
      final amounts = _calculateFromTotal(totalAmount);

      final pdf = pw.Document();

      // PDF Styles
      final titleStyle = pw.TextStyle(
        fontSize: 24,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.blue900,
      );
      final headerStyle = pw.TextStyle(
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
      );
      final normalStyle = const pw.TextStyle(fontSize: 11);
      final boldStyle = pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold);
      final smallStyle = const pw.TextStyle(fontSize: 9, color: PdfColors.grey700);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue50,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(_brandName, style: titleStyle),
                          pw.SizedBox(height: 4),
                          pw.Text('Contact: $_fromContact', style: normalStyle),
                          pw.SizedBox(height: 2),
                          pw.Container(
                            width: 200,
                            child: pw.Text(_fromAddress, style: smallStyle),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.blue900,
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Text(
                              'TAX INVOICE',
                              style: pw.TextStyle(
                                color: PdfColors.white,
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text('Invoice No: ${_invoiceNumberController.text}', style: boldStyle),
                          pw.Text('Date: ${DateFormat('dd MMM yyyy').format(DateTime.now())}', style: normalStyle),
                          pw.Text('Time: ${DateFormat('hh:mm a').format(DateTime.now())}', style: smallStyle),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 24),

                // Bill To Section
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('BILL TO:', style: headerStyle),
                      pw.Divider(height: 8),
                      pw.Text(_toNameController.text, style: boldStyle),
                      if (_toPhoneController.text.isNotEmpty)
                        pw.Text('Phone: ${_toPhoneController.text}', style: normalStyle),
                      pw.SizedBox(height: 4),
                      pw.Text(_toAddressController.text, style: normalStyle),
                    ],
                  ),
                ),
                pw.SizedBox(height: 24),

                // Description/Items Section
                pw.Text('DESCRIPTION', style: headerStyle),
                pw.SizedBox(height: 8),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1),
                    1: const pw.FlexColumnWidth(5),
                    2: const pw.FlexColumnWidth(2),
                  },
                  children: [
                    // Header row
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('S.No', style: boldStyle),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Particulars', style: boldStyle),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Amount (₹)', style: boldStyle),
                        ),
                      ],
                    ),
                    // Item row
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('1', style: normalStyle),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            _descriptionController.text.isNotEmpty
                                ? _descriptionController.text
                                : 'Services / Products',
                            style: normalStyle,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            amounts['base']!.toStringAsFixed(2),
                            style: normalStyle,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),

                // GST Calculation Table
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Container(
                      width: 280,
                      child: pw.Table(
                        border: pw.TableBorder.all(color: PdfColors.grey400),
                        columnWidths: {
                          0: const pw.FlexColumnWidth(2),
                          1: const pw.FlexColumnWidth(1.5),
                        },
                        children: [
                          // Subtotal
                          pw.TableRow(
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text('Subtotal (Before Tax)', style: normalStyle),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  '₹ ${amounts['base']!.toStringAsFixed(2)}',
                                  style: normalStyle,
                                  textAlign: pw.TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                          // SGST
                          pw.TableRow(
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text('SGST @ $_sgstRate%', style: normalStyle),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  '₹ ${amounts['sgst']!.toStringAsFixed(2)}',
                                  style: normalStyle,
                                  textAlign: pw.TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                          // CGST
                          pw.TableRow(
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text('CGST @ $_cgstRate%', style: normalStyle),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  '₹ ${amounts['cgst']!.toStringAsFixed(2)}',
                                  style: normalStyle,
                                  textAlign: pw.TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                          // Total
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(10),
                                child: pw.Text('GRAND TOTAL', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(10),
                                child: pw.Text(
                                  '₹ ${amounts['total']!.toStringAsFixed(2)}',
                                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                                  textAlign: pw.TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),

                // Amount in Words
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Amount in Words:', style: boldStyle),
                      pw.Text(
                        _numberToWords(amounts['total']!.round()) + ' Rupees Only',
                        style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic),
                      ),
                    ],
                  ),
                ),

                pw.Spacer(),

                // Footer
                pw.Divider(),
                pw.SizedBox(height: 16),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Terms & Conditions:', style: boldStyle),
                        pw.SizedBox(height: 4),
                        pw.Text('1. Goods once sold will not be taken back.', style: smallStyle),
                        pw.Text('2. Payment is due upon receipt.', style: smallStyle),
                        pw.Text('3. This is a computer generated invoice.', style: smallStyle),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('For $_brandName', style: boldStyle),
                        pw.SizedBox(height: 30),
                        pw.Container(
                          width: 100,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(top: pw.BorderSide(color: PdfColors.black)),
                          ),
                          child: pw.Text(
                            'Authorized Signatory',
                            style: smallStyle,
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Center(
                  child: pw.Text(
                    'Thank you for your business!',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue700,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );

      // Show preview and print/save
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'GST_Invoice_${_invoiceNumberController.text}.pdf',
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating invoice: $e')),
        );
      }
    }

    setState(() => _isGenerating = false);
  }

  // Convert number to words
  String _numberToWords(int number) {
    if (number == 0) return 'Zero';

    final ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten',
      'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
    final tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

    String convertLessThanThousand(int n) {
      if (n == 0) return '';
      if (n < 20) return ones[n];
      if (n < 100) return tens[n ~/ 10] + (n % 10 != 0 ? ' ${ones[n % 10]}' : '');
      return '${ones[n ~/ 100]} Hundred' + (n % 100 != 0 ? ' ${convertLessThanThousand(n % 100)}' : '');
    }

    if (number < 0) return 'Negative ${_numberToWords(-number)}';
    if (number < 1000) return convertLessThanThousand(number);
    if (number < 100000) {
      return '${convertLessThanThousand(number ~/ 1000)} Thousand' +
          (number % 1000 != 0 ? ' ${convertLessThanThousand(number % 1000)}' : '');
    }
    if (number < 10000000) {
      return '${convertLessThanThousand(number ~/ 100000)} Lakh' +
          (number % 100000 != 0 ? ' ${_numberToWords(number % 100000)}' : '');
    }
    return '${convertLessThanThousand(number ~/ 10000000)} Crore' +
        (number % 10000000 != 0 ? ' ${_numberToWords(number % 10000000)}' : '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Calculate preview amounts
    double totalAmount = 0;
    try {
      totalAmount = double.parse(_amountController.text.replaceAll(',', ''));
    } catch (_) {}
    final amounts = _calculateFromTotal(totalAmount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GST Bill Generator'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // From Address Card (Fixed)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primaryContainer,
                        theme.colorScheme.primaryContainer.withOpacity(0.5),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.business, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'FROM (Your Business)',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      Text(_brandName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('📞 $_fromContact'),
                      const SizedBox(height: 4),
                      Text('📍 $_fromAddress', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // To Address Card
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.person, color: theme.colorScheme.secondary),
                          const SizedBox(width: 8),
                          Text(
                            'TO (Customer Details)',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      TextFormField(
                        controller: _toNameController,
                        decoration: InputDecoration(
                          labelText: 'Customer Name *',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _toPhoneController,
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          prefixIcon: const Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _toAddressController,
                        decoration: InputDecoration(
                          labelText: 'Address *',
                          prefixIcon: const Icon(Icons.location_on_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        maxLines: 2,
                        validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Invoice Details Card
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.receipt_long, color: theme.colorScheme.tertiary),
                          const SizedBox(width: 8),
                          Text(
                            'INVOICE DETAILS',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.tertiary,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      TextFormField(
                        controller: _invoiceNumberController,
                        decoration: InputDecoration(
                          labelText: 'Invoice Number',
                          prefixIcon: const Icon(Icons.tag),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: InputDecoration(
                          labelText: 'Description / Particulars',
                          hintText: 'e.g., Services rendered, Products sold',
                          prefixIcon: const Icon(Icons.description_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _amountController,
                        decoration: InputDecoration(
                          labelText: 'Total Amount (Inclusive of GST) *',
                          prefixIcon: const Icon(Icons.currency_rupee),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          helperText: 'Enter final amount including 18% GST',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v?.isEmpty ?? true) return 'Required';
                          try {
                            double.parse(v!.replaceAll(',', ''));
                          } catch (_) {
                            return 'Enter valid amount';
                          }
                          return null;
                        },
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // GST Calculation Preview
              if (totalAmount > 0)
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.calculate, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'GST BREAKDOWN PREVIEW',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        _buildPreviewRow('Base Amount', amounts['base']!, theme),
                        _buildPreviewRow('SGST @ $_sgstRate%', amounts['sgst']!, theme),
                        _buildPreviewRow('CGST @ $_cgstRate%', amounts['cgst']!, theme),
                        const Divider(),
                        _buildPreviewRow('Total Amount', amounts['total']!, theme, isTotal: true),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // Generate Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _generateGSTBill,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf),
                  label: Text(_isGenerating ? 'Generating...' : 'Generate GST Invoice'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewRow(String label, double amount, ThemeData theme, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: isTotal
                ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
                : theme.textTheme.bodyMedium,
          ),
          Text(
            '₹ ${amount.toStringAsFixed(2)}',
            style: isTotal
                ? theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  )
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

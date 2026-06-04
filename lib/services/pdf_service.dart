import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../data/models/invoice_model.dart';
import '../data/models/customer_model.dart';

class PdfService {
  Future<File> generateInvoicePdf(InvoiceModel invoice, CustomerModel customer) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('INVOICE', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Invoice #: ${invoice.invoiceNumber}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text('Date: ${DateTime.now().toString().split(' ')[0]}'),
                      pw.Text('Billing Period: ${invoice.monthName} ${invoice.year}'),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 30),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Bill To:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                      pw.SizedBox(height: 4),
                      pw.Text(customer.name, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.Container(width: 200, child: pw.Text(customer.address, style: const pw.TextStyle(fontSize: 10))),
                      pw.Text(customer.phone, style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 30),
              
              // Table Header
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _padding(pw.Text('Description', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      _padding(pw.Text('Qty', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      _padding(pw.Text('Rate', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      _padding(pw.Text('Amount', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    ],
                  ),
                  // Line Items
                  ...invoice.lineItems.map((item) {
                    return pw.TableRow(
                      children: [
                        _padding(pw.Text(item.description)),
                        _padding(pw.Text('${item.deliveryCount}', textAlign: pw.TextAlign.center)),
                        _padding(pw.Text('₹${item.pricePerDelivery.toStringAsFixed(2)}', textAlign: pw.TextAlign.right)),
                        _padding(pw.Text('₹${item.subtotal.toStringAsFixed(2)}', textAlign: pw.TextAlign.right)),
                      ],
                    );
                  }),
                ],
              ),
              
              pw.SizedBox(height: 20),
              
              // Totals
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 200,
                    child: pw.Column(
                      children: [
                        _summaryRow('Subtotal:', '₹${invoice.subtotal.toStringAsFixed(2)}'),
                        if (invoice.totalDiscount > 0)
                          _summaryRow('Discount:', '-₹${invoice.totalDiscount.toStringAsFixed(2)}', color: PdfColors.red),
                        if (invoice.extraCharges > 0)
                          _summaryRow('Extra Charges:', '₹${invoice.extraCharges.toStringAsFixed(2)}'),
                        pw.Divider(color: PdfColors.grey300),
                        _summaryRow('Total Amount:', '₹${invoice.totalAmount.toStringAsFixed(2)}', isBold: true, fontSize: 14),
                        _summaryRow('Paid Amount:', '₹${invoice.paidAmount.toStringAsFixed(2)}', color: PdfColors.green),
                        pw.Divider(color: PdfColors.grey300),
                        _summaryRow('Balance Due:', '₹${invoice.pendingAmount.toStringAsFixed(2)}', isBold: true, color: PdfColors.red),
                      ],
                    ),
                  ),
                ],
              ),
              
              pw.Spacer(),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text('Thank you for your business!', style: pw.TextStyle(fontStyle: pw.FontStyle.italic))),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text('This is a computer generated invoice.', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey))),
            ],
          );
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File("${output.path}/invoice_${invoice.invoiceNumber}.pdf");
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  pw.Widget _padding(pw.Widget child) {
    return pw.Padding(padding: const pw.EdgeInsets.all(8), child: child);
  }

  pw.Widget _summaryRow(String label, String value, {bool isBold = false, double fontSize = 10, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value, style: pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
        ],
      ),
    );
  }
}

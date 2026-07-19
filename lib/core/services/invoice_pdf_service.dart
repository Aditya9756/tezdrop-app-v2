import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/order_model.dart';

class InvoicePdfService {
  static Future<List<int>> buildInvoicePdf(OrderModel order) async {
    final doc = pw.Document();
    final dateStr = order.timestamp.length >= 10 ? order.timestamp.substring(0, 10) : order.timestamp;

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.all(28),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('TezDrop', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#EF4444'))),
              pw.Text('Lightning Fast Food & Grocery Delivery', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('INVOICE', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#EF4444'))),
              pw.Text('#${order.orderId}', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
            ]),
          ]),
          pw.SizedBox(height: 16), pw.Divider(), pw.SizedBox(height: 10),
          _row('Date', dateStr),
          _row('Delivery To', order.address),
          _row('Payment', order.payment),
          _row('Status', order.status),
          pw.SizedBox(height: 10), pw.Divider(), pw.SizedBox(height: 10),
          pw.Text('Items Ordered', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1.2), 3: pw.FlexColumnWidth(1.2)},
            children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [_cell('Item', bold: true), _cell('Qty', bold: true), _cell('Price', bold: true), _cell('Subtotal', bold: true)]),
              ...order.items.map((item) => pw.TableRow(children: [_cell(item.name), _cell('${item.qty}'), _cell('Rs.${item.price.toInt()}'), _cell('Rs.${(item.price * item.qty).toInt()}')])),
            ],
          ),
          pw.SizedBox(height: 14), pw.Divider(), pw.SizedBox(height: 8),
          if (order.coinsUsed > 0)
            pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Coins Used: -Rs.${order.coinsUsed}', style: const pw.TextStyle(fontSize: 11))),
          pw.SizedBox(height: 4),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Total Paid', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text('Rs.${order.total.toInt()}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#EF4444'))),
          ]),
          if (order.coinsEarned > 0) ...[
            pw.SizedBox(height: 8),
            pw.Text('+${order.coinsEarned} TezCoins earned', style: const pw.TextStyle(fontSize: 10, color: PdfColors.amber800)),
          ],
          pw.SizedBox(height: 24),
          pw.Center(child: pw.Text('Thank you for ordering with TezDrop!', style: const pw.TextStyle(fontSize: 11, color: PdfColors.green800))),
        ]),
      ),
    ));
    return doc.save();
  }

  static pw.Widget _row(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(width: 90, child: pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700))),
      pw.Expanded(child: pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
    ]),
  );

  static pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: pw.Text(text, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
  );
}

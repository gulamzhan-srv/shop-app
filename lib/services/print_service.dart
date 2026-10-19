// Печатная форма накладной (PDF): печать на принтере, сохранение или отправка
// (WhatsApp, Telegram и т.п.) через стандартное окно Android.

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'receipt_service.dart';

class PrintService {
  PrintService._();
  static final PrintService instance = PrintService._();

  pw.Font? _regular;
  pw.Font? _bold;

  /// Шрифты с кириллицей лежат в приложении (печать работает и без интернета).
  Future<void> _fonts() async {
    _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
  }

  String _m(double v) => '${NumberFormat('#,##0', 'ru').format(v.round()).replaceAll(' ', ' ')} ₸';
  String _q(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Future<void> printReceipt(ReceiptDoc d, {bool withPrices = true}) async {
    await _fonts();
    final prefs = await SharedPreferences.getInstance();
    final shop = prefs.getString('shop_name') ?? 'AVTOMAG GRS SOFT';
    final theme = pw.ThemeData.withFont(base: _regular!, bold: _bold!);
    final doc = pw.Document(theme: theme, title: 'Поступление № ${d.number}', author: shop);
    final head = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.grey700);
    pw.Widget cell(String t, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
          padding: pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          child: pw.Text(t, textAlign: align, style: pw.TextStyle(fontSize: 10.5, fontWeight: bold ? pw.FontWeight.bold : null)),
        );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.all(32),
      build: (_) => [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(shop, style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
          pw.Text(DateFormat('dd.MM.yyyy HH:mm').format(d.date), style: pw.TextStyle(fontSize: 11)),
        ]),
        pw.SizedBox(height: 10),
        pw.Text('Поступление товаров № ${d.number}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text('Поставщик: ${d.supplier}', style: pw.TextStyle(fontSize: 12)),
        if (d.comment != null && d.comment!.isNotEmpty) pw.Text('Комментарий: ${d.comment}', style: pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
              bottom: pw.BorderSide(color: PdfColors.grey600), top: pw.BorderSide(color: PdfColors.grey600)),
          columnWidths: withPrices
              ? {0: pw.FixedColumnWidth(24), 1: pw.FlexColumnWidth(5), 2: pw.FlexColumnWidth(2), 3: pw.FlexColumnWidth(2), 4: pw.FlexColumnWidth(2)}
              : {0: pw.FixedColumnWidth(24), 1: pw.FlexColumnWidth(6), 2: pw.FlexColumnWidth(2)},
          children: [
            pw.TableRow(children: [
              pw.Padding(padding: pw.EdgeInsets.all(4), child: pw.Text('№', style: head)),
              pw.Padding(padding: pw.EdgeInsets.all(4), child: pw.Text('ТОВАР', style: head)),
              pw.Padding(padding: pw.EdgeInsets.all(4), child: pw.Text('КОЛ-ВО', style: head, textAlign: pw.TextAlign.right)),
              if (withPrices) pw.Padding(padding: pw.EdgeInsets.all(4), child: pw.Text('ЦЕНА', style: head, textAlign: pw.TextAlign.right)),
              if (withPrices) pw.Padding(padding: pw.EdgeInsets.all(4), child: pw.Text('СУММА', style: head, textAlign: pw.TextAlign.right)),
            ]),
            for (var i = 0; i < d.lines.length; i++)
              pw.TableRow(children: [
                cell('${i + 1}'),
                cell(d.lines[i].name),
                cell('${_q(d.lines[i].qty)} ${d.lines[i].unit}', align: pw.TextAlign.right),
                if (withPrices) cell(_m(d.lines[i].price), align: pw.TextAlign.right),
                if (withPrices) cell(_m(d.lines[i].sum), bold: true, align: pw.TextAlign.right),
              ]),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          pw.Text('Итого: ${_q(d.qty)} ед.', style: pw.TextStyle(fontSize: 12)),
          if (withPrices) pw.SizedBox(width: 24),
          if (withPrices) pw.Text(_m(d.total), style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        ]),
        if (withPrices && d.debt > 0.5) ...[
          pw.SizedBox(height: 4),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
            pw.Text('Оплачено: ${_m(d.paid)}   В долг: ${_m(d.debt)}', style: pw.TextStyle(fontSize: 11)),
          ]),
        ],
        pw.SizedBox(height: 36),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Принял: ${d.author} ____________', style: pw.TextStyle(fontSize: 11)),
          pw.Text('Сдал: ____________', style: pw.TextStyle(fontSize: 11)),
        ]),
      ],
    ));
    await Printing.layoutPdf(name: 'Поступление_${d.number}.pdf', onLayout: (_) async => doc.save());
  }
}

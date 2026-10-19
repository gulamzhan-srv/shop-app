// Печатные формы документов в PDF: просмотр на экране, печать, скачать/сохранить
// и отправить (WhatsApp, Telegram, почта) — кнопки внизу экрана просмотра.
//   • Поступление товаров (накладная, A4)
//   • Чек продажи (лента 80 мм)
//   • Отчёт по смене / закрытие кассы (A4)
//   • Акт сверки с покупателем или поставщиком (A4)

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/glass.dart';
import 'receipt_service.dart';
import 'report_service.dart';
import 'shift_service.dart';

/// Строка акта сверки.
class StatementRow {
  final DateTime date;
  final String text;
  final double plus; // увеличивает долг
  final double minus; // уменьшает долг (оплата)
  StatementRow(this.date, this.text, this.plus, this.minus);
}

class PrintService {
  PrintService._();
  static final PrintService instance = PrintService._();

  pw.Font? _regular;
  pw.Font? _bold;

  /// Шрифты с кириллицей и ₸ встроены в приложение (работает без интернета).
  Future<pw.ThemeData> _theme() async {
    _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
    return pw.ThemeData.withFont(base: _regular!, bold: _bold!);
  }

  Future<String> _shop() async =>
      (await SharedPreferences.getInstance()).getString('shop_name') ?? 'AVTOMAG GRS SOFT';

  String _m(double v) => '${NumberFormat('#,##0', 'ru').format(v.round()).replaceAll(' ', ' ')} ₸';
  String _q(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  String _dt(DateTime d) => DateFormat('dd.MM.yyyy HH:mm').format(d);
  String _d(DateTime d) => DateFormat('dd.MM.yyyy').format(d);

  /// Открыть экран просмотра PDF.
  Future<void> _preview(BuildContext context, String title, String fileName, Future<Uint8List> Function() build) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PdfPreviewScreen(title: title, fileName: fileName, maker: build),
    ));
  }

  pw.TextStyle get _head => pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: PdfColors.grey700);

  pw.Widget _cell(String t, {bool bold = false, pw.TextAlign align = pw.TextAlign.left, double size = 10.5}) =>
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: pw.Text(t, textAlign: align, style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null)),
      );

  pw.Widget _hcell(String t, {pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Padding(padding: pw.EdgeInsets.all(4), child: pw.Text(t, style: _head, textAlign: align));

  pw.TableBorder get _border => pw.TableBorder(
      horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      bottom: pw.BorderSide(color: PdfColors.grey600),
      top: pw.BorderSide(color: PdfColors.grey600));

  pw.Widget _header(String shop, String title, DateTime date, List<String> lines) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(shop, style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
            pw.Text(_dt(date), style: pw.TextStyle(fontSize: 11)),
          ]),
          pw.SizedBox(height: 10),
          pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          for (final l in lines) pw.Text(l, style: pw.TextStyle(fontSize: 11.5)),
          pw.SizedBox(height: 12),
        ],
      );

  // ---------------- Поступление ----------------

  Future<void> receipt(BuildContext context, ReceiptDoc d, {bool withPrices = true}) =>
      _preview(context, 'Поступление № ${d.number}', 'Поступление_${d.number}.pdf', () async {
        final shop = await _shop();
        final doc = pw.Document(theme: await _theme(), title: 'Поступление № ${d.number}', author: shop);
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(32),
          build: (_) => [
            _header(shop, 'Поступление товаров № ${d.number}', d.date, [
              'Поставщик: ${d.supplier}',
              if (d.comment != null && d.comment!.isNotEmpty) 'Комментарий: ${d.comment}',
            ]),
            pw.Table(
              border: _border,
              columnWidths: withPrices
                  ? {0: pw.FixedColumnWidth(24), 1: pw.FlexColumnWidth(5), 2: pw.FlexColumnWidth(2), 3: pw.FlexColumnWidth(2), 4: pw.FlexColumnWidth(2)}
                  : {0: pw.FixedColumnWidth(24), 1: pw.FlexColumnWidth(6), 2: pw.FlexColumnWidth(2)},
              children: [
                pw.TableRow(children: [
                  _hcell('№'),
                  _hcell('ТОВАР'),
                  _hcell('КОЛ-ВО', align: pw.TextAlign.right),
                  if (withPrices) _hcell('ЦЕНА', align: pw.TextAlign.right),
                  if (withPrices) _hcell('СУММА', align: pw.TextAlign.right),
                ]),
                for (var i = 0; i < d.lines.length; i++)
                  pw.TableRow(children: [
                    _cell('${i + 1}'),
                    _cell(d.lines[i].name),
                    _cell('${_q(d.lines[i].qty)} ${d.lines[i].unit}', align: pw.TextAlign.right),
                    if (withPrices) _cell(_m(d.lines[i].price), align: pw.TextAlign.right),
                    if (withPrices) _cell(_m(d.lines[i].sum), bold: true, align: pw.TextAlign.right),
                  ]),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
              pw.Text('Итого: ${_q(d.qty)} ед.', style: pw.TextStyle(fontSize: 12)),
              if (withPrices) pw.SizedBox(width: 24),
              if (withPrices) pw.Text(_m(d.total), style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
            ]),
            if (withPrices && d.debt > 0.5)
              pw.Padding(
                padding: pw.EdgeInsets.only(top: 4),
                child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                  pw.Text('Оплачено: ${_m(d.paid)}   В долг: ${_m(d.debt)}', style: pw.TextStyle(fontSize: 11)),
                ]),
              ),
            pw.SizedBox(height: 36),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('Принял: ${d.author} ____________', style: pw.TextStyle(fontSize: 11)),
              pw.Text('Сдал: ____________', style: pw.TextStyle(fontSize: 11)),
            ]),
          ],
        ));
        return doc.save();
      });

  // ---------------- Чек продажи (лента 80 мм) ----------------

  Future<void> check(BuildContext context, CheckRow c, List<CheckLine> lines) {
    final payment = switch (c.payment) {
      'cash' => 'Наличные',
      'kaspi' => 'Kaspi',
      'mixed' => 'Наличные ${_m(c.paidCash)} + Kaspi ${_m(c.paidKaspi)}',
      'debt' => 'В долг',
      _ => c.payment,
    };
    return _preview(context, 'Чек', 'Чек_${DateFormat('ddMMyyyy_HHmm').format(c.date)}.pdf', () async {
      final shop = await _shop();
      final doc = pw.Document(theme: await _theme(), title: 'Чек', author: shop);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: pw.EdgeInsets.all(10),
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Text(shop, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text('Товарный чек', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10)),
          pw.Text(_dt(c.date), textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9)),
          pw.Divider(),
          for (final l in lines) ...[
            pw.Text(l.name, style: pw.TextStyle(fontSize: 9.5)),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('${_q(l.qty)} × ${_m(l.price)}', style: pw.TextStyle(fontSize: 9)),
              pw.Text(_m(l.sum), style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
            ]),
            pw.SizedBox(height: 3),
          ],
          pw.Divider(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('ИТОГО', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.Text(_m(c.total), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 4),
          pw.Text('Оплата: $payment', style: pw.TextStyle(fontSize: 9)),
          if (c.customer != null) pw.Text('Покупатель: ${c.customer}', style: pw.TextStyle(fontSize: 9)),
          pw.Text('Кассир: ${c.cashier}', style: pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 8),
          pw.Text('Спасибо за покупку!', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10)),
        ]),
      ));
      return doc.save();
    });
  }

  // ---------------- Отчёт по смене (касса) ----------------

  Future<void> shift(BuildContext context, Shift sh, ShiftSummary s, String cashier) =>
      _preview(context, 'Отчёт по смене', 'Смена_${DateFormat('ddMMyyyy').format(sh.openedAt)}.pdf', () async {
        final shop = await _shop();
        final doc = pw.Document(theme: await _theme(), title: 'Отчёт по смене', author: shop);
        pw.TableRow row(String a, double v, {bool bold = false}) => pw.TableRow(children: [
              _cell(a, bold: bold),
              _cell(_m(v), bold: bold, align: pw.TextAlign.right),
            ]);
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(32),
          build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _header(shop, sh.isOpen ? 'Отчёт по смене (смена открыта)' : 'Закрытие кассы', DateTime.now(), [
              'Смена: ${_dt(sh.openedAt)} — ${sh.closedAt == null ? 'открыта' : _dt(sh.closedAt!)}',
              'Кассир: $cashier',
              'Чеков: ${s.salesCount}',
            ]),
            pw.Table(border: _border, columnWidths: {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2)}, children: [
              row('Наличные на начало смены', s.cashStart),
              row('Продажи наличными', s.cashSales),
              row('Продажи Kaspi', s.kaspiSales),
              row('Продажи в долг', s.debtSales),
              row('Оплаты долгов наличными', s.debtPaidCash),
              row('Оплаты долгов Kaspi', s.debtPaidKaspi),
              row('Приход денег в кассу', s.cashIn),
              row('Расход денег из кассы', s.cashOut),
              row('Возвраты наличными', s.cashReturns),
              row('Должно быть наличных в кассе', s.cashExpected, bold: true),
              if (sh.cashEnd != null) row('Посчитано при закрытии', sh.cashEnd!, bold: true),
              if (sh.cashEnd != null) row('Разница', sh.cashEnd! - s.cashExpected, bold: true),
            ]),
            pw.SizedBox(height: 40),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('Кассир: ____________', style: pw.TextStyle(fontSize: 11)),
              pw.Text('Проверил: ____________', style: pw.TextStyle(fontSize: 11)),
            ]),
          ]),
        ));
        return doc.save();
      });

  // ---------------- Акт сверки ----------------

  /// supplier = true — с поставщиком (долг наш), иначе с покупателем (долг нам).
  Future<void> statement(BuildContext context,
          {required String name, required bool supplier, required List<StatementRow> rows}) =>
      _preview(context, 'Акт сверки', 'Акт_сверки_$name.pdf', () async {
        final shop = await _shop();
        final doc = pw.Document(theme: await _theme(), title: 'Акт сверки', author: shop);
        final sorted = [...rows]..sort((a, b) => a.date.compareTo(b.date));
        var bal = 0.0;
        final plus = sorted.fold<double>(0, (s, r) => s + r.plus);
        final minus = sorted.fold<double>(0, (s, r) => s + r.minus);
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(32),
          build: (_) => [
            _header(shop, 'Акт сверки взаиморасчётов', DateTime.now(), [
              supplier ? 'Поставщик: $name' : 'Покупатель: $name',
            ]),
            pw.Table(
              border: _border,
              columnWidths: {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(4), 2: pw.FlexColumnWidth(2), 3: pw.FlexColumnWidth(2), 4: pw.FlexColumnWidth(2)},
              children: [
                pw.TableRow(children: [
                  _hcell('ДАТА'),
                  _hcell('ДОКУМЕНТ'),
                  _hcell(supplier ? 'ПОЛУЧЕНО' : 'ВЗЯЛ', align: pw.TextAlign.right),
                  _hcell('ОПЛАЧЕНО', align: pw.TextAlign.right),
                  _hcell('ДОЛГ', align: pw.TextAlign.right),
                ]),
                for (final r in sorted)
                  () {
                    bal += r.plus - r.minus;
                    return pw.TableRow(children: [
                      _cell(_d(r.date), size: 9.5),
                      _cell(r.text, size: 9.5),
                      _cell(r.plus > 0 ? _m(r.plus) : '', align: pw.TextAlign.right, size: 9.5),
                      _cell(r.minus > 0 ? _m(r.minus) : '', align: pw.TextAlign.right, size: 9.5),
                      _cell(_m(bal), bold: true, align: pw.TextAlign.right, size: 9.5),
                    ]);
                  }(),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Text('Всего ${supplier ? 'получено' : 'взято'}: ${_m(plus)}   Оплачено: ${_m(minus)}',
                style: pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 4),
            pw.Text(
                supplier ? 'Наш долг на ${_d(DateTime.now())}: ${_m(plus - minus)}' : 'Долг покупателя на ${_d(DateTime.now())}: ${_m(plus - minus)}',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 40),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('$shop ____________', style: pw.TextStyle(fontSize: 11)),
              pw.Text('$name ____________', style: pw.TextStyle(fontSize: 11)),
            ]),
          ],
        ));
        return doc.save();
      });
}

/// Экран просмотра PDF: листать документ, «Печать», «Отправить / Скачать».
class PdfPreviewScreen extends StatelessWidget {
  final String title;
  final String fileName;
  final Future<Uint8List> Function() maker;
  PdfPreviewScreen({super.key, required this.title, required this.fileName, required this.maker});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: title),
          Expanded(
            child: PdfPreview(
              build: (_) => maker(),
              pdfFileName: fileName,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              allowPrinting: true,
              allowSharing: true,
              loadingWidget: Center(child: CircularProgressIndicator()),
              actions: [
                PdfPreviewAction(
                  icon: Icon(Icons.download_outlined),
                  onPressed: (ctx, b, format) async {
                    // «Скачать»: стандартное окно Android — «Сохранить в Файлы / Google Диск».
                    await Printing.sharePdf(bytes: await b(format), filename: fileName);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('Внизу: печать · отправить (WhatsApp, Telegram) · скачать (сохранить в Файлы)',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          ),
        ]),
      ),
    );
  }
}

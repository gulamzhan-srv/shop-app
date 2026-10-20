// Печатные формы документов в PDF в стиле 1С: просмотр на экране, печать, скачать/сохранить
// и отправить (WhatsApp, Telegram, почта) — кнопки внизу экрана просмотра.
//   • Приходная накладная (поступление товаров, A4)
//   • Товарный чек (лента 80 мм) — логотип, реквизиты, сумма прописью, реклама внизу
//   • Расходная накладная по чеку (A4)
//   • Отчёт по смене / закрытие кассы (A4)
//   • Акт сверки с покупателем или поставщиком (A4)
// Реквизиты фирмы (название, БИН, адрес, телефон, логотип, реклама) берутся из «Реквизиты фирмы».

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../db/database.dart';
import '../ui/glass.dart';
import 'firm_service.dart';
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

/// Сумма прописью: «Двенадцать тысяч пятьсот тенге 00 тиын».
String amountInWords(double v) {
  final total = (v * 100).round();
  final t = total ~/ 100;
  final ty = total % 100;
  const ones = ['', 'один', 'два', 'три', 'четыре', 'пять', 'шесть', 'семь', 'восемь', 'девять'];
  const onesF = ['', 'одна', 'две', 'три', 'четыре', 'пять', 'шесть', 'семь', 'восемь', 'девять'];
  const teens = [
    'десять', 'одиннадцать', 'двенадцать', 'тринадцать', 'четырнадцать',
    'пятнадцать', 'шестнадцать', 'семнадцать', 'восемнадцать', 'девятнадцать'
  ];
  const tens = ['', '', 'двадцать', 'тридцать', 'сорок', 'пятьдесят', 'шестьдесят', 'семьдесят', 'восемьдесят', 'девяносто'];
  const hund = ['', 'сто', 'двести', 'триста', 'четыреста', 'пятьсот', 'шестьсот', 'семьсот', 'восемьсот', 'девятьсот'];

  String triple(int x, bool fem) {
    final parts = <String>[hund[x ~/ 100]];
    final r = x % 100;
    if (r >= 10 && r < 20) {
      parts.add(teens[r - 10]);
    } else {
      parts.add(tens[r ~/ 10]);
      parts.add((fem ? onesF : ones)[r % 10]);
    }
    return parts.where((e) => e.isNotEmpty).join(' ');
  }

  String form(int x, String a, String b, String c) {
    final r100 = x % 100;
    final r10 = x % 10;
    if (r100 >= 11 && r100 <= 19) return c;
    if (r10 == 1) return a;
    if (r10 >= 2 && r10 <= 4) return b;
    return c;
  }

  const unitNames = [
    ['', '', ''],
    ['тысяча', 'тысячи', 'тысяч'],
    ['миллион', 'миллиона', 'миллионов'],
    ['миллиард', 'миллиарда', 'миллиардов'],
  ];
  var words = '';
  if (t == 0) {
    words = 'ноль';
  } else {
    var n = t;
    var g = 0;
    final out = <String>[];
    while (n > 0 && g < 4) {
      final x = n % 1000;
      n ~/= 1000;
      if (x > 0) {
        final u = unitNames[g];
        out.insert(0, '${triple(x, g == 1)}${g > 0 ? ' ${form(x, u[0], u[1], u[2])}' : ''}');
      }
      g++;
    }
    words = out.join(' ');
  }
  final first = words[0].toUpperCase() + words.substring(1);
  return '$first тенге ${ty.toString().padLeft(2, '0')} тиын';
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

  static const _months = [
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
  ];

  String _m(double v) => '${NumberFormat('#,##0', 'ru').format(v.round())} ₸';
  String _n2(double v) => NumberFormat('#,##0.00', 'ru').format(v); // как в 1С: 12 500,00
  String _q(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll('.', ',');
  String _dt(DateTime d) => DateFormat('dd.MM.yyyy HH:mm').format(d);
  String _d(DateTime d) => DateFormat('dd.MM.yyyy').format(d);
  String _long(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year} г.';

  /// Открыть экран просмотра PDF.
  Future<void> _preview(BuildContext context, String title, String fileName, Future<Uint8List> Function() build) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PdfPreviewScreen(title: title, fileName: fileName, maker: build),
    ));
  }

  /// Номер чека: порядковый по дате.
  Future<int> _saleNo(DateTime date) async {
    final db = await AppDatabase.instance.db;
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM sales WHERE deleted = 0 AND opening = 0 AND sale_date <= ?',
        [date.millisecondsSinceEpoch]);
    return (r.first['c'] as int?) ?? 1;
  }

  pw.MemoryImage? _logo(FirmInfo f) {
    if (f.logo == null) return null;
    try {
      return pw.MemoryImage(f.logo!);
    } catch (_) {
      return null;
    }
  }

  // ---------------- Общие элементы в стиле 1С ----------------

  static final _black = PdfColors.black;
  pw.TableBorder get _grid => pw.TableBorder.all(color: _black, width: 0.7);

  pw.Widget _cell(String t, {bool bold = false, pw.TextAlign align = pw.TextAlign.left, double size = 10}) =>
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 4),
        child: pw.Text(t, textAlign: align, style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null)),
      );

  pw.Widget _hcell(String t, {pw.TextAlign align = pw.TextAlign.center}) => pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
        child: pw.Text(t, textAlign: align, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
      );

  pw.TableRow _hrow(List<pw.Widget> c) =>
      pw.TableRow(decoration: pw.BoxDecoration(color: PdfColors.grey200), children: c);

  /// Шапка документа: логотип и реквизиты фирмы.
  pw.Widget _firmBlock(FirmInfo f) {
    final logo = _logo(f);
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      if (logo != null) pw.Container(height: 54, width: 54, margin: pw.EdgeInsets.only(right: 12), child: pw.Image(logo, fit: pw.BoxFit.contain)),
      pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(f.name, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          for (final l in f.lines) pw.Text(l, style: pw.TextStyle(fontSize: 9.5, color: PdfColors.grey800)),
        ]),
      ),
    ]);
  }

  /// Заголовок как в 1С: жирная строка и толстая линия под ней.
  pw.Widget _title(String text) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(text, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 3),
        pw.Container(height: 2, color: _black),
        pw.SizedBox(height: 8),
      ]);

  /// Строка «Поставщик: …» — подпись слева, значение рядом.
  pw.Widget _party(String label, String value) => pw.Padding(
        padding: pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 78, child: pw.Text(label, style: pw.TextStyle(fontSize: 10.5))),
          pw.Expanded(child: pw.Text(value, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold))),
        ]),
      );

  String _firmLine(FirmInfo f) => [f.name, ...f.lines].join(', ');

  pw.Widget _sign(String label) => pw.Row(children: [
        pw.Text('$label ', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.Container(width: 120, height: 14, decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.7)))),
        pw.SizedBox(width: 6),
        pw.Text('/', style: pw.TextStyle(fontSize: 10)),
        pw.Container(width: 90, height: 14, decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.7)))),
        pw.Text('/', style: pw.TextStyle(fontSize: 10)),
      ]);

  /// Итоги под таблицей накладной: «Всего наименований…» и сумма прописью.
  List<pw.Widget> _totals(int count, double total, {double? qty}) => [
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          pw.Text('Итого: ', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.Text(_n2(total), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.SizedBox(height: 4),
        pw.Text('Всего наименований $count${qty == null ? '' : ', количество ${_q(qty)}'}, на сумму ${_n2(total)} ₸',
            style: pw.TextStyle(fontSize: 10.5)),
        pw.Text(amountInWords(total), style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
      ];

  // ---------------- Приходная накладная (поступление) ----------------

  Future<void> receipt(BuildContext context, ReceiptDoc d, {bool withPrices = true}) =>
      _preview(context, 'Поступление № ${d.number}', 'Приходная_накладная_${d.number}.pdf', () async {
        final f = await FirmService.instance.load();
        final doc = pw.Document(theme: await _theme(), title: 'Приходная накладная № ${d.number}', author: f.name);
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
          build: (_) => [
            _firmBlock(f),
            pw.SizedBox(height: 14),
            _title('Приходная накладная № ${d.number} от ${_long(d.date)}'),
            _party('Поставщик:', d.supplier),
            _party('Получатель:', _firmLine(f)),
            if (d.comment != null && d.comment!.isNotEmpty) _party('Основание:', d.comment!),
            pw.SizedBox(height: 8),
            pw.Table(
              border: _grid,
              columnWidths: withPrices
                  ? {
                      0: pw.FixedColumnWidth(26),
                      1: pw.FlexColumnWidth(5),
                      2: pw.FixedColumnWidth(50),
                      3: pw.FixedColumnWidth(34),
                      4: pw.FlexColumnWidth(1.7),
                      5: pw.FlexColumnWidth(1.9),
                    }
                  : {0: pw.FixedColumnWidth(26), 1: pw.FlexColumnWidth(6), 2: pw.FixedColumnWidth(60), 3: pw.FixedColumnWidth(40)},
              children: [
                _hrow([
                  _hcell('№'),
                  _hcell('Товар'),
                  _hcell('Кол-во'),
                  _hcell('Ед.'),
                  if (withPrices) _hcell('Цена'),
                  if (withPrices) _hcell('Сумма'),
                ]),
                for (var i = 0; i < d.lines.length; i++)
                  pw.TableRow(children: [
                    _cell('${i + 1}', align: pw.TextAlign.center),
                    _cell(d.lines[i].name),
                    _cell(_q(d.lines[i].qty), align: pw.TextAlign.right),
                    _cell(d.lines[i].unit, align: pw.TextAlign.center),
                    if (withPrices) _cell(_n2(d.lines[i].price), align: pw.TextAlign.right),
                    if (withPrices) _cell(_n2(d.lines[i].sum), align: pw.TextAlign.right),
                  ]),
              ],
            ),
            if (withPrices) ..._totals(d.lines.length, d.total, qty: d.qty)
            else ...[
              pw.SizedBox(height: 8),
              pw.Text('Всего наименований ${d.lines.length}, количество ${_q(d.qty)}', style: pw.TextStyle(fontSize: 10.5)),
            ],
            if (withPrices && d.debt > 0.5)
              pw.Padding(
                padding: pw.EdgeInsets.only(top: 4),
                child: pw.Text('Оплачено: ${_n2(d.paid)} ₸     В долг: ${_n2(d.debt)} ₸', style: pw.TextStyle(fontSize: 10.5)),
              ),
            pw.SizedBox(height: 34),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              _sign('Отпустил'),
              _sign('Принял'),
            ]),
            pw.SizedBox(height: 4),
            pw.Text('Принял на склад: ${d.author}', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ],
        ));
        return doc.save();
      });

  // ---------------- Товарный чек (лента 80 мм) ----------------

  String _paymentText(CheckRow c) => switch (c.payment) {
        'cash' => 'Наличные',
        'kaspi' => 'Kaspi',
        'mixed' => 'Наличные ${_m(c.paidCash)} + Kaspi ${_m(c.paidKaspi)}',
        'debt' => 'В долг',
        _ => c.payment,
      };

  Future<Uint8List> _checkBytes(FirmInfo f, CheckRow c, List<CheckLine> lines, int no) async {
    final doc = pw.Document(theme: await _theme(), title: 'Товарный чек № $no', author: f.name);
    final logo = _logo(f);
    pw.Widget line() => pw.Container(margin: pw.EdgeInsets.symmetric(vertical: 4), height: 0.8, color: _black);
    pw.Widget center(String t, {double size = 9, bool bold = false}) => pw.Text(t,
        textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null));
    final qtySum = lines.fold<double>(0, (s, l) => s + l.qty);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: pw.EdgeInsets.fromLTRB(10, 10, 10, 14),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        if (logo != null) pw.Center(child: pw.Container(height: 46, margin: pw.EdgeInsets.only(bottom: 4), child: pw.Image(logo, fit: pw.BoxFit.contain))),
        center(f.name, size: 12.5, bold: true),
        for (final l in f.lines) center(l, size: 8.5),
        line(),
        center('Товарный чек № $no', size: 11.5, bold: true),
        center('от ${_dt(c.date)}', size: 9),
        line(),
        // Шапка таблицы как в 1С
        pw.Row(children: [
          pw.Expanded(child: pw.Text('Наименование', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))),
          pw.Text('Сумма', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.Container(margin: pw.EdgeInsets.only(top: 2, bottom: 3), height: 0.5, color: _black),
        for (var i = 0; i < lines.length; i++) ...[
          pw.Text('${i + 1}. ${lines[i].name}', style: pw.TextStyle(fontSize: 9.5)),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('   ${_q(lines[i].qty)} ${lines[i].unit} × ${_n2(lines[i].price)}', style: pw.TextStyle(fontSize: 9)),
            pw.Text(_n2(lines[i].sum), style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 3),
        ],
        line(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('ИТОГО:', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.Text(_n2(c.total) + ' ₸', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.SizedBox(height: 3),
        pw.Text('Всего наименований ${lines.length}, количество ${_q(qtySum)}', style: pw.TextStyle(fontSize: 8.5)),
        pw.Text(amountInWords(c.total), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Оплата: ${_paymentText(c)}', style: pw.TextStyle(fontSize: 9)),
        if (c.customer != null) pw.Text('Покупатель: ${c.customer}', style: pw.TextStyle(fontSize: 9)),
        pw.Text('Продавец: ${c.cashier}', style: pw.TextStyle(fontSize: 9)),
        line(),
        if (f.ad.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          center(f.ad, size: 9.5, bold: true),
          pw.SizedBox(height: 4),
        ],
        center('Спасибо за покупку!', size: 10),
      ]),
    ));
    return doc.save();
  }

  Future<void> check(BuildContext context, CheckRow c, List<CheckLine> lines) async {
    final no = await _saleNo(c.date);
    if (!context.mounted) return;
    return _preview(context, 'Чек № $no', 'Чек_${DateFormat('ddMMyyyy_HHmm').format(c.date)}.pdf', () async {
      final f = await FirmService.instance.load();
      return _checkBytes(f, c, lines, no);
    });
  }

  /// Пример чека по введённым реквизитам (экран «Реквизиты фирмы»).
  Future<void> sampleCheck(BuildContext context, FirmInfo f) {
    if (f.name.trim().isEmpty) f.name = 'Название фирмы';
    final now = DateTime.now();
    final lines = [
      CheckLine('Кока-Кола 1 л', 'шт', 2, 650, 1300),
      CheckLine('Хлеб белый', 'шт', 3, 150, 450),
      CheckLine('Сахар', 'кг', 1.5, 520, 780),
    ];
    final c = CheckRow('sample', now, 'cash', 2530, 2000, 2530, 0, 'Кассир', null, null);
    return _preview(context, 'Пример чека', 'Пример_чека.pdf', () => _checkBytes(f, c, lines, 1));
  }

  // ---------------- Расходная накладная по чеку (A4) ----------------

  Future<void> saleInvoice(BuildContext context, CheckRow c, List<CheckLine> lines) async {
    final no = await _saleNo(c.date);
    if (!context.mounted) return;
    return _preview(context, 'Расходная накладная № $no', 'Расходная_накладная_$no.pdf', () async {
      final f = await FirmService.instance.load();
      final doc = pw.Document(theme: await _theme(), title: 'Расходная накладная № $no', author: f.name);
      final qty = lines.fold<double>(0, (s, l) => s + l.qty);
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
        build: (_) => [
          _firmBlock(f),
          pw.SizedBox(height: 14),
          _title('Расходная накладная № $no от ${_long(c.date)}'),
          _party('Поставщик:', _firmLine(f)),
          _party('Покупатель:', c.customer ?? 'Розничный покупатель'),
          _party('Основание:', 'Продажа, оплата: ${_paymentText(c)}'),
          pw.SizedBox(height: 8),
          pw.Table(
            border: _grid,
            columnWidths: {
              0: pw.FixedColumnWidth(26),
              1: pw.FlexColumnWidth(5),
              2: pw.FixedColumnWidth(50),
              3: pw.FixedColumnWidth(34),
              4: pw.FlexColumnWidth(1.7),
              5: pw.FlexColumnWidth(1.9),
            },
            children: [
              _hrow([_hcell('№'), _hcell('Товар'), _hcell('Кол-во'), _hcell('Ед.'), _hcell('Цена'), _hcell('Сумма')]),
              for (var i = 0; i < lines.length; i++)
                pw.TableRow(children: [
                  _cell('${i + 1}', align: pw.TextAlign.center),
                  _cell(lines[i].name),
                  _cell(_q(lines[i].qty), align: pw.TextAlign.right),
                  _cell(lines[i].unit, align: pw.TextAlign.center),
                  _cell(_n2(lines[i].price), align: pw.TextAlign.right),
                  _cell(_n2(lines[i].sum), align: pw.TextAlign.right),
                ]),
            ],
          ),
          ..._totals(lines.length, c.total, qty: qty),
          pw.SizedBox(height: 34),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            _sign('Отпустил'),
            _sign('Получил'),
          ]),
          pw.SizedBox(height: 4),
          pw.Text('Продавец: ${c.cashier}', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          if (f.ad.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Center(child: pw.Text(f.ad, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
          ],
        ],
      ));
      return doc.save();
    });
  }

  // ---------------- Отчёт по смене (касса) ----------------

  Future<void> shift(BuildContext context, Shift sh, ShiftSummary s, String cashier) =>
      _preview(context, 'Отчёт по смене', 'Смена_${DateFormat('ddMMyyyy').format(sh.openedAt)}.pdf', () async {
        final f = await FirmService.instance.load();
        final doc = pw.Document(theme: await _theme(), title: 'Отчёт по смене', author: f.name);
        pw.TableRow row(String a, double v, {bool bold = false}) => pw.TableRow(children: [
              _cell(a, bold: bold),
              _cell(_n2(v), bold: bold, align: pw.TextAlign.right),
            ]);
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
          build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _firmBlock(f),
            pw.SizedBox(height: 14),
            _title(sh.isOpen ? 'Отчёт по смене (смена открыта)' : 'Закрытие кассовой смены'),
            _party('Смена:', '${_dt(sh.openedAt)} — ${sh.closedAt == null ? 'открыта' : _dt(sh.closedAt!)}'),
            _party('Кассир:', cashier),
            _party('Чеков:', '${s.salesCount}'),
            pw.SizedBox(height: 8),
            pw.Table(border: _grid, columnWidths: {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.6)}, children: [
              _hrow([_hcell('Показатель', align: pw.TextAlign.left), _hcell('Сумма, ₸', align: pw.TextAlign.right)]),
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
              _sign('Кассир'),
              _sign('Проверил'),
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
        final f = await FirmService.instance.load();
        final doc = pw.Document(theme: await _theme(), title: 'Акт сверки', author: f.name);
        final sorted = [...rows]..sort((a, b) => a.date.compareTo(b.date));
        var bal = 0.0;
        final plus = sorted.fold<double>(0, (s, r) => s + r.plus);
        final minus = sorted.fold<double>(0, (s, r) => s + r.minus);
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
          build: (_) => [
            _firmBlock(f),
            pw.SizedBox(height: 14),
            _title('Акт сверки взаиморасчётов на ${_long(DateTime.now())}'),
            _party('Организация:', _firmLine(f)),
            _party(supplier ? 'Поставщик:' : 'Покупатель:', name),
            pw.SizedBox(height: 8),
            pw.Table(
              border: _grid,
              columnWidths: {0: pw.FlexColumnWidth(1.8), 1: pw.FlexColumnWidth(4), 2: pw.FlexColumnWidth(2), 3: pw.FlexColumnWidth(2), 4: pw.FlexColumnWidth(2)},
              children: [
                _hrow([
                  _hcell('Дата'),
                  _hcell('Документ'),
                  _hcell(supplier ? 'Получено' : 'Взял'),
                  _hcell('Оплачено'),
                  _hcell('Долг'),
                ]),
                for (final r in sorted)
                  () {
                    bal += r.plus - r.minus;
                    return pw.TableRow(children: [
                      _cell(_d(r.date), size: 9.5),
                      _cell(r.text, size: 9.5),
                      _cell(r.plus > 0 ? _n2(r.plus) : '', align: pw.TextAlign.right, size: 9.5),
                      _cell(r.minus > 0 ? _n2(r.minus) : '', align: pw.TextAlign.right, size: 9.5),
                      _cell(_n2(bal), bold: true, align: pw.TextAlign.right, size: 9.5),
                    ]);
                  }(),
                pw.TableRow(children: [
                  _cell(''),
                  _cell('Итого', bold: true),
                  _cell(_n2(plus), bold: true, align: pw.TextAlign.right),
                  _cell(_n2(minus), bold: true, align: pw.TextAlign.right),
                  _cell(_n2(plus - minus), bold: true, align: pw.TextAlign.right),
                ]),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Text(
                supplier
                    ? 'Наш долг перед поставщиком на ${_d(DateTime.now())}: ${_n2(plus - minus)} ₸'
                    : 'Долг покупателя на ${_d(DateTime.now())}: ${_n2(plus - minus)} ₸',
                style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold)),
            pw.Text(amountInWords((plus - minus).abs()), style: pw.TextStyle(fontSize: 10.5)),
            pw.SizedBox(height: 40),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              _sign(f.name.length > 18 ? 'Фирма' : f.name),
              _sign(name.length > 18 ? (supplier ? 'Поставщик' : 'Покупатель') : name),
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

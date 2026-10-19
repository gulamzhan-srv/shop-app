// Смена: открыть, итоги, приход/расход денег, закрыть кассу.

import 'package:flutter/material.dart';

import '../db/repo.dart';
import '../services/print_service.dart';
import '../services/sale_service.dart';
import '../services/shift_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';

class ShiftScreen extends StatefulWidget {
  ShiftScreen({super.key});
  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  Shift? _shift;
  ShiftSummary? _sum;
  List<Map<String, Object?>> _sales = [];
  bool _loading = true;
  final _cashStart = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sh = await ShiftService.instance.current();
    ShiftSummary? s;
    var sales = <Map<String, Object?>>[];
    if (sh != null) {
      s = await ShiftService.instance.summary(sh.id);
      sales = await SaleService.instance.shiftSales(sh.id);
    }
    if (mounted) {
      setState(() {
        _shift = sh;
        _sum = s;
        _sales = sales;
        _loading = false;
      });
    }
  }

  Future<void> _open() async {
    await ShiftService.instance.open(parseNum(_cashStart.text) ?? 0);
    _load();
  }

  Future<void> _cashOp(String kind) async {
    final amount = TextEditingController();
    final who = TextEditingController();
    final comment = TextEditingController();
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(kind == 'in' ? 'Приход денег в кассу' : 'Расход денег из кассы'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Сумма, ₸'),
          ),
          TextField(
            controller: who,
            decoration: InputDecoration(labelText: kind == 'in' ? 'От кого' : 'Кому (например, поставщику)'),
          ),
          TextField(controller: comment, decoration: InputDecoration(labelText: 'Комментарий')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Сохранить')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await ShiftService.instance.cashOp(
      kind: kind,
      amount: parseNum(amount.text) ?? 0,
      counterparty: who.text.trim().isEmpty ? null : who.text.trim(),
      comment: comment.text.trim().isEmpty ? null : comment.text.trim(),
    );
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
    _load();
  }

  Future<void> _close() async {
    final expected = _sum!.cashExpected;
    final counted = TextEditingController(text: qtyText(expected.roundToDouble()));
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setD) {
        final diff = (parseNum(counted.text) ?? 0) - expected;
        return AlertDialog(
          title: Text('Закрыть кассу'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Должно быть наличных: ${money(expected)}'),
            SizedBox(height: 8),
            TextField(
              controller: counted,
              onChanged: (_) => setD(() {}),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Посчитали в кассе, ₸'),
            ),
            SizedBox(height: 8),
            Text(
              diff.abs() < 0.5
                  ? 'Сходится'
                  : diff > 0
                      ? 'Излишек: ${money(diff)}'
                      : 'Недостача: ${money(-diff)}',
              style: TextStyle(
                  color: diff.abs() < 0.5 ? Colors.green : Colors.orange, fontWeight: FontWeight.w700),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Закрыть смену')),
          ],
        );
      }),
    );
    if (ok != true) return;
    await ShiftService.instance.close(_shift!.id, parseNum(counted.text) ?? 0);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _row(String label, double v, {Color? color, bool bold = false}) => Padding(
        padding: EdgeInsets.symmetric(vertical: 5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(color: AppColors.textDim)),
          Text(money(v),
              style: TextStyle(
                  color: color ?? AppColors.text, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );

  String _payName(String p) => paymentName(p);

  /// Отчёт по смене в PDF: просмотр, печать, отправить.
  Future<void> _print() async {
    final sh = _shift, sum = _sum;
    if (sh == null || sum == null) return;
    final rows = await Repo.instance.list('employees', where: 'id = ?', args: [sh.openedBy]);
    if (!mounted) return;
    await PrintService.instance.shift(context, sh, sum, rows.isEmpty ? '' : rows.first['name'] as String);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Касса · смена', actions: [
            if (_shift != null && _sum != null)
              IconButton(
                onPressed: _print,
                icon: Icon(Icons.picture_as_pdf_outlined, color: AppColors.text),
                tooltip: 'Отчёт по смене (PDF)',
              ),
          ]),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : _shift == null
                    ? _openView()
                    : _openedView(),
          ),
        ]),
      ),
    );
  }

  Widget _openView() => ListView(padding: EdgeInsets.all(16), children: [
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Смена закрыта',
                style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
            SizedBox(height: 6),
            Text('Введите, сколько наличных сейчас в кассе.',
                style: TextStyle(color: AppColors.textDim)),
            SizedBox(height: 14),
            TextField(
              controller: _cashStart,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: AppColors.text),
              decoration: glassInput('Наличные на начало, ₸', hint: '0'),
            ),
            SizedBox(height: 14),
            AccentButton(label: 'Открыть смену', onPressed: _open),
          ]),
        ),
      ]);

  Widget _openedView() {
    final s = _sum!;
    return ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Text('Открыта ${dateTimeText(_shift!.openedAt)} · ${_shift!.openedBy}',
          style: TextStyle(color: AppColors.textDim, fontSize: 13)),
      SizedBox(height: 10),
      GlassCard(
        child: Column(children: [
          _row('Выручка (${s.salesCount} продаж)', s.revenue, bold: true),
          _row('Наличные', s.cashSales),
          _row('Kaspi', s.kaspiSales),
          _row('В долг', s.debtSales, color: AppColors.warn),
          if (s.debtPaidCash + s.debtPaidKaspi > 0) _row('Оплаты долгов', s.debtPaidCash + s.debtPaidKaspi),
          _row('Приход денег', s.cashIn),
          _row('Расход денег', s.cashOut),
          if (s.cashReturns > 0) _row('Возвраты наличными', s.cashReturns),
          Divider(color: AppColors.overlay(0.24)),
          _row('Наличные в кассе', s.cashExpected, color: AppColors.accent, bold: true),
        ]),
      ),
      SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _cashOp('in'),
            icon: Icon(Icons.south_west),
            label: Text('Приход'),
            style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent, minimumSize: Size.fromHeight(50)),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _cashOp('out'),
            icon: Icon(Icons.north_east),
            label: Text('Расход'),
            style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.warn, minimumSize: Size.fromHeight(50)),
          ),
        ),
      ]),
      SizedBox(height: 16),
      if (_sales.isNotEmpty)
        Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Продажи смены',
              style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 16)),
        ),
      for (final r in _sales)
        Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: GlassCard(
            radius: 16,
            padding: EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Text(
                  '${DateTime.fromMillisecondsSinceEpoch(r['sale_date'] as int).toString().substring(11, 16)} · '
                  '${_payName(r['payment'] as String)}'
                  '${r['customer'] != null ? ' · ${r['customer']}' : ''}',
                  style: TextStyle(color: AppColors.textDim),
                ),
              ),
              Text(money((r['total'] as num).toDouble()),
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      SizedBox(height: 12),
      AccentButton(label: 'Закрыть кассу', onPressed: _close),
    ]);
  }
}

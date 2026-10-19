// Поступления в виде накладных: № документа, автор, статус, дата, поставщик, сумма,
// таблица «Товар · Кол-во × Цена · Сумма», итого и кнопки «Открыть» / «Печать».
// Сверху поиск (поставщик или №), период и итоги: сколько документов и на какую сумму.

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/print_service.dart';
import '../services/receipt_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';
import 'receipt_edit_screen.dart';

class ReceiptsScreen extends StatefulWidget {
  ReceiptsScreen({super.key});
  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  final bool _manager = AuthService.instance.current?.isManager ?? false;
  final _q = TextEditingController();
  late DateTime _from = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _to = DateTime.now();
  List<ReceiptDoc> _items = [];
  bool _loading = true;
  String? _open; // раскрытая накладная (первая раскрыта по умолчанию)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final to = DateTime(_to.year, _to.month, _to.day).add(Duration(days: 1));
    final l = await ReceiptService.instance.docs(_from, to, query: _q.text);
    if (mounted) {
      setState(() {
        _items = l;
        _loading = false;
        if (_open == null && l.isNotEmpty) _open = l.first.id;
      });
    }
  }

  Future<void> _period() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (r == null) return;
    _from = r.start;
    _to = r.end;
    _load();
  }

  Future<void> _edit(String? id) async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => ReceiptEditScreen(receiptId: id)));
    if (changed == true) _load();
  }

  Future<void> _print(ReceiptDoc d) async {
    try {
      await PrintService.instance.printReceipt(d, withPrices: _manager);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось подготовить печать: $e')));
      }
    }
  }

  Widget _kpi(String label, String value, Color c) => Expanded(
        child: Container(
          padding: EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: c.withOpacity(0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.withOpacity(0.45), width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13)),
            SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      );

  Widget _badge(String t, Color c) => Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12.5)),
      );

  Widget _btn(String label, IconData icon, Color fg, Color bg, VoidCallback onTap) => Expanded(
        child: SizedBox(
          height: 44,
          child: FilledButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: FilledButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: fg,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ),
      );

  Widget _doc(ReceiptDoc d) {
    final open = _open == d.id;
    final dim = TextStyle(color: AppColors.textDim, fontSize: 12.5);
    final head = TextStyle(color: AppColors.textDim, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.4);
    return GlassCard(
      radius: 20,
      padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => setState(() => _open = open ? null : d.id),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('№ ${d.number}', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
          SizedBox(width: 8),
          Expanded(
            child: Text(d.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
          ),
          if (d.debt > 0.5) ...[_badge('в долг', AppColors.danger), SizedBox(width: 6)],
          _badge('проведён', Color(0xFF2563EB)),
        ]),
        SizedBox(height: 2),
        Text('${dateTimeText(d.date)} · ${d.lines.length} поз. · ${qtyText(d.qty)} ед.', style: dim),
        SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: Text(d.supplier,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          if (_manager)
            Text(money(d.total), style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
        if (open) ...[
          Divider(height: 18, color: AppColors.overlay(0.12)),
          Row(children: [
            Expanded(flex: 5, child: Text('ТОВАР', style: head)),
            Expanded(
                flex: 4,
                child: Text(_manager ? 'КОЛ-ВО × ЦЕНА' : 'КОЛ-ВО', textAlign: TextAlign.right, style: head)),
            if (_manager) Expanded(flex: 3, child: Text('СУММА', textAlign: TextAlign.right, style: head)),
          ]),
          for (final l in d.lines) ...[
            Divider(height: 12, color: AppColors.overlay(0.08)),
            Row(children: [
              Expanded(
                flex: 5,
                child: Text(l.name, style: TextStyle(color: AppColors.text, fontSize: 14.5)),
              ),
              Expanded(
                flex: 4,
                child: Text(_manager ? '${qtyText(l.qty)} × ${money(l.price)}' : '${qtyText(l.qty)} ${l.unit}',
                    textAlign: TextAlign.right, style: TextStyle(color: AppColors.textDim, fontSize: 13.5)),
              ),
              if (_manager)
                Expanded(
                  flex: 3,
                  child: Text(money(l.sum),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: AppColors.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
                ),
            ]),
          ],
          Divider(height: 16, thickness: 2, color: AppColors.overlay(0.12)),
          Row(children: [
            Expanded(
                flex: 5,
                child: Text('Итого', style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w800))),
            Expanded(
                flex: 4,
                child: Text('${qtyText(d.qty)} ед.',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w800))),
            if (_manager)
              Expanded(
                  flex: 3,
                  child: Text(money(d.total),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w800))),
          ]),
          if (_manager && d.debt > 0.5)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Оплачено ${money(d.paid)} · в долг ${money(d.debt)}',
                  style: TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          SizedBox(height: 6),
          Text.rich(TextSpan(children: [
            TextSpan(text: 'Принял: ', style: dim),
            TextSpan(text: d.author, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13)),
          ])),
          SizedBox(height: 10),
          Row(children: [
            _btn(_manager ? 'Изменить' : 'Открыть', _manager ? Icons.edit_outlined : Icons.visibility_outlined,
                AppColors.accent, AppColors.accent.withOpacity(0.1), () => _edit(d.id)),
            SizedBox(width: 10),
            _btn('Печать', Icons.print_outlined, Color(0xFFC2410C), Color(0xFFFFF4E5), () => _print(d)),
          ]),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<double>(0, (s, d) => s + d.total);
    return Scaffold(
      floatingActionButton: !_manager
          ? null
          : FloatingActionButton(
              onPressed: () => _edit(null),
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.onAccent,
              tooltip: 'Новое поступление',
              child: Icon(Icons.add, size: 30),
            ),
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Поступления'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: EdgeInsets.fromLTRB(14, 0, 14, 96), children: [
                TextField(
                  controller: _q,
                  onChanged: (_) => _load(),
                  style: TextStyle(color: AppColors.text, fontSize: 16),
                  decoration: glassInput('Поставщик или №', suffix: Icon(Icons.search, color: AppColors.textDim))
                      .copyWith(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13)),
                ),
                SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _period,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: AppColors.overlay(0.06), borderRadius: BorderRadius.circular(10)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.event_outlined, size: 18, color: AppColors.accent),
                        SizedBox(width: 6),
                        Text('${dateText(_from).substring(0, 5)} – ${dateText(_to).substring(0, 5)}',
                            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
                SizedBox(height: 10),
                Row(children: [
                  _kpi('Документов', '${_items.length}', Color(0xFF2563EB)),
                  if (_manager) ...[SizedBox(width: 10), _kpi('На сумму', money(total), Color(0xFF16A34A))],
                ]),
                SizedBox(height: 12),
                if (_loading)
                  Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
                else if (_items.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 30),
                    child: Center(child: Text('За период поступлений нет', style: TextStyle(color: AppColors.textDim))),
                  ),
                for (final d in _items) Padding(padding: EdgeInsets.only(bottom: 10), child: _doc(d)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

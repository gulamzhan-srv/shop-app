// Отчёты (хозяин и администратор) за выбранный период:
// товары, чеки, клиенты, самые продаваемые, самые маржинальные.

import 'package:flutter/material.dart';

import '../services/report_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';
import 'checks_screen.dart';

class ReportsScreen extends StatefulWidget {
  /// Какая вкладка открыта сразу: 0 Товары, 1 Чеки, 2 Клиенты, 3 Топ продаж, 4 Маржа.
  final int initialTab;
  ReportsScreen({super.key, this.initialTab = 0});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime _from;
  late DateTime _to; // не включительно
  String _preset = 'month';

  List<ProductStat>? _products;
  List<ProductStat>? _top;
  List<ProductStat>? _margin;
  List<CheckRow>? _checks;
  List<CustomerStat>? _customers;

  @override
  void initState() {
    super.initState();
    _setPreset('month');
  }

  void _setPreset(String p) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    _preset = p;
    switch (p) {
      case 'day':
        _from = today;
        _to = today.add(Duration(days: 1));
      case 'week':
        _from = today.subtract(Duration(days: today.weekday - 1));
        _to = _from.add(Duration(days: 7));
      case 'year':
        _from = DateTime(n.year);
        _to = DateTime(n.year + 1);
      default:
        _from = DateTime(n.year, n.month);
        _to = DateTime(n.year, n.month + 1);
    }
    _load();
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to.subtract(Duration(days: 1))),
    );
    if (r == null) return;
    _preset = 'custom';
    _from = DateTime(r.start.year, r.start.month, r.start.day);
    _to = DateTime(r.end.year, r.end.month, r.end.day).add(Duration(days: 1));
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _products = _top = _margin = null;
      _checks = null;
      _customers = null;
    });
    final rs = ReportService.instance;
    final p = await rs.products(_from, _to);
    final t = await rs.products(_from, _to, orderBy: 'qty');
    final m = await rs.products(_from, _to, orderBy: 'profit');
    final c = await rs.checks(_from, _to);
    final cu = await rs.customers(_from, _to);
    if (!mounted) return;
    setState(() {
      _products = p;
      _top = t.take(20).toList();
      _margin = m.take(20).toList();
      _checks = c;
      _customers = cu;
    });
  }

  Widget _presetBtn(String id, String label) {
    final on = _preset == id;
    return Padding(
      padding: EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: on,
        showCheckmark: false,
        onSelected: (_) => _setPreset(id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _products ?? <ProductStat>[];
    final sum = p.fold<double>(0, (s, x) => s + x.sum);
    final cost = p.fold<double>(0, (s, x) => s + x.cost);
    return DefaultTabController(
      initialIndex: widget.initialTab,
      length: 5,
      child: Scaffold(
        body: GlassBackground(
          child: Column(children: [
            GlassHeader(title: 'Отчёты'),
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, padding: EdgeInsets.symmetric(horizontal: 16), children: [
                _presetBtn('day', 'День'),
                _presetBtn('week', 'Неделя'),
                _presetBtn('month', 'Месяц'),
                _presetBtn('year', 'Год'),
                Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: ActionChip(
                    avatar: Icon(Icons.date_range, size: 18),
                    label: Text(_preset == 'custom'
                        ? '${dateText(_from)} – ${dateText(_to.subtract(Duration(days: 1)))}'
                        : 'Свои даты'),
                    onPressed: _pickRange,
                  ),
                ),
              ]),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: GlassCard(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(children: [
                  _sumBox('Выручка', money(sum)),
                  _sumBox('Себестоимость', money(cost)),
                  _sumBox('Прибыль', money(sum - cost), accent: true),
                ]),
              ),
            ),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.textDim,
              indicatorColor: AppColors.accent,
              tabs: [
                Tab(text: 'Товары'),
                Tab(text: 'Чеки'),
                Tab(text: 'Клиенты'),
                Tab(text: 'Топ продаж'),
                Tab(text: 'Маржа'),
              ],
            ),
            Expanded(
              child: _products == null
                  ? Center(child: CircularProgressIndicator())
                  : TabBarView(children: [
                      _productList(_products!, showMarkup: false),
                      _checkList(),
                      _customerList(),
                      _productList(_top!, showMarkup: false, byQty: true),
                      _productList(_margin!, showMarkup: true),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sumBox(String label, String value, {bool accent = false}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 11)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    color: accent ? AppColors.accent : AppColors.text, fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ]),
      );

  Widget _empty() => Center(child: Text('За этот период продаж нет', style: TextStyle(color: AppColors.textDim)));

  Widget _productList(List<ProductStat> l, {required bool showMarkup, bool byQty = false}) {
    if (l.isEmpty) return _empty();
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: l.length,
      itemBuilder: (_, i) {
        final x = l[i];
        return Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: GlassCard(
            radius: 12,
            padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              SizedBox(
                width: 26,
                child: Text('${i + 1}', style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(x.name, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                  Text(
                      '${qtyText(x.qty)} ${x.unit} · выручка ${money(x.sum)} · себест. ${money(x.cost)}',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(byQty ? '${qtyText(x.qty)} ${x.unit}' : money(x.profit),
                    style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
                Text(showMarkup ? 'наценка ${x.markup.round()}%' : (byQty ? money(x.sum) : 'прибыль'),
                    style: TextStyle(color: AppColors.textDim, fontSize: 11)),
              ]),
            ]),
          ),
        );
      },
    );
  }

  Widget _checkList() {
    final l = _checks!;
    if (l.isEmpty) return _empty();
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text('Чеков: ${l.length} · средний чек ${money(l.fold<double>(0, (s, c) => s + c.total) / l.length)}',
              style: TextStyle(color: AppColors.textDim)),
        ),
        for (final c in l) CheckTile(check: c),
      ],
    );
  }

  Widget _customerList() {
    final l = _customers!;
    if (l.isEmpty) {
      return Center(
          child: Text('Покупок с указанным покупателем нет', style: TextStyle(color: AppColors.textDim)));
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final c in l)
          Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: GlassCard(
              radius: 12,
              padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.name, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                    Text('${c.phone ?? ''} · чеков: ${c.checks}',
                        style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(money(c.sum), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
                  if (c.owed > 0.5)
                    Text('долг ${money(c.owed)}', style: TextStyle(color: AppColors.warn, fontSize: 12)),
                ]),
              ]),
            ),
          ),
      ],
    );
  }
}

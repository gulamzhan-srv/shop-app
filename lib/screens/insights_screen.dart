// Анализ для хозяина: Автозаявка, Не продаются, Ходовые, Топ, Долги.

import 'package:flutter/material.dart';

import '../services/debt_service.dart';
import '../services/insights_service.dart';
import '../services/supplier_debt_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';

class InsightsScreen extends StatelessWidget {
  final int initialTab;
  InsightsScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      initialIndex: initialTab,
      child: Scaffold(
        body: GlassBackground(
          child: Column(children: [
            GlassHeader(title: 'Анализ товаров'),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.textDim,
              indicatorColor: AppColors.accent,
              labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              tabs: [
                Tab(text: 'Автозаявка'),
                Tab(text: 'Не продаются'),
                Tab(text: 'Ходовые'),
                Tab(text: 'Топ'),
                Tab(text: 'Долги'),
              ],
            ),
            Expanded(
              child: TabBarView(children: [
                _AutoOrderTab(),
                _DeadTab(),
                _FrequentTab(),
                _TopTab(),
                _DebtsTab(),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------- общие элементы ----------

Widget _loading() => Center(child: CircularProgressIndicator());

Widget _empty(String t) => Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
      ),
    );

Widget _summary(String label, String value, {Color? color, String? note}) => GlassCard(
      radius: 14,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            if (note != null) Text(note, style: TextStyle(color: AppColors.textDim, fontSize: 11)),
          ]),
        ),
        Text(value, style: TextStyle(color: color ?? AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
      ]),
    );

/// Строка списка: слева название и пояснение, справа крупное значение.
Widget _row(String title, String sub, String value, {Color? color, String? value2}) => Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 15)),
            Text(sub, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          ]),
        ),
        SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(value, style: TextStyle(color: color ?? AppColors.accent, fontWeight: FontWeight.w800, fontSize: 17)),
          if (value2 != null) Text(value2, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        ]),
      ]),
    );

Widget _list(List<Widget> rows) => GlassCard(
      radius: 12,
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, color: AppColors.overlay(0.08)),
          rows[i],
        ],
      ]),
    );

Widget _periodChips(int days, ValueChanged<int> onChanged, {List<int> options = const [30, 90, 365]}) => Wrap(
      spacing: 6,
      children: [
        for (final d in options)
          ChoiceChip(
            label: Text(d == 365 ? 'Год' : '$d дней'),
            selected: d == days,
            onSelected: (_) => onChanged(d),
          ),
      ],
    );

// ---------- Автозаявка ----------

class _AutoOrderTab extends StatefulWidget {
  @override
  State<_AutoOrderTab> createState() => _AutoOrderTabState();
}

class _AutoOrderTabState extends State<_AutoOrderTab> {
  List<OrderSuggestion>? _items;

  @override
  void initState() {
    super.initState();
    InsightsService.instance.autoOrder().then((l) {
      if (mounted) setState(() => _items = l);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = _items;
    if (l == null) return _loading();
    final total = l.fold<double>(0, (s, x) => s + x.sum);
    return ListView(padding: EdgeInsets.fromLTRB(12, 10, 12, 24), children: [
      _summary('Заказать на сумму', money(total), note: '${l.length} товаров · по последней цене закупки'),
      SizedBox(height: 6),
      Text('Мин. остаток задаётся в карточке товара. Предлагаем докупить до двух минимумов '
          '(или на 2 недели продаж). Закончившиеся, но продающиеся товары — по продажам за 30 дней.',
          style: TextStyle(color: AppColors.textDim, fontSize: 12)),
      SizedBox(height: 8),
      if (l.isEmpty)
        _empty('Докупать пока нечего')
      else
        _list([
          for (final x in l)
            _row(
              x.name,
              '${x.reason} · ост. ${qtyText(x.stock)}${x.minStock > 0 ? ' / мин. ${qtyText(x.minStock)}' : ''}'
                  ' · продано за 30 дн. ${qtyText(x.sold30)}',
              '${qtyText(x.qty)} ${x.unit}',
              color: x.stock <= 0 ? AppColors.danger : AppColors.warn,
              value2: x.cost == null ? null : money(x.sum),
            ),
        ]),
    ]);
  }
}

// ---------- Не продаются ----------

class _DeadTab extends StatefulWidget {
  @override
  State<_DeadTab> createState() => _DeadTabState();
}

class _DeadTabState extends State<_DeadTab> {
  int _days = 30;
  List<DeadItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await InsightsService.instance.deadStock(days: _days);
    if (mounted) setState(() => _items = l);
  }

  @override
  Widget build(BuildContext context) {
    final l = _items;
    if (l == null) return _loading();
    final total = l.fold<double>(0, (s, x) => s + x.stockSum);
    return ListView(padding: EdgeInsets.fromLTRB(12, 10, 12, 24), children: [
      _periodChips(_days, (d) {
        _days = d;
        _load();
      }, options: [30, 60, 90]),
      SizedBox(height: 8),
      _summary('Лежит без продаж', money(total), color: AppColors.warn, note: '${l.length} товаров · по цене закупки'),
      SizedBox(height: 8),
      if (l.isEmpty)
        _empty('Все товары на складе продаются')
      else
        _list([
          for (final x in l)
            _row(
              x.name,
              x.lastSale == null ? 'ни разу не продавался' : 'последняя продажа ${dateText(x.lastSale!)}',
              '${qtyText(x.stock)} ${x.unit}',
              color: AppColors.warn,
              value2: money(x.stockSum),
            ),
        ]),
    ]);
  }
}

// ---------- Ходовые ----------

class _FrequentTab extends StatefulWidget {
  @override
  State<_FrequentTab> createState() => _FrequentTabState();
}

class _FrequentTabState extends State<_FrequentTab> {
  int _days = 30;
  List<FrequentItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await InsightsService.instance.frequent(days: _days);
    if (mounted) setState(() => _items = l);
  }

  @override
  Widget build(BuildContext context) {
    final l = _items;
    if (l == null) return _loading();
    final weeks = _days / 7;
    return ListView(padding: EdgeInsets.fromLTRB(12, 10, 12, 24), children: [
      _periodChips(_days, (d) {
        _days = d;
        _load();
      }, options: [7, 30, 90]),
      SizedBox(height: 8),
      if (l.isEmpty)
        _empty('За период продаж не было')
      else
        _list([
          for (final x in l)
            _row(
              x.name,
              'продавался ${x.days} из $_days дн. · ${(x.checks / weeks).toStringAsFixed(1).replaceAll('.', ',')} чеков в неделю',
              '${qtyText(x.qty)} ${x.unit}',
              value2: money(x.sum),
            ),
        ]),
    ]);
  }
}

// ---------- Топ клиентов и поставщиков ----------

class _TopTab extends StatefulWidget {
  @override
  State<_TopTab> createState() => _TopTabState();
}

class _TopTabState extends State<_TopTab> {
  int _days = 90;
  List<TopRow>? _cust;
  List<TopRow>? _sup;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await InsightsService.instance.topCustomers(days: _days);
    final s = await InsightsService.instance.topSuppliers(days: _days);
    if (mounted) {
      setState(() {
        _cust = c;
        _sup = s;
      });
    }
  }

  Widget _block(String title, List<TopRow> l, String countWord) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(2, 12, 0, 6),
            child: Text(title, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          if (l.isEmpty)
            Text('Нет данных за период', style: TextStyle(color: AppColors.textDim))
          else
            _list([
              for (var i = 0; i < l.length; i++)
                _row('${i + 1}. ${l[i].name}', '${l[i].count} $countWord', money(l[i].sum)),
            ]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (_cust == null || _sup == null) return _loading();
    return ListView(padding: EdgeInsets.fromLTRB(12, 10, 12, 24), children: [
      _periodChips(_days, (d) {
        _days = d;
        _load();
      }),
      _block('Топ клиентов (покупки с именем клиента)', _cust!, 'покупок'),
      _block('Топ поставщиков', _sup!, 'поступлений'),
    ]);
  }
}

// ---------- Долги ----------

class _DebtsTab extends StatefulWidget {
  @override
  State<_DebtsTab> createState() => _DebtsTabState();
}

class _DebtsTabState extends State<_DebtsTab> {
  List<CustomerDebt>? _cust;
  List<SupplierDebt>? _sup;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await DebtService.instance.byCustomer(onlyOwing: true);
    final s = await SupplierDebtService.instance.bySupplier(onlyOwing: true);
    if (mounted) {
      setState(() {
        _cust = c;
        _sup = s;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cust == null || _sup == null) return _loading();
    final toUs = _cust!.fold<double>(0, (s, x) => s + x.owed);
    final weOwe = _sup!.fold<double>(0, (s, x) => s + x.owed);
    return ListView(padding: EdgeInsets.fromLTRB(12, 10, 12, 24), children: [
      Row(children: [
        Expanded(child: _summary('Нам должны', money(toUs), color: AppColors.accent)),
        SizedBox(width: 8),
        Expanded(child: _summary('Мы должны', money(weOwe), color: AppColors.danger)),
      ]),
      SizedBox(height: 6),
      _summary('Разница', money(toUs - weOwe), color: toUs >= weOwe ? AppColors.accent : AppColors.danger),
      Padding(
        padding: EdgeInsets.fromLTRB(2, 12, 0, 6),
        child: Text('Нам должны — клиенты', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
      ),
      if (_cust!.isEmpty)
        Text('Нет долгов', style: TextStyle(color: AppColors.textDim))
      else
        _list([
          for (final c in _cust!)
            _row(c.name, c.nearestDue == null ? 'без срока' : (c.overdue ? 'просрочен' : 'до ${dateText(c.nearestDue!)}'),
                money(c.owed),
                color: c.soon ? AppColors.warn : AppColors.accent),
        ]),
      Padding(
        padding: EdgeInsets.fromLTRB(2, 12, 0, 6),
        child: Text('Мы должны — поставщикам', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
      ),
      if (_sup!.isEmpty)
        Text('Нет долгов', style: TextStyle(color: AppColors.textDim))
      else
        _list([
          for (final s in _sup!)
            _row(s.name, s.nearestDue == null ? 'без срока' : (s.overdue ? 'просрочен' : 'до ${dateText(s.nearestDue!)}'),
                money(s.owed),
                color: AppColors.danger),
        ]),
    ]);
  }
}

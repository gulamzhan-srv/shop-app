// Аналитика хозяина на главной: период, продажи со сравнением, столбики, KPI-блоки, склад.

import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';
import 'debts_screen.dart';
import 'returns_screen.dart';
import 'supplier_debts_screen.dart';

class AnalyticsView extends StatefulWidget {
  AnalyticsView({super.key});
  @override
  State<AnalyticsView> createState() => AnalyticsViewState();
}

class AnalyticsViewState extends State<AnalyticsView> {
  Period _period = Period.week;
  Dashboard? _d;
  List<StockItem>? _stock; // раскрытый список склада
  bool _stockOpen = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Перезагрузить цифры (кнопка «Обновить» на главной).
  String? _error;

  Future<void> reload() async {
    try {
      final d = await AnalyticsService.instance.load(_period);
      final st = _stockOpen ? await AnalyticsService.instance.stock() : null;
      if (mounted) {
        setState(() {
          _d = d;
          _stock = st;
          _error = null;
        });
      }
    } catch (e) {
      // Вместо бесконечного кольца — показываем ошибку.
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _toggleStock() async {
    if (_stockOpen) {
      setState(() => _stockOpen = false);
      return;
    }
    final st = await AnalyticsService.instance.stock();
    if (mounted) {
      setState(() {
        _stock = st;
        _stockOpen = true;
      });
    }
  }

  /// 86400 → «86,4k», 1250000 → «1,25M»
  String _short(double v) {
    if (v.abs() >= 1e6) return '${(v / 1e6).toStringAsFixed(2).replaceAll('.', ',')}M';
    if (v.abs() >= 1e3) return '${(v / 1e3).toStringAsFixed(1).replaceAll('.', ',')}k';
    return v.round().toString();
  }

  String _pct(double? p) => p == null ? '—' : '${p >= 0 ? '+' : ''}${p.round()}%';

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ---- Переключатель периода ----
      GlassCard(
        radius: 16,
        padding: EdgeInsets.all(4),
        child: Row(children: [
          for (final p in Period.values)
            Expanded(
              child: Material(
                color: _period == p ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() => _period = p);
                    reload();
                  },
                  child: SizedBox(
                    height: 34,
                    child: Center(
                      child: Text(periodName(p),
                          style: TextStyle(
                              color: _period == p ? AppColors.onAccent : AppColors.textDim,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
      SizedBox(height: 12),
      if (d == null && _error != null)
        GlassCard(
          child: Text('Не удалось посчитать аналитику: $_error',
              style: TextStyle(color: AppColors.warn, fontSize: 13)),
        )
      else if (d == null)
        Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
      else ...[
        _salesCard(d),
        SizedBox(height: 8),
        if (d.pendingReturns > 0) ...[
          GlassCard(
            borderColor: AppColors.warn.withOpacity(0.55),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReturnsScreen()));
              reload();
            },
            child: Row(children: [
              Icon(Icons.assignment_return_outlined, color: AppColors.warn),
              SizedBox(width: 10),
              Expanded(
                child: Text('Возвратов ждут подтверждения: ${d.pendingReturns}',
                    style: TextStyle(color: AppColors.text)),
              ),
              Icon(Icons.chevron_right, color: AppColors.textDim),
            ]),
          ),
          SizedBox(height: 12),
        ],
        _kpiGrid(d),
        SizedBox(height: 10),
        _stockCard(d),
      ],
    ]);
  }

  Widget _salesCard(Dashboard d) {
    final up = (d.delta ?? 0) >= 0;
    final maxV = d.bars.fold<double>(0, (m, b) => b.value > m ? b.value : m);
    const maxH = 80.0;
    final many = d.bars.length > 10;
    final barW = many ? 34.0 : null;

    Widget bar(Bar b) {
      final h = maxV <= 0 ? 0.0 : (b.value / maxV * maxH);
      final col = Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        // Сумма стоит прямо на столбике, без отступа — у всех одинаково.
        Text(b.value > 0 ? _short(b.value) : '',
            maxLines: 1,
            style: TextStyle(color: AppColors.text, fontSize: 10, fontWeight: FontWeight.w700, height: 1.3)),
        Container(
          height: h < 2 && b.value > 0 ? 2 : h,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.vertical(top: Radius.circular(7), bottom: Radius.circular(2)),
          ),
        ),
        SizedBox(height: 6),
        Text(b.label, style: TextStyle(color: AppColors.textDim, fontSize: 11)),
      ]);
      return barW == null
          ? Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 3), child: col))
          : SizedBox(width: barW, child: Padding(padding: EdgeInsets.symmetric(horizontal: 3), child: col));
    }

    final bars = SizedBox(
      height: maxH + 40,
      child: many
          ? ListView(scrollDirection: Axis.horizontal, children: [for (final b in d.bars) bar(b)])
          : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [for (final b in d.bars) bar(b)]),
    );

    return GlassCard(
      radius: 24,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Продажи · ${periodName(_period)}',
                  style: TextStyle(color: AppColors.textDim, fontSize: 13)),
              SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(money(d.sales),
                    style: TextStyle(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w800)),
              ),
              SizedBox(height: 2),
              Text('${previousName(_period)}: ${money(d.prevSales)}',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            ]),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (up ? AppColors.accent : AppColors.danger).withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_pct(d.delta),
                style: TextStyle(
                    color: up ? AppColors.accent : AppColors.danger, fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ]),
        SizedBox(height: 8),
        bars,
      ]),
    );
  }

  String _vsPrev() => switch (_period) {
        Period.day => 'ко вчера',
        Period.week => 'к прошлой неделе',
        Period.month => 'к прошлому месяцу',
        Period.quarter => 'к прошлому кварталу',
        Period.year => 'к прошлому году',
      };

  double? _chg(double cur, double prev) => prev.abs() < 0.5 ? null : (cur - prev) / prev.abs() * 100;

  /// Значок со светлой подложкой (как в карточках GRS).
  Widget _icon(IconData i, Color c) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: c.withOpacity(0.13), borderRadius: BorderRadius.circular(10)),
        child: Icon(i, color: c, size: 21),
      );

  /// Плашка изменения: «▲ +12%», «▼ −5%» или «▲ новое».
  Widget _badge(double cur, double? pct, {bool upIsGood = true}) {
    String t;
    bool up;
    if (pct == null) {
      if (cur.abs() < 0.5) return SizedBox.shrink();
      t = '▲ новое';
      up = true;
    } else {
      up = pct >= 0;
      t = '${up ? '▲ +' : '▼ '}${pct.round()}%';
    }
    final good = up == upIsGood;
    final c = good ? Color(0xFF16A34A) : AppColors.danger;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(7)),
      child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11.5)),
    );
  }

  /// Мини-столбики за 7 дней, значение — над самым большим.
  Widget _mini(List<double> v, Color c) {
    if (v.isEmpty) return SizedBox(height: 34);
    final maxV = v.fold<double>(0, (m, x) => x > m ? x : m);
    return SizedBox(
      height: 34,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final x in v)
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (maxV > 0 && x == maxV)
                  Text(_short(x),
                      maxLines: 1,
                      style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.w800, height: 1.1)),
                Container(
                  height: maxV <= 0 ? 3 : (x / maxV * 22).clamp(3, 22).toDouble(),
                  decoration: BoxDecoration(
                    color: c.withOpacity(x == maxV && maxV > 0 ? 0.85 : 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }

  /// KPI-блок: значок, изменение, крупная сумма, 1–2 строки пояснения, мини-столбики или ссылка.
  Widget _kpi({
    required String title,
    required IconData icon,
    required Color color,
    required String value,
    double cur = 0,
    double? pct,
    bool upIsGood = true,
    String? line1,
    String? line2,
    List<double>? days,
    String? link,
    VoidCallback? onTap,
  }) =>
      GlassCard(
        radius: 22,
        padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            if (onTap != null) Icon(Icons.chevron_right, size: 16, color: AppColors.textDim),
          ]),
          SizedBox(height: 6),
          Row(children: [
            _icon(icon, color),
            SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _badge(cur, pct, upIsGood: upIsGood),
                SizedBox(height: 2),
                Text(_vsPrev(),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textDim, fontSize: 10.5)),
              ]),
            ),
          ]),
          SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(color: AppColors.text, fontSize: 21, fontWeight: FontWeight.w800)),
          ),
          if (line1 != null)
            Text(line1, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          if (line2 != null)
            Text(line2, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          Spacer(),
          if (link != null)
            Text('$link ›', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13))
          else if (days != null)
            _mini(days, color),
        ]),
      );

  String _ofSales(double v, Dashboard d) =>
      d.sales <= 0 ? '' : '${(v / d.sales * 100).toStringAsFixed(1).replaceAll('.', ',')}% от продаж';

  Widget _kpiGrid(Dashboard d) {
    final tiles = [
      _kpi(
          title: 'Выручка',
          icon: Icons.payments_outlined,
          color: Color(0xFF16A34A),
          value: money(d.revenue),
          cur: d.revenue,
          pct: d.delta,
          line1: 'было: ${money(d.prevSales)}',
          days: d.salesDays),
      _kpi(
          title: 'Прибыль (ФИФО)',
          icon: Icons.trending_up,
          color: Color(0xFF2563EB),
          value: money(d.profit),
          cur: d.profit,
          pct: d.profitDelta,
          line1: d.revenue <= 0 ? null : 'маржа ${(d.profit / d.revenue * 100).round()}%',
          line2: 'было: ${money(d.prevProfit)}'),
      _kpi(
          title: 'Нам должны',
          icon: Icons.call_received,
          color: Color(0xFFDB2777),
          value: money(d.debts),
          line1: 'должников: ${d.debtors}',
          link: 'Список должников',
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DebtsScreen()));
            reload();
          }),
      _kpi(
          title: 'Мы должны',
          icon: Icons.call_made,
          color: Color(0xFF7C3AED),
          value: money(d.supplierDebts),
          line1: 'поставщикам: ${d.suppliersOwed}',
          link: 'Поставщики',
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupplierDebtsScreen()));
            reload();
          }),
      _kpi(
          title: 'Возвраты',
          icon: Icons.assignment_return_outlined,
          color: Color(0xFFEA580C),
          value: money(d.returns),
          cur: d.returns,
          pct: _chg(d.returns, d.prevReturns),
          upIsGood: false,
          line1: _ofSales(d.returns, d),
          line2: '${d.returnsCount} возвратов принято',
          days: d.returnsDays),
      _kpi(
          title: 'Расходы из кассы',
          icon: Icons.receipt_outlined,
          color: AppColors.danger,
          value: money(d.cashOut),
          cur: d.cashOut,
          pct: _chg(d.cashOut, d.prevCashOut),
          upIsGood: false,
          line1: _ofSales(d.cashOut, d),
          line2: '${d.cashOutCount} операций',
          days: d.cashOutDays),
      _kpi(
          title: 'Поступления',
          icon: Icons.download_outlined,
          color: Color(0xFF0891B2),
          value: money(d.receipts),
          cur: d.receipts,
          pct: _chg(d.receipts, d.prevReceipts),
          line1: 'закупка у поставщиков',
          line2: '${d.receiptsCount} документов',
          days: d.receiptsDays),
      _kpi(
          title: 'Остаток в кассе',
          icon: Icons.account_balance_wallet_outlined,
          color: Color(0xFFCA8A04),
          value: money(d.cashInRegister),
          line1: d.shiftOpen ? 'наличные, смена открыта' : 'на закрытии смены'),
    ];
    return LayoutBuilder(builder: (c, box) {
      final w = (box.maxWidth - 10) / 2;
      // Все KPI-блоки одного размера: одинаковая ширина и высота.
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final t in tiles) SizedBox(width: w, height: 196, child: t),
      ]);
    });
  }

  Widget _stockCard(Dashboard d) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GlassCard(
          radius: 20,
          onTap: _toggleStock,
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Товары на складе', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                SizedBox(height: 4),
                Text('${qtyText(d.stockQty)} ед. · ${money(d.stockSum)}',
                    style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
                Text('по цене закупки', style: TextStyle(color: AppColors.textDim, fontSize: 11)),
              ]),
            ),
            Text(_stockOpen ? 'Скрыть' : 'Подробно',
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
          ]),
        ),
        if (_stockOpen && _stock != null)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: GlassCard(
              radius: 20,
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(children: [
                if (_stock!.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Склад пуст', style: TextStyle(color: AppColors.textDim)),
                  ),
                for (final s in _stock!)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(child: Text(s.name, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600))),
                      Text('${qtyText(s.qty)} ${s.unit} · ${money(s.sum)}',
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                    ]),
                  ),
              ]),
            ),
          ),
      ]);
}

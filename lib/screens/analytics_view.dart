// Аналитика хозяина на главной: период, продажи со сравнением, столбики, KPI-блоки, склад.

import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';
import 'debts_screen.dart';
import 'returns_screen.dart';

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
                color: _period == p ? AppColors.text : Colors.transparent,
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
                              color: _period == p ? AppColors.bg : AppColors.textDim,
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

  Widget _kpi(String label, String value, String note, {Color? noteColor, VoidCallback? onTap}) => GlassCard(
        radius: 20,
        padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          SizedBox(height: 2),
          Text(note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: noteColor ?? AppColors.textDim, fontSize: 11)),
        ]),
      );

  Widget _kpiGrid(Dashboard d) {
    final prev = previousName(_period).toLowerCase();
    final tiles = [
      _kpi('Выручка', money(d.revenue), '${_pct(d.delta)} · $prev',
          noteColor: (d.delta ?? 0) >= 0 ? AppColors.accent : AppColors.danger),
      _kpi('Прибыль (ФИФО)', money(d.profit), '${_pct(d.profitDelta)} · $prev',
          noteColor: (d.profitDelta ?? 0) >= 0 ? AppColors.accent : AppColors.danger),
      _kpi('Поступления', money(d.receipts), '${d.receiptsCount} документов'),
      _kpi('Расходы из кассы', money(d.cashOut), '${d.cashOutCount} операций'),
      _kpi('Остаток в кассе', money(d.cashInRegister), d.shiftOpen ? 'наличные, смена открыта' : 'на закрытии смены'),
      _kpi('Долги клиентов', money(d.debts), 'нажмите — по клиентам', noteColor: AppColors.warn, onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DebtsScreen()));
        reload();
      }),
    ];
    return LayoutBuilder(builder: (c, box) {
      final w = (box.maxWidth - 10) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
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
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Expanded(child: Text(s.name, style: TextStyle(color: AppColors.text))),
                      Text('${qtyText(s.qty)} ${s.unit} · ${money(s.sum)}',
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                    ]),
                  ),
              ]),
            ),
          ),
      ]);
}

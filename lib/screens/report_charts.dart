// Диаграммы в разделе «Отчёты»: продажи по группам и по способу оплаты (кольца),
// самые продаваемые товары (полосы). Период: 7 / 30 / 90 дней / год.

import 'package:flutter/material.dart';

import '../services/insights_service.dart';
import '../ui/charts.dart';
import '../ui/glass.dart';

class ReportCharts extends StatefulWidget {
  ReportCharts({super.key});
  @override
  State<ReportCharts> createState() => _ReportChartsState();
}

class _ReportChartsState extends State<ReportCharts> {
  int _days = 30;
  List<ChartValue>? _groups, _payments, _top;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = InsightsService.instance;
      final g = await s.salesByGroup(days: _days);
      final p = await s.salesByPayment(days: _days);
      final t = await s.topProducts(days: _days);
      List<ChartValue> map(List<ChartItem> l) => [for (final x in l) ChartValue(x.label, x.value)];
      if (mounted) {
        setState(() {
          _groups = map(g);
          _payments = map(p);
          _top = map(t);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _groups = [];
          _payments = [];
          _top = [];
        });
      }
    }
  }

  Widget _card(String title, Widget child) => Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: GlassCard(
          radius: 20,
          padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w800)),
            SizedBox(height: 10),
            child,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, children: [
        for (final d in [7, 30, 90, 365])
          ChoiceChip(
            label: Text(d == 365 ? 'Год' : '$d дней'),
            selected: _days == d,
            onSelected: (_) {
              _days = d;
              _load();
            },
          ),
      ]),
      SizedBox(height: 10),
      if (_groups == null)
        Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
      else ...[
        _card('Продажи по группам товаров', DonutChart(items: _groups!, centerLabel: 'Продажи')),
        _card('Способы оплаты', DonutChart(items: _payments!, centerLabel: 'Оплачено')),
        _card('Самые продаваемые товары', HBarChart(items: _top!)),
      ],
    ]);
  }
}

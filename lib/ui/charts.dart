// Диаграммы для отчётов:
//  • DonutChart — кольцевая диаграмма, у каждого значения свой цвет с градиентом,
//    в центре — итог; рядом легенда: название слева, сумма и % справа.
//  • HBarChart — горизонтальные полосы: над полосой название слева и значение справа,
//    полоса с градиентом.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'format.dart';
import 'glass.dart';

/// Набор ярких цветов для значений (у каждого — пара для градиента).
const chartColors = <List<Color>>[
  [Color(0xFFEF4444), Color(0xFFF97316)],
  [Color(0xFF3B82F6), Color(0xFF06B6D4)],
  [Color(0xFF22C55E), Color(0xFF84CC16)],
  [Color(0xFFA855F7), Color(0xFFEC4899)],
  [Color(0xFFF59E0B), Color(0xFFFDE047)],
  [Color(0xFF14B8A6), Color(0xFF2DD4BF)],
  [Color(0xFF6366F1), Color(0xFF8B5CF6)],
  [Color(0xFFDB2777), Color(0xFFF472B6)],
];

class ChartValue {
  final String label;
  final double value;
  ChartValue(this.label, this.value);
}

class DonutChart extends StatelessWidget {
  final List<ChartValue> items;
  final String centerLabel;
  DonutChart({super.key, required this.items, this.centerLabel = 'Итого'});

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (s, x) => s + x.value);
    if (total <= 0) {
      return Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('Нет данных за период', style: TextStyle(color: AppColors.textDim))),
      );
    }
    return Column(children: [
      SizedBox(
        height: 190,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(size: Size(190, 190), painter: _DonutPainter(items, total)),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(centerLabel, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            Text(money(total), style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),
      SizedBox(height: 12),
      for (var i = 0; i < items.length; i++)
        Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(colors: chartColors[i % chartColors.length]),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(items[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
            ),
            Text(money(items[i].value), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
            SizedBox(
              width: 52,
              child: Text('${(items[i].value / total * 100).round()}%',
                  textAlign: TextAlign.right, style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  final List<ChartValue> items;
  final double total;
  _DonutPainter(this.items, this.total);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.17;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - stroke / 2);
    var start = -math.pi / 2;
    final gap = items.length > 1 ? 0.025 : 0.0;
    for (var i = 0; i < items.length; i++) {
      final sweep = items[i].value / total * 2 * math.pi;
      if (sweep <= 0) continue;
      final colors = chartColors[i % chartColors.length];
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + sweep,
          colors: colors,
          transform: GradientRotation(0),
        ).createShader(rect);
      canvas.drawArc(rect, start + gap / 2, math.max(0.001, sweep - gap), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.items != items || old.total != total;
}

class HBarChart extends StatelessWidget {
  final List<ChartValue> items;
  HBarChart({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('Нет данных за период', style: TextStyle(color: AppColors.textDim))),
      );
    }
    final maxV = items.fold<double>(0, (m, x) => x.value > m ? x.value : m);
    return Column(children: [
      for (var i = 0; i < items.length; i++)
        Padding(
          padding: EdgeInsets.symmetric(vertical: 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Над полосой: название слева, значение справа.
            Row(children: [
              Expanded(
                child: Text('${i + 1}. ${items[i].label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              SizedBox(width: 8),
              Text(money(items[i].value),
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 14)),
            ]),
            SizedBox(height: 4),
            LayoutBuilder(
              builder: (_, box) => Stack(children: [
                Container(
                  height: 12,
                  decoration: BoxDecoration(color: AppColors.overlay(0.07), borderRadius: BorderRadius.circular(6)),
                ),
                Container(
                  height: 12,
                  width: maxV <= 0 ? 0 : math.max(6, box.maxWidth * items[i].value / maxV),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: LinearGradient(colors: chartColors[i % chartColors.length]),
                  ),
                ),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

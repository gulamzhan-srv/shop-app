// Форматирование чисел, денег и дат.

import 'package:intl/intl.dart';

/// 1250000 → «1 250 000 ₸»
String money(double v) => '${NumberFormat('#,##0', 'ru').format(v.round()).replaceAll(' ', ' ')} ₸';

/// 2.0 → «2», 2.5 → «2,5»
String qtyText(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString().replaceAll('.', ',');

/// «18.10.2026»
String dateText(DateTime d) => DateFormat('dd.MM.yyyy').format(d);

/// «18.10.2026 21:30»
String dateTimeText(DateTime d) => DateFormat('dd.MM.yyyy HH:mm').format(d);

/// Число из поля ввода: «1 250,5» → 1250.5 (null, если не число)
double? parseNum(String s) => double.tryParse(s.replaceAll(' ', '').replaceAll(',', '.'));

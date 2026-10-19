// Аналитика хозяина: продажи за период со сравнением, столбики, KPI, склад.
//
// Выручка = продажи − подтверждённые возвраты.
// Себестоимость = себестоимость продаж (ФИФО) − себестоимость товара,
//                 вернувшегося на склад (брак остаётся убытком).
// Прибыль = выручка − себестоимость.

import '../db/database.dart';
import 'debt_service.dart';
import 'shift_service.dart';
import 'supplier_debt_service.dart';

enum Period { day, week, month, quarter, year }

String periodName(Period p) => switch (p) {
      Period.day => 'День',
      Period.week => 'Неделя',
      Period.month => 'Месяц',
      Period.quarter => 'Квартал',
      Period.year => 'Год',
    };

String previousName(Period p) => switch (p) {
      Period.day => 'Вчера',
      Period.week => 'Прошлая неделя',
      Period.month => 'Прошлый месяц',
      Period.quarter => 'Прошлый квартал',
      Period.year => 'Прошлый год',
    };

class Range {
  final DateTime from; // включительно
  final DateTime to; // не включительно
  Range(this.from, this.to);
  int get a => from.millisecondsSinceEpoch;
  int get b => to.millisecondsSinceEpoch;
}

class Bar {
  final String label;
  final double value;
  Bar(this.label, this.value);
}

class StockItem {
  final String name;
  final String unit;
  final double qty;
  final double sum;
  StockItem(this.name, this.unit, this.qty, this.sum);
}

class Dashboard {
  final double sales;
  final double prevSales;
  final List<Bar> bars;
  final double revenue;
  final double profit;
  final double prevProfit;
  final double receipts;
  final int receiptsCount;
  final double cashOut;
  final int cashOutCount;
  final double cashInRegister;
  final bool shiftOpen;
  final double debts;
  final double stockQty;
  final double stockSum;
  final int pendingReturns;
  // Для KPI-блоков: прошлый период, число должников, наш долг, возвраты и мини-столбики за 7 дней.
  final double prevReceipts;
  final double prevCashOut;
  final int debtors;
  final double supplierDebts;
  final int suppliersOwed;
  final double returns;
  final int returnsCount;
  final double prevReturns;
  final List<double> salesDays, receiptsDays, cashOutDays, returnsDays;
  Dashboard({
    this.prevReceipts = 0,
    this.prevCashOut = 0,
    this.debtors = 0,
    this.supplierDebts = 0,
    this.suppliersOwed = 0,
    this.returns = 0,
    this.returnsCount = 0,
    this.prevReturns = 0,
    this.salesDays = const [],
    this.receiptsDays = const [],
    this.cashOutDays = const [],
    this.returnsDays = const [],
    required this.sales,
    required this.prevSales,
    required this.bars,
    required this.revenue,
    required this.profit,
    required this.prevProfit,
    required this.receipts,
    required this.receiptsCount,
    required this.cashOut,
    required this.cashOutCount,
    required this.cashInRegister,
    required this.shiftOpen,
    required this.debts,
    required this.stockQty,
    required this.stockSum,
    required this.pendingReturns,
  });

  /// Изменение к прошлому периоду в процентах (null — не с чем сравнить).
  double? get delta => prevSales.abs() < 0.5 ? null : (sales - prevSales) / prevSales * 100;
  double? get profitDelta => prevProfit.abs() < 0.5 ? null : (profit - prevProfit) / prevProfit.abs() * 100;
}

class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  static const _months = ['Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'];
  static const _wd = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  /// Текущий период (календарный) и такой же прошлый.
  (Range, Range) ranges(Period p, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    switch (p) {
      case Period.day:
        return (
          Range(today, today.add(Duration(days: 1))),
          Range(today.subtract(Duration(days: 1)), today)
        );
      case Period.week:
        final start = today.subtract(Duration(days: today.weekday - 1));
        return (
          Range(start, start.add(Duration(days: 7))),
          Range(start.subtract(Duration(days: 7)), start)
        );
      case Period.month:
        final start = DateTime(n.year, n.month);
        return (Range(start, DateTime(n.year, n.month + 1)), Range(DateTime(n.year, n.month - 1), start));
      case Period.quarter:
        final qm = ((n.month - 1) ~/ 3) * 3 + 1;
        final start = DateTime(n.year, qm);
        return (Range(start, DateTime(n.year, qm + 3)), Range(DateTime(n.year, qm - 3), start));
      case Period.year:
        final start = DateTime(n.year);
        return (Range(start, DateTime(n.year + 1)), Range(DateTime(n.year - 1), start));
    }
  }

  Future<double> _one(String sql, List<Object?> args) async {
    final db = await AppDatabase.instance.db;
    final r = await db.rawQuery(sql, args);
    // Пустая база (нет смен/продаж) — запрос может не вернуть строк: считаем 0.
    if (r.isEmpty || r.first.isEmpty) return 0;
    return ((r.first.values.first as num?) ?? 0).toDouble();
  }

  /// Выручка за диапазон (продажи − подтверждённые возвраты).
  Future<double> revenue(Range r) async {
    final s = await _one('SELECT SUM(total) FROM sales WHERE deleted = 0 AND opening = 0 AND sale_date >= ? AND sale_date < ?', [r.a, r.b]);
    final ret = await _one(
        "SELECT SUM(refund) FROM returns WHERE deleted = 0 AND status = 'approved' AND approved_at >= ? AND approved_at < ?",
        [r.a, r.b]);
    return s - ret;
  }

  /// Прибыль за диапазон.
  Future<double> profit(Range r) async {
    final rev = await revenue(r);
    final cost = await _one(
        'SELECT SUM(cost_total) FROM sales WHERE deleted = 0 AND opening = 0 AND sale_date >= ? AND sale_date < ?', [r.a, r.b]);
    final backToStock = await _one('''
      SELECT SUM(rb.qty * b.cost_price) FROM return_batches rb
      JOIN batches b ON b.id = rb.batch_id
      JOIN return_lines rl ON rl.id = rb.return_line_id
      JOIN returns rt ON rt.id = rl.return_id
      WHERE rb.deleted = 0 AND rt.deleted = 0 AND rt.status = 'approved'
        AND rt.approved_at >= ? AND rt.approved_at < ?''', [r.a, r.b]);
    return rev - (cost - backToStock);
  }

  /// Столбики выручки: по дням (день/неделя/месяц) или по месяцам (квартал/год).
  Future<List<Bar>> bars(Period p) async {
    final db = await AppDatabase.instance.db;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (p == Period.quarter || p == Period.year) {
      final (cur, _) = ranges(p);
      final rows = await db.rawQuery('''
        SELECT strftime('%Y-%m', sale_date / 1000, 'unixepoch', 'localtime') AS k, SUM(total) AS v
        FROM sales WHERE deleted = 0 AND opening = 0 AND sale_date >= ? AND sale_date < ? GROUP BY k''', [cur.a, cur.b]);
      final map = {for (final r in rows) r['k'] as String: (r['v'] as num).toDouble()};
      final out = <Bar>[];
      for (var m = DateTime(cur.from.year, cur.from.month);
          m.isBefore(cur.to);
          m = DateTime(m.year, m.month + 1)) {
        final k = '${m.year}-${m.month.toString().padLeft(2, '0')}';
        out.add(Bar(_months[m.month - 1], map[k] ?? 0));
      }
      return out;
    }

    // День → последние 7 дней; неделя → эта неделя; месяц → все дни месяца.
    late DateTime from;
    late int days;
    if (p == Period.day) {
      from = today.subtract(Duration(days: 6));
      days = 7;
    } else if (p == Period.week) {
      from = today.subtract(Duration(days: today.weekday - 1));
      days = 7;
    } else {
      from = DateTime(now.year, now.month);
      days = DateTime(now.year, now.month + 1, 0).day;
    }
    final to = from.add(Duration(days: days));
    final rows = await db.rawQuery('''
      SELECT strftime('%Y-%m-%d', sale_date / 1000, 'unixepoch', 'localtime') AS k, SUM(total) AS v
      FROM sales WHERE deleted = 0 AND opening = 0 AND sale_date >= ? AND sale_date < ? GROUP BY k''',
        [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
    final map = {for (final r in rows) r['k'] as String: (r['v'] as num).toDouble()};
    final out = <Bar>[];
    for (var i = 0; i < days; i++) {
      final d = DateTime(from.year, from.month, from.day + i);
      final k = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final label = p == Period.month ? '${d.day}' : _wd[d.weekday - 1];
      out.add(Bar(label, map[k] ?? 0));
    }
    return out;
  }

  /// Суммы по дням за последние 7 дней (для мини-столбиков в KPI-блоках).
  Future<List<double>> _days(String sql) async {
    final db = await AppDatabase.instance.db;
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day).subtract(Duration(days: 6));
    final rows = await db.rawQuery(sql, [from.millisecondsSinceEpoch]);
    final map = {for (final r in rows) r['k'] as String: ((r['v'] as num?) ?? 0).toDouble()};
    return [
      for (var i = 0; i < 7; i++)
        () {
          final d = from.add(Duration(days: i));
          return map['${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'] ?? 0.0;
        }(),
    ];
  }

  static String _dayKey(String col) => "strftime('%Y-%m-%d', $col / 1000, 'unixepoch', 'localtime')";

  Future<List<StockItem>> stock() async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT p.name, p.unit, SUM(b.qty_left) AS q, SUM(b.qty_left * b.cost_price) AS s
      FROM batch_left b JOIN products p ON p.id = b.product_id
      WHERE p.deleted = 0
      GROUP BY p.id HAVING q > 0.0001
      ORDER BY s DESC''');
    return rows
        .map((r) => StockItem(r['name'] as String, r['unit'] as String, (r['q'] as num).toDouble(),
            (r['s'] as num).toDouble()))
        .toList();
  }

  Future<Dashboard> load(Period p) async {
    final (cur, prev) = ranges(p);
    final db = await AppDatabase.instance.db;

    final sales = await revenue(cur);
    final prevSales = await revenue(prev);
    final prof = await profit(cur);
    final prevProf = await profit(prev);

    final rec = await db.rawQuery(
        'SELECT COALESCE(SUM(total),0) AS s, COUNT(*) AS c FROM receipts WHERE deleted = 0 AND opening = 0 AND doc_date >= ? AND doc_date < ?',
        [cur.a, cur.b]);
    final out = await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS s, COUNT(*) AS c FROM cash_ops WHERE deleted = 0 AND kind = 'out' AND op_date >= ? AND op_date < ?",
        [cur.a, cur.b]);

    // Наличные в кассе: по открытой смене, иначе — сколько оставили при закрытии последней.
    final shift = await ShiftService.instance.current();
    double cash;
    if (shift != null) {
      cash = (await ShiftService.instance.summary(shift.id)).cashExpected;
    } else {
      cash = await _one(
          'SELECT cash_end FROM shifts WHERE deleted = 0 AND closed_at IS NOT NULL ORDER BY closed_at DESC LIMIT 1', []);
    }

    final st = await db.rawQuery(
        'SELECT COALESCE(SUM(qty_left),0) AS q, COALESCE(SUM(qty_left * cost_price),0) AS s FROM batch_left WHERE qty_left > 0');
    final pend = await db.rawQuery("SELECT COUNT(*) AS c FROM returns WHERE deleted = 0 AND status = 'pending'");

    final prevRec = await _one(
        'SELECT SUM(total) FROM receipts WHERE deleted = 0 AND opening = 0 AND doc_date >= ? AND doc_date < ?',
        [prev.a, prev.b]);
    final prevOut = await _one(
        "SELECT SUM(amount) FROM cash_ops WHERE deleted = 0 AND kind = 'out' AND op_date >= ? AND op_date < ?",
        [prev.a, prev.b]);
    final ret = await db.rawQuery(
        "SELECT COALESCE(SUM(refund),0) AS s, COUNT(*) AS c FROM returns WHERE deleted = 0 AND status = 'approved' AND approved_at >= ? AND approved_at < ?",
        [cur.a, cur.b]);
    final prevRet = await _one(
        "SELECT SUM(refund) FROM returns WHERE deleted = 0 AND status = 'approved' AND approved_at >= ? AND approved_at < ?",
        [prev.a, prev.b]);
    final debtors = (await DebtService.instance.byCustomer(onlyOwing: true)).length;
    final sup = await SupplierDebtService.instance.bySupplier(onlyOwing: true);

    return Dashboard(
      sales: sales,
      prevSales: prevSales,
      bars: await bars(p),
      revenue: sales,
      profit: prof,
      prevProfit: prevProf,
      receipts: (rec.first['s'] as num).toDouble(),
      receiptsCount: rec.first['c'] as int,
      cashOut: (out.first['s'] as num).toDouble(),
      cashOutCount: out.first['c'] as int,
      cashInRegister: cash,
      shiftOpen: shift != null,
      debts: await DebtService.instance.totalOwed(),
      stockQty: (st.first['q'] as num).toDouble(),
      stockSum: (st.first['s'] as num).toDouble(),
      pendingReturns: pend.first['c'] as int,
      prevReceipts: prevRec,
      prevCashOut: prevOut,
      debtors: debtors,
      supplierDebts: sup.fold<double>(0, (a, x) => a + x.owed),
      suppliersOwed: sup.length,
      returns: (ret.first['s'] as num).toDouble(),
      returnsCount: ret.first['c'] as int,
      prevReturns: prevRet,
      salesDays: await _days('SELECT ${_dayKey('sale_date')} AS k, SUM(total) AS v FROM sales '
          'WHERE deleted = 0 AND opening = 0 AND sale_date >= ? GROUP BY k'),
      receiptsDays: await _days('SELECT ${_dayKey('doc_date')} AS k, SUM(total) AS v FROM receipts '
          'WHERE deleted = 0 AND opening = 0 AND doc_date >= ? GROUP BY k'),
      cashOutDays: await _days("SELECT ${_dayKey('op_date')} AS k, SUM(amount) AS v FROM cash_ops "
          "WHERE deleted = 0 AND kind = 'out' AND op_date >= ? GROUP BY k"),
      returnsDays: await _days("SELECT ${_dayKey('approved_at')} AS k, SUM(refund) AS v FROM returns "
          "WHERE deleted = 0 AND status = 'approved' AND approved_at >= ? GROUP BY k"),
    );
  }
}

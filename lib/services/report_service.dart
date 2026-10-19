// Чеки и отчёты.
//  • Чеки по сменам — для кассира и хозяина.
//  • Отчёты за период (только хозяин и администратор): по товарам, по чекам,
//    по клиентам, самые продаваемые, самые маржинальные.

import '../db/database.dart';

class ShiftChecks {
  final String id;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String cashier;
  final int count;
  final double total;
  ShiftChecks(this.id, this.openedAt, this.closedAt, this.cashier, this.count, this.total);
}

class CheckRow {
  final String id;
  final DateTime date;
  final String payment;
  final double total;
  final double cost;
  final double paidCash;
  final double paidKaspi;
  final String cashier;
  final String? customer;
  final String? comment;
  CheckRow(this.id, this.date, this.payment, this.total, this.cost, this.paidCash, this.paidKaspi,
      this.cashier, this.customer, this.comment);
  double get profit => total - cost;
}

class CheckLine {
  final String name;
  final String unit;
  final double qty;
  final double price;
  final double sum;
  CheckLine(this.name, this.unit, this.qty, this.price, this.sum);
}

class ProductStat {
  final String name;
  final String unit;
  final double qty;
  final double sum;
  final double cost;
  ProductStat(this.name, this.unit, this.qty, this.sum, this.cost);
  double get profit => sum - cost;

  /// Наценка в % к себестоимости.
  double get markup => cost <= 0 ? 0 : profit / cost * 100;
}

class CustomerStat {
  final String name;
  final String? phone;
  final int checks;
  final double sum;
  final double owed;
  CustomerStat(this.name, this.phone, this.checks, this.sum, this.owed);
}

class ReportService {
  ReportService._();
  static final ReportService instance = ReportService._();

  // ---------------- Чеки по сменам ----------------

  Future<List<ShiftChecks>> shifts({int limit = 60}) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT sh.id, sh.opened_at, sh.closed_at, COALESCE(e.name, '') AS cashier,
        (SELECT COUNT(*) FROM sales s WHERE s.shift_id = sh.id AND s.deleted = 0) AS cnt,
        (SELECT COALESCE(SUM(total), 0) FROM sales s WHERE s.shift_id = sh.id AND s.deleted = 0) AS total
      FROM shifts sh LEFT JOIN employees e ON e.id = sh.opened_by
      WHERE sh.deleted = 0
      ORDER BY sh.opened_at DESC LIMIT ?''', [limit]);
    return rows
        .map((r) => ShiftChecks(
              r['id'] as String,
              DateTime.fromMillisecondsSinceEpoch(r['opened_at'] as int),
              r['closed_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['closed_at'] as int),
              r['cashier'] as String,
              r['cnt'] as int,
              (r['total'] as num).toDouble(),
            ))
        .toList();
  }

  static const _checkSelect = '''
    SELECT s.id, s.sale_date, s.payment, s.total, s.cost_total, s.paid_cash, s.paid_kaspi, s.comment,
      COALESCE(e.name, '') AS cashier, c.name AS customer
    FROM sales s
    LEFT JOIN employees e ON e.id = s.cashier_id
    LEFT JOIN customers c ON c.id = s.customer_id''';

  CheckRow _check(Map<String, Object?> r) => CheckRow(
        r['id'] as String,
        DateTime.fromMillisecondsSinceEpoch(r['sale_date'] as int),
        r['payment'] as String,
        (r['total'] as num).toDouble(),
        (r['cost_total'] as num).toDouble(),
        ((r['paid_cash'] as num?) ?? 0).toDouble(),
        ((r['paid_kaspi'] as num?) ?? 0).toDouble(),
        r['cashier'] as String,
        r['customer'] as String?,
        r['comment'] as String?,
      );

  Future<List<CheckRow>> checksOfShift(String shiftId) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery(
        '$_checkSelect WHERE s.shift_id = ? AND s.deleted = 0 ORDER BY s.sale_date DESC', [shiftId]);
    return rows.map(_check).toList();
  }

  Future<List<CheckLine>> checkLines(String saleId) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT p.name, p.unit, l.qty, l.price, l.sum
      FROM sale_lines l JOIN products p ON p.id = l.product_id
      WHERE l.sale_id = ? AND l.deleted = 0''', [saleId]);
    return rows
        .map((r) => CheckLine(r['name'] as String, r['unit'] as String, (r['qty'] as num).toDouble(),
            (r['price'] as num).toDouble(), (r['sum'] as num).toDouble()))
        .toList();
  }

  // ---------------- Отчёты за период ----------------

  Future<List<CheckRow>> checks(DateTime from, DateTime to) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery(
        '$_checkSelect WHERE s.deleted = 0 AND s.sale_date >= ? AND s.sale_date < ? ORDER BY s.sale_date DESC',
        [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
    return rows.map(_check).toList();
  }

  /// Продажи по товарам. orderBy: 'sum' | 'qty' | 'profit' | 'markup'.
  Future<List<ProductStat>> products(DateTime from, DateTime to, {String orderBy = 'sum'}) async {
    final db = await AppDatabase.instance.db;
    final order = switch (orderBy) {
      'qty' => 'q DESC',
      'profit' => '(sm - cs) DESC',
      'markup' => 'CASE WHEN cs > 0 THEN (sm - cs) / cs ELSE 0 END DESC',
      _ => 'sm DESC',
    };
    final rows = await db.rawQuery('''
      SELECT p.name, p.unit, SUM(l.qty) AS q, SUM(l.sum) AS sm, SUM(l.cost) AS cs
      FROM sale_lines l
      JOIN sales s ON s.id = l.sale_id
      JOIN products p ON p.id = l.product_id
      WHERE l.deleted = 0 AND s.deleted = 0 AND s.sale_date >= ? AND s.sale_date < ?
      GROUP BY p.id
      ORDER BY $order''', [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
    return rows
        .map((r) => ProductStat(r['name'] as String, r['unit'] as String, (r['q'] as num).toDouble(),
            (r['sm'] as num).toDouble(), (r['cs'] as num).toDouble()))
        .toList();
  }

  /// По клиентам: сколько чеков и на какую сумму за период, сколько должен сейчас.
  Future<List<CustomerStat>> customers(DateTime from, DateTime to) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT c.name, c.phone, COUNT(s.id) AS cnt, COALESCE(SUM(s.total), 0) AS sm,
        (SELECT COALESCE(SUM(
            d.total
            - COALESCE((SELECT SUM(p.amount) FROM debt_payments p WHERE p.sale_id = d.id AND p.deleted = 0), 0)
            - COALESCE((SELECT SUM(r.refund) FROM returns r WHERE r.sale_id = d.id AND r.deleted = 0
                        AND r.status = 'approved' AND r.refund_payment = 'debt'), 0)), 0)
          FROM sales d WHERE d.customer_id = c.id AND d.deleted = 0 AND d.payment = 'debt') AS owed
      FROM customers c
      JOIN sales s ON s.customer_id = c.id AND s.deleted = 0 AND s.sale_date >= ? AND s.sale_date < ?
      WHERE c.deleted = 0
      GROUP BY c.id
      ORDER BY sm DESC''', [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
    return rows
        .map((r) => CustomerStat(r['name'] as String, r['phone'] as String?, r['cnt'] as int,
            (r['sm'] as num).toDouble(), (r['owed'] as num).toDouble()))
        .toList();
  }
}

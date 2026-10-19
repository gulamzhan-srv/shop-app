// Анализ товаров для хозяина:
//  • автозаявка — что докупить (остаток ниже минимального или закончился, а продаётся);
//  • не продаются — на складе есть, но за N дней ни одной продажи;
//  • ходовые — как часто продаётся товар (сколько дней из N, сколько чеков в неделю);
//  • топ клиентов и поставщиков за период.

import '../db/database.dart';

class OrderSuggestion {
  final String productId;
  final String name;
  final String unit;
  final double stock;
  final double minStock;
  final double sold30; // продано за 30 дней
  final double qty; // сколько предлагаем заказать
  final double? cost; // последняя цена закупки
  final String reason;
  OrderSuggestion(this.productId, this.name, this.unit, this.stock, this.minStock, this.sold30, this.qty,
      this.cost, this.reason);
  double get sum => (cost ?? 0) * qty;
}

class DeadItem {
  final String name;
  final String unit;
  final double stock;
  final double stockSum; // по цене закупки
  final DateTime? lastSale;
  DeadItem(this.name, this.unit, this.stock, this.stockSum, this.lastSale);
}

class FrequentItem {
  final String name;
  final String unit;
  final int days; // в скольких днях из периода были продажи
  final int checks; // сколько чеков
  final double qty;
  final double sum;
  FrequentItem(this.name, this.unit, this.days, this.checks, this.qty, this.sum);
}

class TopRow {
  final String name;
  final int count;
  final double sum;
  TopRow(this.name, this.count, this.sum);
}

class InsightsService {
  InsightsService._();
  static final InsightsService instance = InsightsService._();

  int _since(int days) => DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;

  static const _stockSql =
      'COALESCE((SELECT SUM(b.qty_left) FROM batch_left b WHERE b.product_id = p.id), 0)';

  /// Автозаявка. Правило:
  ///  • задан мин. остаток и остаток ≤ минимума → заказать до двух минимумов
  ///    (но не меньше, чем продаётся за 2 недели);
  ///  • мин. остаток не задан, товар закончился, но за 30 дней продавался →
  ///    заказать столько, сколько продали за 30 дней.
  Future<List<OrderSuggestion>> autoOrder() async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT p.id, p.name, p.unit, p.min_stock,
        $_stockSql AS stock,
        COALESCE((SELECT SUM(l.qty) FROM sale_lines l JOIN sales s ON s.id = l.sale_id
                  WHERE l.product_id = p.id AND l.deleted = 0 AND s.deleted = 0 AND s.sale_date >= ?), 0) AS sold,
        (SELECT b.cost_price FROM batches b WHERE b.product_id = p.id AND b.deleted = 0
          ORDER BY b.received_at DESC LIMIT 1) AS cost
      FROM products p
      WHERE p.deleted = 0 AND p.active = 1
      ORDER BY p.name COLLATE NOCASE''', [_since(30)]);
    final out = <OrderSuggestion>[];
    for (final r in rows) {
      final stock = (r['stock'] as num).toDouble();
      final min = ((r['min_stock'] as num?) ?? 0).toDouble();
      final sold = (r['sold'] as num).toDouble();
      final cost = (r['cost'] as num?)?.toDouble();
      double qty = 0;
      String reason = '';
      if (min > 0 && stock <= min) {
        final twoWeeks = sold / 30 * 14;
        final target = (min * 2) > (min + twoWeeks) ? min * 2 : min + twoWeeks;
        qty = (target - stock).ceilToDouble();
        reason = stock <= 0 ? 'закончился' : 'ниже минимума';
      } else if (min <= 0 && stock <= 0 && sold > 0) {
        qty = sold.ceilToDouble();
        reason = 'закончился, а продаётся';
      }
      if (qty > 0) {
        out.add(OrderSuggestion(r['id'] as String, r['name'] as String, r['unit'] as String, stock, min, sold,
            qty, cost, reason));
      }
    }
    return out;
  }

  /// Не продаются: на складе есть, но продаж не было [days] дней.
  Future<List<DeadItem>> deadStock({int days = 30}) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT p.name, p.unit,
        $_stockSql AS stock,
        COALESCE((SELECT SUM(b.qty_left * b.cost_price) FROM batch_left b WHERE b.product_id = p.id), 0) AS ssum,
        (SELECT MAX(s.sale_date) FROM sale_lines l JOIN sales s ON s.id = l.sale_id
          WHERE l.product_id = p.id AND l.deleted = 0 AND s.deleted = 0) AS last
      FROM products p
      WHERE p.deleted = 0''');
    final since = _since(days);
    final out = <DeadItem>[];
    for (final r in rows) {
      final stock = (r['stock'] as num).toDouble();
      final last = r['last'] as int?;
      if (stock > 0 && (last == null || last < since)) {
        out.add(DeadItem(r['name'] as String, r['unit'] as String, stock, (r['ssum'] as num).toDouble(),
            last == null ? null : DateTime.fromMillisecondsSinceEpoch(last)));
      }
    }
    out.sort((a, b) => b.stockSum.compareTo(a.stockSum));
    return out;
  }

  /// Ходовые товары за [days] дней: в скольких днях были продажи, сколько чеков.
  Future<List<FrequentItem>> frequent({int days = 30}) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT p.name, p.unit,
        COUNT(DISTINCT strftime('%Y-%m-%d', s.sale_date / 1000, 'unixepoch', 'localtime')) AS days,
        COUNT(DISTINCT s.id) AS checks,
        SUM(l.qty) AS qty, SUM(l.sum) AS sm
      FROM sale_lines l
      JOIN sales s ON s.id = l.sale_id
      JOIN products p ON p.id = l.product_id
      WHERE l.deleted = 0 AND s.deleted = 0 AND s.sale_date >= ?
      GROUP BY p.id
      ORDER BY days DESC, checks DESC''', [_since(days)]);
    return rows
        .map((r) => FrequentItem(r['name'] as String, r['unit'] as String, r['days'] as int, r['checks'] as int,
            (r['qty'] as num).toDouble(), (r['sm'] as num).toDouble()))
        .toList();
  }

  /// Топ покупателей по сумме покупок за [days] дней.
  Future<List<TopRow>> topCustomers({int days = 90}) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT c.name, COUNT(s.id) AS cnt, SUM(s.total) AS sm
      FROM sales s JOIN customers c ON c.id = s.customer_id
      WHERE s.deleted = 0 AND s.opening = 0 AND s.sale_date >= ?
      GROUP BY c.id ORDER BY sm DESC LIMIT 30''', [_since(days)]);
    return rows
        .map((r) => TopRow(r['name'] as String, r['cnt'] as int, (r['sm'] as num).toDouble()))
        .toList();
  }

  /// Топ поставщиков по сумме поступлений за [days] дней.
  Future<List<TopRow>> topSuppliers({int days = 90}) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT su.name, COUNT(r.id) AS cnt, SUM(r.total) AS sm
      FROM receipts r JOIN suppliers su ON su.id = r.supplier_id
      WHERE r.deleted = 0 AND r.opening = 0 AND r.doc_date >= ?
      GROUP BY su.id ORDER BY sm DESC LIMIT 30''', [_since(days)]);
    return rows
        .map((r) => TopRow(r['name'] as String, r['cnt'] as int, (r['sm'] as num).toDouble()))
        .toList();
  }
}

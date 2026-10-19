// ФИФО: учёт товара по партиям.
//
// Каждое поступление создаёт партию со своей ценой закупки.
// При продаже товар списывается сначала из самой старой партии,
// когда она кончается — из следующей. Так прибыль считается точно.
//
// Пример: пришло 10 шт по 100 ₸, потом 10 шт по 120 ₸. Продали 15:
//   10 шт × 100 = 1000 ₸ и 5 шт × 120 = 600 ₸ → себестоимость 1600 ₸.
//
// Остаток партии не хранится, а считается (представление batch_left):
//   пришло − продано (sale_line_batches) + вернули на склад (return_batches).
// Поэтому записи о продаже с разных телефонов никогда не затирают друг друга.

import 'package:sqflite/sqflite.dart';

import '../db/repo.dart';

/// Сколько и из какой партии списали.
class BatchTake {
  final String batchId;
  final double qty;
  final double costPrice;
  BatchTake(this.batchId, this.qty, this.costPrice);
  double get cost => qty * costPrice;
}

class NotEnoughStock implements Exception {
  final double available;
  NotEnoughStock(this.available);
  @override
  String toString() => 'Недостаточно товара на складе (есть $available)';
}

class FifoService {
  FifoService._();
  static final FifoService instance = FifoService._();

  final _repo = Repo.instance;

  /// Создать партию при поступлении.
  Future<String> addBatch(
    Transaction txn, {
    required String productId,
    required String receiptLineId,
    required int receivedAt,
    required double qty,
    required double costPrice,
  }) {
    return _repo.save(
      'batches',
      {
        'product_id': productId,
        'receipt_line_id': receiptLineId,
        'received_at': receivedAt,
        'cost_price': costPrice,
        'qty_in': qty,
        'qty_left': qty, // справочно; настоящий остаток — в batch_left
      },
      txn: txn,
    );
  }

  /// Остаток товара (сумма остатков всех партий).
  Future<double> stock(DatabaseExecutor ex, String productId) async {
    final r = await ex.rawQuery(
      'SELECT COALESCE(SUM(qty_left),0) AS s FROM batch_left WHERE product_id = ?',
      [productId],
    );
    return (r.first['s'] as num).toDouble();
  }

  /// Какие партии нужно взять, чтобы списать qty товара по ФИФО.
  /// Сама запись о списании — это строки sale_line_batches (делает продажа).
  /// Если товара не хватает — NotEnoughStock.
  Future<List<BatchTake>> consume(Transaction txn, String productId, double qty) async {
    final batches = await txn.rawQuery('''
      SELECT id, qty_left, cost_price FROM batch_left
      WHERE product_id = ? AND qty_left > 0.0000001
      ORDER BY received_at ASC, updated_at ASC''', [productId]);
    final available = batches.fold<double>(0, (s, b) => s + (b['qty_left'] as num).toDouble());
    if (available + 1e-9 < qty) throw NotEnoughStock(_round(available));

    final takes = <BatchTake>[];
    var need = qty;
    for (final b in batches) {
      if (need <= 1e-9) break;
      final left = (b['qty_left'] as num).toDouble();
      final take = left < need ? left : need;
      takes.add(BatchTake(b['id'] as String, _round(take), (b['cost_price'] as num).toDouble()));
      need = _round(need - take);
    }
    return takes;
  }

  /// Последняя цена закупки товара (подсказка при поступлении).
  Future<double?> lastCost(DatabaseExecutor ex, String productId) async {
    final r = await ex.query('batches',
        columns: ['cost_price'],
        where: 'product_id = ? AND deleted = 0',
        whereArgs: [productId],
        orderBy: 'received_at DESC',
        limit: 1);
    return r.isEmpty ? null : (r.first['cost_price'] as num).toDouble();
  }

  double _round(double v) => (v * 1000).roundToDouble() / 1000;
}

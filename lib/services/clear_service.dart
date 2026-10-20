// Очистка базы. Записи не стираются физически, а помечаются удалёнными и уходят
// в журнал синхронизации — поэтому очистка применится и на остальных телефонах магазина.
//   • all      — пустая база: документы, товары, группы, покупатели, поставщики, журнал.
//                Остаются: сотрудники, настройки и реквизиты фирмы.
//   • docs     — только документы (продажи, поступления, касса, возвраты, долги, смены);
//                справочники (товары, группы, покупатели, поставщики) остаются.
//   • period   — документы за выбранный период.
//                Поступления остаются, если товар из них продаётся позже выбранного периода.

import 'package:sqflite/sqflite.dart';

import '../db/database.dart';
import '../db/repo.dart';
import 'sync_service.dart';

class ClearResult {
  final int rows;
  final int keptReceipts;
  ClearResult(this.rows, this.keptReceipts);
}

class PeriodCounts {
  final int sales, receipts, cashOps, returns;
  PeriodCounts(this.sales, this.receipts, this.cashOps, this.returns);
}

class ClearService {
  ClearService._();
  static final ClearService instance = ClearService._();

  static const _docTables = [
    'return_batches', 'return_lines', 'returns', 'sale_line_batches', 'debt_payments',
    'sale_lines', 'sales', 'cash_ops', 'supplier_payments', 'batches', 'receipt_lines', 'receipts', 'shifts',
  ];
  static const _catalogTables = ['product_photos', 'products', 'categories', 'customers', 'suppliers', 'access_log'];

  int _rows = 0;

  Future<void> _del(Transaction t, String table, String where, List<Object?> args, int ts, String dev) async {
    final cond = where.isEmpty ? 'deleted = 0' : 'deleted = 0 AND ($where)';
    await t.rawInsert(
        'INSERT INTO sync_outbox(table_name, row_id, changed_at) SELECT ?, id, ? FROM $table WHERE $cond',
        [table, ts, ...args]);
    _rows += await t.rawUpdate('UPDATE $table SET deleted = 1, updated_at = ?, device_id = ? WHERE $cond',
        [ts, dev, ...args]);
  }

  Future<ClearResult> _run(Future<int> Function(Transaction t, int ts, String dev) body) async {
    final db = await AppDatabase.instance.db;
    final dev = await Repo.instance.deviceId();
    final ts = Repo.instance.now();
    _rows = 0;
    var kept = 0;
    await db.transaction((t) async {
      kept = await body(t, ts, dev);
    });
    Repo.onChange?.call();
    SyncService.instance.dataChanged.value++;
    return ClearResult(_rows, kept);
  }

  Future<ClearResult> clearDocuments() => _run((t, ts, dev) async {
        for (final tb in _docTables) {
          await _del(t, tb, '', [], ts, dev);
        }
        return 0;
      });

  Future<ClearResult> clearAll() => _run((t, ts, dev) async {
        for (final tb in _docTables) {
          await _del(t, tb, '', [], ts, dev);
        }
        for (final tb in _catalogTables) {
          await _del(t, tb, '', [], ts, dev);
        }
        return 0;
      });

  /// Сколько документов попадёт под очистку за период.
  Future<PeriodCounts> countPeriod(DateTime from, DateTime to) async {
    final db = await AppDatabase.instance.db;
    final a = from.millisecondsSinceEpoch, b = to.millisecondsSinceEpoch;
    Future<int> c(String sql) async => ((await db.rawQuery(sql, [a, b])).first['c'] as int?) ?? 0;
    return PeriodCounts(
      await c('SELECT COUNT(*) AS c FROM sales WHERE deleted = 0 AND opening = 0 AND sale_date >= ? AND sale_date < ?'),
      await c('SELECT COUNT(*) AS c FROM receipts WHERE deleted = 0 AND opening = 0 AND doc_date >= ? AND doc_date < ?'),
      await c('SELECT COUNT(*) AS c FROM cash_ops WHERE deleted = 0 AND op_date >= ? AND op_date < ?'),
      await c('SELECT COUNT(*) AS c FROM returns WHERE deleted = 0 AND created_at >= ? AND created_at < ?'),
    );
  }

  /// [from] включительно, [to] не включительно.
  Future<ClearResult> clearPeriod(DateTime from, DateTime to) => _run((t, ts, dev) async {
        final a = from.millisecondsSinceEpoch, b = to.millisecondsSinceEpoch;
        const saleIds = 'SELECT id FROM sales WHERE opening = 0 AND sale_date >= ? AND sale_date < ?';
        const retIds = 'SELECT id FROM returns WHERE (created_at >= ? AND created_at < ?) '
            'OR sale_id IN ($saleIds)';
        // Возвраты (и их строки / возвраты в партии).
        await _del(t, 'return_batches',
            'return_line_id IN (SELECT id FROM return_lines WHERE return_id IN ($retIds))', [a, b, a, b], ts, dev);
        await _del(t, 'return_lines', 'return_id IN ($retIds)', [a, b, a, b], ts, dev);
        await _del(t, 'returns', 'id IN ($retIds)', [a, b, a, b], ts, dev);
        // Продажи: списание из партий возвращается на склад само (остаток партии считается).
        await _del(t, 'sale_line_batches',
            'sale_line_id IN (SELECT id FROM sale_lines WHERE sale_id IN ($saleIds))', [a, b], ts, dev);
        await _del(t, 'debt_payments', '(paid_at >= ? AND paid_at < ?) OR sale_id IN ($saleIds)', [a, b, a, b], ts, dev);
        await _del(t, 'sale_lines', 'sale_id IN ($saleIds)', [a, b], ts, dev);
        await _del(t, 'sales', 'id IN ($saleIds)', [a, b], ts, dev);
        await _del(t, 'cash_ops', 'op_date >= ? AND op_date < ?', [a, b], ts, dev);
        await _del(t, 'supplier_payments', 'paid_at >= ? AND paid_at < ?', [a, b], ts, dev);

        // Поступления: только те, из партий которых ничего не продано (после очистки продаж выше).
        final rec = await t.rawQuery('''
          SELECT r.id FROM receipts r
          WHERE r.deleted = 0 AND r.opening = 0 AND r.doc_date >= ? AND r.doc_date < ?
            AND NOT EXISTS (
              SELECT 1 FROM receipt_lines rl
              JOIN batches bt ON bt.receipt_line_id = rl.id
              JOIN sale_line_batches x ON x.batch_id = bt.id
              WHERE rl.receipt_id = r.id AND x.deleted = 0)''', [a, b]);
        final ids = [for (final r in rec) r['id'] as String];
        final total = (await t.rawQuery(
                'SELECT COUNT(*) AS c FROM receipts WHERE deleted = 0 AND opening = 0 AND doc_date >= ? AND doc_date < ?',
                [a, b]))
            .first['c'] as int;
        for (var i = 0; i < ids.length; i += 400) {
          final chunk = ids.sublist(i, i + 400 > ids.length ? ids.length : i + 400);
          final ph = List.filled(chunk.length, '?').join(',');
          await _del(t, 'batches',
              'receipt_line_id IN (SELECT id FROM receipt_lines WHERE receipt_id IN ($ph))', chunk, ts, dev);
          await _del(t, 'receipt_lines', 'receipt_id IN ($ph)', chunk, ts, dev);
          await _del(t, 'receipts', 'id IN ($ph)', chunk, ts, dev);
        }

        // Закрытые смены за период, в которых не осталось документов.
        await _del(
            t,
            'shifts',
            'closed_at IS NOT NULL AND opened_at >= ? AND opened_at < ? '
            'AND NOT EXISTS (SELECT 1 FROM sales s WHERE s.shift_id = shifts.id AND s.deleted = 0) '
            'AND NOT EXISTS (SELECT 1 FROM cash_ops c WHERE c.shift_id = shifts.id AND c.deleted = 0) '
            'AND NOT EXISTS (SELECT 1 FROM debt_payments d WHERE d.shift_id = shifts.id AND d.deleted = 0) '
            'AND NOT EXISTS (SELECT 1 FROM returns r WHERE r.shift_id = shifts.id AND r.deleted = 0)',
            [a, b],
            ts,
            dev);
        return total - ids.length;
      });
}

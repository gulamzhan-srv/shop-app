// Возврат товара.
//
// 1. Кассир выбирает продажу, отмечает, что и сколько возвращают → возврат «ожидает».
// 2. Хозяин подтверждает и выбирает вид:
//    • «На склад» — товар новый (например, не та запчасть), возвращается в свои
//      партии и потом снова продаётся;
//    • «Брак» — заводской брак или испорчен клиентом, на склад для продажи не идёт
//      (его себестоимость становится убытком).
//    Деньги клиенту: наличными, через Kaspi или — если продажа была в долг —
//    уменьшается долг.
// 3. Или хозяин отклоняет возврат.

import '../db/database.dart';
import '../db/repo.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'shift_service.dart';

class SaleBrief {
  final String id;
  final DateTime date;
  final String payment;
  final double total;
  final String? customer;
  SaleBrief(this.id, this.date, this.payment, this.total, this.customer);
}

class SaleLineInfo {
  final String id;
  final String productName;
  final String unit;
  final double qty;
  final double price;
  final double returned; // уже возвращено или ждёт подтверждения
  SaleLineInfo(this.id, this.productName, this.unit, this.qty, this.price, this.returned);
  double get canReturn => qty - returned;
}

class ReturnInfo {
  final String id;
  final String saleId;
  final DateTime createdAt;
  final String createdBy;
  final String status;
  final String? returnType;
  final String salePayment;
  final double total;
  final String? comment;
  final List<String> lines; // «Масляный фильтр × 2»
  ReturnInfo(this.id, this.saleId, this.createdAt, this.createdBy, this.status, this.returnType,
      this.salePayment, this.total, this.comment, this.lines);
}

class ReturnService {
  ReturnService._();
  static final ReturnService instance = ReturnService._();

  final _repo = Repo.instance;

  /// Продажи за последние дни (из них выбираем, что возвращают).
  Future<List<SaleBrief>> recentSales({int days = 30}) async {
    final db = await AppDatabase.instance.db;
    final from = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final rows = await db.rawQuery('''
      SELECT s.id, s.sale_date, s.payment, s.total, c.name AS customer
      FROM sales s LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.deleted = 0 AND s.opening = 0 AND s.sale_date >= ?
      ORDER BY s.sale_date DESC LIMIT 300''', [from]);
    return rows
        .map((r) => SaleBrief(
              r['id'] as String,
              DateTime.fromMillisecondsSinceEpoch(r['sale_date'] as int),
              r['payment'] as String,
              (r['total'] as num).toDouble(),
              r['customer'] as String?,
            ))
        .toList();
  }

  Future<List<SaleLineInfo>> saleLines(String saleId) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT l.id, l.qty, l.price, p.name, p.unit,
        COALESCE((SELECT SUM(rl.qty) FROM return_lines rl
                  JOIN returns r ON r.id = rl.return_id
                  WHERE rl.sale_line_id = l.id AND rl.deleted = 0 AND r.deleted = 0
                    AND r.status IN ('pending','approved')), 0) AS returned
      FROM sale_lines l JOIN products p ON p.id = l.product_id
      WHERE l.sale_id = ? AND l.deleted = 0''', [saleId]);
    return rows
        .map((r) => SaleLineInfo(
              r['id'] as String,
              r['name'] as String,
              r['unit'] as String,
              (r['qty'] as num).toDouble(),
              (r['price'] as num).toDouble(),
              (r['returned'] as num).toDouble(),
            ))
        .toList();
  }

  /// Кассир создаёт возврат. qty: id строки продажи → сколько возвращают.
  Future<String?> create(String saleId, Map<String, double> qty, String? comment) async {
    final user = AuthService.instance.current;
    if (user == null) return 'Войдите по PIN-коду';
    final lines = await saleLines(saleId);
    final chosen = <SaleLineInfo, double>{};
    for (final l in lines) {
      final q = qty[l.id] ?? 0;
      if (q <= 0) continue;
      if (q > l.canReturn + 1e-9) return 'По «${l.productName}» можно вернуть не больше ${l.canReturn}';
      chosen[l] = q;
    }
    if (chosen.isEmpty) return 'Отметьте, что возвращают';
    final total = chosen.entries.fold<double>(0, (s, e) => s + e.key.price * e.value);
    final db = await AppDatabase.instance.db;
    await db.transaction((txn) async {
      final id = await _repo.save(
        'returns',
        {
          'sale_id': saleId,
          'created_by': user.id,
          'created_at': _repo.now(),
          'status': 'pending',
          'comment': (comment?.trim().isEmpty ?? true) ? null : comment!.trim(),
          'total': total,
          'refund': 0,
        },
        txn: txn,
      );
      for (final e in chosen.entries) {
        await _repo.save(
          'return_lines',
          {'return_id': id, 'sale_line_id': e.key.id, 'qty': e.value, 'sum': e.key.price * e.value},
          txn: txn,
        );
      }
    });
    return null;
  }

  Future<List<ReturnInfo>> list({bool onlyPending = false}) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT r.*, e.name AS author, s.payment AS sale_payment
      FROM returns r
      LEFT JOIN employees e ON e.id = r.created_by
      LEFT JOIN sales s ON s.id = r.sale_id
      WHERE r.deleted = 0 ${onlyPending ? "AND r.status = 'pending'" : ''}
      ORDER BY (r.status = 'pending') DESC, r.created_at DESC LIMIT 200''');
    final out = <ReturnInfo>[];
    for (final r in rows) {
      final lines = await db.rawQuery('''
        SELECT p.name, rl.qty, p.unit FROM return_lines rl
        JOIN sale_lines l ON l.id = rl.sale_line_id
        JOIN products p ON p.id = l.product_id
        WHERE rl.return_id = ? AND rl.deleted = 0''', [r['id']]);
      out.add(ReturnInfo(
        r['id'] as String,
        r['sale_id'] as String,
        DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        (r['author'] as String?) ?? '',
        r['status'] as String,
        r['return_type'] as String?,
        (r['sale_payment'] as String?) ?? 'cash',
        (r['total'] as num).toDouble(),
        r['comment'] as String?,
        [
          for (final l in lines)
            '${l['name']} × ${_q((l['qty'] as num).toDouble())} ${l['unit']}',
        ],
      ));
    }
    return out;
  }

  String _q(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// Хозяин подтверждает. type: 'to_stock' | 'defect'; refund: 'cash' | 'kaspi' | 'debt'.
  Future<String?> approve(String returnId, String type, String refund) async {
    final user = AuthService.instance.current;
    if (user == null || !user.isOwner) return 'Подтверждает только хозяин';
    final shift = await ShiftService.instance.current();
    if (refund != 'debt' && shift == null) return 'Чтобы вернуть деньги, откройте смену';

    final db = await AppDatabase.instance.db;
    final rows = await db.query('returns', where: 'id = ? AND deleted = 0', whereArgs: [returnId]);
    if (rows.isEmpty) return 'Возврат не найден';
    final ret = rows.first;
    if (ret['status'] != 'pending') return 'Возврат уже обработан';

    await db.transaction((txn) async {
      if (type == 'to_stock') {
        // Возвращаем товар в те партии, из которых он был продан (сначала — последние).
        final lines = await txn.query('return_lines',
            where: 'return_id = ? AND deleted = 0', whereArgs: [returnId]);
        for (final rl in lines) {
          var left = (rl['qty'] as num).toDouble();
          final takes = await txn.query('sale_line_batches',
              where: 'sale_line_id = ? AND deleted = 0',
              whereArgs: [rl['sale_line_id']],
              orderBy: 'rowid DESC');
          for (final t in takes) {
            if (left <= 1e-9) break;
            final already = (await txn.rawQuery(
                    'SELECT COALESCE(SUM(qty),0) AS s FROM return_batches WHERE batch_id = ? AND deleted = 0 '
                    'AND return_line_id IN (SELECT id FROM return_lines WHERE sale_line_id = ?)',
                    [t['batch_id'], rl['sale_line_id']]))
                .first['s'] as num;
            final can = (t['qty'] as num).toDouble() - already.toDouble();
            if (can <= 1e-9) continue;
            final q = can < left ? can : left;
            await _repo.save('return_batches',
                {'return_line_id': rl['id'], 'batch_id': t['batch_id'], 'qty': q}, txn: txn);
            left -= q;
          }
        }
      }
      await _repo.save(
        'returns',
        {
          ...ret,
          'status': 'approved',
          'return_type': type,
          'approved_by': user.id,
          'approved_at': _repo.now(),
          'shift_id': shift?.id,
          'refund': ret['total'],
          'refund_payment': refund,
        },
        txn: txn,
      );
    });
    if (refund == 'debt') await NotificationService.instance.rescheduleDebts();
    return null;
  }

  Future<void> reject(String returnId) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('returns', where: 'id = ?', whereArgs: [returnId]);
    if (rows.isEmpty) return;
    await _repo.save('returns', {
      ...rows.first,
      'status': 'rejected',
      'approved_by': AuthService.instance.current?.id,
      'approved_at': _repo.now(),
    });
  }
}

// Кассовые смены и приход/расход денег.
//
// Открытие смены: кассир вводит сумму наличных в кассе.
// Закрытие: программа показывает, сколько наличных ДОЛЖНО быть, кассир
// вводит, сколько есть на самом деле — разница сохраняется.
//
// Наличные по смене = начало + продажи наличными + оплаты долгов наличными
//                     + приход денег − расход денег − возвраты наличными.

import '../db/database.dart';
import '../db/repo.dart';
import 'auth_service.dart';

class Shift {
  final String id;
  final DateTime openedAt;
  final String openedBy;
  final double cashStart;
  final DateTime? closedAt;
  final double? cashEnd;
  Shift(this.id, this.openedAt, this.openedBy, this.cashStart, this.closedAt, this.cashEnd);
  bool get isOpen => closedAt == null;
}

class ShiftSummary {
  final double cashStart;
  final double cashSales;
  final double kaspiSales;
  final double debtSales;
  final double debtPaidCash;
  final double debtPaidKaspi;
  final double cashIn;
  final double cashOut;
  final double cashReturns;
  final int salesCount;
  ShiftSummary({
    required this.cashStart,
    required this.cashSales,
    required this.kaspiSales,
    required this.debtSales,
    required this.debtPaidCash,
    required this.debtPaidKaspi,
    required this.cashIn,
    required this.cashOut,
    required this.cashReturns,
    required this.salesCount,
  });

  /// Сколько наличных должно быть в кассе.
  double get cashExpected => cashStart + cashSales + debtPaidCash + cashIn - cashOut - cashReturns;
  double get revenue => cashSales + kaspiSales + debtSales;
}

class ShiftService {
  ShiftService._();
  static final ShiftService instance = ShiftService._();

  final _repo = Repo.instance;

  Shift _fromRow(Map<String, Object?> r) => Shift(
        r['id'] as String,
        DateTime.fromMillisecondsSinceEpoch(r['opened_at'] as int),
        (r['opener'] as String?) ?? '',
        (r['cash_start'] as num).toDouble(),
        r['closed_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['closed_at'] as int),
        (r['cash_end'] as num?)?.toDouble(),
      );

  /// Открытая смена (если есть).
  Future<Shift?> current() async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT s.*, e.name AS opener FROM shifts s
      LEFT JOIN employees e ON e.id = s.opened_by
      WHERE s.deleted = 0 AND s.closed_at IS NULL
      ORDER BY s.opened_at DESC LIMIT 1''');
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<Shift> open(double cashStart) async {
    final cur = await current();
    if (cur != null) return cur;
    await _repo.save('shifts', {
      'opened_by': AuthService.instance.current!.id,
      'opened_at': _repo.now(),
      'cash_start': cashStart,
    });
    return (await current())!;
  }

  Future<void> close(String shiftId, double cashEnd) async {
    final db = await AppDatabase.instance.db;
    final row = (await db.query('shifts', where: 'id = ?', whereArgs: [shiftId])).first;
    await _repo.save('shifts', {
      ...row,
      'closed_by': AuthService.instance.current!.id,
      'closed_at': _repo.now(),
      'cash_end': cashEnd,
    });
  }

  Future<ShiftSummary> summary(String shiftId) async {
    final db = await AppDatabase.instance.db;
    Future<double> one(String sql) async {
      final r = await db.rawQuery(sql, [shiftId]);
      return ((r.first.values.first as num?) ?? 0).toDouble();
    }

    final s = (await db.query('shifts', where: 'id = ?', whereArgs: [shiftId])).first;
    final cnt = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM sales WHERE shift_id = ? AND deleted = 0', [shiftId]);
    return ShiftSummary(
      cashStart: (s['cash_start'] as num).toDouble(),
      cashSales: await one("SELECT SUM(paid_cash) FROM sales WHERE shift_id = ? AND deleted = 0"),
      kaspiSales: await one("SELECT SUM(paid_kaspi) FROM sales WHERE shift_id = ? AND deleted = 0"),
      debtSales: await one(
          "SELECT SUM(total) FROM sales WHERE shift_id = ? AND deleted = 0 AND payment = 'debt'"),
      debtPaidCash: await one(
          "SELECT SUM(amount) FROM debt_payments WHERE shift_id = ? AND deleted = 0 AND payment = 'cash'"),
      debtPaidKaspi: await one(
          "SELECT SUM(amount) FROM debt_payments WHERE shift_id = ? AND deleted = 0 AND payment = 'kaspi'"),
      cashIn: await one(
          "SELECT SUM(amount) FROM cash_ops WHERE shift_id = ? AND deleted = 0 AND kind = 'in'"),
      cashOut: await one(
          "SELECT SUM(amount) FROM cash_ops WHERE shift_id = ? AND deleted = 0 AND kind = 'out'"),
      cashReturns: await one(
          "SELECT SUM(refund) FROM returns WHERE shift_id = ? AND deleted = 0 AND status = 'approved' AND refund_payment = 'cash'"),
      salesCount: cnt.first['c'] as int,
    );
  }

  /// Приход (kind = 'in') или расход (kind = 'out') денег из кассы.
  Future<String?> cashOp({
    required String kind,
    required double amount,
    String? counterparty,
    String? comment,
  }) async {
    if (amount <= 0) return 'Сумма должна быть больше 0';
    final sh = await current();
    if (sh == null) return 'Сначала откройте смену';
    await _repo.save('cash_ops', {
      'op_date': _repo.now(),
      'shift_id': sh.id,
      'kind': kind,
      'amount': amount,
      'counterparty': counterparty,
      'comment': comment,
      'author_id': AuthService.instance.current!.id,
    });
    return null;
  }
}

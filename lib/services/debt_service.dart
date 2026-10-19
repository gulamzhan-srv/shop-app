// Долги покупателей.
//
// Долг по продаже = сумма продажи − оплаты − возвраты «в счёт долга».
// Оплата покупателя гасит его самые ранние (по дате оплаты) долги.

import '../db/database.dart';
import '../db/repo.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'shift_service.dart';

class DebtSale {
  final String saleId;
  final DateTime saleDate;
  final DateTime? due;
  final double total;
  final double remaining;
  DebtSale(this.saleId, this.saleDate, this.due, this.total, this.remaining);
}

class CustomerDebt {
  final String customerId;
  final String name;
  final String? phone;
  final double taken; // всего взял в долг
  final double owed; // сколько ещё должен
  final DateTime? nearestDue; // ближайшая дата оплаты по неоплаченным
  CustomerDebt(this.customerId, this.name, this.phone, this.taken, this.owed, this.nearestDue);

  double get paid => taken - owed;

  /// Срок через 3 дня или меньше (или уже прошёл).
  bool get soon =>
      owed > 0.5 && nearestDue != null && nearestDue!.difference(DateTime.now()).inHours <= 72;
  bool get overdue => owed > 0.5 && nearestDue != null && nearestDue!.isBefore(DateTime.now());
}

class DebtService {
  DebtService._();
  static final DebtService instance = DebtService._();

  final _repo = Repo.instance;

  /// SQL: долговые продажи с остатком долга.
  static const _debtSalesSql = '''
    SELECT s.id, s.customer_id, s.sale_date, s.due_date, s.total,
      s.total
      - COALESCE((SELECT SUM(p.amount) FROM debt_payments p WHERE p.sale_id = s.id AND p.deleted = 0), 0)
      - COALESCE((SELECT SUM(r.refund) FROM returns r
                  WHERE r.sale_id = s.id AND r.deleted = 0 AND r.status = 'approved'
                    AND r.refund_payment = 'debt'), 0) AS remaining
    FROM sales s
    WHERE s.deleted = 0 AND s.payment = 'debt' ''';

  /// Все неоплаченные долговые продажи (для уведомлений).
  Future<List<DebtSale>> unpaidSales() async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('SELECT * FROM ($_debtSalesSql) WHERE remaining > 0.5');
    return rows.map(_toSale).toList();
  }

  DebtSale _toSale(Map<String, Object?> r) => DebtSale(
        r['id'] as String,
        DateTime.fromMillisecondsSinceEpoch(r['sale_date'] as int),
        r['due_date'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['due_date'] as int),
        (r['total'] as num).toDouble(),
        (r['remaining'] as num).toDouble(),
      );

  /// Долги по клиентам: сначала те, у кого срок ближе.
  Future<List<CustomerDebt>> byCustomer({bool onlyOwing = false}) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT c.id, c.name, c.phone,
        SUM(d.total) AS taken,
        SUM(CASE WHEN d.remaining > 0 THEN d.remaining ELSE 0 END) AS owed,
        MIN(CASE WHEN d.remaining > 0.5 THEN d.due_date END) AS nearest
      FROM ($_debtSalesSql) d
      JOIN customers c ON c.id = d.customer_id
      GROUP BY c.id
      ORDER BY (nearest IS NULL), nearest, c.name COLLATE NOCASE''');
    final list = rows
        .map((r) => CustomerDebt(
              r['id'] as String,
              r['name'] as String,
              r['phone'] as String?,
              (r['taken'] as num).toDouble(),
              (r['owed'] as num).toDouble(),
              r['nearest'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['nearest'] as int),
            ))
        .toList();
    return onlyOwing ? list.where((c) => c.owed > 0.5).toList() : list;
  }

  /// Долговые продажи одного покупателя.
  Future<List<DebtSale>> salesOf(String customerId) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery(
        'SELECT * FROM ($_debtSalesSql) WHERE customer_id = ? ORDER BY due_date, sale_date', [customerId]);
    return rows.map(_toSale).toList();
  }

  /// Общая сумма долгов всех покупателей.
  Future<double> totalOwed() async {
    final db = await AppDatabase.instance.db;
    final r = await db.rawQuery('SELECT COALESCE(SUM(remaining),0) AS s FROM ($_debtSalesSql) WHERE remaining > 0');
    return (r.first['s'] as num).toDouble();
  }

  /// Принять оплату долга. payment: 'cash' или 'kaspi'.
  Future<String?> pay(String customerId, double amount, String payment) async {
    if (amount <= 0) return 'Сумма должна быть больше 0';
    final shift = await ShiftService.instance.current();
    if (shift == null) return 'Сначала откройте смену';
    final user = AuthService.instance.current;
    if (user == null) return 'Войдите по PIN-коду';

    final open = (await salesOf(customerId)).where((s) => s.remaining > 0.5).toList();
    final owed = open.fold<double>(0, (s, x) => s + x.remaining);
    if (owed < 0.5) return 'У покупателя нет долга';
    if (amount > owed + 0.5) return 'Сумма больше долга (${owed.round()} ₸)';

    final db = await AppDatabase.instance.db;
    await db.transaction((txn) async {
      var left = amount;
      for (final s in open) {
        if (left <= 0.001) break;
        final part = left < s.remaining ? left : s.remaining;
        await _repo.save(
          'debt_payments',
          {
            'sale_id': s.saleId,
            'paid_at': _repo.now(),
            'amount': part,
            'payment': payment,
            'employee_id': user.id,
            'shift_id': shift.id,
          },
          txn: txn,
        );
        left -= part;
      }
    });
    await NotificationService.instance.rescheduleDebts();
    return null;
  }
}

// Долги перед поставщиками.
//
// Долг по поступлению = сумма поступления − сколько оплачено сразу.
// Оплаты поставщику гасят долг, начиная с самых старых поступлений.

import '../db/database.dart';
import '../db/repo.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'shift_service.dart';

/// Одно поступление, взятое в долг.
class SupplierDebtDoc {
  final String receiptId;
  final DateTime date;
  final DateTime? due;
  final double total; // сумма поступления
  final double debt; // сколько взято в долг
  final double remaining; // сколько ещё должны по нему
  SupplierDebtDoc(this.receiptId, this.date, this.due, this.total, this.debt, this.remaining);
}

/// Оплата поставщику.
class SupplierPayment {
  final DateTime at;
  final double amount;
  final String payment;
  final String? comment;
  SupplierPayment(this.at, this.amount, this.payment, this.comment);
}

class SupplierDebt {
  final String supplierId;
  final String name;
  final String? phone;
  final double taken; // всего взяли в долг
  final double owed; // сколько ещё должны
  final DateTime? nearestDue;
  SupplierDebt(this.supplierId, this.name, this.phone, this.taken, this.owed, this.nearestDue);

  double get paid => taken - owed;
  bool get soon =>
      owed > 0.5 && nearestDue != null && nearestDue!.difference(DateTime.now()).inHours <= 72;
  bool get overdue => owed > 0.5 && nearestDue != null && nearestDue!.isBefore(DateTime.now());
}

String supplierPaymentName(String p) => switch (p) {
      'cash' => 'Наличные из кассы',
      'kaspi' => 'Kaspi',
      _ => 'Другое',
    };

class SupplierDebtService {
  SupplierDebtService._();
  static final SupplierDebtService instance = SupplierDebtService._();

  final _repo = Repo.instance;

  /// Поступления поставщика в долг, с остатком (оплаты разнесены по самым старым).
  Future<List<SupplierDebtDoc>> docsOf(String supplierId) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT id, doc_date, due_date, total, total - COALESCE(paid, total) AS debt
      FROM receipts
      WHERE supplier_id = ? AND deleted = 0 AND total - COALESCE(paid, total) > 0.5
      ORDER BY doc_date''', [supplierId]);
    final p = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS s FROM supplier_payments WHERE supplier_id = ? AND deleted = 0',
        [supplierId]);
    var pool = (p.first['s'] as num).toDouble();
    final list = <SupplierDebtDoc>[];
    for (final r in rows) {
      final debt = (r['debt'] as num).toDouble();
      final cover = pool < debt ? pool : debt;
      pool -= cover;
      list.add(SupplierDebtDoc(
        r['id'] as String,
        DateTime.fromMillisecondsSinceEpoch(r['doc_date'] as int),
        r['due_date'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['due_date'] as int),
        (r['total'] as num).toDouble(),
        debt,
        debt - cover,
      ));
    }
    return list;
  }

  /// Оплаты поставщику (новые сверху).
  Future<List<SupplierPayment>> paymentsOf(String supplierId) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery(
        'SELECT * FROM supplier_payments WHERE supplier_id = ? AND deleted = 0 ORDER BY paid_at DESC',
        [supplierId]);
    return rows
        .map((r) => SupplierPayment(
              DateTime.fromMillisecondsSinceEpoch(r['paid_at'] as int),
              (r['amount'] as num).toDouble(),
              r['payment'] as String,
              r['comment'] as String?,
            ))
        .toList();
  }

  /// Долги по поставщикам: сначала те, у кого срок ближе.
  Future<List<SupplierDebt>> bySupplier({bool onlyOwing = false}) async {
    final db = await AppDatabase.instance.db;
    final sup = await db.rawQuery('''
      SELECT DISTINCT s.id, s.name, s.phone FROM suppliers s
      JOIN receipts r ON r.supplier_id = s.id
      WHERE s.deleted = 0 AND r.deleted = 0 AND r.total - COALESCE(r.paid, r.total) > 0.5''');
    final list = <SupplierDebt>[];
    for (final s in sup) {
      final id = s['id'] as String;
      final docs = await docsOf(id);
      final taken = docs.fold<double>(0, (a, d) => a + d.debt);
      final owed = docs.fold<double>(0, (a, d) => a + d.remaining);
      DateTime? nearest;
      for (final d in docs) {
        if (d.remaining > 0.5 && d.due != null && (nearest == null || d.due!.isBefore(nearest))) {
          nearest = d.due;
        }
      }
      list.add(SupplierDebt(id, s['name'] as String, s['phone'] as String?, taken, owed, nearest));
    }
    list.sort((a, b) {
      if (a.nearestDue == null && b.nearestDue != null) return 1;
      if (a.nearestDue != null && b.nearestDue == null) return -1;
      if (a.nearestDue != null && b.nearestDue != null) {
        final c = a.nearestDue!.compareTo(b.nearestDue!);
        if (c != 0) return c;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return onlyOwing ? list.where((x) => x.owed > 0.5).toList() : list;
  }

  /// Сколько всего должны поставщикам.
  Future<double> totalOwed() async {
    final l = await bySupplier(onlyOwing: true);
    return l.fold<double>(0, (a, x) => a + x.owed);
  }

  /// Оплатить поставщику. payment: 'cash' (из кассы — нужна открытая смена), 'kaspi', 'other'.
  Future<String?> pay(String supplierId, String supplierName, double amount, String payment,
      {String? comment}) async {
    if (amount <= 0) return 'Сумма должна быть больше 0';
    final user = AuthService.instance.current;
    if (user == null) return 'Войдите по PIN-коду';
    final docs = await docsOf(supplierId);
    final owed = docs.fold<double>(0, (a, d) => a + d.remaining);
    if (owed < 0.5) return 'Долга перед поставщиком нет';
    if (amount > owed + 0.5) return 'Сумма больше долга (${owed.round()} ₸)';
    if (payment == 'cash') {
      // Деньги берутся из кассы — записываем расход в текущую смену.
      final err = await ShiftService.instance.cashOp(
        kind: 'out',
        amount: amount,
        counterparty: supplierName,
        comment: 'Оплата долга поставщику',
      );
      if (err != null) return err;
    }
    final c = comment?.trim();
    await _repo.save('supplier_payments', {
      'supplier_id': supplierId,
      'paid_at': _repo.now(),
      'amount': amount,
      'payment': payment,
      'employee_id': user.id,
      'comment': (c == null || c.isEmpty) ? null : c,
    });
    NotificationService.instance.rescheduleDebts().catchError((_) {});
    return null;
  }
}

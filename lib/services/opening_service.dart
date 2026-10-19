// Начальные остатки (при переходе на программу):
//  • начальный долг покупателя — продажа «в долг» без товаров, opening = 1;
//  • наш начальный долг поставщику — поступление без товаров, оплачено 0, opening = 1;
//  • начальный остаток склада — поступление с товарами без поставщика, opening = 1
//    (создаёт партии ФИФО по цене закупки).
// В выручку, чеки и «Поступления за период» они не попадают, а в долги и остатки — попадают.

import '../db/database.dart';
import '../db/repo.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'receipt_service.dart';

class OpeningDebt {
  final String id;
  final String name; // покупатель или поставщик
  final double amount;
  final DateTime? due;
  final DateTime date;
  OpeningDebt(this.id, this.name, this.amount, this.due, this.date);
}

class OpeningStockDoc {
  final String id;
  final DateTime date;
  final int lines;
  final double total;
  OpeningStockDoc(this.id, this.date, this.lines, this.total);
}

class OpeningService {
  OpeningService._();
  static final OpeningService instance = OpeningService._();

  final _repo = Repo.instance;

  DateTime? _dt(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);

  // ---------- Долги покупателей ----------

  Future<List<OpeningDebt>> customerDebts() async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT s.id, s.total, s.due_date, s.sale_date, COALESCE(c.name, '—') AS name
      FROM sales s LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.deleted = 0 AND s.opening = 1
      ORDER BY c.name COLLATE NOCASE''');
    return rows
        .map((r) => OpeningDebt(r['id'] as String, r['name'] as String, (r['total'] as num).toDouble(),
            _dt(r['due_date']), _dt(r['sale_date'])!))
        .toList();
  }

  Future<String?> addCustomerDebt(String customerId, double amount, DateTime? due) async {
    if (amount <= 0) return 'Сумма должна быть больше 0';
    final user = AuthService.instance.current;
    if (user == null) return 'Войдите по PIN-коду';
    await _repo.save('sales', {
      'sale_date': _repo.now(),
      'shift_id': null,
      'cashier_id': user.id,
      'payment': 'debt',
      'customer_id': customerId,
      'due_date': due?.millisecondsSinceEpoch,
      'comment': 'Начальный долг',
      'total': amount,
      'cost_total': 0,
      'paid_cash': 0,
      'paid_kaspi': 0,
      'opening': 1,
    });
    NotificationService.instance.rescheduleDebts().catchError((_) {});
    return null;
  }

  Future<String?> deleteCustomerDebt(String saleId) async {
    final db = await AppDatabase.instance.db;
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM debt_payments WHERE sale_id = ? AND deleted = 0', [saleId]);
    if ((r.first['c'] as int) > 0) return 'По этому долгу уже были оплаты — удалить нельзя';
    await _repo.remove('sales', saleId);
    NotificationService.instance.rescheduleDebts().catchError((_) {});
    return null;
  }

  // ---------- Наши долги поставщикам ----------

  Future<List<OpeningDebt>> supplierDebts() async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT r.id, r.total, r.due_date, r.doc_date, COALESCE(s.name, '—') AS name
      FROM receipts r LEFT JOIN suppliers s ON s.id = r.supplier_id
      WHERE r.deleted = 0 AND r.opening = 1 AND r.supplier_id IS NOT NULL
      ORDER BY s.name COLLATE NOCASE''');
    return rows
        .map((r) => OpeningDebt(r['id'] as String, r['name'] as String, (r['total'] as num).toDouble(),
            _dt(r['due_date']), _dt(r['doc_date'])!))
        .toList();
  }

  Future<String?> addSupplierDebt(String supplierId, double amount, DateTime? due) async {
    if (amount <= 0) return 'Сумма должна быть больше 0';
    final user = AuthService.instance.current;
    if (user == null) return 'Войдите по PIN-коду';
    await _repo.save('receipts', {
      'doc_date': _repo.now(),
      'supplier_id': supplierId,
      'comment': 'Начальный долг',
      'author_id': user.id,
      'device_name': await ReceiptService.instance.deviceName(),
      'total': amount,
      'paid': 0,
      'due_date': due?.millisecondsSinceEpoch,
      'opening': 1,
    });
    NotificationService.instance.rescheduleDebts().catchError((_) {});
    return null;
  }

  Future<String?> deleteSupplierDebt(String receiptId) async {
    await _repo.remove('receipts', receiptId);
    NotificationService.instance.rescheduleDebts().catchError((_) {});
    return null;
  }

  // ---------- Начальный остаток склада ----------

  Future<List<OpeningStockDoc>> stockDocs() async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT r.id, r.doc_date, r.total,
        (SELECT COUNT(*) FROM receipt_lines l WHERE l.receipt_id = r.id AND l.deleted = 0) AS cnt
      FROM receipts r
      WHERE r.deleted = 0 AND r.opening = 1 AND r.supplier_id IS NULL
      ORDER BY r.doc_date DESC''');
    return rows
        .map((r) => OpeningStockDoc(r['id'] as String, _dt(r['doc_date'])!, r['cnt'] as int,
            (r['total'] as num).toDouble()))
        .toList();
  }
}

// Покупатели (для продажи в долг).

import '../db/database.dart';
import '../db/repo.dart';
import 'auth_service.dart';

class Customer {
  final String? id;
  final String name;
  final String? phone;
  Customer({this.id, required this.name, this.phone});
}

class CustomerService {
  CustomerService._();
  static final CustomerService instance = CustomerService._();

  final _repo = Repo.instance;

  /// Удалить покупателя. Есть в документах → отключаем (скрываем из списков), иначе удаляем.
  Future<String> removeOrDisable(String id, {double owed = 0}) async {
    if (!(AuthService.instance.current?.isManager ?? false)) return 'Удалять может только хозяин или администратор';
    if (owed > 0.5) return 'Нельзя: у покупателя есть долг. Сначала примите оплату.';
    final db = await AppDatabase.instance.db;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM sales WHERE customer_id = ? AND deleted = 0', [id]);
    if (((r.first['c'] as int?) ?? 0) > 0) {
      final row = (await db.query('customers', where: 'id = ?', whereArgs: [id])).first;
      await _repo.save('customers', {...row, 'active': 0});
      return 'Покупатель есть в документах — он не удалён, а отключён (скрыт из списков)';
    }
    await _repo.remove('customers', id);
    return 'Покупатель удалён';
  }

  Future<List<Customer>> search([String q = '']) async {
    final t = q.trim();
    final rows = await _repo.list(
      'customers',
      where: t.isEmpty ? 'active = 1' : 'active = 1 AND (name LIKE ? COLLATE NOCASE OR phone LIKE ?)',
      args: t.isEmpty ? null : ['%$t%', '%$t%'],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows
        .map((r) => Customer(id: r['id'] as String, name: r['name'] as String, phone: r['phone'] as String?))
        .toList();
  }

  Future<String> save(Customer c) => _repo.save('customers', {
        if (c.id != null) 'id': c.id,
        'name': c.name.trim(),
        'phone': c.phone?.trim(),
      });
}

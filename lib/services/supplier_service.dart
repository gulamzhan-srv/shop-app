// Поставщики.

import '../db/database.dart';
import '../db/repo.dart';
import 'auth_service.dart';

class Supplier {
  final String? id;
  final String name;
  final String? phone;
  final String? address;
  Supplier({this.id, required this.name, this.phone, this.address});
}

class SupplierService {
  SupplierService._();
  static final SupplierService instance = SupplierService._();

  final _repo = Repo.instance;

  /// Удалить поставщика. Есть в документах → отключаем (скрываем из списков), иначе удаляем.
  Future<String> removeOrDisable(String id, {double owed = 0}) async {
    if (!(AuthService.instance.current?.isManager ?? false)) return 'Удалять может только хозяин или администратор';
    if (owed > 0.5) return 'Нельзя: перед поставщиком есть долг. Сначала погасите его.';
    final db = await AppDatabase.instance.db;
    final r = await db.rawQuery('''
      SELECT (SELECT COUNT(*) FROM receipts WHERE supplier_id = ? AND deleted = 0)
           + (SELECT COUNT(*) FROM supplier_payments WHERE supplier_id = ? AND deleted = 0) AS c''', [id, id]);
    if (((r.first['c'] as int?) ?? 0) > 0) {
      final row = (await db.query('suppliers', where: 'id = ?', whereArgs: [id])).first;
      await _repo.save('suppliers', {...row, 'active': 0});
      return 'Поставщик есть в документах — он не удалён, а отключён (скрыт из списков)';
    }
    await _repo.remove('suppliers', id);
    return 'Поставщик удалён';
  }

  Future<List<Supplier>> all() async {
    final rows = await _repo.list('suppliers', where: 'active = 1', orderBy: 'name COLLATE NOCASE');
    return rows
        .map((r) => Supplier(
              id: r['id'] as String,
              name: r['name'] as String,
              phone: r['phone'] as String?,
              address: r['address'] as String?,
            ))
        .toList();
  }

  Future<String> save(Supplier s) => _repo.save('suppliers', {
        if (s.id != null) 'id': s.id,
        'name': s.name.trim(),
        'phone': s.phone?.trim(),
        'address': s.address?.trim(),
      });
}

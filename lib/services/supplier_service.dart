// Поставщики.

import '../db/repo.dart';

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

  Future<List<Supplier>> all() async {
    final rows = await _repo.list('suppliers', orderBy: 'name COLLATE NOCASE');
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

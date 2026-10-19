// Покупатели (для продажи в долг).

import '../db/repo.dart';

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

  Future<List<Customer>> search([String q = '']) async {
    final t = q.trim();
    final rows = await _repo.list(
      'customers',
      where: t.isEmpty ? null : 'name LIKE ? COLLATE NOCASE OR phone LIKE ?',
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

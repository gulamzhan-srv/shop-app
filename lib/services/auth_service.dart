// Сотрудники, вход по PIN-коду, код восстановления и журнал входов.
//
// Роли: хозяин (owner), администратор (admin, полные права), кассир (cashier).
// PIN — 6 цифр. Хранится только хэш (SHA-256) с «солью», сам PIN нигде не сохраняется.
// Сотрудники со старым 4-значным PIN могут войти, но сразу должны сменить его на 6-значный.

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../db/database.dart';
import '../db/repo.dart';
import 'device_service.dart';

enum Role { owner, admin, cashier }

const pinLength = 6;

Role roleFrom(Object? s) => switch (s) {
      'owner' => Role.owner,
      'admin' => Role.admin,
      _ => Role.cashier,
    };

String roleCode(Role r) => switch (r) {
      Role.owner => 'owner',
      Role.admin => 'admin',
      Role.cashier => 'cashier',
    };

String roleName(Role r) => switch (r) {
      Role.owner => 'Хозяин',
      Role.admin => 'Администратор',
      Role.cashier => 'Кассир',
    };

class Employee {
  final String id;
  final String name;
  final Role role;
  final int pinLen;
  Employee(this.id, this.name, this.role, this.pinLen);

  /// Хозяин или администратор — видят всё: аналитику, цены закупки, отчёты, Google Диск.
  bool get isManager => role != Role.cashier;
  bool get isOwner => isManager; // старое имя, оставлено для совместимости
  bool get isAdmin => role == Role.admin;
  bool get mustChangePin => pinLen < pinLength;

  static Employee fromRow(Map<String, Object?> r) => Employee(
        r['id'] as String,
        r['name'] as String,
        roleFrom(r['role']),
        (r['pin_len'] as int?) ?? 4,
      );
}

class LogEntry {
  final DateTime at;
  final String who;
  final String role;
  final String event;
  final String ip;
  final String device;
  LogEntry(this.at, this.who, this.role, this.event, this.ip, this.device);
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final _repo = Repo.instance;

  /// Кто сейчас вошёл в приложение.
  Employee? current;

  String _salt() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  String _hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  bool _validPin(String pin) => RegExp('^\\d{$pinLength}\$').hasMatch(pin);
  static const _pinError = 'PIN должен быть из $pinLength цифр';

  /// Есть ли уже хозяин или администратор? Если нет — экран первой настройки.
  Future<bool> hasOwner() async {
    final rows = await _repo.list('employees', where: "role IN ('owner','admin') AND active = 1");
    return rows.isNotEmpty;
  }

  /// Есть ли ещё сотрудники со старым 4-значным PIN (тогда вход проверяется и на 4 цифрах).
  Future<bool> hasLegacyPins() async {
    final rows = await _repo.list('employees', where: 'active = 1 AND pin_len < $pinLength');
    return rows.isNotEmpty;
  }

  /// Создать сотрудника. PIN — 6 цифр, у всех сотрудников разный.
  Future<String?> addEmployee({required String name, required Role role, required String pin}) async {
    if (!_validPin(pin)) return _pinError;
    if (await login(pin, remember: false) != null) return 'Такой PIN уже занят';
    final salt = _salt();
    await _repo.save('employees', {
      'name': name.trim(),
      'role': roleCode(role),
      'pin_hash': _hash(pin, salt),
      'pin_salt': salt,
      'active': 1,
      'pin_len': pinLength,
    });
    return null; // null = всё хорошо
  }

  /// Вход: ищем сотрудника, у которого совпадает PIN.
  Future<Employee?> login(String pin, {bool remember = true}) async {
    final rows = await _repo.list('employees', where: 'active = 1');
    for (final r in rows) {
      if (_hash(pin, r['pin_salt'] as String) == r['pin_hash']) {
        final e = Employee.fromRow(r);
        if (remember) {
          current = e;
          logEvent('Вход');
        }
        return e;
      }
    }
    return null;
  }

  /// Все сотрудники (для экрана «Сотрудники»).
  Future<List<Map<String, Object?>>> all() => _repo.list('employees',
      orderBy: "CASE role WHEN 'admin' THEN 0 WHEN 'owner' THEN 1 ELSE 2 END, name COLLATE NOCASE");

  /// Включить / отключить сотрудника (отключённый не сможет войти).
  Future<String?> setActive(String id, bool active) async {
    final rows = await _repo.list('employees', where: 'id = ?', args: [id]);
    if (rows.isEmpty) return 'Сотрудник не найден';
    final r = rows.first;
    if (!active && r['role'] != 'cashier') {
      final managers = await _repo.list('employees', where: "role IN ('owner','admin') AND active = 1");
      if (managers.length <= 1) return 'Нельзя отключить единственного хозяина / администратора';
    }
    if (!active && r['role'] == 'admin' && !(current?.isAdmin ?? false)) {
      return 'Отключить администратора может только администратор';
    }
    await _repo.save('employees', {...r, 'active': active ? 1 : 0});
    return null;
  }

  /// Задать новый PIN сотруднику (сброс хозяином / администратором, или после восстановления).
  Future<String?> changePin(String id, String pin) async {
    if (!_validPin(pin)) return _pinError;
    final other = await login(pin, remember: false);
    if (other != null && other.id != id) return 'Такой PIN уже занят';
    final rows = await _repo.list('employees', where: 'id = ?', args: [id]);
    if (rows.isEmpty) return 'Сотрудник не найден';
    final salt = _salt();
    await _repo.save('employees',
        {...rows.first, 'pin_hash': _hash(pin, salt), 'pin_salt': salt, 'pin_len': pinLength});
    if (current?.id == id) {
      current = Employee(current!.id, current!.name, current!.role, pinLength);
    }
    return null;
  }

  /// Сотрудник сам меняет свой PIN: нужно ввести старый.
  Future<String?> changeOwnPin(String oldPin, String newPin) async {
    final me = current;
    if (me == null) return 'Войдите по PIN-коду';
    final check = await login(oldPin, remember: false);
    if (check == null || check.id != me.id) return 'Старый PIN введён неверно';
    if (oldPin == newPin) return 'Новый PIN должен отличаться от старого';
    final err = await changePin(me.id, newPin);
    if (err == null) logEvent('Смена PIN');
    return err;
  }

  /// Кнопка «Блокировать»: выходим, снова нужен PIN.
  void lock() => current = null;

  // ---------------- Код восстановления PIN хозяина ----------------

  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // без похожих 0/O, 1/I

  /// Создать новый код восстановления (старый перестаёт действовать).
  /// Показывается ОДИН раз — хозяин должен его записать.
  Future<String> newRecoveryCode() async {
    final r = Random.secure();
    final raw = List.generate(12, (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
    final code = '${raw.substring(0, 4)}-${raw.substring(4, 8)}-${raw.substring(8)}';
    final salt = _salt();
    await _repo.save('settings', {
      'id': 'recovery',
      'value': jsonEncode({'salt': salt, 'hash': _hash(_norm(code), salt), 'at': _repo.now()}),
    });
    return code;
  }

  String _norm(String code) => code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  Future<bool> hasRecoveryCode() async {
    final rows = await _repo.list('settings', where: "id = 'recovery'");
    return rows.isNotEmpty && rows.first['value'] != null;
  }

  Future<bool> checkRecoveryCode(String code) async {
    final rows = await _repo.list('settings', where: "id = 'recovery'");
    if (rows.isEmpty || rows.first['value'] == null) return false;
    final j = jsonDecode(rows.first['value'] as String) as Map<String, dynamic>;
    return _hash(_norm(code), j['salt'] as String) == j['hash'];
  }

  /// Хозяева и администраторы — кому можно восстановить PIN кодом.
  Future<List<Employee>> managers() async {
    final rows = await _repo.list('employees', where: "role IN ('owner','admin') AND active = 1");
    return rows.map(Employee.fromRow).toList();
  }

  // ---------------- Журнал входов (2 месяца) ----------------

  static const keepDays = 60;

  /// Записать событие в журнал (не ждём: IP может определяться несколько секунд).
  Future<void> logEvent(String event, {Employee? who}) async {
    try {
      final e = who ?? current;
      final ip = await DeviceService.instance.ip();
      final device = await DeviceService.instance.name();
      await _repo.save('access_log', {
        'at': _repo.now(),
        'employee_id': e?.id,
        'employee_name': e?.name ?? '—',
        'role': e == null ? null : roleCode(e.role),
        'event': event,
        'ip': ip,
        'device_name': device,
      }, notify: false);
      final db = await AppDatabase.instance.db;
      final old = DateTime.now().subtract(Duration(days: keepDays)).millisecondsSinceEpoch;
      await db.delete('access_log', where: 'at < ?', whereArgs: [old]);
    } catch (_) {
      // журнал не должен мешать работе
    }
  }

  Future<List<LogEntry>> journal() async {
    final db = await AppDatabase.instance.db;
    final old = DateTime.now().subtract(Duration(days: keepDays)).millisecondsSinceEpoch;
    final rows = await db.query('access_log',
        where: 'deleted = 0 AND at >= ?', whereArgs: [old], orderBy: 'at DESC', limit: 1000);
    return rows
        .map((r) => LogEntry(
              DateTime.fromMillisecondsSinceEpoch(r['at'] as int),
              (r['employee_name'] as String?) ?? '—',
              r['role'] == null ? '' : roleName(roleFrom(r['role'])),
              r['event'] as String,
              (r['ip'] as String?) ?? '',
              (r['device_name'] as String?) ?? '',
            ))
        .toList();
  }

  /// Последняя синхронизация каждого телефона (пишет SyncService).
  Future<List<(String device, DateTime at)>> deviceSyncs() async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('settings', where: "deleted = 0 AND id LIKE 'sync_%'");
    final out = <(String, DateTime)>[];
    for (final r in rows) {
      try {
        final j = jsonDecode(r['value'] as String) as Map<String, dynamic>;
        out.add(((j['device'] as String?) ?? 'Телефон', DateTime.fromMillisecondsSinceEpoch(j['at'] as int)));
      } catch (_) {}
    }
    out.sort((a, b) => b.$2.compareTo(a.$2));
    return out;
  }
}

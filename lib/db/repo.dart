// Общие функции записи в базу.
// Любая запись проходит через save(): она сама ставит служебные поля
// и кладёт изменение в журнал синхронизации (sync_outbox).

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

class Repo {
  Repo._();
  static final Repo instance = Repo._();

  static const _uuid = Uuid();

  /// Вызывается после каждого изменения (синхронизация подписывается на это).
  static void Function()? onChange;
  String? _deviceId;

  /// Постоянный код этого телефона (создаётся один раз при первом запуске).
  Future<String> deviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_id');
    if (id == null) {
      id = _uuid.v4();
      await prefs.setString('device_id', id);
    }
    return _deviceId = id;
  }

  String newId() => _uuid.v4();
  int now() => DateTime.now().millisecondsSinceEpoch;

  /// Вставить или обновить запись. Если id нет — создаётся новый.
  Future<String> save(String table, Map<String, Object?> row,
      {Transaction? txn, bool notify = true}) async {
    final id = (row['id'] as String?) ?? newId();
    final ts = now();
    final data = {
      ...row,
      'id': id,
      'updated_at': ts,
      'device_id': await deviceId(),
      'deleted': row['deleted'] ?? 0,
    };
    Future<void> run(DatabaseExecutor ex) async {
      await ex.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
      await ex.insert('sync_outbox', {
        'table_name': table,
        'row_id': id,
        'changed_at': ts,
      });
    }

    if (txn != null) {
      await run(txn);
    } else {
      final db = await AppDatabase.instance.db;
      await db.transaction((t) => run(t));
    }
    if (notify) onChange?.call();
    return id;
  }

  /// Пометить запись удалённой (чтобы удаление тоже ушло на другие телефоны).
  Future<void> remove(String table, String id, {Transaction? txn}) async {
    final db = await AppDatabase.instance.db;
    final DatabaseExecutor ex = txn ?? db;
    final rows = await ex.query(table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    await save(table, {...rows.first, 'deleted': 1}, txn: txn);
  }

  /// Выборка без удалённых записей.
  Future<List<Map<String, Object?>>> list(
    String table, {
    String? where,
    List<Object?>? args,
    String? orderBy,
  }) async {
    final db = await AppDatabase.instance.db;
    final w = where == null ? 'deleted = 0' : 'deleted = 0 AND ($where)';
    return db.query(table, where: w, whereArgs: args, orderBy: orderBy);
  }
}

// Синхронизация через Google Диск (скрытая папка приложения — appDataFolder).
//
// Как это работает:
//  • Каждое изменение в базе попадает в журнал sync_outbox (это делает Repo.save).
//  • ОТПРАВКА: телефон собирает изменённые записи в файл
//      chg_<время>_<код телефона>.json
//    и кладёт его в скрытую папку на Google Диске. Фото товаров кладутся
//    отдельными файлами photo_<имя>.jpg.
//  • ПРИЁМ: телефон смотрит, какие файлы chg_ от ДРУГИХ телефонов он ещё не
//    применял, скачивает их и записывает к себе. Если одна и та же запись
//    изменена на двух телефонах, остаётся более поздняя (по времени изменения).
//  • НОВЫЙ ТЕЛЕФОН: входит в тот же Google-аккаунт и применяет все файлы —
//    база восстанавливается с того места, где остановились.
//
// Папку appDataFolder видит только это приложение; пользователь её не видит
// и случайно удалить не может. Нужен ОДИН Google-аккаунт на всех телефонах магазина.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database.dart';
import '../db/repo.dart';
import 'device_service.dart';
import 'notification_service.dart';
import 'photo_service.dart';

class SyncStatus {
  final String? email;
  final DateTime? lastSync;
  final int pending; // изменений ждут отправки
  final String? lastError;
  SyncStatus(this.email, this.lastSync, this.pending, this.lastError);
}

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final _gsi = GoogleSignIn(scopes: [drive.DriveApi.driveAppdataScope]);
  final _repo = Repo.instance;

  bool _running = false;
  bool _again = false;
  Timer? _debounce;
  Timer? _periodic;
  String? _lastError;
  final Map<String, Set<String>> _columns = {};

  /// Ход синхронизации для полосы прогресса: 0…1, null — сейчас не идёт.
  final progress = ValueNotifier<double?>(null);
  /// Что сейчас делается (текст под полосой прогресса).
  final stage = ValueNotifier<String>('');

  void _step(double p, String text) {
    progress.value = p;
    stage.value = text;
  }

  /// Пакет и SHA-1 этого приложения — их нужно указать в Google Cloud (OAuth-клиент Android).
  static const packageName = 'kz.grs.shop_app';
  static const sha1 = '6A:8E:33:CE:D5:A2:21:15:17:2B:B5:38:6D:AC:C6:F4:37:04:2A:98';

  /// Понятный текст ошибки входа в Google.
  static String explainSignInError(Object e) {
    final t = e.toString();
    if (t.contains('10:') || t.contains('DEVELOPER_ERROR')) {
      return 'Google не знает это приложение (ошибка 10). В Google Cloud → Credentials создайте '
          'OAuth-клиент типа Android: пакет $packageName, SHA-1 $sha1. Включите Google Drive API, '
          'на экране согласия добавьте свою почту в тестовые пользователи. Через 5–10 минут повторите.';
    }
    if (t.contains('12501') || t.contains('sign_in_canceled')) return 'Вход отменён';
    if (t.contains('network') || t.contains('7:')) return 'Нет интернета';
    if (t.contains('access_denied') || t.contains('12500')) {
      return 'Google отказал во входе. Проверьте, что эта почта добавлена в тестовые пользователи '
          '(Google Cloud → экран согласия → Test users).';
    }
    return 'Не удалось войти: $t';
  }

  /// Запуск: тихий вход (если уже входили) и синхронизация каждые 3 минуты.
  Future<void> start() async {
    Repo.onChange = scheduleSoon;
    try {
      await _gsi.signInSilently();
    } catch (_) {}
    _periodic ??= Timer.periodic(Duration(minutes: 3), (_) => syncNow());
    unawaited(syncNow());
  }

  String? get email => _gsi.currentUser?.email;
  bool get signedIn => _gsi.currentUser != null;

  /// Вход в Google-аккаунт (показывает выбор аккаунта).
  Future<String?> signIn() async {
    try {
      final acc = await _gsi.signIn();
      if (acc == null) return 'Вход отменён';
      return null;
    } catch (e) {
      return explainSignInError(e);
    }
  }

  Future<void> signOut() => _gsi.signOut();

  /// Есть ли на Google Диске этого аккаунта данные магазина (резервная копия).
  /// null — проверить не удалось (нет интернета и т.п.).
  Future<bool?> hasBackup() async {
    try {
      final client = await _gsi.authenticatedClient();
      if (client == null) return null;
      final api = drive.DriveApi(client);
      final res = await api.files.list(
        spaces: 'appDataFolder',
        q: "name contains 'chg_'",
        pageSize: 1,
        $fields: 'files(id)',
      );
      return (res.files ?? []).isNotEmpty;
    } catch (_) {
      return null;
    }
  }

  /// После изменения в базе — синхронизировать через несколько секунд
  /// (чтобы несколько изменений подряд ушли одним файлом).
  void scheduleSoon() {
    _debounce?.cancel();
    _debounce = Timer(Duration(seconds: 8), () => syncNow());
  }

  Future<SyncStatus> status() async {
    final db = await AppDatabase.instance.db;
    final p = await SharedPreferences.getInstance();
    final last = p.getInt('last_sync');
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM sync_outbox WHERE sent = 0');
    return SyncStatus(email, last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
        r.first['c'] as int, _lastError);
  }

  /// Отправить свои изменения и принять чужие. Возвращает текст ошибки или null.
  Future<String?> syncNow() async {
    if (!signedIn) return 'не выполнен вход в Google';
    if (_running) {
      _again = true;
      return null;
    }
    _running = true;
    try {
      do {
        _again = false;
        _step(0.03, 'Подключение к Google…');
        final client = await _gsi.authenticatedClient();
        if (client == null) return _lastError = 'нет доступа к Google Диску';
        final api = drive.DriveApi(client);
        _step(0.1, 'Отправка изменений…');
        await _push(api);
        _step(0.3, 'Получение данных…');
        final newSales = <String>[];
        final changed = await _pull(api, newSales);
        _step(0.85, 'Фото товаров…');
        await _uploadPhotos(api);
        await _downloadPhotos(api);
        if (changed) await NotificationService.instance.rescheduleDebts();
        if (newSales.isNotEmpty) await NotificationService.instance.notifySales(newSales);
        _step(1, 'Готово');
        final p = await SharedPreferences.getInstance();
        await p.setInt('last_sync', DateTime.now().millisecondsSinceEpoch);
        // Для журнала администратора: когда этот телефон последний раз синхронизировался.
        await _repo.save('settings', {
          'id': 'sync_${await _repo.deviceId()}',
          'value': jsonEncode({'device': await DeviceService.instance.name(), 'at': _repo.now()}),
        }, notify: false);
        _lastError = null;
      } while (_again);
      return null;
    } on SocketException {
      return _lastError = 'нет интернета';
    } catch (e) {
      return _lastError = '$e';
    } finally {
      _running = false;
      progress.value = null;
    }
  }

  /// Полное восстановление на новом телефоне (вызывается с экрана первой настройки).
  Future<String?> restore() async {
    if (!signedIn) {
      final err = await signIn();
      if (err != null) return err;
    }
    return syncNow();
  }

  // ---------------- ОТПРАВКА ----------------

  Future<void> _push(drive.DriveApi api) async {
    final db = await AppDatabase.instance.db;
    final device = await _repo.deviceId();
    while (true) {
      final out = await db.query('sync_outbox', where: 'sent = 0', orderBy: 'seq', limit: 800);
      if (out.isEmpty) break;
      final maxSeq = out.last['seq'] as int;

      // Одна запись могла меняться несколько раз — отправляем её текущее состояние один раз.
      final keys = <String, Set<String>>{};
      for (final o in out) {
        keys.putIfAbsent(o['table_name'] as String, () => {}).add(o['row_id'] as String);
      }
      final rows = <Map<String, Object?>>[];
      for (final e in keys.entries) {
        if (!AppDatabase.syncTables.contains(e.key)) continue;
        final ids = e.value.toList();
        for (var i = 0; i < ids.length; i += 500) {
          final part = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
          final found = await db.query(e.key,
              where: 'id IN (${List.filled(part.length, '?').join(',')})', whereArgs: part);
          for (final r in found) {
            rows.add({'t': e.key, 'r': r});
          }
        }
      }

      if (rows.isNotEmpty) {
        final ts = DateTime.now().toUtc().millisecondsSinceEpoch.toString().padLeft(14, '0');
        final bytes = Uint8List.fromList(utf8.encode(jsonEncode({'v': 1, 'device': device, 'rows': rows})));
        final file = drive.File()
          ..name = 'chg_${ts}_$device.json'
          ..parents = ['appDataFolder'];
        await api.files.create(file, uploadMedia: drive.Media(Stream.value(bytes), bytes.length));
      }
      await db.delete('sync_outbox', where: 'seq <= ?', whereArgs: [maxSeq]);
    }
  }

  // ---------------- ПРИЁМ ----------------

  Future<List<drive.File>> _listFiles(drive.DriveApi api, String q) async {
    final all = <drive.File>[];
    String? token;
    do {
      final res = await api.files.list(
        spaces: 'appDataFolder',
        q: q,
        orderBy: 'name',
        pageSize: 1000,
        pageToken: token,
        $fields: 'nextPageToken, files(id, name)',
      );
      all.addAll(res.files ?? []);
      token = res.nextPageToken;
    } while (token != null);
    return all;
  }

  Future<Uint8List> _download(drive.DriveApi api, String id) async {
    final media =
        await api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final b = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      b.add(chunk);
    }
    return b.takeBytes();
  }

  Future<Set<String>> _localColumns(Database db, String table) async {
    final c = _columns[table];
    if (c != null) return c;
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return _columns[table] = {for (final r in info) r['name'] as String};
  }

  /// Возвращает true, если что-то изменилось.
  Future<bool> _pull(drive.DriveApi api, List<String> newSales) async {
    final db = await AppDatabase.instance.db;
    final device = await _repo.deviceId();
    final applied = {
      for (final r in await db.query('sync_applied', columns: ['file_name'])) r['file_name'] as String
    };
    final files = (await _listFiles(api, "name contains 'chg_'"))
        .where((f) => f.name != null && !applied.contains(f.name) && !f.name!.contains(device))
        .toList()
      ..sort((a, b) => a.name!.compareTo(b.name!));

    // Список колонок узнаём заранее: внутри транзакции нельзя обращаться к db.
    for (final t in AppDatabase.syncTables) {
      await _localColumns(db, t);
    }
    var changed = false;
    var done = 0;
    for (final f in files) {
      done++;
      _step(0.3 + 0.55 * done / files.length, 'Получение данных: $done из ${files.length}…');
      final data = jsonDecode(utf8.decode(await _download(api, f.id!))) as Map<String, dynamic>;
      final rows = (data['rows'] as List).cast<Map<String, dynamic>>();
      await db.transaction((txn) async {
        for (final item in rows) {
          final table = item['t'] as String;
          if (!AppDatabase.syncTables.contains(table)) continue;
          final cols = _columns[table]!;
          final r = Map<String, Object?>.from(item['r'] as Map)..removeWhere((k, _) => !cols.contains(k));
          final id = r['id'] as String?;
          if (id == null) continue;
          final local = await txn.query(table, columns: ['updated_at', 'device_id'], where: 'id = ?', whereArgs: [id]);
          if (local.isEmpty && table == 'sales' && r['deleted'] == 0) newSales.add(id);
          if (local.isNotEmpty) {
            final lu = local.first['updated_at'] as int;
            final ru = (r['updated_at'] as num).toInt();
            // Остаётся более позднее изменение; при равном времени — по коду телефона.
            if (ru < lu) continue;
            if (ru == lu && (r['device_id'] as String).compareTo(local.first['device_id'] as String) <= 0) continue;
          }
          await txn.insert(table, r, conflictAlgorithm: ConflictAlgorithm.replace);
          changed = true;
        }
        await txn.insert('sync_applied', {'file_name': f.name, 'applied_at': _repo.now()},
            conflictAlgorithm: ConflictAlgorithm.replace);
      });
    }
    return changed;
  }

  // ---------------- ФОТО ----------------

  Future<void> _uploadPhotos(drive.DriveApi api) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT DISTINCT file_name FROM product_photos
      WHERE deleted = 0 AND file_name NOT IN (SELECT file_name FROM sync_photos)''');
    for (final r in rows) {
      final name = r['file_name'] as String;
      final f = await PhotoService.instance.fileFor(name);
      if (!await f.exists()) continue; // фото с другого телефона, ещё не скачано
      final bytes = await f.readAsBytes();
      final file = drive.File()
        ..name = 'photo_$name'
        ..parents = ['appDataFolder'];
      await api.files.create(file, uploadMedia: drive.Media(Stream.value(bytes), bytes.length));
      await db.insert('sync_photos', {'file_name': name, 'uploaded_at': _repo.now()},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _downloadPhotos(drive.DriveApi api) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('SELECT DISTINCT file_name FROM product_photos WHERE deleted = 0');
    final missing = <String>[];
    for (final r in rows) {
      final name = r['file_name'] as String;
      if (!await (await PhotoService.instance.fileFor(name)).exists()) missing.add(name);
    }
    if (missing.isEmpty) return;
    final remote = {
      for (final f in await _listFiles(api, "name contains 'photo_'")) f.name!: f.id!,
    };
    for (final name in missing) {
      final id = remote['photo_$name'];
      if (id == null) continue; // ещё не выгружено с другого телефона
      final bytes = await _download(api, id);
      await (await PhotoService.instance.fileFor(name)).writeAsBytes(bytes, flush: true);
      await db.insert('sync_photos', {'file_name': name, 'uploaded_at': _repo.now()},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}

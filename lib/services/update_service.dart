// Автообновление из одного места.
// GitHub после каждой сборки кладёт новый APK и файл version.json в открытый
// репозиторий avtomag-update. Приложение при запуске читает version.json и, если
// номер сборки больше своего, предлагает обновиться: скачивается APK, Android
// показывает «Установить» — данные на телефоне сохраняются.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/glass.dart';

class UpdateInfo {
  final int build;
  final String version;
  final String apk;
  final String notes;
  UpdateInfo(this.build, this.version, this.apk, this.notes);
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  /// Откуда берутся обновления (последний релиз репозитория avtomag-update).
  static const versionUrl =
      'https://github.com/gulamzhan-srv/avtomag-update/releases/latest/download/version.json';

  bool _askedThisRun = false;

  Future<(int, String)> current() async {
    final i = await PackageInfo.fromPlatform();
    return (int.tryParse(i.buildNumber) ?? 0, i.version);
  }

  /// Есть ли новая версия. null — нет обновления или нет интернета.
  Future<UpdateInfo?> check() async {
    try {
      final r = await http.get(Uri.parse(versionUrl)).timeout(Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final info = UpdateInfo(
        (j['build'] as num).toInt(),
        j['version'] as String? ?? '',
        j['apk'] as String,
        (j['notes'] as String? ?? '').trim(),
      );
      final (mine, _) = await current();
      return info.build > mine ? info : null;
    } catch (_) {
      return null;
    }
  }

  /// Открыть ссылку на APK: Android скачает файл и предложит установить.
  Future<bool> install(UpdateInfo u) =>
      launchUrl(Uri.parse(u.apk), mode: LaunchMode.externalApplication);

  /// Проверить и, если есть новая версия, показать окно «Обновить».
  /// silent = true — при запуске (без сообщений, если обновлений нет).
  Future<void> checkAndAsk(BuildContext context, {bool silent = true}) async {
    if (silent && _askedThisRun) return;
    final u = await check();
    if (!context.mounted) return;
    if (u == null) {
      if (!silent) {
        final (b, v) = await current();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('У вас последняя версия ($v, сборка $b)')));
      }
      return;
    }
    _askedThisRun = true;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(children: [
          Icon(Icons.system_update, color: AppColors.accent),
          SizedBox(width: 8),
          Expanded(child: Text('Новая версия ${u.version}')),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (u.notes.isNotEmpty) ...[
            Text('Что нового:', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text(u.notes),
            SizedBox(height: 10),
          ],
          Text('Нажмите «Обновить» → скачается файл → нажмите «Установить». '
              'Все данные на телефоне сохранятся.',
              style: TextStyle(fontSize: 13)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Позже')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('Обновить')),
        ],
      ),
    );
    if (ok == true) await install(u);
  }
}

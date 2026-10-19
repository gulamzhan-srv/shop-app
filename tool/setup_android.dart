// Настройка Android-части проекта (запустить ОДИН раз после `flutter create`):
//
//   dart run tool/setup_android.dart
//
// Что делает:
//  1. AndroidManifest.xml — название «AVTOMAG GRS SOFT», разрешения (интернет, камера,
//     уведомления) и приёмники для уведомлений о долгах (работают и после перезагрузки).
//  2. app/build.gradle(.kts) — включает «desugaring», без него не соберутся уведомления.
// Повторный запуск ничего не ломает: уже сделанное пропускается.

import 'dart:io';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('Не найден ${manifest.path}. Сначала выполните:\n'
        '  flutter create --platforms=android --org kz.grs .');
    exit(1);
  }
  _patchManifest(manifest);

  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  if (kts.existsSync()) {
    _patchGradle(kts, kotlin: true);
  } else if (groovy.existsSync()) {
    _patchGradle(groovy, kotlin: false);
  } else {
    stderr.writeln('Не найден android/app/build.gradle(.kts)');
    exit(1);
  }
  _setupSigning(kotlin: kts.existsSync(), gradle: kts.existsSync() ? kts : groovy);
  _copyIcons();
  _proguard();
  stdout.writeln('\nГотово. Теперь: flutter pub get  и  flutter run');
}

/// Иконка приложения: готовые картинки из tool/icons заменяют стандартную иконку Flutter.
void _copyIcons() {
  final src = Directory('tool/icons');
  if (!src.existsSync()) return;
  for (final d in src.listSync().whereType<Directory>()) {
    final name = d.path.split(Platform.pathSeparator).last.split('/').last;
    final f = File('${d.path}/ic_launcher.png');
    final dest = Directory('android/app/src/main/res/$name');
    if (f.existsSync() && dest.existsSync()) f.copySync('${dest.path}/ic_launcher.png');
  }
  stdout.writeln('✓ иконка приложения');
}

/// Постоянный ключ подписи (tool/release.jks). Один и тот же ключ на всех сборках
/// нужен, чтобы работал вход Google (его SHA-1 вписывается в Google Cloud)
/// и чтобы новая версия APK ставилась поверх старой без потери данных.
void _setupSigning({required bool kotlin, required File gradle}) {
  final jks = File('tool/release.jks');
  final props = File('tool/key.properties');
  if (!jks.existsSync() || !props.existsSync()) {
    stdout.writeln('— tool/release.jks не найден, подпись не настраиваю');
    return;
  }
  jks.copySync('android/app/release.jks');
  props.copySync('android/key.properties');

  var s = gradle.readAsStringSync();
  if (s.contains('key.properties')) {
    stdout.writeln('✓ подпись уже настроена');
    return;
  }
  final block = kotlin
      ? '''
    signingConfigs {
        create("release") {
            val props = rootProject.file("key.properties").readLines()
                .filter { it.contains("=") }
                .associate { it.substringBefore("=").trim() to it.substringAfter("=").trim() }
            keyAlias = props.getValue("keyAlias")
            keyPassword = props.getValue("keyPassword")
            storeFile = file(props.getValue("storeFile"))
            storePassword = props.getValue("storePassword")
        }
    }

'''
      : '''
    signingConfigs {
        release {
            def props = new Properties()
            props.load(rootProject.file('key.properties').newInputStream())
            keyAlias props['keyAlias']
            keyPassword props['keyPassword']
            storeFile file(props['storeFile'])
            storePassword props['storePassword']
        }
    }

''';
  final i = s.indexOf(RegExp(r'^\s*buildTypes\s*\{', multiLine: true));
  if (i < 0) {
    stderr.writeln('Не нашёл buildTypes в ${gradle.path} — подпись не настроена');
    return;
  }
  s = s.substring(0, i) + block + s.substring(i);
  if (kotlin) {
    s = s.replaceAll('signingConfigs.getByName("debug")', 'signingConfigs.getByName("release")');
    s = s.replaceFirstMapped(RegExp(r'buildTypes\s*\{'),
        (m) => '${m[0]}\n        getByName("debug") {\n            signingConfig = signingConfigs.getByName("release")\n        }');
  } else {
    s = s.replaceAll('signingConfigs.debug', 'signingConfigs.release');
    s = s.replaceFirstMapped(RegExp(r'buildTypes\s*\{'),
        (m) => '${m[0]}\n        debug {\n            signingConfig signingConfigs.release\n        }');
  }
  gradle.writeAsStringSync(s);
  stdout.writeln('✓ подпись APK постоянным ключом');
}

void _patchManifest(File f) {
  var s = f.readAsStringSync();
  const perms = [
    'android.permission.INTERNET',
    'android.permission.CAMERA',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.VIBRATE',
    // Координаты входа для журнала администратора (по разрешению пользователя).
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.ACCESS_FINE_LOCATION',
  ];
  final add = StringBuffer();
  for (final p in perms) {
    if (!s.contains('"$p"')) add.writeln('    <uses-permission android:name="$p"/>');
  }
  if (add.isNotEmpty) {
    s = s.replaceFirstMapped(RegExp(r'<manifest[^>]*>'), (m) => '${m[0]}\n$add');
  }

  s = s.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="AVTOMAG GRS SOFT"');

  // Старый проверенный движок отрисовки (Skia) вместо Impeller: на части телефонов
  // Impeller с эффектом размытия «стекла» показывает пустой серый экран.
  if (!s.contains('EnableImpeller')) {
    s = s.replaceFirst('</application>',
        '        <meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="false" />\n    </application>');
  }

  if (!s.contains('ScheduledNotificationReceiver')) {
    const receivers = '''
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
''';
    s = s.replaceFirst('</application>', '$receivers    </application>');
  }
  f.writeAsStringSync(s);
  stdout.writeln('✓ ${f.path}');
}

void _patchGradle(File f, {required bool kotlin}) {
  var s = f.readAsStringSync();
  if (s.contains('desugar_jdk_libs')) {
    stdout.writeln('✓ ${f.path} (уже настроен)');
    return;
  }
  final enable = kotlin ? 'isCoreLibraryDesugaringEnabled = true' : 'coreLibraryDesugaringEnabled true';
  if (s.contains('compileOptions {')) {
    s = s.replaceFirst('compileOptions {', 'compileOptions {\n        $enable');
  } else {
    s = s.replaceFirst(RegExp(r'android\s*\{'), 'android {\n    compileOptions {\n        $enable\n    }');
  }
  final dep = kotlin
      ? 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")'
      : "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4'";
  if (RegExp(r'^dependencies\s*\{', multiLine: true).hasMatch(s)) {
    s = s.replaceFirstMapped(RegExp(r'^dependencies\s*\{', multiLine: true), (m) => '${m[0]}\n    $dep');
  } else {
    s = '$s\ndependencies {\n    $dep\n}\n';
  }
  f.writeAsStringSync(s);
  stdout.writeln('✓ ${f.path}');
}

/// Правила для оптимизатора R8 (финальная сборка): без них модуль уведомлений
/// падает с ошибкой «Missing type parameter» (вырезаются данные Gson TypeToken).
void _proguard() {
  File('android/app/proguard-rules.pro').writeAsStringSync('''
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**
''');
  stdout.writeln('✓ proguard-rules.pro для уведомлений');
}

// AVTOMAG GRS SOFT: касса и учёт на телефоне.
// Автор: Гуламжан Саттаркулович

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'db/database.dart';
import 'screens/pin_screen.dart';
import 'screens/setup_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'ui/glass.dart';

/// Текст на экране загрузки: какой шаг запуска сейчас идёт (или какая ошибка).
final _bootStatus = ValueNotifier<String>('Запуск…');
bool _appStarted = false;

/// Метка версии: видна на экране загрузки и на экране ошибки.
const _buildTag = 'версия 20.10-8';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ошибка при построении экрана — показываем её текст, а не серый экран.
  ErrorWidget.builder = (details) => _ErrorView(details.exceptionAsString(), details.stack);
  // Любая ошибка интерфейса (в том числе при раскладке и отрисовке) — на весь экран с текстом.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    runApp(_ErrorView('Ошибка интерфейса: ${details.exceptionAsString()}', details.stack));
  };
  // Сразу показываем экран загрузки: если запуск зависнет, будет видно, на каком шаге.
  runApp(_BootView());
  try {
    _bootStatus.value = 'Шаг 1 из 4: язык и даты…';
    await initializeDateFormatting('ru');
    _bootStatus.value = 'Шаг 2 из 4: открываю базу…';
    await AppDatabase.instance.db; // открываем (или создаём) базу
    _bootStatus.value = 'Шаг 3 из 4: тема оформления…';
    await AppThemes.load(); // сохранённая тема: Ночь / День / Рубин / Зумруд
    _bootStatus.value = 'Шаг 4 из 4: сотрудники…';
    final hasOwner = await AuthService.instance.hasOwner();
    _appStarted = true;
    runApp(ShopApp(firstRun: !hasOwner));
    // Уведомления о долгах и синхронизация — уже после показа приложения.
    NotificationService.instance
        .init()
        .then((_) => NotificationService.instance.rescheduleDebts())
        .catchError((_) {});
    SyncService.instance.start().catchError((_) {});
  } catch (e, st) {
    // Ошибка при запуске (например, при обновлении базы) — показываем её на экране.
    if (!_appStarted) runApp(_ErrorView('Ошибка запуска (${_bootStatus.value}): $e', st));
  }
}

/// Простой экран загрузки (без темы и шрифтов — показывается даже при проблемах).
class _BootView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFF0B0F17),
        child: Center(
          child: ValueListenableBuilder<String>(
            valueListenable: _bootStatus,
            builder: (_, v, __) => Text('AVTOMAG GRS SOFT\n$_buildTag\n\n$v',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFF5F7FA), fontSize: 15, decoration: TextDecoration.none)),
          ),
        ),
      ),
    );
  }
}

/// Экран с текстом ошибки (чтобы прислать разработчику скриншот).
/// Работает даже если ошибка случилась выше MaterialApp (нет темы, языка, размеров экрана).
class _ErrorView extends StatelessWidget {
  final String message;
  final StackTrace? stack;
  _ErrorView(this.message, this.stack);

  @override
  Widget build(BuildContext context) {
    final lines = (stack?.toString() ?? '').split('\n').take(14).join('\n');
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFF1B1F27),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 48, 16, 16),
          child: Text(
            'Произошла ошибка ($_buildTag). Сделайте скриншот и отправьте разработчику.\n\n$message\n\n$lines',
            style: TextStyle(color: Color(0xFFFFB4A8), fontSize: 12, decoration: TextDecoration.none),
          ),
        ),
      ),
    );
  }
}

class ShopApp extends StatelessWidget {
  final bool firstRun;
  late final Widget _home = firstRun ? SetupScreen() : PinScreen();
  ShopApp({super.key, required this.firstRun});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppPalette>(
      valueListenable: AppThemes.current,
      builder: (context, palette, _) {
        try {
          return _app(palette);
        } catch (e, st) {
          return _ErrorView('Ошибка оформления: $e', st);
        }
      },
    );
  }

  /// Шрифт по названию (Google Fonts); если не получилось — Manrope.
  TextTheme _fontTheme(String font, TextTheme base) {
    try {
      return GoogleFonts.getTextTheme(font, base);
    } catch (_) {
      return GoogleFonts.manropeTextTheme(base);
    }
  }

  Widget _app(AppPalette palette) {
    final base = ThemeData(
      brightness: palette.brightness,
      useMaterial3: true,
      colorSchemeSeed: palette.accent,
    );
    return MaterialApp(
      title: 'AVTOMAG GRS SOFT',
      debugShowCheckedModeBanner: false,
      locale: Locale('ru'),
      supportedLocales: [Locale('ru')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: base.copyWith(
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: base.colorScheme.copyWith(primary: palette.accent, onPrimary: palette.onAccent),
        // Если в основном шрифте нет символа (например, ₸) — берём его из встроенного DejaVu Sans.
        textTheme: _fontTheme(palette.font, base.textTheme).apply(fontFamilyFallback: ['DejaVuSans']),
      ),
      // Размер текста из настроек темы.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(palette.textScale)),
        child: child ?? SizedBox.shrink(),
      ),
      home: _home,
    );
  }
}

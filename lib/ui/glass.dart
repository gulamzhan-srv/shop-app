// Стеклянный стиль: тёмный фон с цветными пятнами и полупрозрачные карточки с размытием.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Набор цветов одной темы.
class AppPalette {
  final String id;
  final String name;
  final Brightness brightness;
  final Color bg, text, textDim, accent, onAccent, warn, amber, danger, blob1, blob2, sheet;
  final double blobOpacity;
  AppPalette({
    required this.id,
    required this.name,
    required this.brightness,
    required this.bg,
    required this.text,
    required this.textDim,
    required this.accent,
    required this.onAccent,
    required this.warn,
    required this.amber,
    required this.danger,
    required this.blob1,
    required this.blob2,
    required this.sheet,
    required this.blobOpacity,
  });
  bool get dark => brightness == Brightness.dark;
}

/// Темы приложения: Ночь, День, Рубин (красная), Зумруд (зелёная).
class AppThemes {
  static final night = AppPalette(
    id: 'night', name: 'Ночь', brightness: Brightness.dark,
    bg: Color(0xFF0B0F17), text: Color(0xFFF5F7FA), textDim: Color(0xBFF5F7FA),
    accent: Color(0xFF2DD4BF), onAccent: Color(0xFF062A26),
    warn: Color(0xFFFBBF24), amber: Color(0xFFF59E0B), danger: Color(0xFFF87171),
    blob1: Color(0xFF2DD4BF), blob2: Color(0xFFF59E0B), sheet: Color(0xFF151B27), blobOpacity: 0.4,
  );
  static final day = AppPalette(
    id: 'day', name: 'День', brightness: Brightness.light,
    bg: Color(0xFFF2F5F8), text: Color(0xFF111827), textDim: Color(0xB3111827),
    accent: Color(0xFF0D9488), onAccent: Color(0xFFFFFFFF),
    warn: Color(0xFFB45309), amber: Color(0xFFF59E0B), danger: Color(0xFFDC2626),
    blob1: Color(0xFF5EEAD4), blob2: Color(0xFFFCD34D), sheet: Color(0xFFFFFFFF), blobOpacity: 0.35,
  );
  static final kaspi = AppPalette(
    id: 'kaspi', name: 'Рубин', brightness: Brightness.light,
    bg: Color(0xFFF7F7F8), text: Color(0xFF1A1A1A), textDim: Color(0xB31A1A1A),
    accent: Color(0xFFF14635), onAccent: Color(0xFFFFFFFF),
    warn: Color(0xFFB45309), amber: Color(0xFFF59E0B), danger: Color(0xFFC81E1E),
    blob1: Color(0xFFF14635), blob2: Color(0xFFFFB4A8), sheet: Color(0xFFFFFFFF), blobOpacity: 0.18,
  );
  static final halyk = AppPalette(
    id: 'halyk', name: 'Зумруд', brightness: Brightness.light,
    bg: Color(0xFFF3F7F4), text: Color(0xFF14231B), textDim: Color(0xB314231B),
    accent: Color(0xFF0B7A55), onAccent: Color(0xFFFFFFFF),
    warn: Color(0xFFB45309), amber: Color(0xFFF2B705), danger: Color(0xFFDC2626),
    blob1: Color(0xFF15A06E), blob2: Color(0xFFFFC72C), sheet: Color(0xFFFFFFFF), blobOpacity: 0.25,
  );
  static final all = [night, day, kaspi, halyk];

  /// Текущая тема. Меняется в разделе «Тема», сохраняется на телефоне.
  static final current = ValueNotifier<AppPalette>(night);

  static AppPalette byId(String? id) => all.firstWhere((p) => p.id == id, orElse: () => night);

  /// Загрузить сохранённую тему (при запуске).
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      current.value = byId(p.getString('theme'));
    } catch (_) {}
  }

  /// Сменить тему и перерисовать все экраны.
  static Future<void> set(BuildContext context, AppPalette palette) async {
    current.value = palette;
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }
    // Перерисовываем всё дерево экранов (включая открытые страницы).
    final root = WidgetsBinding.instance.rootElement ?? context as Element;
    root.visitChildren(rebuild);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('theme', palette.id);
    } catch (_) {}
  }
}

/// Цвета текущей темы (используются во всех экранах).
class AppColors {
  static AppPalette get _p => AppThemes.current.value;
  static Color get bg => _p.bg;
  static Color get text => _p.text;
  static Color get textDim => _p.textDim;
  static Color get accent => _p.accent;
  static Color get onAccent => _p.onAccent;
  static Color get warn => _p.warn;
  static Color get amber => _p.amber;
  static Color get danger => _p.danger;
  static Color get sheet => _p.sheet;
  static bool get dark => _p.dark;

  /// Полупрозрачная заливка «стекла»: в тёмной теме — белая, в светлой — тёмная.
  static Color overlay(double opacity) =>
      _p.dark ? Colors.white.withOpacity(opacity) : Colors.black.withOpacity(opacity * 0.7);
}

/// Фон экрана: тёмный цвет + размытые цветные пятна.
class GlassBackground extends StatelessWidget {
  final Widget child;
  GlassBackground({super.key, required this.child});

  Widget _blob(Color c, double size, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(opacity)),
      );

  @override
  Widget build(BuildContext context) {
    // Значки строки состояния: светлые на тёмной теме, тёмные на светлой.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppColors.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: _body(),
    );
  }

  Widget _body() {
    return Container(
      color: AppColors.bg,
      child: Stack(children: [
        Positioned(top: -90, left: -100, child: _blob(AppThemes.current.value.blob1, 320, AppThemes.current.value.blobOpacity)),
        Positioned(bottom: 40, right: -110, child: _blob(AppThemes.current.value.blob2, 290, AppThemes.current.value.blobOpacity * 0.8)),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: SizedBox.expand(),
          ),
        ),
        Positioned.fill(child: SafeArea(child: child)),
      ]),
    );
  }
}

/// Стеклянная карточка.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? borderColor;

  GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.onTap,
    this.borderColor,
  });

  /// Скругление уменьшено для всего приложения (меньше «острые», аккуратнее).
  static const roundness = 0.55;

  @override
  Widget build(BuildContext context) {
    final radius = this.radius * roundness;
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.overlay(0.08),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor ?? AppColors.overlay(0.14)),
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: card),
    );
  }
}

/// Оформление полей ввода в стеклянном стиле.
InputDecoration glassInput(String label, {Widget? suffix, String? hint}) {
  OutlineInputBorder b(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    counterText: '',
    suffixIcon: suffix,
    labelStyle: TextStyle(color: AppColors.textDim),
    hintStyle: TextStyle(color: AppColors.text.withOpacity(0.45)),
    filled: true,
    fillColor: AppColors.overlay(0.06),
    border: b(AppColors.overlay(0.14)),
    enabledBorder: b(AppColors.overlay(0.14)),
    focusedBorder: b(AppColors.accent),
  );
}

/// Шапка экрана: кнопка «Назад» и заголовок.
class GlassHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  GlassHeader({super.key, required this.title, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(children: [
        GlassCard(
          radius: 14,
          padding: EdgeInsets.all(9),
          onTap: () => Navigator.of(context).maybePop(),
          child: Icon(Icons.arrow_back_ios_new, color: AppColors.text, size: 18, semanticLabel: 'Назад'),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(title,
              style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        ...actions,
      ]),
    );
  }
}

/// Главная кнопка (бирюзовая).
class AccentButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  AccentButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          disabledBackgroundColor: AppColors.accent.withOpacity(0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}

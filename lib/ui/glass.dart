// Стеклянный стиль: тёмный фон с цветными пятнами и полупрозрачные карточки с размытием.

import 'dart:convert';
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
  /// true — «плоская» тема: белые карточки с тенью вместо стекла, без цветных пятен.
  final bool solid;
  /// Цвет заливки шапки экрана и строки состояния (null — прозрачная шапка).
  final Color? header;
  /// Непрозрачность «стеклянных» карточек (0.03 — почти прозрачные, 0.35 — плотные).
  final double cardOpacity;
  /// Сила размытия под карточками.
  final double blur;
  /// Шрифт (Google Fonts) и масштаб текста.
  final String font;
  final double textScale;
  AppPalette({
    this.solid = false,
    this.header,
    this.cardOpacity = 0.08,
    this.blur = 20,
    this.font = 'Manrope',
    this.textScale = 1.0,
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

  /// Копия темы с изменёнными шрифтом и размером текста.
  AppPalette withFont(String f, double scale) => AppPalette(
        id: id, name: name, brightness: brightness, bg: bg, text: text, textDim: textDim, accent: accent,
        onAccent: onAccent, warn: warn, amber: amber, danger: danger, blob1: blob1, blob2: blob2, sheet: sheet,
        blobOpacity: blobOpacity, solid: solid, header: header, cardOpacity: cardOpacity, blur: blur,
        font: f, textScale: scale,
      );
}

/// Настройки «своей» темы (сохраняются на телефоне).
class ThemeSettings {
  bool dark;
  int accent; // цвет кнопок
  int bg; // цвет фона
  bool solid; // плоские карточки вместо стекла
  bool header; // цветная шапка
  double cardOpacity;
  double blur;
  String font;
  double textScale;
  ThemeSettings({
    this.dark = false,
    this.accent = 0xFFD7191F,
    this.bg = 0xFFF3F4F6,
    this.solid = true,
    this.header = true,
    this.cardOpacity = 0.08,
    this.blur = 20,
    this.font = 'Manrope',
    this.textScale = 1.0,
  });

  Map<String, Object> toJson() => {
        'dark': dark, 'accent': accent, 'bg': bg, 'solid': solid, 'header': header,
        'cardOpacity': cardOpacity, 'blur': blur, 'font': font, 'textScale': textScale,
      };

  static ThemeSettings fromJson(Map<String, dynamic> j) => ThemeSettings(
        dark: j['dark'] as bool? ?? false,
        accent: (j['accent'] as num?)?.toInt() ?? 0xFFD7191F,
        bg: (j['bg'] as num?)?.toInt() ?? 0xFFF3F4F6,
        solid: j['solid'] as bool? ?? true,
        header: j['header'] as bool? ?? true,
        cardOpacity: (j['cardOpacity'] as num?)?.toDouble() ?? 0.08,
        blur: (j['blur'] as num?)?.toDouble() ?? 20,
        font: j['font'] as String? ?? 'Manrope',
        textScale: (j['textScale'] as num?)?.toDouble() ?? 1.0,
      );

  /// Собрать тему из настроек.
  AppPalette toPalette() {
    final a = Color(accent);
    final onA = a.computeLuminance() > 0.5 ? Color(0xFF111111) : Color(0xFFFFFFFF);
    return AppPalette(
      id: 'custom', name: 'Своя', brightness: dark ? Brightness.dark : Brightness.light,
      bg: Color(bg),
      text: dark ? Color(0xFFECEFF4) : Color(0xFF111827),
      textDim: dark ? Color(0xFF9AA4B2) : Color(0xFF6B7280),
      accent: a, onAccent: onA,
      warn: dark ? Color(0xFFFBBF24) : Color(0xFFC2410C),
      amber: Color(0xFFF59E0B),
      danger: dark ? Color(0xFFF87171) : Color(0xFFDC2626),
      blob1: a, blob2: a.withOpacity(0.6),
      sheet: dark ? Color.lerp(Color(bg), Colors.white, 0.08)! : Color(0xFFFFFFFF),
      blobOpacity: solid ? 0 : 0.3,
      solid: solid, header: header ? a : null,
      cardOpacity: cardOpacity, blur: blur, font: font, textScale: textScale,
    );
  }
}

/// Темы приложения: GRS (красно-белая), Ночь, День, Рубин (красная), Зумруд (зелёная).
class AppThemes {
  /// Фирменная тема GRS Soft: красная шапка, белые карточки, светло-серый фон.
  static final grs = AppPalette(
    id: 'grs', name: 'GRS (красно-белая)', brightness: Brightness.light,
    bg: Color(0xFFF3F4F6), text: Color(0xFF111827), textDim: Color(0xFF6B7280),
    accent: Color(0xFFD7191F), onAccent: Color(0xFFFFFFFF),
    warn: Color(0xFFC2410C), amber: Color(0xFFF59E0B), danger: Color(0xFFDC2626),
    blob1: Color(0xFFF3F4F6), blob2: Color(0xFFF3F4F6), sheet: Color(0xFFFFFFFF), blobOpacity: 0,
    solid: true, header: Color(0xFFD7191F),
  );
  /// Тёмная тема: ровный графитовый фон, плотные карточки, читаемый серый текст.
  static final night = AppPalette(
    id: 'night', name: 'Ночь', brightness: Brightness.dark,
    bg: Color(0xFF111318), text: Color(0xFFECEFF4), textDim: Color(0xFF9AA4B2),
    accent: Color(0xFF2DD4BF), onAccent: Color(0xFF062A26),
    warn: Color(0xFFFBBF24), amber: Color(0xFFF59E0B), danger: Color(0xFFF87171),
    blob1: Color(0xFF2DD4BF), blob2: Color(0xFF6366F1), sheet: Color(0xFF1B1F27), blobOpacity: 0.18,
    cardOpacity: 0.06, blur: 14,
  );
  /// Графит: тёмная плоская тема с оранжевыми кнопками.
  static final graphite = AppPalette(
    id: 'graphite', name: 'Графит', brightness: Brightness.dark,
    bg: Color(0xFF16181D), text: Color(0xFFF1F3F6), textDim: Color(0xFFA0A8B4),
    accent: Color(0xFFF97316), onAccent: Color(0xFFFFFFFF),
    warn: Color(0xFFFBBF24), amber: Color(0xFFF59E0B), danger: Color(0xFFF87171),
    blob1: Color(0xFF16181D), blob2: Color(0xFF16181D), sheet: Color(0xFF22252C), blobOpacity: 0,
    solid: true, header: Color(0xFF22252C),
  );
  /// Океан: светлая тема с синей шапкой.
  static final ocean = AppPalette(
    id: 'ocean', name: 'Океан', brightness: Brightness.light,
    bg: Color(0xFFF1F5F9), text: Color(0xFF0F172A), textDim: Color(0xFF64748B),
    accent: Color(0xFF2563EB), onAccent: Color(0xFFFFFFFF),
    warn: Color(0xFFC2410C), amber: Color(0xFFF59E0B), danger: Color(0xFFDC2626),
    blob1: Color(0xFFF1F5F9), blob2: Color(0xFFF1F5F9), sheet: Color(0xFFFFFFFF), blobOpacity: 0,
    solid: true, header: Color(0xFF2563EB),
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
  static final all = [grs, ocean, night, graphite, day, kaspi, halyk];

  /// Своя тема пользователя (null — ещё не настраивал).
  static ThemeSettings custom = ThemeSettings();

  /// Текущая тема. Меняется в разделе «Тема», сохраняется на телефоне.
  static final current = ValueNotifier<AppPalette>(grs);

  static AppPalette byId(String? id) => all.firstWhere((p) => p.id == id, orElse: () => grs);

  /// Загрузить сохранённую тему (при запуске).
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      // Один раз после обновления включаем фирменную тему GRS (потом можно сменить в «Настройки → Тема»).
      if (!(p.getBool('theme_grs_set') ?? false)) {
        await p.setBool('theme_grs_set', true);
        await p.setString('theme', grs.id);
      }
      final cj = p.getString('theme_custom');
      if (cj != null) {
        try {
          custom = ThemeSettings.fromJson(jsonDecode(cj) as Map<String, dynamic>);
        } catch (_) {}
      }
      final id = p.getString('theme');
      var pal = id == 'custom' ? custom.toPalette() : byId(id);
      // Шрифт и размер текста можно менять и для готовых тем.
      final f = p.getString('theme_font');
      final sc = p.getDouble('theme_scale');
      if (id != 'custom' && (f != null || sc != null)) pal = pal.withFont(f ?? pal.font, sc ?? pal.textScale);
      current.value = pal;
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
      if (palette.id == 'custom') {
        await p.setString('theme_custom', jsonEncode(custom.toJson()));
      } else {
        await p.setString('theme_font', palette.font);
        await p.setDouble('theme_scale', palette.textScale);
      }
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
  static bool get solid => _p.solid;
  static Color? get header => _p.header;

  /// Полупрозрачная заливка «стекла»: в тёмной теме — белая, в светлой — тёмная.
  static Color overlay(double opacity) => _p.dark
      ? Colors.white.withOpacity(opacity)
      : Colors.black.withOpacity(opacity * (_p.solid ? 0.45 : 0.7));
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
      value: (AppColors.dark || AppColors.header != null) ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: AppColors.solid ? _flat(context) : _body(),
    );
  }

  /// Плоская тема: ровный фон, строка состояния в цвет шапки.
  Widget _flat(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      color: AppColors.bg,
      child: Column(children: [
        if (AppColors.header != null) Container(height: top, color: AppColors.header),
        Expanded(
          child: SafeArea(top: AppColors.header == null, child: child),
        ),
      ]),
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
    if (AppColors.solid) {
      // Плоская тема: белая карточка с мягкой тенью.
      final flat = Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.sheet,
          borderRadius: BorderRadius.circular(radius + 4),
          border: Border.all(color: borderColor ?? Color(0xFFE5E7EB)),
          boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: child,
      );
      if (onTap == null) return flat;
      return Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: BorderRadius.circular(radius + 4), onTap: onTap, child: flat),
      );
    }
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: AppThemes.current.value.blur, sigmaY: AppThemes.current.value.blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.overlay(AppThemes.current.value.cardOpacity),
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
    final h = AppColors.header;
    if (h != null) {
      // Плоская тема: шапка залита фирменным цветом, текст и значки белые.
      return Container(
        color: h,
        padding: EdgeInsets.fromLTRB(12, 8, 8, 10),
        margin: EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Material(
            color: Colors.white.withOpacity(0.16),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.of(context).maybePop(),
              child: Padding(
                padding: EdgeInsets.all(9),
                child: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18, semanticLabel: 'Назад'),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          if (actions.isNotEmpty)
            ColorFiltered(
              colorFilter: ColorFilter.mode(Colors.white, BlendMode.srcIn),
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
        ]),
      );
    }
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
      height: 48,
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

/// Окно поверх экрана с размытым прозрачным фоном («стекло») — для всех диалогов.
/// Используется вместо showDialog: те же параметры context / builder / barrierDismissible.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Закрыть',
    barrierColor: Colors.black.withOpacity(0.22),
    transitionDuration: Duration(milliseconds: 180),
    pageBuilder: (ctx, _, __) {
      final theme = Theme.of(ctx);
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
        child: Theme(
          // Полупрозрачный фон самого окна (Material 3 берёт его из surfaceContainerHigh).
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              surfaceContainerHigh: AppColors.sheet.withOpacity(0.86),
              surfaceTint: Colors.transparent,
            ),
          ),
          child: Builder(builder: builder),
        ),
      );
    },
    transitionBuilder: (_, a, __, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
    ),
  );
}

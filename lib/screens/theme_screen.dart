// Оформление: готовые темы, своя тема (цвет кнопок и фона, стекло или плоские карточки,
// прозрачность, размытие, цветная шапка), шрифт и размер текста. Всё видно сразу.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../ui/glass.dart';

class ThemeScreen extends StatefulWidget {
  ThemeScreen({super.key});
  @override
  State<ThemeScreen> createState() => _ThemeScreenState();
}

class _ThemeScreenState extends State<ThemeScreen> {
  static const _fonts = ['Manrope', 'Inter', 'Roboto', 'Montserrat', 'Nunito', 'Open Sans', 'PT Sans', 'Rubik'];
  static const _accents = [
    0xFFD7191F, 0xFFF14635, 0xFFEA580C, 0xFFF59E0B, 0xFF16A34A, 0xFF0B7A55,
    0xFF0D9488, 0xFF0891B2, 0xFF2563EB, 0xFF4F46E5, 0xFF7C3AED, 0xFFDB2777,
  ];
  static const _lightBg = [0xFFF3F4F6, 0xFFFFFFFF, 0xFFF1F5F9, 0xFFFEF2F2, 0xFFECFDF5, 0xFFFFF7ED, 0xFFF5F3FF];
  static const _darkBg = [0xFF111318, 0xFF0B0F17, 0xFF16181D, 0xFF0F172A, 0xFF1A1A2E, 0xFF102A2A, 0xFF1F1B24];

  AppPalette get _cur => AppThemes.current.value;
  ThemeSettings get _c => AppThemes.custom;

  Future<void> _apply(AppPalette p) async {
    await AppThemes.set(context, p);
    if (mounted) setState(() {});
  }

  /// Изменить свою тему и сразу применить.
  Future<void> _custom(void Function(ThemeSettings c) change) async {
    if (_cur.id != 'custom') {
      // Начинаем «свою» тему с текущей: цвета, стиль, шрифт и размер.
      final p = _cur;
      _c
        ..dark = p.dark
        ..accent = p.accent.value
        ..bg = p.bg.value
        ..solid = p.solid
        ..header = p.header != null
        ..cardOpacity = p.cardOpacity
        ..blur = p.blur
        ..font = p.font
        ..textScale = p.textScale;
    }
    change(_c);
    await _apply(_c.toPalette());
  }

  Future<void> _font(String f) async {
    if (_cur.id == 'custom') return _custom((c) => c.font = f);
    await _apply(_cur.withFont(f, _cur.textScale));
  }

  Future<void> _scale(double s) async {
    if (_cur.id == 'custom') return _custom((c) => c.textScale = s);
    await _apply(_cur.withFont(_cur.font, s));
  }

  Widget _title(String t) => Padding(
        padding: EdgeInsets.fromLTRB(2, 16, 0, 8),
        child: Text(t, style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _swatch(int color, bool selected, VoidCallback onTap, {bool border = false}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Color(color),
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? AppColors.text : (border ? AppColors.overlay(0.25) : Colors.transparent),
                width: selected ? 3 : 1),
          ),
          child: selected ? Icon(Icons.check, size: 18, color: Color(color).computeLuminance() > 0.5 ? Colors.black : Colors.white) : null,
        ),
      );

  Widget _preview() => GlassCard(
        radius: 22,
        padding: EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Образец', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          SizedBox(height: 4),
          Text('Выручка: 1 250 000 ₸', style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
          Text('Кола 1л · в наличии 24 шт', style: TextStyle(color: AppColors.textDim)),
          SizedBox(height: 10),
          AccentButton(label: 'Оплатить', onPressed: () {}),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final cur = _cur;
    final isCustom = cur.id == 'custom';
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Тема и шрифт'),
          Expanded(
            child: ListView(padding: EdgeInsets.fromLTRB(16, 0, 16, 30), children: [
              _preview(),

              // ---------- Готовые темы ----------
              _title('Готовые темы'),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final p in AppThemes.all)
                  GestureDetector(
                    onTap: () => _apply(p.withFont(cur.font, cur.textScale)),
                    child: Container(
                      width: 100,
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: p.bg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cur.id == p.id ? p.accent : AppColors.overlay(0.2), width: cur.id == p.id ? 3 : 1),
                      ),
                      child: Column(children: [
                        Container(height: 10, decoration: BoxDecoration(color: p.header ?? p.accent.withOpacity(0.5), borderRadius: BorderRadius.circular(4))),
                        SizedBox(height: 6),
                        Container(height: 18, decoration: BoxDecoration(color: p.solid ? p.sheet : p.text.withOpacity(0.12), borderRadius: BorderRadius.circular(5))),
                        SizedBox(height: 6),
                        Container(height: 12, decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(4))),
                        SizedBox(height: 6),
                        Text(p.name, textAlign: TextAlign.center, maxLines: 2,
                            style: TextStyle(color: p.text, fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
              ]),

              // ---------- Своя тема ----------
              _title('Своя тема${isCustom ? ' (включена)' : ''}'),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text('Светлая'), icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(value: true, label: Text('Тёмная'), icon: Icon(Icons.dark_mode_outlined)),
                ],
                selected: {isCustom ? _c.dark : cur.dark},
                onSelectionChanged: (v) => _custom((c) {
                  c.dark = v.first;
                  final bgLight = Color(c.bg).computeLuminance() > 0.5;
                  if (c.dark && bgLight) c.bg = _darkBg.first;
                  if (!c.dark && !bgLight) c.bg = _lightBg.first;
                }),
              ),
              SizedBox(height: 12),
              Text('Цвет кнопок и акцентов', style: TextStyle(color: AppColors.textDim)),
              SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final a in _accents) _swatch(a, isCustom && _c.accent == a, () => _custom((c) => c.accent = a)),
              ]),
              SizedBox(height: 12),
              Text('Цвет фона', style: TextStyle(color: AppColors.textDim)),
              SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final b in (isCustom ? _c.dark : cur.dark) ? _darkBg : _lightBg)
                  _swatch(b, isCustom && _c.bg == b, () => _custom((c) => c.bg = b), border: true),
              ]),
              SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text('Плоские карточки')),
                  ButtonSegment(value: false, label: Text('Стекло (размытие)')),
                ],
                selected: {isCustom ? _c.solid : cur.solid},
                onSelectionChanged: (v) => _custom((c) => c.solid = v.first),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Цветная шапка экранов', style: TextStyle(color: AppColors.text)),
                value: isCustom ? _c.header : cur.header != null,
                onChanged: (v) => _custom((c) => c.header = v),
              ),
              if (!(isCustom ? _c.solid : cur.solid)) ...[
                Text('Прозрачность карточек: ${((isCustom ? _c.cardOpacity : cur.cardOpacity) * 100).round()}%',
                    style: TextStyle(color: AppColors.textDim)),
                Slider(
                  min: 0.03,
                  max: 0.35,
                  value: (isCustom ? _c.cardOpacity : cur.cardOpacity).clamp(0.03, 0.35).toDouble(),
                  onChanged: (v) => _custom((c) => c.cardOpacity = v),
                ),
                Text('Размытие: ${(isCustom ? _c.blur : cur.blur).round()}', style: TextStyle(color: AppColors.textDim)),
                Slider(
                  min: 0,
                  max: 40,
                  value: (isCustom ? _c.blur : cur.blur).clamp(0, 40).toDouble(),
                  onChanged: (v) => _custom((c) => c.blur = v),
                ),
              ],

              // ---------- Шрифт ----------
              _title('Шрифт'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final f in _fonts)
                  ChoiceChip(
                    selected: cur.font == f,
                    onSelected: (_) => _font(f),
                    label: Text(f, style: _safeFont(f)),
                  ),
              ]),
              _title('Размер текста: ${(cur.textScale * 100).round()}%'),
              Row(children: [
                Text('А', style: TextStyle(color: AppColors.text, fontSize: 13)),
                Expanded(
                  child: Slider(
                    min: 0.85,
                    max: 1.35,
                    divisions: 10,
                    value: cur.textScale.clamp(0.85, 1.35).toDouble(),
                    label: '${(cur.textScale * 100).round()}%',
                    onChanged: (v) => _scale(v),
                  ),
                ),
                Text('А', style: TextStyle(color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w700)),
              ]),
              Center(
                child: TextButton(
                  onPressed: () => _scale(1.0),
                  child: Text('Обычный размер'),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  TextStyle? _safeFont(String f) {
    try {
      return GoogleFonts.getFont(f, fontWeight: FontWeight.w600);
    } catch (_) {
      return null;
    }
  }
}

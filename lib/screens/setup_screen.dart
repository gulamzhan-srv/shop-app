// Первая настройка: название магазина, имя хозяина и его PIN-код.
// Показывается только один раз, пока в базе нет хозяина.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../ui/glass.dart';
import '../ui/recovery_dialog.dart';
import 'pin_screen.dart';

class SetupScreen extends StatefulWidget {
  SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _shop = TextEditingController();
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _error = null);
    if (_shop.text.trim().isEmpty || _name.text.trim().isEmpty) {
      setState(() => _error = 'Заполните название магазина и имя');
      return;
    }
    if (_pin.text != _pin2.text) {
      setState(() => _error = 'PIN-коды не совпадают');
      return;
    }
    setState(() => _busy = true);
    final err = await AuthService.instance
        .addEmployee(name: _name.text, role: Role.owner, pin: _pin.text);
    if (err != null) {
      setState(() {
        _error = err;
        _busy = false;
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shop_name', _shop.text.trim());
    final code = await AuthService.instance.newRecoveryCode();
    if (!mounted) return;
    await showRecoveryCode(context, code);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PinScreen()));
  }

  /// Новый телефон: входим в Google-аккаунт магазина и скачиваем всё с Google Диска.
  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await SyncService.instance.restore();
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = 'Не удалось восстановить: $err';
      });
      return;
    }
    if (!await AuthService.instance.hasOwner()) {
      setState(() {
        _busy = false;
        _error = 'На Google Диске (${SyncService.instance.email}) нет данных магазина. '
            'Проверьте, что выбран тот же аккаунт, что на старом телефоне.';
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getString('shop_name') ?? '').isEmpty) await prefs.setString('shop_name', 'Магазин');
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PinScreen()));
  }

  Widget _field(String label, TextEditingController c, {bool pin = false}) => Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: pin,
          maxLength: pin ? pinLength : null,
          keyboardType: pin ? TextInputType.number : TextInputType.text,
          style: TextStyle(color: AppColors.text, fontSize: 16),
          decoration: InputDecoration(
            labelText: label,
            counterText: '',
            labelStyle: TextStyle(color: AppColors.textDim),
            filled: true,
            fillColor: AppColors.overlay(0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.overlay(0.14)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.overlay(0.14)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.accent),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 420),
              child: GlassCard(
                radius: 28,
                padding: EdgeInsets.all(22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Первая настройка',
                      style: TextStyle(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w800)),
                  SizedBox(height: 6),
                  Text('Создайте хозяина магазина. Кассиров добавите потом.',
                      style: TextStyle(color: AppColors.textDim, fontSize: 14)),
                  SizedBox(height: 18),
                  _field('Название магазина', _shop),
                  _field('Имя хозяина', _name),
                  _field('PIN-код ($pinLength цифр)', _pin, pin: true),
                  _field('Повторите PIN-код', _pin2, pin: true),
                  if (_error != null)
                    Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: TextStyle(color: AppColors.danger)),
                    ),
                  AccentButton(label: _busy ? 'Сохраняю…' : 'Сохранить', onPressed: _busy ? null : _save),
                  SizedBox(height: 18),
                  Divider(color: AppColors.overlay(0.24)),
                  SizedBox(height: 10),
                  Text('Магазин уже работал на другом телефоне?',
                      style: TextStyle(color: AppColors.textDim, fontSize: 14)),
                  SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _restore,
                    icon: Icon(Icons.cloud_download_outlined),
                    label: Text('Восстановить из Google Диска'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      minimumSize: Size.fromHeight(52),
                      side: BorderSide(color: AppColors.accent.withOpacity(0.6)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Первый запуск.
//  1) Вход в Google-аккаунт магазина.
//  2) Если на Google Диске этого аккаунта уже есть база — восстанавливаем её (с полосой прогресса).
//  3) Если базы нет — создаём новую: название магазина, хозяин и его PIN.
// Можно работать и без Google (данные только на этом телефоне), вход сделать позже.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/repo.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../ui/glass.dart';
import '../ui/recovery_dialog.dart';
import 'pin_screen.dart';
import 'sync_screen.dart';

enum _Step { start, checking, found, newBase, restoring }

class SetupScreen extends StatefulWidget {
  SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  _Step _step = _Step.start;
  final _shop = TextEditingController();
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _showGoogleHint = false;

  String get _email => SyncService.instance.email ?? '';

  // ---------- Вход в Google и поиск резервной копии ----------
  Future<void> _google() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    if (!SyncService.instance.signedIn) {
      final err = await SyncService.instance.signIn();
      if (!mounted) return;
      if (err != null) {
        setState(() {
          _busy = false;
          _error = err;
          _showGoogleHint = err.contains('ошибка 10');
        });
        return;
      }
    }
    setState(() => _step = _Step.checking);
    final has = await SyncService.instance.hasBackup();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (has == null) {
        _step = _Step.start;
        _error = 'Не удалось проверить Google Диск. Проверьте интернет и попробуйте ещё раз.';
      } else {
        _step = has ? _Step.found : _Step.newBase;
      }
    });
  }

  Future<void> _otherAccount() async {
    await SyncService.instance.signOut();
    if (!mounted) return;
    setState(() => _step = _Step.start);
    _google();
  }

  // ---------- Восстановление ----------
  Future<void> _restore() async {
    setState(() {
      _step = _Step.restoring;
      _error = null;
    });
    final err = await SyncService.instance.syncNow();
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _step = _Step.found;
        _error = 'Не удалось восстановить: $err';
      });
      return;
    }
    if (!await AuthService.instance.hasOwner()) {
      setState(() {
        _step = _Step.found;
        _error = 'Данные скачаны не полностью (нет хозяина магазина). Нажмите «Восстановить» ещё раз.';
      });
      return;
    }
    // Название магазина хранится в общей базе (settings) — берём его оттуда.
    final rows = await Repo.instance.list('settings', where: 'id = ?', args: ['shop_name']);
    final prefs = await SharedPreferences.getInstance();
    final name = rows.isEmpty ? null : rows.first['value'] as String?;
    await prefs.setString('shop_name', (name == null || name.isEmpty) ? 'AVTOMAG GRS SOFT' : name);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PinScreen()));
  }

  // ---------- Новая база ----------
  Future<void> _create() async {
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
    final err = await AuthService.instance.addEmployee(name: _name.text, role: Role.owner, pin: _pin.text);
    if (err != null) {
      setState(() {
        _error = err;
        _busy = false;
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shop_name', _shop.text.trim());
    await Repo.instance.save('settings', {'id': 'shop_name', 'value': _shop.text.trim()});
    final code = await AuthService.instance.newRecoveryCode();
    if (!mounted) return;
    await showRecoveryCode(context, code);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PinScreen()));
  }

  // ---------- Оформление ----------
  Widget _field(String label, TextEditingController c, {bool pin = false}) => Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          obscureText: pin,
          maxLength: pin ? pinLength : null,
          keyboardType: pin ? TextInputType.number : TextInputType.text,
          style: TextStyle(color: AppColors.text, fontSize: 16),
          decoration: glassInput(label).copyWith(counterText: ''),
        ),
      );

  Widget _title(String t, String sub) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t, style: TextStyle(color: AppColors.text, fontSize: 21, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        Text(sub, style: TextStyle(color: AppColors.textDim, fontSize: 14, height: 1.35)),
        SizedBox(height: 16),
      ]);

  Widget _outlined(String label, IconData icon, VoidCallback? onTap) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          minimumSize: Size.fromHeight(48),
          side: BorderSide(color: AppColors.accent.withOpacity(0.6)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  List<Widget> _content() {
    switch (_step) {
      case _Step.start:
        return [
          _title('Добро пожаловать',
              'Войдите в Google-аккаунт магазина. Если на нём уже есть база — она восстановится, '
                  'если нет — создадим новую. Все телефоны магазина входят в ОДИН аккаунт.'),
          AccentButton(label: _busy ? 'Вход…' : 'Войти через Google', onPressed: _busy ? null : _google),
          if (_showGoogleHint) ...[SizedBox(height: 12), GoogleSetupHint()],
          SizedBox(height: 12),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _step = _Step.newBase),
            child: Text('Начать без Google (только на этом телефоне)',
                style: TextStyle(color: AppColors.textDim)),
          ),
        ];
      case _Step.checking:
        return [
          _title('Проверяю Google Диск', _email),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 12),
        ];
      case _Step.found:
        return [
          _title('База магазина найдена',
              'На Google Диске аккаунта $_email есть данные магазина. Восстановите их на этот телефон.'),
          AccentButton(label: 'Восстановить', onPressed: _restore),
          SizedBox(height: 10),
          _outlined('Выбрать другой аккаунт', Icons.switch_account_outlined, _otherAccount),
        ];
      case _Step.restoring:
        return [
          _title('Восстановление', 'Скачиваю данные магазина с Google Диска…'),
          SyncProgressBar(),
        ];
      case _Step.newBase:
        return [
          _title(
              'Новая база',
              SyncService.instance.signedIn
                  ? 'На аккаунте $_email базы ещё нет. Создайте хозяина магазина — '
                      'данные будут сохраняться на этот Google Диск.'
                  : 'Создайте хозяина магазина. Войти в Google можно позже в разделе «Google Диск».'),
          _field('Название магазина', _shop),
          _field('Имя хозяина', _name),
          _field('PIN-код ($pinLength цифр)', _pin, pin: true),
          _field('Повторите PIN-код', _pin2, pin: true),
          AccentButton(label: _busy ? 'Сохраняю…' : 'Создать', onPressed: _busy ? null : _create),
          if (SyncService.instance.signedIn) ...[
            SizedBox(height: 10),
            _outlined('Выбрать другой аккаунт', Icons.switch_account_outlined, _busy ? null : _otherAccount),
          ] else
            TextButton(
              onPressed: _busy ? null : () => setState(() => _step = _Step.start),
              child: Text('Назад к входу через Google', style: TextStyle(color: AppColors.textDim)),
            ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 420),
              child: Column(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset('assets/icon.png', width: 72, height: 72),
                ),
                SizedBox(height: 8),
                Text('AVTOMAG GRS SOFT',
                    style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w800)),
                SizedBox(height: 14),
                GlassCard(
                  radius: 20,
                  padding: EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    ..._content(),
                    if (_error != null)
                      Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(_error!, style: TextStyle(color: AppColors.danger)),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

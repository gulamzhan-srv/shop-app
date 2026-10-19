// Экран входа по PIN-коду (6 цифр). По PIN определяется роль.
// «Забыли PIN?» — восстановление PIN хозяина / администратора по коду восстановления.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../ui/glass.dart';
import '../ui/pin_pad.dart';
import 'change_pin_screen.dart';
import 'home_screen.dart';

class PinScreen extends StatefulWidget {
  PinScreen({super.key});
  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _pin = '';
  bool _error = false;
  bool _busy = false;
  bool _legacy = false; // есть сотрудники со старым 4-значным PIN
  String _shopName = '';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _shopName = p.getString('shop_name') ?? 'AVTOMAG GRS SOFT');
    });
    AuthService.instance.hasLegacyPins().then((v) => _legacy = v);
  }

  Future<void> _add(String d) async {
    if (_busy || _pin.length >= pinLength) return;
    setState(() {
      _pin += d;
      _error = false;
    });
    if (_pin.length == 4 && _legacy) {
      // Старый 4-значный PIN: пробуем тихо, без ошибки (вдруг вводят 6 цифр).
      final e = await AuthService.instance.login(_pin, remember: false);
      if (e != null && e.mustChangePin) {
        AuthService.instance.current = e;
        AuthService.instance.logEvent('Вход (старый PIN)');
        return _enter(e);
      }
    }
    if (_pin.length == pinLength) await _check();
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    final e = await AuthService.instance.login(_pin);
    if (!mounted) return;
    if (e == null) {
      setState(() {
        _error = true;
        _pin = '';
        _busy = false;
      });
      return;
    }
    await _enter(e);
  }

  Future<void> _enter(Employee e) async {
    if (e.mustChangePin) {
      // Старый 4-значный PIN — сначала обязательно задать новый из 6 цифр.
      final ok = await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => ChangePinScreen(forced: true)));
      if (ok != true) {
        AuthService.instance.lock();
        if (mounted) setState(() {
          _pin = '';
          _busy = false;
        });
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen()));
  }

  Future<void> _forgot() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecoverPinScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 420),
              child: Column(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset('assets/icon.png', width: 84, height: 84),
                ),
                SizedBox(height: 10),
                Text(_shopName,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text(_error ? 'Неверный PIN-код' : 'Введите PIN-код',
                    style: TextStyle(color: _error ? AppColors.danger : AppColors.textDim, fontSize: 15)),
                SizedBox(height: 20),
                PinDots(filled: _pin.length, error: _error),
                SizedBox(height: 22),
                PinPad(
                  onDigit: _add,
                  onBackspace: () => setState(() {
                    if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
                  }),
                  onClear: () => setState(() => _pin = ''),
                ),
                SizedBox(height: 10),
                TextButton(
                  onPressed: _forgot,
                  child: Text('Забыли PIN?', style: TextStyle(color: AppColors.accent)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Восстановление PIN хозяина / администратора по коду восстановления.
class RecoverPinScreen extends StatefulWidget {
  RecoverPinScreen({super.key});
  @override
  State<RecoverPinScreen> createState() => _RecoverPinScreenState();
}

class _RecoverPinScreenState extends State<RecoverPinScreen> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  List<Employee> _managers = [];
  String? _who;
  bool _codeOk = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AuthService.instance.managers().then((l) {
      if (mounted) {
        setState(() {
          _managers = l;
          if (l.length == 1) _who = l.first.id;
        });
      }
    });
  }

  Future<void> _checkCode() async {
    final ok = await AuthService.instance.checkRecoveryCode(_code.text);
    setState(() {
      _codeOk = ok;
      _error = ok ? null : 'Код восстановления неверный';
    });
  }

  Future<void> _save() async {
    if (_who == null) return setState(() => _error = 'Выберите, чей PIN восстановить');
    if (_pin.text != _pin2.text) return setState(() => _error = 'PIN-коды не совпадают');
    final err = await AuthService.instance.changePin(_who!, _pin.text);
    if (!mounted) return;
    if (err != null) return setState(() => _error = err);
    final who = _managers.firstWhere((m) => m.id == _who);
    AuthService.instance.logEvent('Восстановление PIN по коду', who: who);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PIN изменён. Войдите с новым PIN.')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Восстановление PIN'),
          Expanded(
            child: ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              Text(
                'Введите код восстановления, который приложение показало хозяину при первой настройке '
                '(вида ABCD-EFGH-JKLM). Если кода нет — PIN может сбросить администратор в разделе «Сотрудники».',
                style: TextStyle(color: AppColors.textDim, height: 1.4),
              ),
              SizedBox(height: 14),
              TextField(
                controller: _code,
                enabled: !_codeOk,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(color: AppColors.text, letterSpacing: 1.5),
                decoration: glassInput('Код восстановления'),
              ),
              SizedBox(height: 12),
              if (!_codeOk) AccentButton(label: 'Проверить код', onPressed: _checkCode),
              if (_codeOk) ...[
                DropdownButtonFormField<String>(
                  value: _who,
                  dropdownColor: AppColors.sheet,
                  style: TextStyle(color: AppColors.text, fontSize: 16),
                  decoration: glassInput('Чей PIN восстановить'),
                  items: [
                    for (final m in _managers)
                      DropdownMenuItem(value: m.id, child: Text('${m.name} · ${roleName(m.role)}')),
                  ],
                  onChanged: (v) => setState(() => _who = v),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: _pin,
                  obscureText: true,
                  maxLength: pinLength,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AppColors.text),
                  decoration: glassInput('Новый PIN ($pinLength цифр)'),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: _pin2,
                  obscureText: true,
                  maxLength: pinLength,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AppColors.text),
                  decoration: glassInput('Повторите PIN'),
                ),
                SizedBox(height: 14),
                AccentButton(label: 'Сохранить новый PIN', onPressed: _save),
              ],
              if (_error != null)
                Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: AppColors.danger)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

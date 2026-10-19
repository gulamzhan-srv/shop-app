// Смена своего PIN-кода (6 цифр).
// forced = true — после входа со старым 4-значным PIN: старый PIN уже проверен при входе.

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../ui/glass.dart';

class ChangePinScreen extends StatefulWidget {
  final bool forced;
  ChangePinScreen({super.key, this.forced = false});
  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final _old = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _error = null);
    if (_pin.text != _pin2.text) return setState(() => _error = 'PIN-коды не совпадают');
    setState(() => _busy = true);
    final me = AuthService.instance.current;
    final String? err;
    if (widget.forced && me != null) {
      err = await AuthService.instance.changePin(me.id, _pin.text);
    } else {
      err = await AuthService.instance.changeOwnPin(_old.text, _pin.text);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) return setState(() => _error = err);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PIN изменён')));
    Navigator.of(context).pop(true);
  }

  Widget _field(TextEditingController c, String label) => Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: true,
          maxLength: pinLength,
          keyboardType: TextInputType.number,
          style: TextStyle(color: AppColors.text, letterSpacing: 4),
          decoration: glassInput(label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: widget.forced ? 'Новый PIN-код' : 'Сменить PIN'),
          Expanded(
            child: ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              if (widget.forced)
                Padding(
                  padding: EdgeInsets.only(bottom: 14),
                  child: Text(
                    'Для безопасности PIN-код теперь из $pinLength цифр. Задайте новый PIN, '
                    'дальше входите с ним.',
                    style: TextStyle(color: AppColors.textDim, height: 1.4),
                  ),
                ),
              if (!widget.forced) _field(_old, 'Текущий PIN'),
              _field(_pin, 'Новый PIN ($pinLength цифр)'),
              _field(_pin2, 'Повторите новый PIN'),
              if (_error != null)
                Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: TextStyle(color: AppColors.danger)),
                ),
              AccentButton(label: _busy ? 'Сохраняю…' : 'Сохранить', onPressed: _busy ? null : _save),
            ]),
          ),
        ]),
      ),
    );
  }
}

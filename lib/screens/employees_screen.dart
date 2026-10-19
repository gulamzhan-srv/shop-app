// Сотрудники (только хозяин): добавить кассира или хозяина, сменить PIN, отключить.

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../ui/glass.dart';
import '../ui/recovery_dialog.dart';

class EmployeesScreen extends StatefulWidget {
  EmployeesScreen({super.key});
  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Map<String, Object?>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await AuthService.instance.all();
    if (mounted) setState(() => _items = l);
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _add() async {
    final name = TextEditingController();
    final pin = TextEditingController();
    var role = Role.cashier;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('Новый сотрудник'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: InputDecoration(labelText: 'Имя')),
            TextField(
              controller: pin,
              maxLength: pinLength,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'PIN-код ($pinLength цифр)'),
            ),
            SegmentedButton<Role>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: Role.cashier, label: Text('Кассир')),
                ButtonSegment(value: Role.owner, label: Text('Хозяин')),
                ButtonSegment(value: Role.admin, label: Text('Админ')),
              ],
              selected: {role},
              onSelectionChanged: (v) => setD(() => role = v.first),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Добавить')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isEmpty) return _snack('Введите имя');
    final err = await AuthService.instance.addEmployee(name: name.text, role: role, pin: pin.text);
    _snack(err ?? 'Сотрудник добавлен');
    _load();
  }

  Future<void> _newRecovery() async {
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Новый код восстановления'),
        content: Text('Старый код перестанет действовать. Создать новый?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Создать')),
        ],
      ),
    );
    if (ok != true) return;
    final code = await AuthService.instance.newRecoveryCode();
    if (mounted) await showRecoveryCode(context, code);
  }

  Future<void> _changePin(Map<String, Object?> e) async {
    final pin = TextEditingController();
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Новый PIN: ${e['name']}'),
        content: TextField(
          controller: pin,
          autofocus: true,
          maxLength: pinLength,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'PIN-код ($pinLength цифр)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Сохранить')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await AuthService.instance.changePin(e['id'] as String, pin.text);
    _snack(err ?? 'PIN изменён');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        icon: Icon(Icons.person_add_alt_1_outlined),
        label: Text('Сотрудник', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Сотрудники', actions: [
            IconButton(
              onPressed: _newRecovery,
              icon: Icon(Icons.key_outlined, color: AppColors.accent),
              tooltip: 'Новый код восстановления PIN',
            ),
          ]),
          Expanded(
            child: ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              for (final e in _items)
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: GlassCard(
                    radius: 18,
                    padding: EdgeInsets.fromLTRB(14, 6, 6, 6),
                    child: Row(children: [
                      Icon(
                          e['role'] == 'admin'
                              ? Icons.admin_panel_settings_outlined
                              : e['role'] == 'owner'
                                  ? Icons.workspace_premium_outlined
                                  : Icons.badge_outlined,
                          color: e['active'] == 1 ? AppColors.accent : AppColors.textDim),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e['name'] as String,
                              style: TextStyle(
                                  color: e['active'] == 1 ? AppColors.text : AppColors.textDim,
                                  fontWeight: FontWeight.w700)),
                          Text(
                              '${roleName(roleFrom(e['role']))}${e['active'] == 1 ? '' : ' · отключён'}'
                              '${((e['pin_len'] as int?) ?? 4) < pinLength ? ' · старый PIN' : ''}',
                              style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                        ]),
                      ),
                      IconButton(
                        onPressed: () => _changePin(e),
                        icon: Icon(Icons.password, color: AppColors.text),
                        tooltip: 'Сменить PIN',
                      ),
                      Switch(
                        value: e['active'] == 1,
                        onChanged: (v) async {
                          final err = await AuthService.instance.setActive(e['id'] as String, v);
                          if (err != null) _snack(err);
                          _load();
                        },
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// Журнал входов (только администратор): за последние 2 месяца —
// кто, когда, с какого телефона и IP-адреса входил; когда телефоны последний раз синхронизировались.

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';

class JournalScreen extends StatefulWidget {
  JournalScreen({super.key});
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  List<LogEntry>? _log;
  List<(String, DateTime)> _syncs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await AuthService.instance.journal();
    final s = await AuthService.instance.deviceSyncs();
    if (mounted) {
      setState(() {
        _log = l;
        _syncs = s;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Журнал входов', actions: [
            IconButton(onPressed: _load, icon: Icon(Icons.refresh, color: AppColors.text), tooltip: 'Обновить'),
          ]),
          Expanded(
            child: _log == null
                ? Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(padding: EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                      Text('Последняя синхронизация с Google Диском',
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
                      SizedBox(height: 6),
                      GlassCard(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Column(children: [
                          if (_syncs.isEmpty)
                            Padding(
                              padding: EdgeInsets.all(8),
                              child: Text('Ещё не было', style: TextStyle(color: AppColors.textDim)),
                            ),
                          for (final s in _syncs)
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Row(children: [
                                Icon(Icons.phone_android, size: 18, color: AppColors.textDim),
                                SizedBox(width: 8),
                                Expanded(child: Text(s.$1, style: TextStyle(color: AppColors.text))),
                                Text(dateTimeText(s.$2),
                                    style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                              ]),
                            ),
                        ]),
                      ),
                      SizedBox(height: 14),
                      Text('Входы за ${AuthService.keepDays} дней (${_log!.length})',
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
                      SizedBox(height: 6),
                      if (_log!.isEmpty)
                        Text('Записей нет', style: TextStyle(color: AppColors.textDim)),
                      for (final e in _log!)
                        Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: GlassCard(
                            radius: 14,
                            padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(
                                  child: Text('${e.who}${e.role.isEmpty ? '' : ' · ${e.role}'}',
                                      style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                                ),
                                Text(dateTimeText(e.at), style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                              ]),
                              SizedBox(height: 2),
                              Text('${e.event} · ${e.device} · IP ${e.ip}',
                                  style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                            ]),
                          ),
                        ),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}

// Google Диск: вход, состояние синхронизации, «Синхронизировать сейчас».

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sync_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';

class SyncScreen extends StatefulWidget {
  SyncScreen({super.key});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  SyncStatus? _s;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await SyncService.instance.status();
    if (mounted) setState(() => _s = s);
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _do(Future<String?> Function() f, String ok) async {
    setState(() => _busy = true);
    final err = await f();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(err ?? ok);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final signed = SyncService.instance.signedIn;
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Google Диск'),
          Expanded(
            child: s == null
                ? Center(child: CircularProgressIndicator())
                : ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                    GlassCard(
                      child: Row(children: [
                        Icon(signed ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                            color: signed ? AppColors.accent : AppColors.warn, size: 30),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(signed ? (s.email ?? '') : 'Вход не выполнен',
                                style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
                            Text(
                                s.lastSync == null
                                    ? 'Ещё не синхронизировалось'
                                    : 'Последняя синхронизация: ${dateTimeText(s.lastSync!)}',
                                style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                          ]),
                        ),
                      ]),
                    ),
                    SizedBox(height: 10),
                    GlassCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Ждут отправки: ${s.pending} изменений',
                            style: TextStyle(color: AppColors.text)),
                        if (s.lastError != null) ...[
                          SizedBox(height: 6),
                          Text('Последняя ошибка: ${s.lastError}', style: TextStyle(color: AppColors.warn)),
                        ],
                      ]),
                    ),
                    SizedBox(height: 10),
                    GlassCard(
                      child: Text(
                        'Данные хранятся в телефоне и копируются в скрытую папку приложения на '
                        'Google Диске. На всех телефонах магазина войдите в ОДИН и тот же Google-аккаунт — '
                        'тогда продажи, товары и долги видны везде, а на новом телефоне всё восстановится.',
                        style: TextStyle(color: AppColors.textDim, height: 1.4),
                      ),
                    ),
                    SizedBox(height: 10),
                    SyncProgressBar(),
                    if (!signed) ...[
                      SizedBox(height: 10),
                      GoogleSetupHint(),
                    ],
                    SizedBox(height: 18),
                    if (!signed)
                      AccentButton(
                        label: _busy ? 'Вхожу…' : 'Войти в Google',
                        onPressed: _busy
                            ? null
                            : () => _do(() async {
                                  final e = await SyncService.instance.signIn();
                                  return e ?? await SyncService.instance.syncNow();
                                }, 'Вход выполнен, данные синхронизированы'),
                      )
                    else ...[
                      AccentButton(
                        label: _busy ? 'Синхронизирую…' : 'Синхронизировать сейчас',
                        onPressed: _busy ? null : () => _do(SyncService.instance.syncNow, 'Готово'),
                      ),
                      SizedBox(height: 10),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                await SyncService.instance.signOut();
                                _load();
                              },
                        child: Text('Выйти из аккаунта', style: TextStyle(color: AppColors.textDim)),
                      ),
                    ],
                  ]),
          ),
        ]),
      ),
    );
  }
}

/// Полоса прогресса синхронизации (проценты и текущий шаг). Пока синхронизации нет — пусто.
class SyncProgressBar extends StatelessWidget {
  SyncProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double?>(
      valueListenable: SyncService.instance.progress,
      builder: (_, p, __) {
        if (p == null) return SizedBox.shrink();
        return GlassCard(
          radius: 14,
          padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: SyncService.instance.stage,
                  builder: (_, t, __) =>
                      Text(t, style: TextStyle(color: AppColors.text, fontSize: 13)),
                ),
              ),
              Text('${(p * 100).round()}%',
                  style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
            ]),
            SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: p,
                minHeight: 8,
                color: AppColors.accent,
                backgroundColor: AppColors.overlay(0.12),
              ),
            ),
          ]),
        );
      },
    );
  }
}

/// Подсказка для разовой настройки Google Cloud (пакет и SHA-1 с кнопкой «копировать»).
class GoogleSetupHint extends StatelessWidget {
  GoogleSetupHint({super.key});

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: EdgeInsets.only(top: 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 11)),
              SelectableText(value,
                  style: TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
          IconButton(
            tooltip: 'Копировать',
            icon: Icon(Icons.copy, size: 18, color: AppColors.accent),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Скопировано')));
            },
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 14,
      padding: EdgeInsets.fromLTRB(12, 10, 4, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Если вход выдаёт «ошибка 10»',
            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 13)),
        SizedBox(height: 2),
        Text('В Google Cloud → APIs & Services → Credentials создайте OAuth client ID типа Android '
            'с этими данными (один раз):',
            style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        _row(context, 'Package name', SyncService.packageName),
        _row(context, 'SHA-1', SyncService.sha1),
      ]),
    );
  }
}

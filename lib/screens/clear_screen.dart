// Очистка базы (хозяин / администратор): пустая база, только документы, документы за период.
// Перед удалением нужно ввести слово УДАЛИТЬ.

import 'package:flutter/material.dart';

import '../services/clear_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';

class ClearScreen extends StatefulWidget {
  ClearScreen({super.key});
  @override
  State<ClearScreen> createState() => _ClearScreenState();
}

class _ClearScreenState extends State<ClearScreen> {
  bool _busy = false;

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<bool> _confirm(String title, String text) async {
    final c = TextEditingController();
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text),
            SizedBox(height: 12),
            Text('Отменить удаление нельзя. Для подтверждения введите слово УДАЛИТЬ:',
                style: TextStyle(fontWeight: FontWeight.w700)),
            TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.characters, onChanged: (_) => setD(() {})),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Отмена')),
            TextButton(
              onPressed: c.text.trim().toUpperCase() == 'УДАЛИТЬ' ? () => Navigator.pop(ctx, true) : null,
              child: Text('Удалить', style: TextStyle(color: c.text.trim().toUpperCase() == 'УДАЛИТЬ' ? AppColors.danger : null)),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _run(Future<ClearResult> Function() job, String okText) async {
    setState(() => _busy = true);
    try {
      final r = await job();
      final kept = r.keptReceipts > 0 ? '\nПоступлений оставлено: ${r.keptReceipts} (товар из них продаётся позже)' : '';
      _snack('$okText Записей удалено: ${r.rows}.$kept');
    } catch (e) {
      _snack('Не удалось очистить: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _all() async {
    if (!await _confirm('Очистить всю базу?',
        'Будут удалены все документы, товары, группы, покупатели, поставщики и журнал входов. '
        'Останутся сотрудники, PIN-коды, реквизиты фирмы и настройки. База станет пустой — как новая.')) return;
    await _run(ClearService.instance.clearAll, 'База очищена.');
  }

  Future<void> _docs() async {
    if (!await _confirm('Очистить документы?',
        'Будут удалены продажи, чеки, поступления, расходы из кассы, возвраты, оплаты долгов и смены. '
        'Товары, группы, покупатели и поставщики останутся (остатки склада станут нулевыми).')) return;
    await _run(ClearService.instance.clearDocuments, 'Документы очищены.');
  }

  Future<void> _period() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      helpText: 'Какой период очистить',
      initialDateRange: DateTimeRange(start: DateTime(now.year, now.month - 1, 1), end: DateTime(now.year, now.month, 0)),
    );
    if (r == null) return;
    final from = DateTime(r.start.year, r.start.month, r.start.day);
    final to = DateTime(r.end.year, r.end.month, r.end.day).add(Duration(days: 1));
    final c = await ClearService.instance.countPeriod(from, to);
    final span = '${dateText(from)} – ${dateText(to.subtract(Duration(days: 1)))}';
    if (c.sales + c.receipts + c.cashOps + c.returns == 0) return _snack('За период $span документов нет');
    if (!await _confirm('Очистить период?',
        'Период: $span\nПродажи: ${c.sales}\nПоступления: ${c.receipts}\nРасходы/приходы кассы: ${c.cashOps}\nВозвраты: ${c.returns}\n\n'
        'Начальные остатки не трогаются. Поступление останется, если товар из него продаётся позже этого периода.')) {
      return;
    }
    await _run(() => ClearService.instance.clearPeriod(from, to), 'Период $span очищен.');
  }

  Widget _card(IconData icon, Color color, String title, String text, VoidCallback onTap) => Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: GlassCard(
          radius: 20,
          onTap: _busy ? null : onTap,
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: color),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 16)),
                SizedBox(height: 2),
                Text(text, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
              ]),
            ),
            Icon(Icons.chevron_right, color: AppColors.textDim),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Очистка базы'),
          if (_busy) LinearProgressIndicator(),
          Expanded(
            child: ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 30), children: [
              GlassCard(
                radius: 18,
                borderColor: AppColors.warn.withOpacity(0.6),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.warn),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('Очистка применится на всех телефонах магазина через Google Диск. Отменить её нельзя.',
                        style: TextStyle(color: AppColors.text, fontSize: 13)),
                  ),
                ]),
              ),
              SizedBox(height: 12),
              _card(Icons.event_busy_outlined, Color(0xFFEA580C), 'Очистить за период',
                  'Продажи, поступления, касса и возвраты за выбранные даты', _period),
              _card(Icons.description_outlined, Color(0xFFDB2777), 'Только документы',
                  'Справочники остаются: товары, группы, покупатели, поставщики', _docs),
              _card(Icons.delete_forever_outlined, AppColors.danger, 'Полностью очистить базу',
                  'Пустое состояние. Остаются сотрудники и реквизиты фирмы', _all),
            ]),
          ),
        ]),
      ),
    );
  }
}

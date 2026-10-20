// Пробитые чеки по сменам: каждая смена отдельно, внутри — её чеки.
// Нажатие на чек показывает его состав. Видят кассир и хозяин (кассир — без себестоимости).

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/print_service.dart';
import '../services/report_service.dart';
import '../services/sale_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';

class ChecksScreen extends StatefulWidget {
  ChecksScreen({super.key});
  @override
  State<ChecksScreen> createState() => _ChecksScreenState();
}

class _ChecksScreenState extends State<ChecksScreen> {
  List<ShiftChecks>? _shifts;
  final Map<String, List<CheckRow>> _open = {}; // раскрытые смены

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await ReportService.instance.shifts();
    if (mounted) setState(() => _shifts = l);
    if (l.isNotEmpty && _open.isEmpty) _toggle(l.first.id); // последняя смена сразу раскрыта
  }

  Future<void> _toggle(String id) async {
    if (_open.containsKey(id)) return setState(() => _open.remove(id));
    final c = await ReportService.instance.checksOfShift(id);
    if (mounted) setState(() => _open[id] = c);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Пробитые чеки'),
          Expanded(
            child: _shifts == null
                ? Center(child: CircularProgressIndicator())
                : _shifts!.isEmpty
                    ? Center(child: Text('Смен ещё не было', style: TextStyle(color: AppColors.textDim)))
                    : ListView(padding: EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                        for (final sh in _shifts!) ...[
                          GlassCard(
                            radius: 16,
                            padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
                            onTap: () => _toggle(sh.id),
                            child: Row(children: [
                              Icon(_open.containsKey(sh.id) ? Icons.expand_less : Icons.expand_more,
                                  color: AppColors.textDim),
                              SizedBox(width: 6),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(
                                      'Смена ${dateTimeText(sh.openedAt)}'
                                      '${sh.closedAt == null ? ' · открыта' : ' — ${dateTimeText(sh.closedAt!).substring(11)}'}',
                                      style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                                  Text('${sh.cashier} · чеков: ${sh.count}',
                                      style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                                ]),
                              ),
                              Text(money(sh.total),
                                  style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
                            ]),
                          ),
                          if (_open[sh.id] != null)
                            Padding(
                              padding: EdgeInsets.only(left: 12, top: 4),
                              child: Column(children: [
                                if (_open[sh.id]!.isEmpty)
                                  Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text('Чеков нет', style: TextStyle(color: AppColors.textDim)),
                                  ),
                                for (final c in _open[sh.id]!) CheckTile(check: c),
                              ]),
                            ),
                          SizedBox(height: 8),
                        ],
                      ]),
          ),
        ]),
      ),
    );
  }
}

/// Строка чека; нажатие — состав чека.
class CheckTile extends StatelessWidget {
  final CheckRow check;
  CheckTile({super.key, required this.check});

  @override
  Widget build(BuildContext context) {
    final c = check;
    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: GlassCard(
        radius: 12,
        padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
        onTap: () => showCheck(context, c),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${dateTimeText(c.date).substring(11)} · ${paymentName(c.payment)}',
                  style: TextStyle(color: AppColors.text)),
              Text('${c.cashier}${c.customer != null ? ' · ${c.customer}' : ''}',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            ]),
          ),
          Text(money(c.total), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

/// Окно с составом чека.
Future<void> showCheck(BuildContext context, CheckRow c) async {
  final lines = await ReportService.instance.checkLines(c.id);
  final manager = AuthService.instance.current?.isManager ?? false;
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.sheet,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Чек от ${dateTimeText(c.date)}',
              style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800)),
          Text('Кассир: ${c.cashier}${c.customer != null ? ' · покупатель: ${c.customer}' : ''}',
              style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          SizedBox(height: 10),
          for (final l in lines)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(l.name, style: TextStyle(color: AppColors.text))),
                Text('${qtyText(l.qty)} × ${money(l.price)}', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                SizedBox(width: 10),
                Text(money(l.sum), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
              ]),
            ),
          Divider(color: AppColors.overlay(0.2)),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Итого', style: TextStyle(color: AppColors.textDim)),
            Text(money(c.total), style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
          SizedBox(height: 4),
          Text(
              c.payment == 'mixed'
                  ? 'Наличными ${money(c.paidCash)} + Kaspi ${money(c.paidKaspi)}'
                  : 'Оплата: ${paymentName(c.payment)}',
              style: TextStyle(color: AppColors.textDim)),
          if (manager)
            Text('Себестоимость ${money(c.cost)} · прибыль ${money(c.profit)}',
                style: TextStyle(color: AppColors.accent)),
          if (c.comment != null) Text('Комментарий: ${c.comment}', style: TextStyle(color: AppColors.textDim)),
          SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => PrintService.instance.check(context, c, lines),
            icon: Icon(Icons.picture_as_pdf_outlined),
            label: Text('Товарный чек: печать / отправить'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              minimumSize: Size.fromHeight(46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => PrintService.instance.saleInvoice(context, c, lines),
            icon: Icon(Icons.description_outlined),
            label: Text('Расходная накладная (A4)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              minimumSize: Size.fromHeight(46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      ),
    ),
  );
}

// Долги перед поставщиками: у каждого поставщика полоса «оплачено / долг».
// Нажатие на поставщика — его поступления в долг, оплаты и кнопка «Оплатить».

import 'package:flutter/material.dart';

import '../db/database.dart';
import '../services/auth_service.dart';
import '../services/print_service.dart';
import '../services/supplier_service.dart';
import '../services/supplier_debt_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';
import '../ui/pay_dialog.dart';

class SupplierDebtsScreen extends StatefulWidget {
  SupplierDebtsScreen({super.key});
  @override
  State<SupplierDebtsScreen> createState() => _SupplierDebtsScreenState();
}

class _SupplierDebtsScreenState extends State<SupplierDebtsScreen> {
  List<_SupRow> _all = [];
  bool _loading = true;
  String _filter = 'all'; // all — все, owe — мы должны, soon — срок близко
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Все поставщики: долг (если есть) и дата последней поставки.
  Future<void> _load() async {
    final rows = <_SupRow>[];
    try {
      final debts = {for (final d in await SupplierDebtService.instance.bySupplier()) d.supplierId: d};
      final db = await AppDatabase.instance.db;
      final sup = await db.rawQuery('''
        SELECT s.id, s.name, s.phone,
          (SELECT MAX(r.doc_date) FROM receipts r WHERE r.supplier_id = s.id AND r.deleted = 0) AS last
        FROM suppliers s WHERE s.deleted = 0 AND s.active = 1
        ORDER BY s.name COLLATE NOCASE''');
      for (final r in sup) {
        final id = r['id'] as String;
        final d = debts[id] ?? SupplierDebt(id, r['name'] as String, r['phone'] as String?, 0, 0, null);
        rows.add(_SupRow(d, r['last'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['last'] as int)));
      }
      rows.sort((a, b) => b.debt.owed.compareTo(a.debt.owed));
    } catch (_) {}
    if (mounted) {
      setState(() {
        _all = rows;
        _loading = false;
      });
    }
  }

  List<_SupRow> get _shown {
    final q = _q.text.trim().toLowerCase();
    return _all.where((r) {
      if (q.isNotEmpty && !r.debt.name.toLowerCase().contains(q)) return false;
      if (_filter == 'owe') return r.debt.owed > 0.5;
      if (_filter == 'soon') return r.debt.soon;
      return true;
    }).toList();
  }

  Widget _tile(String label, String value, Color c) => Expanded(
        child: Container(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: c.withOpacity(0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.withOpacity(0.45), width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 14)),
            SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      );

  Widget _chip(String id, String label) {
    final on = _filter == id;
    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _filter = id),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on ? AppColors.accent : AppColors.sheet,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? AppColors.accent : AppColors.overlay(0.15)),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? AppColors.onAccent : AppColors.text, fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ),
    );
  }

  Widget _row(_SupRow r) {
    final d = r.debt;
    final owe = d.owed > 0.5;
    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupplierDebtScreen(debt: d)));
        _load();
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Text(d.name.isEmpty ? '?' : d.name.substring(0, 1).toUpperCase(),
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 18)),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 16)),
              if (owe && d.nearestDue != null)
                Text(d.overdue ? 'срок прошёл ${dateText(d.nearestDue!)}' : 'оплатить до ${dateText(d.nearestDue!)}',
                    style: TextStyle(color: d.soon ? AppColors.warn : AppColors.textDim, fontSize: 12.5))
              else if (r.last != null)
                Text('поставка ${dateText(r.last!)}', style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(owe ? '−${money(d.owed)}' : money(0),
                style: TextStyle(
                    color: owe ? AppColors.danger : AppColors.textDim, fontWeight: FontWeight.w800, fontSize: 17)),
            if (owe)
              Text('мы должны', style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final owed = _all.fold<double>(0, (s, r) => s + r.debt.owed);
    final paid = _all.fold<double>(0, (s, r) => s + r.debt.paid);
    final list = _shown;
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Поставщики'),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(padding: EdgeInsets.fromLTRB(14, 4, 14, 24), children: [
                      Row(children: [
                        _tile('Мы должны', owed > 0.5 ? '−${money(owed)}' : money(0), AppColors.danger),
                        SizedBox(width: 10),
                        _tile('Оплачено', money(paid), Color(0xFF16A34A)),
                      ]),
                      SizedBox(height: 12),
                      TextField(
                        controller: _q,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(color: AppColors.text, fontSize: 16),
                        decoration: glassInput('Поиск поставщика', suffix: Icon(Icons.search, color: AppColors.textDim))
                            .copyWith(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13)),
                      ),
                      SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [_chip('all', 'Все'), _chip('owe', 'Мы должны'), _chip('soon', 'Срок близко')]),
                      ),
                      SizedBox(height: 10),
                      if (list.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 30),
                          child: Center(
                            child: Text('Поставщиков нет.',
                                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
                          ),
                        )
                      else
                        GlassCard(
                          radius: 16,
                          padding: EdgeInsets.symmetric(vertical: 2),
                          child: Column(children: [
                            for (var i = 0; i < list.length; i++) ...[
                              if (i > 0) Divider(height: 1, color: AppColors.overlay(0.08)),
                              _row(list[i]),
                            ],
                          ]),
                        ),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _SupRow {
  final SupplierDebt debt;
  final DateTime? last;
  _SupRow(this.debt, this.last);
}

/// Один поставщик: поступления в долг, оплаты и кнопка «Оплатить».
class SupplierDebtScreen extends StatefulWidget {
  final SupplierDebt debt;
  SupplierDebtScreen({super.key, required this.debt});
  @override
  State<SupplierDebtScreen> createState() => _SupplierDebtScreenState();
}

class _SupplierDebtScreenState extends State<SupplierDebtScreen> {
  List<SupplierDebtDoc> _docs = [];
  List<SupplierPayment> _pays = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await SupplierDebtService.instance.docsOf(widget.debt.supplierId);
    final p = await SupplierDebtService.instance.paymentsOf(widget.debt.supplierId);
    if (mounted) {
      setState(() {
        _docs = d;
        _pays = p;
      });
    }
  }

  double get _owed => _docs.fold(0, (s, x) => s + x.remaining);

  /// Удалить поставщика (если есть в документах — будет отключён).
  Future<void> _delete() async {
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Удалить «${widget.debt.name}»?'),
        content: Text('Если поставщик уже есть в документах, он не удалится, а будет отключён.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    final msg = await SupplierService.instance.removeOrDisable(widget.debt.supplierId, owed: _owed);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    if (!msg.startsWith('Нельзя')) Navigator.of(context).pop();
  }

  /// Акт сверки с поставщиком: поступления в долг и наши оплаты.
  Future<void> _statement() async {
    final rows = <StatementRow>[
      for (final d in _docs) StatementRow(d.date, 'Поступление на ${money(d.total)} (в долг)', d.debt, 0),
      for (final p in _pays) StatementRow(p.at, 'Оплата (${supplierPaymentName(p.payment)})', 0, p.amount),
    ];
    await PrintService.instance.statement(context, name: widget.debt.name, supplier: true, rows: rows);
  }

  Future<void> _pay() async {
    final r = await showPayDialog(
      context,
      title: 'Оплата поставщику: ${widget.debt.name}',
      owed: _owed,
      methods: [PayMethod.cash('Из кассы'), PayMethod.kaspi(), PayMethod.other()],
      note: '«Из кассы» — сумма спишется из кассы текущей смены как расход.',
      withComment: true,
    );
    if (r == null) return;
    final err = await SupplierDebtService.instance.pay(
      widget.debt.supplierId,
      widget.debt.name,
      r.amount,
      r.method,
      comment: r.comment,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Оплата записана')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: widget.debt.name, actions: [
            if (AuthService.instance.current?.isManager ?? false)
              IconButton(
                onPressed: _delete,
                icon: Icon(Icons.delete_outline, color: AppColors.text),
                tooltip: 'Удалить поставщика',
              ),
            IconButton(
              onPressed: _statement,
              icon: Icon(Icons.picture_as_pdf_outlined, color: AppColors.text),
              tooltip: 'Акт сверки (PDF)',
            ),
          ]),
          Expanded(
            child: ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              GlassCard(
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Мы должны', style: TextStyle(color: AppColors.textDim)),
                  Text(money(_owed),
                      style: TextStyle(color: AppColors.warn, fontSize: 22, fontWeight: FontWeight.w800)),
                ]),
              ),
              SizedBox(height: 12),
              Text('Поступления в долг', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
              SizedBox(height: 6),
              for (final d in _docs)
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: GlassCard(
                    radius: 16,
                    padding: EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Поступление ${dateText(d.date)} на ${money(d.total)}',
                              style: TextStyle(color: AppColors.text)),
                          Text(
                              'В долг ${money(d.debt)}'
                              '${d.due == null ? '' : ' · оплатить до ${dateText(d.due!)}'}',
                              style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                        ]),
                      ),
                      Text(d.remaining > 0.5 ? money(d.remaining) : 'оплачено',
                          style: TextStyle(
                              color: d.remaining > 0.5 ? AppColors.warn : AppColors.accent,
                              fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
              if (_pays.isNotEmpty) ...[
                SizedBox(height: 10),
                Text('Оплаты', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                for (final p in _pays)
                  Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: GlassCard(
                      radius: 14,
                      padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                              '${dateTimeText(p.at)} · ${supplierPaymentName(p.payment)}'
                              '${p.comment == null ? '' : ' · ${p.comment}'}',
                              style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                        ),
                        Text(money(p.amount),
                            style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
              ],
              SizedBox(height: 12),
              if (_owed > 0.5) AccentButton(label: 'Оплатить поставщику', onPressed: _pay),
            ]),
          ),
        ]),
      ),
    );
  }
}

// Долги перед поставщиками: у каждого поставщика полоса «оплачено / долг».
// Нажатие на поставщика — его поступления в долг, оплаты и кнопка «Оплатить».

import 'package:flutter/material.dart';

import '../services/supplier_debt_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';

class SupplierDebtsScreen extends StatefulWidget {
  SupplierDebtsScreen({super.key});
  @override
  State<SupplierDebtsScreen> createState() => _SupplierDebtsScreenState();
}

class _SupplierDebtsScreenState extends State<SupplierDebtsScreen> {
  List<SupplierDebt> _items = [];
  bool _loading = true;
  bool _onlyOwing = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<SupplierDebt> l = [];
    try {
      l = await SupplierDebtService.instance.bySupplier(onlyOwing: _onlyOwing);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _items = l;
        _loading = false;
      });
    }
  }

  Widget _legend(Color c, String t) => Row(children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
        SizedBox(width: 6),
        Text(t, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
      ]);

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<double>(0, (s, c) => s + c.owed);
    final soon = _items.where((c) => c.soon).length;
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Долги поставщикам'),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                    GlassCard(
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Мы должны', style: TextStyle(color: AppColors.textDim)),
                            SizedBox(height: 4),
                            Text(money(total),
                                style: TextStyle(color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w800)),
                          ]),
                        ),
                        Text('${_items.where((c) => c.owed > 0.5).length} поставщ.',
                            style: TextStyle(color: AppColors.textDim)),
                      ]),
                    ),
                    if (soon > 0) ...[
                      SizedBox(height: 10),
                      GlassCard(
                        borderColor: AppColors.warn.withOpacity(0.55),
                        child: Row(children: [
                          Icon(Icons.notifications_active_outlined, color: AppColors.warn),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text('Срок оплаты $soon поставщикам — в ближайшие 3 дня или уже прошёл',
                                style: TextStyle(color: AppColors.text)),
                          ),
                        ]),
                      ),
                    ],
                    SizedBox(height: 8),
                    Row(children: [
                      _legend(AppColors.accent, 'Оплачено'),
                      SizedBox(width: 14),
                      _legend(AppColors.amber, 'Долг'),
                      Spacer(),
                      FilterChip(
                        label: Text('Только долги'),
                        selected: _onlyOwing,
                        onSelected: (v) {
                          _onlyOwing = v;
                          _load();
                        },
                      ),
                    ]),
                    SizedBox(height: 8),
                    if (_items.isEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: Center(
                          child: Text('Долгов перед поставщиками нет.\n'
                              'Чтобы взять товар в долг, в поступлении включите «Взять в долг у поставщика».',
                              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
                        ),
                      ),
                    for (final c in _items)
                      Padding(padding: EdgeInsets.only(bottom: 10), child: _card(c)),
                  ]),
          ),
        ]),
      ),
    );
  }

  Widget _card(SupplierDebt c) {
    final paidShare = c.taken <= 0 ? 1.0 : (c.paid / c.taken).clamp(0.0, 1.0);
    final warn = c.soon;
    return GlassCard(
      borderColor: warn ? AppColors.warn.withOpacity(0.55) : null,
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupplierDebtScreen(debt: c)));
        _load();
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w800)),
              if (c.phone != null && c.phone!.isNotEmpty)
                Text(c.phone!, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            ]),
          ),
          if (c.nearestDue != null && c.owed > 0.5)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: warn ? AppColors.warn.withOpacity(0.15) : AppColors.overlay(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(c.overdue ? 'просрочен' : 'до ${dateText(c.nearestDue!)}',
                  style: TextStyle(
                      color: warn ? AppColors.warn : AppColors.text, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ]),
        SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: paidShare,
            minHeight: 12,
            color: AppColors.accent,
            backgroundColor: AppColors.amber,
          ),
        ),
        SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Взяли: ${money(c.taken)}', style: TextStyle(color: AppColors.textDim)),
          Text('Долг: ${money(c.owed)}', style: TextStyle(color: AppColors.warn, fontWeight: FontWeight.w800)),
        ]),
      ]),
    );
  }
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

  Future<void> _pay() async {
    final amount = TextEditingController(text: qtyText(_owed.roundToDouble()));
    final comment = TextEditingController();
    String method = 'cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('Оплата поставщику'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Сумма, ₸ (долг ${money(_owed)})'),
              ),
              SizedBox(height: 12),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'cash', label: Text('Из кассы')),
                  ButtonSegment(value: 'kaspi', label: Text('Kaspi')),
                  ButtonSegment(value: 'other', label: Text('Другое')),
                ],
                selected: {method},
                onSelectionChanged: (v) => setD(() => method = v.first),
              ),
              if (method == 'cash')
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Сумма будет списана из кассы текущей смены как расход.',
                      style: TextStyle(fontSize: 12)),
                ),
              SizedBox(height: 8),
              TextField(controller: comment, decoration: InputDecoration(labelText: 'Комментарий')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Оплатить')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final err = await SupplierDebtService.instance.pay(
      widget.debt.supplierId,
      widget.debt.name,
      parseNum(amount.text) ?? 0,
      method,
      comment: comment.text,
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
          GlassHeader(title: widget.debt.name),
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

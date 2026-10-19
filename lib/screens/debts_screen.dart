// Долги по клиентам: у каждого полоса «оплачено / долг», сколько взял и сколько должен.
// Нажатие на клиента — его продажи в долг и приём оплаты.

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/debt_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';
import '../ui/pay_dialog.dart';
import 'supplier_debts_screen.dart';

class DebtsScreen extends StatefulWidget {
  DebtsScreen({super.key});
  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  List<CustomerDebt> _items = [];
  bool _loading = true;
  bool _onlyOwing = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await DebtService.instance.byCustomer(onlyOwing: _onlyOwing);
    if (mounted) {
      setState(() {
        _items = l;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<double>(0, (s, c) => s + c.owed);
    final soon = _items.where((c) => c.soon).length;
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Долги по клиентам'),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                    if (AuthService.instance.current?.isManager ?? false) ...[
                      GlassCard(
                        radius: 16,
                        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => SupplierDebtsScreen())),
                        child: Row(children: [
                          Icon(Icons.request_quote_outlined, color: AppColors.accent),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text('Наши долги поставщикам',
                                style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                          ),
                          Icon(Icons.chevron_right, color: AppColors.textDim),
                        ]),
                      ),
                      SizedBox(height: 10),
                    ],
                    GlassCard(
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Всего должны', style: TextStyle(color: AppColors.textDim)),
                            SizedBox(height: 4),
                            Text(money(total),
                                style: TextStyle(
                                    color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w800)),
                          ]),
                        ),
                        Text('${_items.where((c) => c.owed > 0.5).length} клиентов',
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
                            child: Text('У $soon клиентов срок оплаты в ближайшие 3 дня или уже прошёл',
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
                        label: Text('Только должники'),
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
                        child: Center(child: Text('Долгов нет', style: TextStyle(color: AppColors.textDim))),
                      ),
                    for (final c in _items)
                      Padding(padding: EdgeInsets.only(bottom: 10), child: _card(c)),
                  ]),
          ),
        ]),
      ),
    );
  }

  Widget _legend(Color c, String t) => Row(children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
        SizedBox(width: 6),
        Text(t, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
      ]);

  Widget _card(CustomerDebt c) {
    final paidShare = c.taken <= 0 ? 1.0 : (c.paid / c.taken).clamp(0.0, 1.0);
    final warn = c.soon;
    return GlassCard(
      borderColor: warn ? AppColors.warn.withOpacity(0.55) : null,
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CustomerDebtScreen(debt: c)));
        _load();
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name,
                  style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w800)),
              if (c.phone != null && c.phone!.isNotEmpty)
                Text(c.phone!, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            ]),
          ),
          if (c.nearestDue != null && c.owed > 0.5)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (warn ? AppColors.warn : Colors.white).withOpacity(0.15),
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
          child: Semantics(
            label: 'Оплачено ${(paidShare * 100).round()}%, долг ${100 - (paidShare * 100).round()}%',
            child: LinearProgressIndicator(
              value: paidShare,
              minHeight: 12,
              color: AppColors.accent,
              backgroundColor: AppColors.amber,
            ),
          ),
        ),
        SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Взял: ${money(c.taken)}', style: TextStyle(color: AppColors.textDim)),
          Text('Долг: ${money(c.owed)}',
              style: TextStyle(color: AppColors.warn, fontWeight: FontWeight.w800)),
        ]),
      ]),
    );
  }
}

/// Один покупатель: его продажи в долг и приём оплаты.
class CustomerDebtScreen extends StatefulWidget {
  final CustomerDebt debt;
  CustomerDebtScreen({super.key, required this.debt});
  @override
  State<CustomerDebtScreen> createState() => _CustomerDebtScreenState();
}

class _CustomerDebtScreenState extends State<CustomerDebtScreen> {
  List<DebtSale> _sales = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await DebtService.instance.salesOf(widget.debt.customerId);
    if (mounted) setState(() => _sales = l);
  }

  double get _owed => _sales.fold(0, (s, x) => s + (x.remaining > 0 ? x.remaining : 0));

  Future<void> _pay() async {
    final r = await showPayDialog(
      context,
      title: 'Оплата долга: ${widget.debt.name}',
      owed: _owed,
      methods: [PayMethod.cash(), PayMethod.kaspi()],
    );
    if (r == null) return;
    final err = await DebtService.instance.pay(widget.debt.customerId, r.amount, r.method);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Оплата принята')));
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
                  Text('Должен', style: TextStyle(color: AppColors.textDim)),
                  Text(money(_owed),
                      style: TextStyle(color: AppColors.warn, fontSize: 22, fontWeight: FontWeight.w800)),
                ]),
              ),
              SizedBox(height: 12),
              for (final s in _sales)
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: GlassCard(
                    radius: 16,
                    padding: EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Покупка ${dateText(s.saleDate)} на ${money(s.total)}',
                              style: TextStyle(color: AppColors.text)),
                          Text(s.due == null ? '' : 'Оплатить до ${dateText(s.due!)}',
                              style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                        ]),
                      ),
                      Text(s.remaining > 0.5 ? money(s.remaining) : 'оплачено',
                          style: TextStyle(
                              color: s.remaining > 0.5 ? AppColors.warn : AppColors.accent,
                              fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
              SizedBox(height: 12),
              if (_owed > 0.5) AccentButton(label: 'Принять оплату', onPressed: _pay),
            ]),
          ),
        ]),
      ),
    );
  }
}

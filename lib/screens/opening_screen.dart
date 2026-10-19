// Начальные остатки (только хозяин / администратор):
//  • остаток склада на начало работы;
//  • долги покупателей (нам должны);
//  • наши долги поставщикам.

import 'package:flutter/material.dart';

import '../services/customer_service.dart';
import '../services/opening_service.dart';
import '../services/supplier_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';
import 'receipt_edit_screen.dart';

class OpeningScreen extends StatefulWidget {
  OpeningScreen({super.key});
  @override
  State<OpeningScreen> createState() => _OpeningScreenState();
}

class _OpeningScreenState extends State<OpeningScreen> {
  int _tab = 0;
  List<OpeningStockDoc> _stock = [];
  List<OpeningDebt> _cust = [];
  List<OpeningDebt> _sup = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = OpeningService.instance;
    final a = await s.stockDocs();
    final b = await s.customerDebts();
    final c = await s.supplierDebts();
    if (mounted) {
      setState(() {
        _stock = a;
        _cust = b;
        _sup = c;
        _loading = false;
      });
    }
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _openStock(String? id) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ReceiptEditScreen(receiptId: id, opening: true)));
    _load();
  }

  /// Диалог добавления долга: выбор (или новый) контрагент, сумма, срок.
  Future<void> _addDebt({required bool customer}) async {
    final items = customer
        ? [for (final c in await CustomerService.instance.search()) (c.id!, c.name)]
        : [for (final s in await SupplierService.instance.all()) (s.id!, s.name)];
    if (!mounted) return;
    String? selected = items.isEmpty ? '' : null; // '' — новый
    final name = TextEditingController();
    final phone = TextEditingController();
    final amount = TextEditingController();
    DateTime? due;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(customer ? 'Долг покупателя' : 'Наш долг поставщику'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: selected,
                isExpanded: true,
                decoration: InputDecoration(labelText: customer ? 'Покупатель' : 'Поставщик'),
                items: [
                  DropdownMenuItem(value: '', child: Text(customer ? '+ Новый покупатель' : '+ Новый поставщик')),
                  for (final it in items) DropdownMenuItem(value: it.$1, child: Text(it.$2)),
                ],
                onChanged: (v) => setD(() => selected = v),
              ),
              if (selected == '') ...[
                TextField(controller: name, decoration: InputDecoration(labelText: 'Имя / название')),
                TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: 'Телефон')),
              ],
              TextField(
                controller: amount,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Сумма долга, ₸'),
              ),
              SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text(due == null ? 'Срок оплаты не указан' : 'Оплатить до ${dateText(due!)}')),
                TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: c,
                      initialDate: DateTime.now().add(Duration(days: 7)),
                      firstDate: DateTime.now().subtract(Duration(days: 365)),
                      lastDate: DateTime.now().add(Duration(days: 730)),
                    );
                    if (d != null) setD(() => due = DateTime(d.year, d.month, d.day, 12));
                  },
                  child: Text('Срок'),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Сохранить')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    var id = selected;
    if (id == null) return _snack(customer ? 'Выберите покупателя' : 'Выберите поставщика');
    if (id == '') {
      if (name.text.trim().isEmpty) return _snack('Укажите имя');
      id = customer
          ? await CustomerService.instance.save(Customer(name: name.text, phone: phone.text))
          : await SupplierService.instance.save(Supplier(name: name.text, phone: phone.text));
    }
    final sum = parseNum(amount.text) ?? 0;
    final err = customer
        ? await OpeningService.instance.addCustomerDebt(id, sum, due)
        : await OpeningService.instance.addSupplierDebt(id, sum, due);
    if (!mounted) return;
    _snack(err ?? 'Сохранено');
    _load();
  }

  Future<void> _deleteDebt(OpeningDebt d, {required bool customer}) async {
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Удалить начальный долг?'),
        content: Text('${d.name}: ${money(d.amount)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    final err = customer
        ? await OpeningService.instance.deleteCustomerDebt(d.id)
        : await OpeningService.instance.deleteSupplierDebt(d.id);
    if (!mounted) return;
    _snack(err ?? 'Удалено');
    _load();
  }

  Widget _tabBtn(int i, String t) => Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = i),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: _tab == i ? AppColors.accent : AppColors.overlay(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(t,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _tab == i ? AppColors.onAccent : AppColors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
        ),
      );

  Widget _total(String label, double v) => GlassCard(
        radius: 14,
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(color: AppColors.textDim)),
          Text(money(v), style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _debtTile(OpeningDebt d, {required bool customer}) => Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: GlassCard(
          radius: 12,
          padding: EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.name, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                Text(d.due == null ? 'без срока' : 'до ${dateText(d.due!)}',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ]),
            ),
            Text(money(d.amount), style: TextStyle(color: AppColors.warn, fontWeight: FontWeight.w800)),
            IconButton(
              tooltip: 'Удалить',
              icon: Icon(Icons.delete_outline, color: AppColors.textDim, size: 20),
              onPressed: () => _deleteDebt(d, customer: customer),
            ),
          ]),
        ),
      );

  List<Widget> _body() {
    switch (_tab) {
      case 0:
        return [
          _total('Склад на начало', _stock.fold<double>(0, (s, d) => s + d.total)),
          SizedBox(height: 8),
          Text('Внесите товары, которые уже есть в магазине, с ценой закупки. '
              'Это не попадёт в «Поступления» за период.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          SizedBox(height: 8),
          for (final d in _stock)
            Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: GlassCard(
                radius: 12,
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                onTap: () => _openStock(d.id),
                child: Row(children: [
                  Expanded(
                    child: Text('${dateText(d.date)} · ${d.lines} поз.',
                        style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                  ),
                  Text(money(d.total), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          SizedBox(height: 6),
          AccentButton(label: 'Внести остаток товаров', onPressed: () => _openStock(null)),
        ];
      case 1:
        return [
          _total('Нам должны (на начало)', _cust.fold<double>(0, (s, d) => s + d.amount)),
          SizedBox(height: 8),
          for (final d in _cust) _debtTile(d, customer: true),
          SizedBox(height: 6),
          AccentButton(label: 'Добавить долг покупателя', onPressed: () => _addDebt(customer: true)),
        ];
      default:
        return [
          _total('Мы должны (на начало)', _sup.fold<double>(0, (s, d) => s + d.amount)),
          SizedBox(height: 8),
          for (final d in _sup) _debtTile(d, customer: false),
          SizedBox(height: 6),
          AccentButton(label: 'Добавить долг поставщику', onPressed: () => _addDebt(customer: false)),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Начальные остатки'),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(children: [
              _tabBtn(0, 'Склад'),
              SizedBox(width: 6),
              _tabBtn(1, 'Долги клиентов'),
              SizedBox(width: 6),
              _tabBtn(2, 'Наш долг'),
            ]),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : ListView(padding: EdgeInsets.fromLTRB(16, 0, 16, 24), children: _body()),
          ),
        ]),
      ),
    );
  }
}

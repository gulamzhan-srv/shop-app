// Документ поступления: дата, поставщик, комментарий, строки товаров.
// Сумма строки = количество × цена, итог = сумма всех строк.

import 'package:flutter/material.dart';

import '../db/database.dart';
import '../services/auth_service.dart';
import '../services/fifo_service.dart';
import '../services/receipt_service.dart';
import '../services/supplier_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';
import '../ui/product_picker.dart';

class _LineEdit {
  final String productId;
  final String name;
  final String unit;
  final TextEditingController qty;
  final TextEditingController price;
  _LineEdit(this.productId, this.name, this.unit, double q, double p)
      : qty = TextEditingController(text: q == 0 ? '' : qtyText(q)),
        price = TextEditingController(text: p == 0 ? '' : qtyText(p));

  double get q => parseNum(qty.text) ?? 0;
  double get p => parseNum(price.text) ?? 0;
  double get sum => q * p;
}

class ReceiptEditScreen extends StatefulWidget {
  final String? receiptId; // null = новый документ
  /// Новый документ «Начальный остаток склада» (без поставщика и долга).
  final bool opening;
  ReceiptEditScreen({super.key, this.receiptId, this.opening = false});
  @override
  State<ReceiptEditScreen> createState() => _ReceiptEditScreenState();
}

class _ReceiptEditScreenState extends State<ReceiptEditScreen> {
  DateTime _date = DateTime.now();
  late bool _opening = widget.opening;
  String? _supplierId;
  List<Supplier> _suppliers = [];
  final _comment = TextEditingController();
  // Долг поставщику: взяли товар в долг, оплатили часть (или ничего) и срок оплаты остатка.
  bool _onCredit = false;
  final _paid = TextEditingController(text: '0');
  DateTime _due = DateTime.now().add(Duration(days: 7));
  final List<_LineEdit> _lines = [];
  String? _author;
  String? _device;
  bool _readOnly = false;
  bool _sold = false; // товар уже продавался — документ нельзя менять
  // Кассир видит только товары и количество, без цен закупки и сумм.
  final bool _hidePrices = !(AuthService.instance.current?.isManager ?? false);
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _suppliers = await SupplierService.instance.all();
    final id = widget.receiptId;
    if (id != null) {
      final r = await ReceiptService.instance.load(id);
      _date = r.date;
      _supplierId = r.supplierId;
      _comment.text = r.comment ?? '';
      _author = r.authorName;
      _device = r.deviceName;
      _opening = r.opening;
      if (r.debt > 0.5) {
        _onCredit = true;
        _paid.text = qtyText(r.paidSum);
        if (r.dueDate != null) _due = r.dueDate!;
      }
      for (final l in r.lines) {
        _lines.add(_LineEdit(l.productId, l.productName, l.unit, l.qty, l.price));
      }
      _sold = !await ReceiptService.instance.canChange(id);
      _readOnly = _sold;
    }
    if (_hidePrices) _readOnly = true;
    if (mounted) setState(() => _loading = false);
  }

  double get _total => _lines.fold(0, (s, l) => s + l.sum);
  double get _paidNow => _onCredit ? (parseNum(_paid.text) ?? 0) : _total;
  double get _debtNow => _total - _paidNow;

  Future<void> _pickDue() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now().add(Duration(days: 730)),
    );
    if (d != null) setState(() => _due = DateTime(d.year, d.month, d.day, 12));
  }

  Widget _paymentCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Взять в долг у поставщика',
                style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
          ),
          Switch(
            value: _onCredit,
            onChanged: _readOnly ? null : (v) => setState(() => _onCredit = v),
          ),
        ]),
        if (!_onCredit)
          Text('Оплачено полностью', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
        if (_onCredit) ...[
          SizedBox(height: 8),
          TextField(
            controller: _paid,
            enabled: !_readOnly,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: AppColors.text),
            decoration: glassInput('Оплачено сразу, ₸ (0 — всё в долг)'),
          ),
          SizedBox(height: 10),
          GlassCard(
            radius: 14,
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            onTap: _readOnly ? null : _pickDue,
            child: Row(children: [
              Icon(Icons.event_outlined, color: AppColors.textDim, size: 20),
              SizedBox(width: 8),
              Text('Оплатить остаток до ${dateText(_due)}',
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
            ]),
          ),
          SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Долг поставщику', style: TextStyle(color: AppColors.textDim)),
            Text(money(_debtNow < 0 ? 0 : _debtNow),
                style: TextStyle(color: AppColors.warn, fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
        ],
      ]),
    );
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 1)),
    );
    if (d != null) {
      setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
    }
  }

  Future<void> _newSupplier() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Новый поставщик'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: 'Название')),
          TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: 'Телефон')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Сохранить')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final id = await SupplierService.instance.save(Supplier(name: name.text, phone: phone.text));
    _suppliers = await SupplierService.instance.all();
    setState(() => _supplierId = id);
  }

  Future<void> _addLine() async {
    final p = await pickProduct(context);
    if (p == null || !mounted) return;
    if (_lines.any((l) => l.productId == p.id)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('«${p.name}» уже есть в документе')));
      return;
    }
    final db = await AppDatabase.instance.db;
    final cost = await FifoService.instance.lastCost(db, p.id!) ?? 0;
    setState(() => _lines.add(_LineEdit(p.id!, p.name, p.unit, 1, cost)));
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    final err = await ReceiptService.instance.save(Receipt(
      id: widget.receiptId,
      date: _date,
      supplierId: _supplierId,
      comment: _comment.text,
      opening: _opening,
      paid: _onCredit && !_opening ? (parseNum(_paid.text) ?? 0) : null,
      dueDate: _onCredit ? _due : null,
      lines: [
        for (final l in _lines)
          ReceiptLine(productId: l.productId, productName: l.name, unit: l.unit, qty: l.q, price: l.p),
      ],
    ));
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _error = err;
        _busy = false;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Удалить поступление?'),
        content: Text('Остатки товаров уменьшатся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await ReceiptService.instance.delete(widget.receiptId!);
    if (!mounted) return;
    if (err != null) return setState(() => _error = err);
    Navigator.of(context).pop(true);
  }

  Widget _lineCard(int i) {
    final l = _lines[i];
    Widget numField(TextEditingController c, String label) => Expanded(
          child: TextField(
            controller: c,
            enabled: !_readOnly,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: AppColors.text),
            decoration: glassInput(label),
          ),
        );
    return GlassCard(
      radius: 18,
      padding: EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(l.name,
                style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          if (!_readOnly)
            IconButton(
              onPressed: () => setState(() => _lines.removeAt(i)),
              icon: Icon(Icons.close, color: AppColors.textDim),
              tooltip: 'Убрать строку',
            ),
        ]),
        SizedBox(height: 8),
        if (_hidePrices)
          Text('Количество: ${qtyText(l.q)} ${l.unit}',
              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800))
        else ...[
          Row(children: [
            numField(l.qty, 'Кол-во, ${l.unit}'),
            SizedBox(width: 10),
            numField(l.price, 'Цена, ₸'),
          ]),
          SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text('Сумма: ${money(l.sum)}',
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.receiptId == null;
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(
            title: _opening ? 'Начальный остаток' : (isNew ? 'Новое поступление' : 'Поступление'),
            actions: [
              if (!isNew && !_readOnly)
                IconButton(
                  onPressed: _delete,
                  icon: Icon(Icons.delete_outline, color: AppColors.danger),
                  tooltip: 'Удалить',
                ),
            ],
          ),
          if (_loading)
            Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                if (_sold && !_hidePrices)
                  Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: GlassCard(
                      borderColor: AppColors.warn.withOpacity(0.5),
                      child: Text(
                          'Товар из этого поступления уже продавался, поэтому документ только для просмотра.',
                          style: TextStyle(color: AppColors.warn)),
                    ),
                  ),
                Row(children: [
                  Expanded(
                    child: GlassCard(
                      radius: 16,
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                      onTap: _readOnly ? null : _pickDate,
                      child: Row(children: [
                        Icon(Icons.event_outlined, color: AppColors.textDim, size: 20),
                        SizedBox(width: 8),
                        Text(dateText(_date),
                            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ]),
                SizedBox(height: 12),
                if (!_opening) Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _suppliers.any((s) => s.id == _supplierId) ? _supplierId : null,
                      dropdownColor: AppColors.sheet,
                      style: TextStyle(color: AppColors.text, fontSize: 16),
                      decoration: glassInput('Поставщик'),
                      items: [
                        DropdownMenuItem<String?>(value: null, child: Text('Без поставщика')),
                        for (final s in _suppliers)
                          DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                      ],
                      onChanged: _readOnly ? null : (v) => setState(() => _supplierId = v),
                    ),
                  ),
                  if (!_readOnly) ...[
                    SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: _newSupplier,
                      icon: Icon(Icons.person_add_alt_1_outlined),
                      tooltip: 'Новый поставщик',
                    ),
                  ],
                ]),
                SizedBox(height: 12),
                TextField(
                  controller: _comment,
                  enabled: !_readOnly,
                  style: TextStyle(color: AppColors.text),
                  decoration: glassInput('Комментарий'),
                ),
                if (_author != null) ...[
                  SizedBox(height: 8),
                  Text('Автор: $_author · ${_device ?? ''}',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                ],
                SizedBox(height: 16),
                for (var i = 0; i < _lines.length; i++)
                  Padding(padding: EdgeInsets.only(bottom: 10), child: _lineCard(i)),
                if (!_readOnly)
                  OutlinedButton.icon(
                    onPressed: _addLine,
                    icon: Icon(Icons.add),
                    label: Text('Добавить товар'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      minimumSize: Size.fromHeight(52),
                      side: BorderSide(color: AppColors.accent.withOpacity(0.6)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                SizedBox(height: 16),
                if (!_hidePrices)
                GlassCard(
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Итого', style: TextStyle(color: AppColors.textDim, fontSize: 15)),
                    Text(money(_total),
                        style: TextStyle(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w800)),
                  ]),
                ),
                if (!_hidePrices && !_opening) ...[
                  SizedBox(height: 12),
                  _paymentCard(),
                ],
                if (_error != null)
                  Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(_error!, style: TextStyle(color: AppColors.danger)),
                  ),
                SizedBox(height: 16),
                if (!_readOnly)
                  AccentButton(label: _busy ? 'Сохраняю…' : 'Провести', onPressed: _busy ? null : _save),
              ]),
            ),
        ]),
      ),
    );
  }
}

// Касса: корзина, поиск товара по названию и штрихкоду, оплата
// наличными / Kaspi / в долг (покупатель + дата оплаты).

import 'dart:io';

import 'package:flutter/material.dart';

import '../services/customer_service.dart';
import '../services/photo_service.dart';
import '../services/product_service.dart';
import '../services/sale_service.dart';
import '../services/shift_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';
import '../ui/product_picker.dart';
import 'barcode_scan_screen.dart';
import 'change_pin_screen.dart';
import 'returns_screen.dart';
import 'shift_screen.dart';

class KassaScreen extends StatefulWidget {
  KassaScreen({super.key});
  @override
  State<KassaScreen> createState() => _KassaScreenState();
}

class _KassaScreenState extends State<KassaScreen> {
  Shift? _shift;
  bool _loading = true;
  final List<CartLine> _cart = [];
  final Map<String, File> _thumbs = {};
  final _comment = TextEditingController();
  Payment _pay = Payment.cash;
  Customer? _customer;
  DateTime? _due;
  bool _busy = false;
  final _cashPart = TextEditingController(); // смешанная оплата: сколько наличными

  @override
  void initState() {
    super.initState();
    _loadShift();
  }

  Future<void> _loadShift() async {
    final sh = await ShiftService.instance.current();
    if (mounted) {
      setState(() {
        _shift = sh;
        _loading = false;
      });
    }
  }

  double get _total => _cart.fold(0, (s, l) => s + l.sum);

  Future<void> _add(Product p) async {
    final i = _cart.indexWhere((l) => l.productId == p.id);
    if (p.stock <= 0) {
      _snack('«${p.name}» нет на складе');
      return;
    }
    if (i >= 0) {
      if (_cart[i].qty + 1 > _cart[i].stock + 1e-9) {
        _snack('На складе только ${qtyText(_cart[i].stock)} ${p.unit}');
        return;
      }
      setState(() => _cart[i].qty += 1);
      return;
    }
    final photo = p.photos.isEmpty ? null : p.photos.first;
    if (photo != null && !_thumbs.containsKey(photo)) {
      _thumbs[photo] = await PhotoService.instance.fileFor(photo);
    }
    setState(() => _cart.add(CartLine(
          productId: p.id!,
          name: p.name,
          unit: p.unit,
          photo: photo,
          stock: p.stock,
          price: p.salePrice,
        )));
  }

  Future<void> _search() async {
    final p = await pickProduct(context);
    if (p != null) await _add(p);
  }

  Future<void> _scan() async {
    final code = await BarcodeScanScreen.scan(context);
    if (code == null || !mounted) return;
    final p = await ProductService.instance.byBarcode(code);
    if (!mounted) return;
    if (p == null) {
      _snack('Товар со штрихкодом $code не найден');
    } else {
      await _add(p);
    }
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _editQty(CartLine l) async {
    final c = TextEditingController(text: qtyText(l.qty));
    final v = await showDialog<double>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l.name),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Количество, ${l.unit}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(d, parseNum(c.text)), child: Text('OK')),
        ],
      ),
    );
    if (v == null || v <= 0) return;
    if (v > l.stock + 1e-9) return _snack('На складе только ${qtyText(l.stock)} ${l.unit}');
    setState(() => l.qty = v);
  }

  Future<void> _pickCustomer() async {
    final c = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.sheet,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _CustomerPicker(),
    );
    if (c != null) setState(() => _customer = c);
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _due ?? now.add(Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(Duration(days: 365)),
    );
    if (d != null) setState(() => _due = DateTime(d.year, d.month, d.day, 12));
  }

  Future<void> _sell() async {
    setState(() => _busy = true);
    final r = await SaleService.instance.sell(
      lines: _cart,
      payment: _pay,
      customerId: _customer?.id,
      dueDate: _due,
      comment: _comment.text,
      cashPart: parseNum(_cashPart.text) ?? 0,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.error != null) return _snack(r.error!);
    setState(() {
      _cart.clear();
      _comment.clear();
      _cashPart.clear();
      _pay = Payment.cash;
      _customer = null;
      _due = null;
    });
    _snack('Продано на ${money(r.total)}');
  }

  Future<void> _openShift() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShiftScreen()));
    _loadShift();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Касса', actions: [
            IconButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => ChangePinScreen())),
              icon: Icon(Icons.password, color: AppColors.text),
              tooltip: 'Сменить мой PIN',
            ),
            IconButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => ReturnsScreen())),
              icon: Icon(Icons.assignment_return_outlined, color: AppColors.warn),
              tooltip: 'Возврат',
            ),
            TextButton.icon(
              onPressed: _openShift,
              icon: Icon(Icons.point_of_sale_outlined, color: AppColors.accent),
              label: Text('Смена', style: TextStyle(color: AppColors.accent)),
            ),
          ]),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : _shift == null
                    ? _noShift()
                    : _cartView(),
          ),
        ]),
      ),
    );
  }

  Widget _noShift() => Padding(
        padding: EdgeInsets.all(16),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Смена не открыта', style: TextStyle(color: AppColors.text, fontSize: 18)),
          SizedBox(height: 14),
          AccentButton(label: 'Открыть смену', onPressed: _openShift),
        ]),
      );

  Widget _thumb(CartLine l) {
    final f = l.photo == null ? null : _thumbs[l.photo];
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: f == null
          ? Container(
              width: 52,
              height: 52,
              color: AppColors.overlay(0.08),
              child: Icon(Icons.inventory_2_outlined, color: AppColors.textDim))
          : Image.file(f, width: 52, height: 52, fit: BoxFit.cover),
    );
  }

  Widget _cartView() {
    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(children: [
          Expanded(
            child: GlassCard(
              radius: 16,
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              onTap: _search,
              child: Row(children: [
                Icon(Icons.search, color: AppColors.textDim),
                SizedBox(width: 8),
                Text('Найти товар по названию', style: TextStyle(color: AppColors.textDim)),
              ]),
            ),
          ),
          SizedBox(width: 8),
          SizedBox(
            width: 56,
            height: 56,
            child: FilledButton(
              onPressed: _scan,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Icon(Icons.qr_code_scanner, semanticLabel: 'Сканировать штрихкод'),
            ),
          ),
        ]),
      ),
      Expanded(
        child: ListView(padding: EdgeInsets.symmetric(horizontal: 16), children: [
          if (_cart.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                  child: Text('Корзина пустая — добавьте товар', style: TextStyle(color: AppColors.textDim))),
            ),
          for (final l in _cart)
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Dismissible(
                key: ValueKey(l.productId),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => setState(() => _cart.remove(l)),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: EdgeInsets.only(right: 20),
                  child: Icon(Icons.delete_outline, color: AppColors.danger),
                ),
                child: GlassCard(
                  radius: 18,
                  padding: EdgeInsets.all(10),
                  child: Row(children: [
                    _thumb(l),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.name,
                            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                        Text('${money(l.price)} / ${l.unit}',
                            style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                        Text('Остаток: ${qtyText(l.stock - l.qty)} ${l.unit}',
                            style: TextStyle(
                                color: l.stock - l.qty <= 0 ? AppColors.warn : AppColors.textDim, fontSize: 12)),
                        Text(money(l.sum),
                            style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                    IconButton(
                      onPressed: () => setState(() {
                        if (l.qty > 1) {
                          l.qty -= 1;
                        } else {
                          _cart.remove(l);
                        }
                      }),
                      icon: Icon(Icons.remove, color: AppColors.text),
                      tooltip: 'Меньше',
                    ),
                    InkWell(
                      onTap: () => _editQty(l),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Text(qtyText(l.qty),
                            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        if (l.qty + 1 > l.stock + 1e-9) {
                          _snack('На складе только ${qtyText(l.stock)} ${l.unit}');
                        } else {
                          setState(() => l.qty += 1);
                        }
                      },
                      icon: Icon(Icons.add, color: AppColors.text),
                      tooltip: 'Больше',
                    ),
                  ]),
                ),
              ),
            ),
          if (_cart.isNotEmpty)
            TextField(
              controller: _comment,
              style: TextStyle(color: AppColors.text),
              decoration: glassInput('Комментарий'),
            ),
          SizedBox(height: 12),
        ]),
      ),
      _payPanel(),
    ]);
  }

  Widget _payPanel() {
    // Кнопки оплаты: текст сжимается, а не обрезается («Наличные» помещается целиком).
    Widget payBtn(Payment p, String label) {
      final on = _pay == p;
      return Expanded(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Material(
            color: on ? AppColors.text : AppColors.overlay(0.06),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _pay = p),
              child: Container(
                height: 42,
                padding: EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1,
                      style: TextStyle(
                          color: on ? AppColors.bg : AppColors.text, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GlassCard(
        radius: 24,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Итого', style: TextStyle(color: AppColors.textDim, fontSize: 15)),
            Text(money(_total),
                style: TextStyle(color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w800)),
          ]),
          SizedBox(height: 10),
          Row(children: [
            payBtn(Payment.cash, 'Наличные'),
            payBtn(Payment.kaspi, 'Kaspi'),
            payBtn(Payment.mixed, 'Нал + Kaspi'),
            payBtn(Payment.debt, 'В долг'),
          ]),
          if (_pay == Payment.mixed) ...[
            SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _cashPart,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppColors.text),
                  decoration: glassInput('Наличными, ₸'),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Kaspi: ${money((_total - (parseNum(_cashPart.text) ?? 0)).clamp(0, double.infinity).toDouble())}',
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ]),
          ],
          if (_pay == Payment.debt) ...[
            SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: GlassCard(
                  radius: 14,
                  padding: EdgeInsets.all(12),
                  onTap: _pickCustomer,
                  child: Text(_customer?.name ?? 'Выбрать покупателя',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _customer == null ? AppColors.textDim : AppColors.text)),
                ),
              ),
              SizedBox(width: 8),
              GlassCard(
                radius: 14,
                padding: EdgeInsets.all(12),
                onTap: _pickDue,
                child: Text(_due == null ? 'Оплатит до' : 'до ${dateText(_due!)}',
                    style: TextStyle(color: _due == null ? AppColors.textDim : AppColors.warn)),
              ),
            ]),
          ],
          SizedBox(height: 12),
          AccentButton(
            label: _busy ? 'Сохраняю…' : (_pay == Payment.debt ? 'Записать в долг' : 'Оплатить'),
            onPressed: _busy || _cart.isEmpty ? null : _sell,
          ),
        ]),
      ),
    );
  }
}

/// Выбор или создание покупателя.
class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker();
  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  final _q = TextEditingController();
  final _phone = TextEditingController();
  List<Customer> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await CustomerService.instance.search(_q.text);
    if (mounted) setState(() => _items = l);
  }

  Future<void> _create() async {
    final name = _q.text.trim();
    if (name.isEmpty) return;
    final id = await CustomerService.instance.save(Customer(name: name, phone: _phone.text));
    if (mounted) Navigator.pop(context, Customer(id: id, name: name, phone: _phone.text));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: TextField(
              controller: _q,
              autofocus: true,
              onChanged: (_) => _load(),
              style: TextStyle(color: AppColors.text),
              decoration: glassInput('Имя или телефон покупателя'),
            ),
          ),
          if (_q.text.trim().isNotEmpty && !_items.any((c) => c.name.toLowerCase() == _q.text.trim().toLowerCase()))
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: AppColors.text),
                    decoration: glassInput('Телефон нового покупателя'),
                  ),
                ),
                SizedBox(width: 8),
                FilledButton(
                  onPressed: _create,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent, foregroundColor: AppColors.onAccent),
                  child: Text('Создать'),
                ),
              ]),
            ),
          Expanded(
            child: ListView(children: [
              for (final c in _items)
                ListTile(
                  onTap: () => Navigator.pop(context, c),
                  leading: Icon(Icons.person_outline, color: AppColors.textDim),
                  title: Text(c.name, style: TextStyle(color: AppColors.text)),
                  subtitle: Text(c.phone ?? '', style: TextStyle(color: AppColors.textDim)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

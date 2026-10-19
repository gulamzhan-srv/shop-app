// Продажа: корзина, поиск товара по названию и штрихкоду, оплата
// наличными / Kaspi / смешанная / в долг (покупатель + дата оплаты).
// Компактный вид: всё помещается на экране. Смена открывается и закрывается в разделе «Касса».

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

class SaleScreen extends StatefulWidget {
  SaleScreen({super.key});
  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
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
    final p = await pickProduct(context, forSale: true);
    if (p != null) await _add(p);
  }

  Future<void> _scan() async {
    final code = await BarcodeScanScreen.scan(context);
    if (code == null || !mounted) return;
    final p = await resolveBarcode(context, code);
    if (!mounted || p == null) return;
    if (!p.active) return _snack('«${p.name}» отключён и не продаётся');
    await _add(p);
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _editQty(CartLine l) async {
    final c = TextEditingController(text: qtyText(l.qty));
    final v = await showGlassDialog<double>(
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
    return PopScope(
      canPop: !_busy, // пока сохраняется продажа — выйти нельзя
      child: Stack(children: [
        _screen(),
        // После нажатия «Оплатить» экран блокируется, пока продажа не сохранится:
        // нельзя нажать второй раз или изменить корзину (даже если интернет «завис»).
        if (_busy)
          Positioned.fill(
            child: AbsorbPointer(
              child: Container(
                color: Colors.black.withOpacity(0.35),
                alignment: Alignment.center,
                child: GlassCard(
                  radius: 16,
                  padding: EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Сохраняю продажу…',
                        style: TextStyle(
                            color: AppColors.text, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _screen() {
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Продажа', actions: [
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
          Icon(Icons.lock_clock_outlined, color: AppColors.textDim, size: 40),
          SizedBox(height: 10),
          Text('Смена не открыта', style: TextStyle(color: AppColors.text, fontSize: 18)),
          SizedBox(height: 4),
          Text('Откройте смену в разделе «Касса»', style: TextStyle(color: AppColors.textDim)),
          SizedBox(height: 14),
          AccentButton(label: 'Перейти в кассу', onPressed: _openShift),
        ]),
      );

  Widget _thumb(CartLine l) {
    final f = l.photo == null ? null : _thumbs[l.photo];
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: f == null
          ? Container(
              width: 38,
              height: 38,
              color: AppColors.overlay(0.08),
              child: Icon(Icons.inventory_2_outlined, color: AppColors.textDim, size: 18))
          : Image.file(f, width: 38, height: 38, fit: BoxFit.cover),
    );
  }

  Widget _small(IconData icon, String tip, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: AppColors.overlay(0.08), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: AppColors.text, semanticLabel: tip),
        ),
      );

  Widget _line(CartLine l) {
    final left = l.stock - l.qty;
    return Dismissible(
      key: ValueKey(l.productId),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => setState(() => _cart.remove(l)),
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 16),
        child: Icon(Icons.delete_outline, color: AppColors.danger),
      ),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.overlay(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.overlay(0.1)),
        ),
        child: Row(children: [
          _thumb(l),
          SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 15)),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${money(l.price)} · ост. '),
                  TextSpan(
                      text: '${qtyText(left)} ${l.unit}',
                      style: TextStyle(
                          color: left <= 0 ? AppColors.warn : AppColors.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ]),
          ),
          _small(Icons.remove, 'Меньше', () => setState(() {
                if (l.qty > 1) {
                  l.qty -= 1;
                } else {
                  _cart.remove(l);
                }
              })),
          InkWell(
            onTap: () => _editQty(l),
            child: Container(
              constraints: BoxConstraints(minWidth: 30),
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(qtyText(l.qty),
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
          _small(Icons.add, 'Больше', () {
            if (l.qty + 1 > l.stock + 1e-9) {
              _snack('На складе только ${qtyText(l.stock)} ${l.unit}');
            } else {
              setState(() => l.qty += 1);
            }
          }),
          SizedBox(width: 8),
          SizedBox(
            width: 74,
            child: Text(money(l.sum),
                textAlign: TextAlign.right,
                maxLines: 1,
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ]),
      ),
    );
  }

  Widget _cartView() {
    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Row(children: [
          Expanded(
            child: InkWell(
              onTap: _search,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 42,
                padding: EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.overlay(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.overlay(0.14)),
                ),
                child: Row(children: [
                  Icon(Icons.search, color: AppColors.textDim, size: 20),
                  SizedBox(width: 8),
                  Text('Товар по названию', style: TextStyle(color: AppColors.textDim)),
                ]),
              ),
            ),
          ),
          SizedBox(width: 6),
          SizedBox(
            width: 42,
            height: 42,
            child: FilledButton(
              onPressed: _scan,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Icon(Icons.qr_code_scanner, size: 22, semanticLabel: 'Сканировать штрихкод'),
            ),
          ),
        ]),
      ),
      if (_cart.isNotEmpty)
        Padding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, 4),
          child: Row(children: [
            Text('Позиций: ${_cart.length}', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            Spacer(),
            Text('Смахните строку влево — удалить', style: TextStyle(color: AppColors.textDim, fontSize: 11)),
          ]),
        ),
      Expanded(
        child: _cart.isEmpty
            ? Center(
                child: Text('Корзина пустая — найдите или отсканируйте товар',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)))
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
                itemCount: _cart.length,
                separatorBuilder: (_, __) => SizedBox(height: 4),
                itemBuilder: (_, i) => _line(_cart[i]),
              ),
      ),
      _payPanel(),
    ]);
  }

  Widget _payPanel() {
    Widget payBtn(Payment p, String label) {
      final on = _pay == p;
      return Expanded(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Material(
            color: on ? AppColors.accent : AppColors.overlay(0.06),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _pay = p),
              child: Container(
                height: 34,
                padding: EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1,
                      style: TextStyle(
                          color: on ? AppColors.onAccent : AppColors.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final dense = InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );

    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.sheet.withOpacity(0.92),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: AppColors.overlay(0.14))),
      ),
      child: SafeArea(
        top: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _comment,
                style: TextStyle(color: AppColors.text, fontSize: 13),
                decoration: glassInput('Комментарий').copyWith(
                    isDense: dense.isDense, contentPadding: dense.contentPadding),
              ),
            ),
            SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Итого', style: TextStyle(color: AppColors.textDim, fontSize: 11)),
              Text(money(_total),
                  style: TextStyle(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
          ]),
          SizedBox(height: 8),
          Row(children: [
            payBtn(Payment.cash, 'Наличные'),
            payBtn(Payment.kaspi, 'Kaspi'),
            payBtn(Payment.mixed, 'Нал+Kaspi'),
            payBtn(Payment.debt, 'В долг'),
          ]),
          if (_pay == Payment.mixed) ...[
            SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _cashPart,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppColors.text, fontSize: 14),
                  decoration: glassInput('Наличными, ₸').copyWith(
                      isDense: dense.isDense, contentPadding: dense.contentPadding),
                ),
              ),
              SizedBox(width: 10),
              Text(
                'Kaspi: ${money((_total - (parseNum(_cashPart.text) ?? 0)).clamp(0, double.infinity).toDouble())}',
                style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ]),
          ],
          if (_pay == Payment.debt) ...[
            SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _chip(Icons.person_outline, _customer?.name ?? 'Покупатель', _customer == null, _pickCustomer),
              ),
              SizedBox(width: 6),
              _chip(Icons.event_outlined, _due == null ? 'Оплатит до' : 'до ${dateText(_due!)}', _due == null,
                  _pickDue),
            ]),
          ],
          SizedBox(height: 8),
          AccentButton(
            label: _busy
                ? 'Сохраняю…'
                : (_pay == Payment.debt ? 'Записать в долг' : 'Оплатить ${money(_total)}'),
            onPressed: _busy || _cart.isEmpty ? null : _sell,
          ),
        ]),
      ),
    );
  }

  Widget _chip(IconData icon, String text, bool empty, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 38,
          padding: EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.overlay(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: empty ? AppColors.warn.withOpacity(0.6) : AppColors.overlay(0.14)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: AppColors.textDim),
            SizedBox(width: 6),
            Flexible(
              child: Text(text,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: empty ? AppColors.textDim : AppColors.text, fontSize: 13)),
            ),
          ]),
        ),
      );
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

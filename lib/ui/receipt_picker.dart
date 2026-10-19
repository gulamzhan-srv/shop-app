// Подбор товаров в поступление: сразу несколько товаров, у каждого «Цена закупки»
// и количество (− / +), видно «в наличии» и «станет на складе». Товары по группам,
// поиск, сканер и кнопка «Новый товар» (создать карточку и сразу добавить).
//   final picked = await pickReceiptLines(context);

import 'package:flutter/material.dart';

import '../db/database.dart';
import '../screens/barcode_scan_screen.dart';
import '../screens/product_edit_screen.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import 'format.dart';
import 'glass.dart';
import 'product_picker.dart';

class PickedLine {
  final Product product;
  double qty;
  double price;
  PickedLine(this.product, this.qty, this.price);
  double get sum => qty * price;
}

Future<List<PickedLine>?> pickReceiptLines(BuildContext context) {
  return showModalBottomSheet<List<PickedLine>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.bg,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _ReceiptPicker(),
  );
}

class _ReceiptPicker extends StatefulWidget {
  @override
  State<_ReceiptPicker> createState() => _ReceiptPickerState();
}

class _ReceiptPickerState extends State<_ReceiptPicker> {
  final _q = TextEditingController();
  List<Product> _items = [];
  List<ProductGroup> _groups = [];
  String? _group;
  Map<String, double> _cost = {}; // последняя цена закупки
  final Map<String, PickedLine> _picked = {};
  final Map<String, TextEditingController> _priceCtl = {};
  final Map<String, TextEditingController> _qtyCtl = {};
  final bool _manager = AuthService.instance.current?.isManager ?? false;

  @override
  void initState() {
    super.initState();
    ProductService.instance.categories().then((l) {
      if (mounted) setState(() => _groups = l);
    });
    _load();
  }

  Future<void> _load() async {
    final list = await ProductService.instance.search(_q.text, _group);
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT b.product_id, b.cost_price FROM batches b
      WHERE b.deleted = 0 AND b.received_at = (SELECT MAX(x.received_at) FROM batches x
                                               WHERE x.product_id = b.product_id AND x.deleted = 0)''');
    final cost = {for (final r in rows) r['product_id'] as String: (r['cost_price'] as num).toDouble()};
    if (mounted) {
      setState(() {
        _items = list;
        _cost = cost;
      });
    }
  }

  TextEditingController _price(Product p) => _priceCtl.putIfAbsent(p.id!, () {
        final c = _cost[p.id];
        return TextEditingController(text: c == null ? '' : qtyText(c));
      });

  TextEditingController _qty(Product p) =>
      _qtyCtl.putIfAbsent(p.id!, () => TextEditingController(text: '1'));

  void _add(Product p, {double qty = 1}) {
    final price = parseNum(_price(p).text) ?? 0;
    setState(() {
      final ex = _picked[p.id!];
      if (ex != null) {
        ex.qty += qty;
      } else {
        _picked[p.id!] = PickedLine(p, qty, price);
      }
      _qty(p).text = qtyText(_picked[p.id!]!.qty);
    });
  }

  void _step(Product p, double d) {
    final l = _picked[p.id!];
    if (l == null) return;
    setState(() {
      l.qty += d;
      if (l.qty <= 0) {
        _picked.remove(p.id!);
        _qty(p).text = '1';
      } else {
        _qty(p).text = qtyText(l.qty);
      }
    });
  }

  Future<void> _scan() async {
    final code = await BarcodeScanScreen.scan(context);
    if (code == null || !mounted) return;
    final p = await resolveBarcode(context, code);
    if (p == null || !mounted) return;
    await _load();
    final fresh = _items.where((x) => x.id == p.id).toList();
    _add(fresh.isEmpty ? p : fresh.first);
  }

  /// Новый товар прямо из поступления: заполняем карточку (группа, штрихкод, цена…)
  /// и он сразу попадает в список выбранных.
  Future<void> _newProduct() async {
    final before = {for (final p in await ProductService.instance.search()) p.id};
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductEditScreen()));
    final all = await ProductService.instance.search();
    await _load();
    for (final p in all) {
      if (!before.contains(p.id)) _add(p);
    }
  }

  Widget _stockPill(Product p) {
    final c = p.stock <= 0 ? AppColors.danger : (p.low ? AppColors.warn : Color(0xFF16A34A));
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(p.stock <= 0 ? 'нет в наличии' : 'в наличии ${qtyText(p.stock)}',
          style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }

  Widget _item(Product p) {
    final l = _picked[p.id];
    final on = l != null;
    return Container(
      color: on ? Color(0xFF16A34A).withOpacity(0.06) : Colors.transparent,
      padding: EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(p.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          SizedBox(width: 6),
          _stockPill(p),
        ]),
        SizedBox(height: 8),
        Row(children: [
          SizedBox(
            width: 140,
            child: TextField(
              controller: _price(p),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) {
                if (l != null) setState(() => l.price = parseNum(v) ?? 0);
              },
              style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800),
              decoration: glassInput('Цена закупки', suffix: Text('₸ ', style: TextStyle(color: AppColors.textDim)))
                  .copyWith(isDense: true, contentPadding: EdgeInsets.fromLTRB(12, 10, 4, 10)),
            ),
          ),
          Spacer(),
          if (l == null)
            SizedBox(
              height: 42,
              child: FilledButton(
                onPressed: () => _add(p),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.onAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                child: Text('Добавить'),
              ),
            )
          else
            Container(
              padding: EdgeInsets.all(4),
              decoration: BoxDecoration(color: AppColors.overlay(0.06), borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  onPressed: () => _step(p, -1),
                  icon: Icon(Icons.remove, color: AppColors.accent),
                  visualDensity: VisualDensity.compact,
                ),
                SizedBox(
                  width: 54,
                  child: TextField(
                    controller: _qty(p),
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      final q = parseNum(v);
                      if (q != null && q > 0) setState(() => l.qty = q);
                    },
                    style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.sheet,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _step(p, 1),
                  icon: Icon(Icons.add, color: AppColors.accent),
                  visualDensity: VisualDensity.compact,
                ),
              ]),
            ),
        ]),
        if (l != null) ...[
          SizedBox(height: 6),
          Row(children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: '${qtyText(l.qty)} × ${money(l.price)} = ', style: TextStyle(color: AppColors.textDim)),
              TextSpan(text: money(l.sum), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
            ])),
            Spacer(),
            Text.rich(TextSpan(children: [
              TextSpan(text: 'станет: ', style: TextStyle(color: AppColors.textDim)),
              TextSpan(
                  text: '${qtyText(p.stock + l.qty)} ${p.unit}',
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
            ])),
          ]),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Группируем по папкам (как в справочнике товаров).
    final names = {for (final g in _groups) g.id: g.name};
    final byGroup = <String, List<Product>>{};
    for (final p in _items) {
      byGroup.putIfAbsent(names[p.categoryId] ?? 'Без группы', () => []).add(p);
    }
    final total = _picked.values.fold<double>(0, (s, l) => s + l.sum);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(children: [
        Container(
          color: AppColors.sheet,
          padding: EdgeInsets.fromLTRB(16, 12, 12, 10),
          child: Row(children: [
            Expanded(
              child: Text('Товары', style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            if (_manager)
              TextButton.icon(
                onPressed: _newProduct,
                icon: Icon(Icons.add_box_outlined),
                label: Text('Новый товар'),
              ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Закрыть')),
          ]),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _q,
                onChanged: (_) => _load(),
                style: TextStyle(color: AppColors.text, fontSize: 16),
                decoration: glassInput('Название или штрихкод', suffix: Icon(Icons.search, color: AppColors.textDim))
                    .copyWith(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
              ),
            ),
            SizedBox(width: 6),
            SizedBox(
              width: 46,
              height: 46,
              child: OutlinedButton(
                onPressed: _scan,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: AppColors.accent,
                  side: BorderSide(color: AppColors.overlay(0.2)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Icon(Icons.qr_code_scanner),
              ),
            ),
          ]),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: CategoryChips(
            cats: _groups,
            selected: _group,
            onSelected: (v) {
              _group = v;
              _load();
            },
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? Center(child: Text('Товаров нет', style: TextStyle(color: AppColors.textDim)))
              : ListView(padding: EdgeInsets.fromLTRB(12, 0, 12, 10), children: [
                  for (final e in byGroup.entries)
                    Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        radius: 16,
                        padding: EdgeInsets.zero,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Container(
                            padding: EdgeInsets.fromLTRB(14, 8, 14, 8),
                            color: AppColors.overlay(0.04),
                            child: Text(e.key,
                                style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w800, fontSize: 14)),
                          ),
                          for (var i = 0; i < e.value.length; i++) ...[
                            if (i > 0) Divider(height: 1, color: AppColors.overlay(0.08)),
                            _item(e.value[i]),
                          ],
                        ]),
                      ),
                    ),
                ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: AccentButton(
              label: _picked.isEmpty ? 'Готово' : 'Готово · ${_picked.length} поз. · ${money(total)}',
              onPressed: () => Navigator.of(context).pop(_picked.values.toList()),
            ),
          ),
        ),
      ]),
    );
  }
}

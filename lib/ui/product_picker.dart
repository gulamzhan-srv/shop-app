// Выбор товара: поиск по названию / штрихкоду, фильтр по группам, сканер.
//   final p = await pickProduct(context);              // для поступления (все товары)
//   final p = await pickProduct(context, forSale: true); // для продажи (без отключённых)
// resolveBarcode — найти товар по отсканированному коду; если не найден, хозяин может
// сразу привязать этот код к существующему товару или создать новый товар.

import 'package:flutter/material.dart';

import '../screens/barcode_scan_screen.dart';
import '../screens/product_edit_screen.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import 'glass.dart';

Future<Product?> pickProduct(BuildContext context, {bool forSale = false}) {
  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.sheet,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _ProductPicker(forSale: forSale),
  );
}

/// Товар по штрихкоду. Не найден → предложить привязать код или создать товар.
Future<Product?> resolveBarcode(BuildContext context, String code) async {
  final found = await ProductService.instance.byBarcode(code);
  if (found != null || !context.mounted) return found;
  final manager = AuthService.instance.current?.isManager ?? false;
  final action = await showGlassDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Штрихкод не найден'),
      content: Text(manager
          ? 'Код $code не привязан ни к одному товару.\n\n'
              'Если на упаковке несколько штрихкодов — привяжите этот код к товару, '
              'и дальше он будет находиться сразу.'
          : 'Код $code не привязан ни к одному товару. Попросите хозяина привязать его к товару '
              'или найдите товар по названию.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(manager ? 'Отмена' : 'Понятно')),
        if (manager) TextButton(onPressed: () => Navigator.pop(c, 'new'), child: Text('Новый товар')),
        if (manager) FilledButton(onPressed: () => Navigator.pop(c, 'link'), child: Text('Привязать')),
      ],
    ),
  );
  if (!context.mounted) return null;
  if (action == 'link') {
    final p = await pickProduct(context);
    if (p == null || !context.mounted) return null;
    final err = await ProductService.instance.addBarcode(p.id!, code);
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err ?? 'Штрихкод $code привязан к «${p.name}»')));
    if (err != null) return null;
    return ProductService.instance.byBarcode(code);
  }
  if (action == 'new') {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ProductEditScreen(initialBarcode: code)));
    return ProductService.instance.byBarcode(code);
  }
  return null;
}

/// Горизонтальный ряд фильтров по группам: «Все», затем группы. null — все.
class CategoryChips extends StatelessWidget {
  final List<ProductGroup> cats;
  final String? selected;
  final ValueChanged<String?> onSelected;
  CategoryChips({super.key, required this.cats, required this.selected, required this.onSelected});

  Widget _chip(String label, bool on, VoidCallback tap) => Padding(
        padding: EdgeInsets.only(right: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: tap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: on ? AppColors.accent : AppColors.overlay(0.07),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (label != 'Все')
                Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.folder_outlined, size: 14, color: on ? AppColors.onAccent : AppColors.textDim),
                ),
              Text(label,
                  style: TextStyle(
                      color: on ? AppColors.onAccent : AppColors.text, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (cats.isEmpty) return SizedBox.shrink();
    return SizedBox(
      height: 32,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        _chip('Все', selected == null, () => onSelected(null)),
        for (final c in cats) _chip(c.name, selected == c.id, () => onSelected(c.id)),
      ]),
    );
  }
}

/// Компактная строка товара: название (жирнее), штрихкод мельче, справа крупный остаток.
class ProductRow extends StatelessWidget {
  final Product p;
  final VoidCallback onTap;
  final Widget? leading;
  final String? subtitle; // вместо штрихкода (например, цена)
  ProductRow({super.key, required this.p, required this.onTap, this.leading, this.subtitle});

  static String fmtQty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final out = p.stock <= 0;
    final stockColor = out ? AppColors.danger : (p.low ? AppColors.warn : AppColors.accent);
    final sub = subtitle ?? p.barcodes.join(', ');
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: p.active ? 1 : 0.5,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(children: [
            if (leading != null) ...[leading!, SizedBox(width: 10)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700, height: 1.15)),
                if (sub.isNotEmpty || !p.active)
                  Text(p.active ? sub : 'отключён${sub.isEmpty ? '' : ' · $sub'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ]),
            ),
            SizedBox(width: 8),
            Text('${fmtQty(p.stock)} ',
                style: TextStyle(color: stockColor, fontSize: 19, fontWeight: FontWeight.w800)),
            Text(p.unit, style: TextStyle(color: stockColor, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _ProductPicker extends StatefulWidget {
  final bool forSale;
  const _ProductPicker({required this.forSale});
  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final _q = TextEditingController();
  List<Product> _items = [];
  List<ProductGroup> _cats = [];
  String? _cat;

  @override
  void initState() {
    super.initState();
    ProductService.instance.categories().then((l) {
      if (mounted) setState(() => _cats = l);
    });
    _load();
  }

  Future<void> _load() async {
    final list = await ProductService.instance.search(_q.text, _cat, widget.forSale);
    if (mounted) setState(() => _items = list);
  }

  Future<void> _scan() async {
    final code = await BarcodeScanScreen.scan(context);
    if (code == null || !mounted) return;
    final p = await resolveBarcode(context, code);
    if (p != null && mounted) Navigator.of(context).pop(p);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.85;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: h,
        child: Column(children: [
          SizedBox(height: 8),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.overlay(0.24), borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _q,
                  autofocus: true,
                  onChanged: (_) => _load(),
                  style: TextStyle(color: AppColors.text, fontSize: 16),
                  decoration: glassInput('Название или штрихкод',
                          suffix: Icon(Icons.search, color: AppColors.textDim))
                      .copyWith(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                ),
              ),
              SizedBox(width: 6),
              SizedBox(
                width: 46,
                height: 46,
                child: FilledButton(
                  onPressed: _scan,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Icon(Icons.qr_code_scanner, semanticLabel: 'Сканировать штрихкод'),
                ),
              ),
            ]),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: CategoryChips(
              cats: _cats,
              selected: _cat,
              onSelected: (v) {
                _cat = v;
                _load();
              },
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? Center(child: Text('Ничего не найдено', style: TextStyle(color: AppColors.textDim)))
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.overlay(0.08)),
                    itemBuilder: (_, i) {
                      final p = _items[i];
                      return ProductRow(p: p, onTap: () => Navigator.of(context).pop(p));
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

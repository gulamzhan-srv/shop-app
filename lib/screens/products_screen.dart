// Список товаров: поиск по названию, сканер штрихкода, остаток, добавление (хозяин).

import 'dart:io';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/photo_service.dart';
import '../services/product_service.dart';
import '../ui/glass.dart';
import '../ui/product_picker.dart';
import 'barcode_scan_screen.dart';
import 'product_edit_screen.dart';

class ProductsScreen extends StatefulWidget {
  ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _search = TextEditingController();
  List<Product> _items = [];
  List<ProductGroup> _cats = [];
  String? _cat; // выбранная группа (null — все)
  final Map<String, File> _thumbs = {};
  bool _loading = true;

  bool get _isOwner => AuthService.instance.current?.isOwner ?? false;

  @override
  void initState() {
    super.initState();
    ProductService.instance.categories().then((l) {
      if (mounted) setState(() => _cats = l);
    });
    _load();
  }

  Future<void> _load() async {
    final list = await ProductService.instance.search(_search.text, _cat);
    for (final p in list) {
      if (p.photos.isNotEmpty && !_thumbs.containsKey(p.photos.first)) {
        _thumbs[p.photos.first] = await PhotoService.instance.fileFor(p.photos.first);
      }
    }
    if (mounted) {
      setState(() {
        _items = list;
        _loading = false;
      });
    }
  }

  Future<void> _open(Product? p, {String? barcode}) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ProductEditScreen(product: p, initialBarcode: barcode),
    ));
    if (changed == true) _load();
  }

  Future<void> _scan() async {
    final code = await BarcodeScanScreen.scan(context);
    if (code == null || !mounted) return;
    // Не найден — хозяин может привязать код к товару или создать новый.
    final p = await resolveBarcode(context, code);
    if (p != null && mounted) _open(p);
    _load();
  }

  String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  String _money(double v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return '$b ₸';
  }

  Widget _thumb(Product p) {
    final f = p.photos.isEmpty ? null : _thumbs[p.photos.first];
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: f == null
          ? Container(
              width: 40,
              height: 40,
              color: AppColors.overlay(0.08),
              child: Icon(Icons.inventory_2_outlined, color: AppColors.textDim, size: 20),
            )
          : Image.file(f, width: 40, height: 40, fit: BoxFit.cover),
    );
  }

  /// Управление группами: добавить, переименовать, удалить.
  Future<void> _groups() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.sheet,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _GroupsSheet(),
    );
    _cats = await ProductService.instance.categories();
    if (_cat != null && !_cats.any((c) => c.id == _cat)) _cat = null;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _isOwner
          ? FloatingActionButton.extended(
              onPressed: () => _open(null),
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.onAccent,
              icon: Icon(Icons.add),
              label: Text('Товар', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Товары', actions: [
            if (_isOwner)
              IconButton(
                onPressed: _groups,
                icon: Icon(Icons.folder_open_outlined, color: AppColors.accent),
                tooltip: 'Группы товаров',
              ),
          ]),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => _load(),
                  style: TextStyle(color: AppColors.text),
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
            padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
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
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(child: Text('Товаров нет', style: TextStyle(color: AppColors.textDim)))
                    : ListView(padding: EdgeInsets.fromLTRB(12, 0, 12, 90), children: [
                        GlassCard(
                          radius: 12,
                          padding: EdgeInsets.symmetric(vertical: 2),
                          child: Column(children: [
                            for (var i = 0; i < _items.length; i++) ...[
                              if (i > 0) Divider(height: 1, color: AppColors.overlay(0.08)),
                              ProductRow(
                                p: _items[i],
                                leading: _thumb(_items[i]),
                                subtitle: '${_money(_items[i].salePrice)} / ${_items[i].unit}'
                                    '${_items[i].low ? ' · мало, мин. ${_num(_items[i].minStock)}' : ''}',
                                onTap: () => _open(_items[i]),
                              ),
                            ],
                          ]),
                        ),
                      ]),
          ),
        ]),
      ),
    );
  }
}

class _GroupsSheet extends StatefulWidget {
  @override
  State<_GroupsSheet> createState() => _GroupsSheetState();
}

class _GroupsSheetState extends State<_GroupsSheet> {
  List<ProductGroup> _cats = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await ProductService.instance.categories();
    if (mounted) setState(() => _cats = l);
  }

  Future<void> _edit(ProductGroup? c) async {
    final t = TextEditingController(text: c?.name ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(c == null ? 'Новая группа' : 'Переименовать группу'),
        content: TextField(controller: t, autofocus: true, decoration: InputDecoration(labelText: 'Название')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text('Сохранить')),
        ],
      ),
    );
    if (ok != true || t.text.trim().isEmpty) return;
    await ProductService.instance.saveCategory(t.text, id: c?.id);
    _load();
  }

  Future<void> _delete(ProductGroup c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Удалить группу «${c.name}»?'),
        content: Text('Товары останутся, но будут «без группы».'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    await ProductService.instance.deleteCategory(c.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: Row(children: [
              Expanded(
                child: Text('Группы товаров',
                    style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              TextButton.icon(
                onPressed: () => _edit(null),
                icon: Icon(Icons.create_new_folder_outlined),
                label: Text('Добавить'),
              ),
            ]),
          ),
          Expanded(
            child: _cats.isEmpty
                ? Center(
                    child: Text('Групп пока нет. Добавьте, например: «Масла», «Фильтры», «Шины».',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)))
                : ListView(children: [
                    for (final c in _cats)
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.folder_outlined, color: AppColors.accent),
                        title: Text(c.name, style: TextStyle(color: AppColors.text, fontSize: 15)),
                        onTap: () => _edit(c),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, color: AppColors.textDim),
                          onPressed: () => _delete(c),
                        ),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

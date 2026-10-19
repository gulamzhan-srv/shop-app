// Список товаров: поиск по названию, сканер штрихкода, остаток, добавление (хозяин).

import 'dart:io';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/photo_service.dart';
import '../services/product_service.dart';
import '../ui/glass.dart';
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
  final Map<String, File> _thumbs = {};
  bool _loading = true;

  bool get _isOwner => AuthService.instance.current?.isOwner ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ProductService.instance.search(_search.text);
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
    final p = await ProductService.instance.byBarcode(code);
    if (p != null) {
      _open(p);
    } else if (_isOwner) {
      _open(null, barcode: code); // нет такого — сразу создаём с этим штрихкодом
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Товар со штрихкодом $code не найден')));
    }
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
      borderRadius: BorderRadius.circular(12),
      child: f == null
          ? Container(
              width: 52,
              height: 52,
              color: AppColors.overlay(0.08),
              child: Icon(Icons.inventory_2_outlined, color: AppColors.textDim),
            )
          : Image.file(f, width: 52, height: 52, fit: BoxFit.cover),
    );
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
          GlassHeader(title: 'Товары'),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => _load(),
                  style: TextStyle(color: AppColors.text),
                  decoration: glassInput('Найти по названию',
                      suffix: Icon(Icons.search, color: AppColors.textDim)),
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
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Text('Товаров пока нет', style: TextStyle(color: AppColors.textDim)))
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final p = _items[i];
                          return GlassCard(
                            radius: 18,
                            padding: EdgeInsets.all(10),
                            onTap: () => _open(p),
                            child: Row(children: [
                              _thumb(p),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p.name,
                                      style: TextStyle(
                                          color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 15)),
                                  SizedBox(height: 2),
                                  Text('${_money(p.salePrice)} / ${p.unit}',
                                      style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                                ]),
                              ),
                              Text('${_num(p.stock)} ${p.unit}',
                                  style: TextStyle(
                                      color: p.stock > 0 ? AppColors.accent : AppColors.warn,
                                      fontWeight: FontWeight.w800)),
                            ]),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}

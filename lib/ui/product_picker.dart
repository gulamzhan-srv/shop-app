// Выбор товара: поиск по названию или сканер штрихкода.
// Используется в поступлении и (позже) в кассе.
//   final p = await pickProduct(context);

import 'package:flutter/material.dart';

import '../screens/barcode_scan_screen.dart';
import '../services/product_service.dart';
import 'glass.dart';

Future<Product?> pickProduct(BuildContext context) {
  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.sheet,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _ProductPicker(),
  );
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker();
  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final _q = TextEditingController();
  List<Product> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ProductService.instance.search(_q.text);
    if (mounted) setState(() => _items = list);
  }

  Future<void> _scan() async {
    final code = await BarcodeScanScreen.scan(context);
    if (code == null || !mounted) return;
    final p = await ProductService.instance.byBarcode(code);
    if (!mounted) return;
    if (p != null) {
      Navigator.of(context).pop(p);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Товар со штрихкодом $code не найден')));
    }
  }

  String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.8;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: h,
        child: Column(children: [
          SizedBox(height: 10),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.overlay(0.24), borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _q,
                  autofocus: true,
                  onChanged: (_) => _load(),
                  style: TextStyle(color: AppColors.text),
                  decoration: glassInput('Найти товар',
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
            child: _items.isEmpty
                ? Center(
                    child: Text('Ничего не найдено', style: TextStyle(color: AppColors.textDim)))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final p = _items[i];
                      return ListTile(
                        onTap: () => Navigator.of(context).pop(p),
                        title: Text(p.name, style: TextStyle(color: AppColors.text)),
                        subtitle: Text(p.barcode ?? '', style: TextStyle(color: AppColors.textDim)),
                        trailing: Text('${_num(p.stock)} ${p.unit}',
                            style: TextStyle(color: AppColors.textDim)),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

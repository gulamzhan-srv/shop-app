// Карточка товара: название, штрихкод (можно сканировать), единица, цена продажи,
// комментарий и несколько фото (камера или галерея, каждое ≤ 200 КБ).

import 'dart:io';

import 'package:flutter/material.dart';

import '../db/database.dart';
import '../services/auth_service.dart';
import '../services/fifo_service.dart';
import '../services/photo_service.dart';
import '../services/product_service.dart';
import '../ui/glass.dart';
import 'barcode_scan_screen.dart';

class ProductEditScreen extends StatefulWidget {
  final Product? product; // null = новый товар
  final String? initialBarcode;
  ProductEditScreen({super.key, this.product, this.initialBarcode});

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final _name = TextEditingController();
  final _barcode = TextEditingController();
  final _price = TextEditingController();
  final _markup = TextEditingController(); // наценка, %
  double? _cost; // последняя цена закупки (из поступлений)
  final _comment = TextEditingController();
  String _unit = 'шт';
  List<String> _photos = [];
  final Map<String, File> _files = {};
  final List<String> _newPhotos = []; // добавлены сейчас (удалим, если не сохранили)
  String? _error;
  bool _busy = false;
  bool _saved = false;

  bool get _canEdit => AuthService.instance.current?.isOwner ?? false;

  @override
  void initState() {
    super.initState();
    final pid = widget.product?.id;
    if (pid != null) {
      AppDatabase.instance.db.then((db) => FifoService.instance.lastCost(db, pid)).then((c) {
        if (!mounted) return;
        setState(() => _cost = c);
        _recalcMarkup();
      });
    }
    final p = widget.product;
    if (p != null) {
      _name.text = p.name;
      _barcode.text = p.barcode ?? '';
      _price.text = p.salePrice == 0 ? '' : _fmt(p.salePrice);
      _comment.text = p.comment ?? '';
      _unit = p.unit;
      ProductService.instance.photosOf(p.id!).then((list) async {
        for (final n in list) {
          _files[n] = await PhotoService.instance.fileFor(n);
        }
        if (mounted) setState(() => _photos = list);
      });
    } else {
      _barcode.text = widget.initialBarcode ?? '';
    }
  }

  @override
  void dispose() {
    // Новые фото, которые не попали в сохранённый товар, удаляем с телефона.
    for (final n in _newPhotos) {
      if (!_saved || !_photos.contains(n)) PhotoService.instance.deleteFile(n);
    }
    super.dispose();
  }

  double? get _priceValue => double.tryParse(_price.text.replaceAll(' ', '').replaceAll(',', '.'));

  /// Цена изменилась → пересчитать наценку.
  void _recalcMarkup() {
    final c = _cost, p = _priceValue;
    if (c == null || c <= 0 || p == null) return setState(() {});
    _markup.text = _fmt(((p - c) / c * 100 * 10).roundToDouble() / 10);
    setState(() {});
  }

  /// Наценка изменилась → пересчитать цену продажи.
  void _applyMarkup() {
    final c = _cost, m = double.tryParse(_markup.text.replaceAll(',', '.'));
    if (c == null || m == null) return;
    _price.text = _fmt((c * (1 + m / 100)).roundToDouble());
    setState(() {});
  }

  /// Окно цены: закупка → наценка → продажа. Видит только хозяин / администратор.
  Widget _priceWindow() {
    final c = _cost, p = _priceValue;
    final diff = (c != null && p != null) ? p - c : null;
    final below = diff != null && diff < 0;
    return GlassCard(
      borderColor: below ? AppColors.danger.withOpacity(0.6) : null,
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Цена и наценка', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
        SizedBox(height: 8),
        if (c == null)
          Text('Цена закупки появится после первого поступления этого товара.',
              style: TextStyle(color: AppColors.textDim, fontSize: 13))
        else ...[
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Закупка (последняя)', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                Text('${_fmt(c)} ₸', style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800)),
              ]),
            ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _markup,
                onChanged: (_) => _applyMarkup(),
                keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
                style: TextStyle(color: AppColors.text),
                decoration: glassInput('Наценка, %'),
              ),
            ),
          ]),
          SizedBox(height: 8),
          Text(
              diff == null
                  ? 'Введите цену продажи'
                  : below
                      ? 'Цена ниже закупки на ${_fmt(-diff)} ₸ — сохранить нельзя'
                      : 'Прибыль с 1 $_unit: ${_fmt(diff)} ₸',
              style: TextStyle(color: below ? AppColors.danger : AppColors.accent, fontWeight: FontWeight.w700)),
        ],
      ]),
    );
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Future<void> _addPhoto() async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.sheet,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(Icons.photo_camera_outlined, color: AppColors.text),
            title: Text('Сфотографировать', style: TextStyle(color: AppColors.text)),
            onTap: () => Navigator.pop(c, true),
          ),
          ListTile(
            leading: Icon(Icons.photo_library_outlined, color: AppColors.text),
            title: Text('Выбрать из галереи', style: TextStyle(color: AppColors.text)),
            onTap: () => Navigator.pop(c, false),
          ),
        ]),
      ),
    );
    if (camera == null) return;
    final name = await PhotoService.instance.pick(fromCamera: camera);
    if (name == null) return;
    _newPhotos.add(name);
    _files[name] = await PhotoService.instance.fileFor(name);
    if (mounted) setState(() => _photos = [..._photos, name]);
  }

  Future<void> _scan() async {
    final code = await BarcodeScanScreen.scan(context);
    if (code != null) setState(() => _barcode.text = code);
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.replaceAll(' ', '').replaceAll(',', '.')) ?? -1;
    if (name.isEmpty) return setState(() => _error = 'Введите название товара');
    if (price < 0) return setState(() => _error = 'Введите цену продажи');
    if (_cost != null && price + 0.001 < _cost!) {
      return setState(() => _error = 'Цена продажи ниже цены закупки (${_fmt(_cost!)} ₸)');
    }
    final code = _barcode.text.trim();
    if (code.isNotEmpty &&
        await ProductService.instance.barcodeTaken(code, exceptId: widget.product?.id)) {
      return setState(() => _error = 'Этот штрихкод уже есть у другого товара');
    }
    setState(() => _busy = true);
    await ProductService.instance.save(Product(
      id: widget.product?.id,
      name: name,
      barcode: code,
      unit: _unit,
      salePrice: price,
      comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
      photos: _photos,
    ));
    _saved = true;
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Удалить товар?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await ProductService.instance.delete(widget.product!);
    if (err != null) return setState(() => _error = err);
    if (mounted) Navigator.of(context).pop(true);
  }

  Widget _photoTile(String n) => Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(_files[n]!, width: 96, height: 96, fit: BoxFit.cover),
        ),
        if (_canEdit)
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () => setState(() => _photos = _photos.where((x) => x != n).toList()),
              child: Container(
                padding: EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: Icon(Icons.close, size: 16, color: Colors.white, semanticLabel: 'Убрать фото'),
              ),
            ),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final isNew = widget.product == null;
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(
            title: isNew ? 'Новый товар' : 'Товар',
            actions: [
              if (!isNew && _canEdit)
                IconButton(
                  onPressed: _delete,
                  icon: Icon(Icons.delete_outline, color: AppColors.danger),
                  tooltip: 'Удалить',
                ),
            ],
          ),
          Expanded(
            child: ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              // ---- Фото ----
              SizedBox(
                height: 96,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final n in _photos)
                    if (_files[n] != null)
                      Padding(padding: EdgeInsets.only(right: 10), child: _photoTile(n)),
                  if (_canEdit)
                    GlassCard(
                      radius: 16,
                      padding: EdgeInsets.zero,
                      onTap: _addPhoto,
                      child: SizedBox(
                        width: 96,
                        height: 96,
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_a_photo_outlined, color: AppColors.text),
                          SizedBox(height: 4),
                          Text('Фото', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                        ]),
                      ),
                    ),
                ]),
              ),
              SizedBox(height: 6),
              Text('Первое фото — главное. Каждое сжимается до 200 КБ.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              SizedBox(height: 16),

              // ---- Поля ----
              TextField(
                controller: _name,
                enabled: _canEdit,
                style: TextStyle(color: AppColors.text),
                decoration: glassInput('Название'),
              ),
              SizedBox(height: 12),
              TextField(
                controller: _barcode,
                enabled: _canEdit,
                style: TextStyle(color: AppColors.text),
                decoration: glassInput('Штрихкод',
                    suffix: _canEdit
                        ? IconButton(
                            onPressed: _scan,
                            icon: Icon(Icons.qr_code_scanner, color: AppColors.accent),
                            tooltip: 'Сканировать',
                          )
                        : null),
              ),
              SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    enabled: _canEdit,
                    onChanged: (_) => _recalcMarkup(),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: AppColors.text),
                    decoration: glassInput('Цена продажи, ₸'),
                  ),
                ),
                SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: DropdownButtonFormField<String>(
                    value: ProductService.units.contains(_unit) ? _unit : 'шт',
                    dropdownColor: AppColors.sheet,
                    style: TextStyle(color: AppColors.text, fontSize: 16),
                    decoration: glassInput('Ед. изм.'),
                    items: [
                      for (final u in ProductService.units) DropdownMenuItem(value: u, child: Text(u)),
                    ],
                    onChanged: _canEdit ? (v) => setState(() => _unit = v ?? 'шт') : null,
                  ),
                ),
              ]),
              if (_canEdit) ...[
                SizedBox(height: 12),
                _priceWindow(),
              ],
              SizedBox(height: 12),
              TextField(
                controller: _comment,
                enabled: _canEdit,
                maxLines: 2,
                style: TextStyle(color: AppColors.text),
                decoration: glassInput('Комментарий'),
              ),
              if (widget.product != null) ...[
                SizedBox(height: 12),
                GlassCard(
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Остаток на складе', style: TextStyle(color: AppColors.textDim)),
                    Text('${_fmt(widget.product!.stock)} ${widget.product!.unit}',
                        style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: AppColors.danger)),
                ),
              SizedBox(height: 20),
              if (_canEdit) AccentButton(label: _busy ? 'Сохраняю…' : 'Сохранить', onPressed: _busy ? null : _save),
            ]),
          ),
        ]),
      ),
    );
  }
}

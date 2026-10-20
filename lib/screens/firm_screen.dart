// Реквизиты фирмы: логотип, название, БИН/ИИН, адрес, телефон, реклама на чеке.
// Эти данные печатаются в шапке чека и накладных.

import 'package:flutter/material.dart';

import '../services/firm_service.dart';
import '../services/print_service.dart';
import '../ui/glass.dart';

class FirmScreen extends StatefulWidget {
  FirmScreen({super.key});
  @override
  State<FirmScreen> createState() => _FirmScreenState();
}

class _FirmScreenState extends State<FirmScreen> {
  final _name = TextEditingController();
  final _bin = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _ad = TextEditingController();
  FirmInfo _f = FirmInfo();
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await FirmService.instance.load();
    _f = f;
    _name.text = f.name;
    _bin.text = f.bin;
    _address.text = f.address;
    _phone.text = f.phone;
    _ad.text = f.ad;
    if (mounted) setState(() => _loaded = true);
  }

  FirmInfo _collect() => FirmInfo(
        name: _name.text,
        bin: _bin.text,
        address: _address.text,
        phone: _phone.text,
        ad: _ad.text,
        logo: _f.logo,
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirmService.instance.save(_collect());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Реквизиты сохранены')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось сохранить: $e')));
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _pickLogo() async {
    try {
      final b = await FirmService.instance.pickLogo();
      if (b != null && mounted) setState(() => _f.logo = b);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось выбрать картинку: $e')));
    }
  }

  Widget _field(String label, TextEditingController c,
          {int lines = 1, TextInputType? type, String? hint}) =>
      Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 2,
          keyboardType: type,
          style: TextStyle(color: AppColors.text),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            filled: true,
            fillColor: AppColors.overlay(0.06),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Реквизиты фирмы'),
          Expanded(
            child: !_loaded
                ? Center(child: CircularProgressIndicator())
                : ListView(padding: EdgeInsets.fromLTRB(16, 4, 16, 30), children: [
                    GlassCard(
                      radius: 20,
                      child: Row(children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.overlay(0.2)),
                          ),
                          child: _f.logo == null
                              ? Icon(Icons.storefront_outlined, size: 38, color: Colors.black38)
                              : Padding(padding: EdgeInsets.all(4), child: Image.memory(_f.logo!, fit: BoxFit.contain)),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Логотип фирмы',
                                style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 16)),
                            Text('печатается в шапке чека и накладных',
                                style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                            SizedBox(height: 8),
                            Wrap(spacing: 8, children: [
                              OutlinedButton.icon(
                                onPressed: _pickLogo,
                                icon: Icon(Icons.image_outlined, size: 18),
                                label: Text(_f.logo == null ? 'Выбрать' : 'Заменить'),
                              ),
                              if (_f.logo != null)
                                TextButton(
                                  onPressed: () => setState(() => _f.logo = null),
                                  child: Text('Убрать'),
                                ),
                            ]),
                          ]),
                        ),
                      ]),
                    ),
                    SizedBox(height: 16),
                    _field('Название фирмы', _name, hint: 'ИП Иванов / Магазин «Авто»'),
                    _field('БИН / ИИН', _bin, type: TextInputType.number),
                    _field('Адрес', _address, lines: 2),
                    _field('Телефон', _phone, type: TextInputType.phone, hint: '+7 7xx xxx xx xx'),
                    _field('Реклама / текст внизу чека', _ad,
                        lines: 3, hint: 'Скидки постоянным клиентам! Работаем с 9:00 до 21:00'),
                    AccentButton(label: _saving ? 'Сохраняю…' : 'Сохранить', onPressed: _saving ? null : _save),
                    SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => PrintService.instance.sampleCheck(context, _collect()),
                      icon: Icon(Icons.receipt_long_outlined),
                      label: Text('Посмотреть пример чека'),
                      style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(46)),
                    ),
                    SizedBox(height: 6),
                    Text('Реквизиты сохраняются в базе и сами появятся на всех телефонах магазина.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ]),
          ),
        ]),
      ),
    );
  }
}

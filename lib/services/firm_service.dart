// Реквизиты фирмы: название, БИН/ИИН, адрес, телефон, реклама на чеке и логотип.
// Хранятся в таблице settings (firm_*), поэтому уходят на все телефоны через Google Диск.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/repo.dart';

class FirmInfo {
  String name;
  String bin;
  String address;
  String phone;
  String ad; // реклама / текст внизу чека
  Uint8List? logo;
  FirmInfo({this.name = '', this.bin = '', this.address = '', this.phone = '', this.ad = '', this.logo});

  /// Строки с реквизитами для шапки документа.
  List<String> get lines => [
        if (bin.isNotEmpty) 'БИН/ИИН: $bin',
        if (address.isNotEmpty) address,
        if (phone.isNotEmpty) 'Тел.: $phone',
      ];
}

class FirmService {
  FirmService._();
  static final FirmService instance = FirmService._();

  static const _keys = ['firm_name', 'firm_bin', 'firm_address', 'firm_phone', 'firm_ad', 'firm_logo'];

  Future<FirmInfo> load() async {
    final rows = await Repo.instance.list('settings', where: "id LIKE 'firm\\_%' ESCAPE '\\'");
    final m = {for (final r in rows) r['id'] as String: ((r['value'] as String?) ?? '')};
    var name = m['firm_name'] ?? '';
    if (name.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      name = prefs.getString('shop_name') ?? 'AVTOMAG GRS SOFT';
    }
    Uint8List? logo;
    final b64 = m['firm_logo'] ?? '';
    if (b64.isNotEmpty) {
      try {
        logo = base64Decode(b64);
      } catch (_) {}
    }
    return FirmInfo(
      name: name,
      bin: m['firm_bin'] ?? '',
      address: m['firm_address'] ?? '',
      phone: m['firm_phone'] ?? '',
      ad: m['firm_ad'] ?? '',
      logo: logo,
    );
  }

  Future<void> _put(String key, String value) =>
      Repo.instance.save('settings', {'id': key, 'value': value}, notify: false);

  Future<void> save(FirmInfo f) async {
    await _put('firm_name', f.name.trim());
    await _put('firm_bin', f.bin.trim());
    await _put('firm_address', f.address.trim());
    await _put('firm_phone', f.phone.trim());
    await _put('firm_ad', f.ad.trim());
    await _put('firm_logo', f.logo == null ? '' : base64Encode(f.logo!));
    final prefs = await SharedPreferences.getInstance();
    if (f.name.trim().isNotEmpty) await prefs.setString('shop_name', f.name.trim());
    Repo.onChange?.call(); // один раз — чтобы синхронизация подхватила всё сразу
  }

  /// Выбрать картинку из галереи и сжать до небольшого логотипа (≈ до 100 КБ).
  Future<Uint8List?> pickLogo() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 800);
    if (x == null) return null;
    final src = await x.readAsBytes();
    var out = await FlutterImageCompress.compressWithList(src,
        minWidth: 360, minHeight: 360, quality: 90, format: CompressFormat.png);
    if (out.lengthInBytes > 120 * 1024) {
      out = await FlutterImageCompress.compressWithList(src,
          minWidth: 360, minHeight: 360, quality: 75, format: CompressFormat.jpeg);
    }
    return out;
  }

  // Ключи нужны, чтобы не потерять их при чистке базы.
  static List<String> get keys => _keys;
}

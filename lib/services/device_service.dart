// Сведения о телефоне для журнала входов: название устройства и IP-адрес.

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

class DeviceService {
  DeviceService._();
  static final DeviceService instance = DeviceService._();

  String? _name;

  /// Например «samsung SM-A515F».
  Future<String> name() async {
    if (_name != null) return _name!;
    try {
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        return _name = '${a.brand} ${a.model}';
      }
    } catch (_) {}
    return _name = 'Телефон';
  }

  /// IP-адрес: сначала внешний (через интернет), если интернета нет — адрес в локальной сети.
  Future<String> ip() async {
    try {
      final r = await http.get(Uri.parse('https://api.ipify.org')).timeout(Duration(seconds: 4));
      if (r.statusCode == 200 && r.body.trim().isNotEmpty) return r.body.trim();
    } catch (_) {}
    try {
      for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in ni.addresses) {
          if (!a.isLoopback) return '${a.address} (локальный)';
        }
      }
    } catch (_) {}
    return 'нет сети';
  }
}

// Курсы валют Национального банка Казахстана (бесплатно, без ключа).
// USD, EUR, RUB — сколько тенге за 1 единицу; UZS — сколько сумов за 1 тенге.
// Последние курсы сохраняются на телефоне, чтобы показывать их без интернета.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Rates {
  final double? usd; // ₸ за 1 $
  final double? eur; // ₸ за 1 €
  final double? rub; // ₸ за 1 ₽
  final double? uzsPerTenge; // сум за 1 ₸
  final DateTime? date;
  Rates({this.usd, this.eur, this.rub, this.uzsPerTenge, this.date});

  bool get isEmpty => usd == null && eur == null && rub == null && uzsPerTenge == null;

  Map<String, Object?> toJson() =>
      {'usd': usd, 'eur': eur, 'rub': rub, 'uzs': uzsPerTenge, 'date': date?.millisecondsSinceEpoch};

  static Rates fromJson(Map<String, dynamic> j) => Rates(
        usd: (j['usd'] as num?)?.toDouble(),
        eur: (j['eur'] as num?)?.toDouble(),
        rub: (j['rub'] as num?)?.toDouble(),
        uzsPerTenge: (j['uzs'] as num?)?.toDouble(),
        date: j['date'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['date'] as int),
      );
}

class RatesService {
  RatesService._();
  static final RatesService instance = RatesService._();

  static const _key = 'rates_cache';

  Future<Rates> cached() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key);
    if (s == null) return Rates();
    try {
      return Rates.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return Rates();
    }
  }

  /// Загрузить свежие курсы. Без интернета — вернёт сохранённые.
  Future<Rates> refresh() async {
    final now = DateTime.now();
    final url = Uri.parse(
        'https://nationalbank.kz/rss/get_rates.cfm?fdate=${DateFormat('dd.MM.yyyy').format(now)}');
    try {
      final res = await http.get(url).timeout(Duration(seconds: 10));
      if (res.statusCode != 200) return cached();
      final xml = utf8.decode(res.bodyBytes, allowMalformed: true);
      final rates = _parse(xml, now);
      if (rates.isEmpty) return cached();
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(rates.toJson()));
      return rates;
    } catch (_) {
      return cached();
    }
  }

  /// В ответе Нацбанка: <item><title>USD</title><description>480.25</description><quant>1</quant>…
  Rates _parse(String xml, DateTime date) {
    final items = RegExp(r'<item>(.*?)</item>', dotAll: true).allMatches(xml);
    final map = <String, double>{}; // код → тенге за 1 единицу
    for (final m in items) {
      final body = m.group(1)!;
      String? tag(String t) => RegExp('<$t>\\s*(.*?)\\s*</$t>', dotAll: true).firstMatch(body)?.group(1);
      final code = tag('title');
      final rate = double.tryParse((tag('description') ?? '').replaceAll(',', '.'));
      final quant = double.tryParse((tag('quant') ?? '1').replaceAll(',', '.')) ?? 1;
      if (code == null || rate == null || quant == 0) continue;
      map[code.trim().toUpperCase()] = rate / quant;
    }
    final uzs = map['UZS'];
    return Rates(
      usd: map['USD'],
      eur: map['EUR'],
      rub: map['RUB'],
      uzsPerTenge: uzs == null || uzs == 0 ? null : 1 / uzs,
      date: date,
    );
  }
}

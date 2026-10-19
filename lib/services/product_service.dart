// Товары: список, поиск по названию и штрихкоду, сохранение, фото, остаток.

import '../db/database.dart';
import '../db/repo.dart';
import 'photo_service.dart';

class Product {
  final String? id;
  final String name;
  final String? barcode;
  final String unit;
  final double salePrice;
  final String? comment;
  final double stock; // остаток (сумма остатков по партиям)
  final List<String> photos; // имена файлов фото

  Product({
    this.id,
    required this.name,
    this.barcode,
    this.unit = 'шт',
    this.salePrice = 0,
    this.comment,
    this.stock = 0,
    this.photos = const [],
  });
}

class ProductService {
  ProductService._();
  static final ProductService instance = ProductService._();

  final _repo = Repo.instance;

  static const units = ['шт', 'кг', 'л', 'м', 'упак', 'компл'];

  /// Список товаров с остатком и первым фото. query — часть названия или штрихкод.
  Future<List<Product>> search([String query = '']) async {
    final db = await AppDatabase.instance.db;
    final q = query.trim();
    final rows = await db.rawQuery('''
      SELECT p.*,
        COALESCE((SELECT SUM(b.qty_left) FROM batch_left b
                  WHERE b.product_id = p.id), 0) AS stock,
        (SELECT ph.file_name FROM product_photos ph
          WHERE ph.product_id = p.id AND ph.deleted = 0
          ORDER BY ph.sort LIMIT 1) AS photo
      FROM products p
      WHERE p.deleted = 0
        AND (? = '' OR p.name LIKE ? COLLATE NOCASE OR p.barcode = ?)
      ORDER BY p.name COLLATE NOCASE
    ''', [q, '%$q%', q]);
    return rows
        .map((r) => Product(
              id: r['id'] as String,
              name: r['name'] as String,
              barcode: r['barcode'] as String?,
              unit: r['unit'] as String,
              salePrice: (r['sale_price'] as num).toDouble(),
              comment: r['comment'] as String?,
              stock: (r['stock'] as num).toDouble(),
              photos: r['photo'] == null ? [] : [r['photo'] as String],
            ))
        .toList();
  }

  /// Найти один товар по штрихкоду (для кассы).
  Future<Product?> byBarcode(String code) async {
    final list = await search(code);
    for (final p in list) {
      if (p.barcode == code) return p;
    }
    return null;
  }

  /// Все фото товара по порядку.
  Future<List<String>> photosOf(String productId) async {
    final rows = await _repo.list('product_photos',
        where: 'product_id = ?', args: [productId], orderBy: 'sort');
    return rows.map((r) => r['file_name'] as String).toList();
  }

  /// Штрихкод уже есть у другого товара?
  Future<bool> barcodeTaken(String code, {String? exceptId}) async {
    final rows = await _repo.list('products',
        where: exceptId == null ? 'barcode = ?' : 'barcode = ? AND id <> ?',
        args: exceptId == null ? [code] : [code, exceptId]);
    return rows.isNotEmpty;
  }

  /// Сохранить товар вместе со списком фото (порядок = порядок в списке).
  Future<String> save(Product p) async {
    final db = await AppDatabase.instance.db;
    late String id;
    final removed = <String>[];
    await db.transaction((txn) async {
      id = await _repo.save(
        'products',
        {
          if (p.id != null) 'id': p.id,
          'name': p.name.trim(),
          'barcode': (p.barcode?.trim().isEmpty ?? true) ? null : p.barcode!.trim(),
          'unit': p.unit,
          'sale_price': p.salePrice,
          'comment': p.comment,
        },
        txn: txn,
      );

      final old = await txn.query('product_photos',
          where: 'product_id = ? AND deleted = 0', whereArgs: [id]);
      final keep = p.photos.toSet();
      for (final r in old) {
        if (!keep.contains(r['file_name'])) {
          await _repo.remove('product_photos', r['id'] as String, txn: txn);
          removed.add(r['file_name'] as String);
        }
      }
      final byName = {for (final r in old) r['file_name'] as String: r};
      for (var i = 0; i < p.photos.length; i++) {
        final name = p.photos[i];
        final existing = byName[name];
        await _repo.save(
          'product_photos',
          {
            if (existing != null) 'id': existing['id'],
            'product_id': id,
            'file_name': name,
            'sort': i,
          },
          txn: txn,
        );
      }
    });
    for (final f in removed) {
      await PhotoService.instance.deleteFile(f);
    }
    return id;
  }

  /// Удалить товар (можно, только если остаток 0).
  Future<String?> delete(Product p) async {
    if (p.id == null) return null;
    if (p.stock > 0) return 'Нельзя удалить: на складе есть остаток';
    await _repo.remove('products', p.id!);
    return null;
  }
}

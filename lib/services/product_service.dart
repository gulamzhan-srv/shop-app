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
  final String? categoryId; // группа (папка) товара
  final double minStock; // минимальный остаток (для автозаявки и подсветки)
  final bool active; // false — товар отключён (не продаётся, скрыт в продаже)

  /// Все штрихкоды товара (у одного товара может быть несколько — через запятую).
  List<String> get barcodes => splitBarcodes(barcode);

  bool get low => active && minStock > 0 && stock <= minStock;

  Product({
    this.categoryId,
    this.minStock = 0,
    this.active = true,
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

/// «123, 456 ,789» → ['123','456','789'] (без пробелов и пустых).
List<String> splitBarcodes(String? s) => (s ?? '')
    .split(RegExp(r'[,;\s]+'))
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

/// Штрихкод со сканера или с клавиатуры: убираем пробелы и переводы строк.
String cleanBarcode(String s) => s.replaceAll(RegExp(r'\s'), '');

class ProductGroup {
  final String id;
  final String name;
  ProductGroup(this.id, this.name);
}

class ProductService {
  ProductService._();
  static final ProductService instance = ProductService._();

  final _repo = Repo.instance;

  static const units = ['шт', 'кг', 'л', 'м', 'упак', 'компл'];

  /// Список товаров с остатком и первым фото. query — часть названия или штрихкода.
  /// categoryId — только эта группа; onlyActive — без отключённых (для продажи).
  Future<List<Product>> search([String query = '', String? categoryId, bool onlyActive = false]) async {
    final db = await AppDatabase.instance.db;
    final q = query.trim();
    final cat = categoryId ?? '';
    final rows = await db.rawQuery('''
      SELECT p.*,
        COALESCE((SELECT SUM(b.qty_left) FROM batch_left b
                  WHERE b.product_id = p.id), 0) AS stock,
        (SELECT ph.file_name FROM product_photos ph
          WHERE ph.product_id = p.id AND ph.deleted = 0
          ORDER BY ph.sort LIMIT 1) AS photo
      FROM products p
      WHERE p.deleted = 0
        AND (? = '' OR p.name LIKE ? COLLATE NOCASE OR p.barcode LIKE ?)
        AND (? = '' OR p.category_id = ?)
        AND (? = 0 OR p.active = 1)
      ORDER BY p.active DESC, p.name COLLATE NOCASE
    ''', [q, '%$q%', '%${cleanBarcode(q)}%', cat, cat, onlyActive ? 1 : 0]);
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
              categoryId: r['category_id'] as String?,
              minStock: ((r['min_stock'] as num?) ?? 0).toDouble(),
              active: ((r['active'] as int?) ?? 1) == 1,
            ))
        .toList();
  }

  // ---------- Группы (папки) товаров ----------

  Future<List<ProductGroup>> categories() async {
    final rows = await _repo.list('categories', orderBy: 'sort, name COLLATE NOCASE');
    return rows.map((r) => ProductGroup(r['id'] as String, r['name'] as String)).toList();
  }

  Future<String> saveCategory(String name, {String? id}) =>
      _repo.save('categories', {if (id != null) 'id': id, 'name': name.trim(), 'sort': 0});

  /// Удалить группу: товары из неё становятся «без группы».
  Future<void> deleteCategory(String id) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('products', where: 'category_id = ? AND deleted = 0', whereArgs: [id]);
    for (final r in rows) {
      await _repo.save('products', {...r, 'category_id': null});
    }
    await _repo.remove('categories', id);
  }

  /// Привязать ещё один штрихкод к товару (например, второй код на упаковке).
  Future<String?> addBarcode(String productId, String code) async {
    final c = cleanBarcode(code);
    if (c.isEmpty) return 'Пустой штрихкод';
    if (await barcodeTaken(c, exceptId: productId)) return 'Штрихкод $c уже есть у другого товара';
    final db = await AppDatabase.instance.db;
    final rows = await db.query('products', where: 'id = ?', whereArgs: [productId]);
    if (rows.isEmpty) return 'Товар не найден';
    final list = splitBarcodes(rows.first['barcode'] as String?);
    if (!list.contains(c)) list.add(c);
    await _repo.save('products', {...rows.first, 'barcode': list.join(',')});
    return null;
  }

  /// Найти один товар по штрихкоду (для кассы). Ищет среди всех штрихкодов товара.
  Future<Product?> byBarcode(String code) async {
    final c = cleanBarcode(code);
    if (c.isEmpty) return null;
    final list = await search(c);
    for (final p in list) {
      if (p.barcodes.contains(c)) return p;
    }
    // Сканер мог вернуть код без ведущего нуля (UPC-A ↔ EAN-13) — пробуем оба варианта.
    final alt = c.length == 12 ? '0$c' : (c.length == 13 && c.startsWith('0') ? c.substring(1) : null);
    if (alt != null) {
      for (final p in await search(alt)) {
        if (p.barcodes.contains(alt)) return p;
      }
    }
    return null;
  }

  /// Все фото товара по порядку.
  Future<List<String>> photosOf(String productId) async {
    final rows = await _repo.list('product_photos',
        where: 'product_id = ?', args: [productId], orderBy: 'sort');
    return rows.map((r) => r['file_name'] as String).toList();
  }

  /// Штрихкод уже есть у другого товара? (проверяются все штрихкоды каждого товара)
  Future<bool> barcodeTaken(String code, {String? exceptId}) async => (await barcodeOwner(code, exceptId: exceptId)) != null;

  /// Название товара, у которого уже есть этот штрихкод (или null).
  Future<String?> barcodeOwner(String code, {String? exceptId}) async {
    final c = cleanBarcode(code);
    if (c.isEmpty) return null;
    final rows = await _repo.list('products',
        where: exceptId == null ? 'barcode LIKE ?' : 'barcode LIKE ? AND id <> ?',
        args: exceptId == null ? ['%$c%'] : ['%$c%', exceptId]);
    for (final r in rows) {
      if (splitBarcodes(r['barcode'] as String?).contains(c)) return r['name'] as String;
    }
    return null;
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
          'barcode': p.barcodes.isEmpty ? null : p.barcodes.join(','),
          'category_id': p.categoryId,
          'min_stock': p.minStock,
          'active': p.active ? 1 : 0,
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

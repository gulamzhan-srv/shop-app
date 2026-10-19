// Документ «Поступление товара».
// Поля: дата, поставщик, комментарий, автор, устройство, строки (товар, кол-во, цена, сумма).
// При сохранении каждая строка создаёт партию (ФИФО) — остаток товара растёт.

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database.dart';
import '../db/repo.dart';
import 'auth_service.dart';
import 'fifo_service.dart';
import 'notification_service.dart';

class ReceiptLine {
  final String productId;
  final String productName;
  final String unit;
  final double qty;
  final double price;
  ReceiptLine({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.qty,
    required this.price,
  });
  double get sum => qty * price;
}

class Receipt {
  final String? id;
  final DateTime date;
  final String? supplierId;
  final String? supplierName;
  final String? comment;
  final String? authorName;
  final String? deviceName;
  final List<ReceiptLine> lines;
  /// Сколько оплачено поставщику при поступлении (null = оплачено полностью).
  final double? paid;
  /// До какого числа оплатить остаток (если взято в долг).
  final DateTime? dueDate;
  Receipt({
    this.paid,
    this.dueDate,
    this.id,
    required this.date,
    this.supplierId,
    this.supplierName,
    this.comment,
    this.authorName,
    this.deviceName,
    this.lines = const [],
  });
  double get total => lines.fold(0, (s, l) => s + l.sum);
  double get paidSum => paid ?? total;
  double get debt => total - paidSum;
}

/// Краткая строка для списка документов.
class ReceiptRow {
  final String id;
  final DateTime date;
  final String supplier;
  final String author;
  final double total;
  final int linesCount;
  ReceiptRow(this.id, this.date, this.supplier, this.author, this.total, this.linesCount);
}

class ReceiptService {
  ReceiptService._();
  static final ReceiptService instance = ReceiptService._();

  final _repo = Repo.instance;
  final _fifo = FifoService.instance;
  String? _deviceName;

  Future<String> deviceName() async {
    if (_deviceName != null) return _deviceName!;
    try {
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        return _deviceName = '${a.brand} ${a.model}';
      }
    } catch (_) {}
    return _deviceName = 'Телефон';
  }

  Future<List<ReceiptRow>> list() async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT r.id, r.doc_date, r.total,
        COALESCE(s.name, 'Без поставщика') AS supplier,
        COALESCE(e.name, '') AS author,
        (SELECT COUNT(*) FROM receipt_lines l WHERE l.receipt_id = r.id AND l.deleted = 0) AS cnt
      FROM receipts r
      LEFT JOIN suppliers s ON s.id = r.supplier_id
      LEFT JOIN employees e ON e.id = r.author_id
      WHERE r.deleted = 0
      ORDER BY r.doc_date DESC
    ''');
    return rows
        .map((r) => ReceiptRow(
              r['id'] as String,
              DateTime.fromMillisecondsSinceEpoch(r['doc_date'] as int),
              r['supplier'] as String,
              r['author'] as String,
              (r['total'] as num).toDouble(),
              r['cnt'] as int,
            ))
        .toList();
  }

  Future<Receipt> load(String id) async {
    final db = await AppDatabase.instance.db;
    final h = (await db.rawQuery('''
      SELECT r.*, s.name AS supplier_name, e.name AS author_name
      FROM receipts r
      LEFT JOIN suppliers s ON s.id = r.supplier_id
      LEFT JOIN employees e ON e.id = r.author_id
      WHERE r.id = ?''', [id])).first;
    final lines = await db.rawQuery('''
      SELECT l.*, p.name AS product_name, p.unit
      FROM receipt_lines l JOIN products p ON p.id = l.product_id
      WHERE l.receipt_id = ? AND l.deleted = 0
      ORDER BY l.rowid''', [id]);
    return Receipt(
      id: id,
      date: DateTime.fromMillisecondsSinceEpoch(h['doc_date'] as int),
      supplierId: h['supplier_id'] as String?,
      supplierName: h['supplier_name'] as String?,
      comment: h['comment'] as String?,
      authorName: h['author_name'] as String?,
      deviceName: h['device_name'] as String?,
      paid: (h['paid'] as num?)?.toDouble(),
      dueDate: h['due_date'] == null ? null : DateTime.fromMillisecondsSinceEpoch(h['due_date'] as int),
      lines: lines
          .map((l) => ReceiptLine(
                productId: l['product_id'] as String,
                productName: l['product_name'] as String,
                unit: l['unit'] as String,
                qty: (l['qty'] as num).toDouble(),
                price: (l['price'] as num).toDouble(),
              ))
          .toList(),
    );
  }

  /// Можно ли менять документ: да, если из его партий ещё ничего не продано.
  Future<bool> canChange(String receiptId) async {
    final db = await AppDatabase.instance.db;
    final r = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM sale_line_batches x
      JOIN batches b ON b.id = x.batch_id
      JOIN receipt_lines l ON l.id = b.receipt_line_id
      WHERE l.receipt_id = ? AND b.deleted = 0 AND x.deleted = 0''', [receiptId]);
    return (r.first['c'] as int) == 0;
  }

  /// Сохранить (провести) поступление. Возвращает текст ошибки или null.
  Future<String?> save(Receipt rc) async {
    if (rc.lines.isEmpty) return 'Добавьте хотя бы один товар';
    for (final l in rc.lines) {
      if (l.qty <= 0) return 'Количество у «${l.productName}» должно быть больше 0';
      if (l.price < 0) return 'Цена у «${l.productName}» не может быть меньше 0';
    }
    if (rc.paidSum < 0) return 'Оплаченная сумма не может быть меньше 0';
    if (rc.paidSum > rc.total + 0.5) return 'Оплачено больше, чем сумма поступления';
    if (rc.debt > 0.5 && rc.supplierId == null) return 'Чтобы взять товар в долг, выберите поставщика';
    if (rc.id != null && !await canChange(rc.id!)) {
      return 'Товар из этого поступления уже продавался — документ менять нельзя';
    }
    final author = AuthService.instance.current;
    if (author == null) return 'Войдите по PIN-коду';
    final device = await deviceName();
    final db = await AppDatabase.instance.db;

    await db.transaction((txn) async {
      if (rc.id != null) await _removeLines(txn, rc.id!);
      final ts = rc.date.millisecondsSinceEpoch;
      final id = await _repo.save(
        'receipts',
        {
          if (rc.id != null) 'id': rc.id,
          'doc_date': ts,
          'supplier_id': rc.supplierId,
          'comment': (rc.comment?.trim().isEmpty ?? true) ? null : rc.comment!.trim(),
          'author_id': author.id,
          'device_name': device,
          'total': rc.total,
          'paid': rc.paidSum,
          'due_date': rc.debt > 0.5 ? rc.dueDate?.millisecondsSinceEpoch : null,
        },
        txn: txn,
      );
      for (final l in rc.lines) {
        final lineId = await _repo.save(
          'receipt_lines',
          {
            'receipt_id': id,
            'product_id': l.productId,
            'qty': l.qty,
            'price': l.price,
            'sum': l.sum,
          },
          txn: txn,
        );
        await _fifo.addBatch(txn,
            productId: l.productId,
            receiptLineId: lineId,
            receivedAt: ts,
            qty: l.qty,
            costPrice: l.price);
      }
    });
    // Напоминания о сроке оплаты поставщику.
    NotificationService.instance.rescheduleDebts().catchError((_) {});
    return null;
  }

  /// Удалить поступление (только если ничего не продано).
  Future<String?> delete(String id) async {
    if (!await canChange(id)) {
      return 'Товар из этого поступления уже продавался — удалить нельзя';
    }
    final db = await AppDatabase.instance.db;
    await db.transaction((txn) async {
      await _removeLines(txn, id);
      await _repo.remove('receipts', id, txn: txn);
    });
    return null;
  }

  Future<void> _removeLines(Transaction txn, String receiptId) async {
    final lines = await txn.query('receipt_lines',
        where: 'receipt_id = ? AND deleted = 0', whereArgs: [receiptId]);
    for (final l in lines) {
      final batches = await txn.query('batches',
          where: 'receipt_line_id = ? AND deleted = 0', whereArgs: [l['id']]);
      for (final b in batches) {
        await _repo.remove('batches', b['id'] as String, txn: txn);
      }
      await _repo.remove('receipt_lines', l['id'] as String, txn: txn);
    }
  }
}

// Продажа в кассе.
// Всё делается одной транзакцией: либо продажа записалась целиком, либо ничего.
//  1. По каждой строке товар списывается из партий по ФИФО.
//  2. Себестоимость строки = сумма (кол-во × цена партии) по списанным партиям.
//  3. Прибыль продажи = итог − себестоимость.

import '../db/database.dart';
import '../db/repo.dart';
import 'auth_service.dart';
import 'fifo_service.dart';
import 'notification_service.dart';
import 'shift_service.dart';

enum Payment { cash, kaspi, mixed, debt }

String paymentCode(Payment p) => switch (p) {
      Payment.cash => 'cash',
      Payment.kaspi => 'kaspi',
      Payment.mixed => 'mixed',
      Payment.debt => 'debt',
    };

/// Название способа оплаты для экрана.
String paymentName(String code) => switch (code) {
      'cash' => 'Наличные',
      'kaspi' => 'Kaspi',
      'mixed' => 'Наличные + Kaspi',
      _ => 'В долг',
    };

class CartLine {
  final String productId;
  final String name;
  final String unit;
  final String? photo;
  final double stock; // остаток на складе в момент добавления
  double qty;
  double price;
  CartLine({
    required this.productId,
    required this.name,
    required this.unit,
    this.photo,
    this.stock = 0,
    this.qty = 1,
    required this.price,
  });
  double get sum => qty * price;
}

class SaleResult {
  final String? saleId;
  final String? error;
  final double total;
  final double profit;
  SaleResult({this.saleId, this.error, this.total = 0, this.profit = 0});
}

class SaleService {
  SaleService._();
  static final SaleService instance = SaleService._();

  final _repo = Repo.instance;
  final _fifo = FifoService.instance;

  Future<SaleResult> sell({
    required List<CartLine> lines,
    required Payment payment,
    String? customerId,
    DateTime? dueDate,
    String? comment,
    double cashPart = 0, // для смешанной оплаты: сколько наличными
  }) async {
    if (lines.isEmpty) return SaleResult(error: 'Корзина пустая');
    for (final l in lines) {
      if (l.qty <= 0) return SaleResult(error: 'Количество у «${l.name}» должно быть больше 0');
    }
    if (payment == Payment.debt) {
      if (customerId == null) return SaleResult(error: 'Выберите покупателя для долга');
      if (dueDate == null) return SaleResult(error: 'Укажите дату оплаты долга');
    }
    final shift = await ShiftService.instance.current();
    if (shift == null) return SaleResult(error: 'Сначала откройте смену');
    final user = AuthService.instance.current;
    if (user == null) return SaleResult(error: 'Войдите по PIN-коду');

    final total = lines.fold<double>(0, (s, l) => s + l.sum);
    double paidCash = 0, paidKaspi = 0;
    switch (payment) {
      case Payment.cash:
        paidCash = total;
      case Payment.kaspi:
        paidKaspi = total;
      case Payment.mixed:
        if (cashPart <= 0 || cashPart >= total) {
          return SaleResult(error: 'Смешанная оплата: наличные должны быть больше 0 и меньше итога');
        }
        paidCash = cashPart;
        paidKaspi = total - cashPart;
      case Payment.debt:
        break;
    }
    final db = await AppDatabase.instance.db;
    try {
      late String saleId;
      double costTotal = 0;
      await db.transaction((txn) async {
        saleId = _repo.newId();
        // Сначала строки (списание по ФИФО), потом шапка с итогами.
        for (final l in lines) {
          final List<BatchTake> takes;
          try {
            takes = await _fifo.consume(txn, l.productId, l.qty);
          } on NotEnoughStock catch (e) {
            // ошибка внутри транзакции → всё, что уже списали, откатывается
            throw _StockError(l.name, e.available);
          }
          final cost = takes.fold<double>(0, (s, t) => s + t.cost);
          // Нельзя продать ниже себестоимости (цены закупки по ФИФО).
          if (l.sum + 0.01 < cost) throw _BelowCost(l.name, cost / l.qty);
          costTotal += cost;
          final lineId = await _repo.save(
            'sale_lines',
            {
              'sale_id': saleId,
              'product_id': l.productId,
              'qty': l.qty,
              'price': l.price,
              'sum': l.sum,
              'cost': cost,
            },
            txn: txn,
          );
          for (final t in takes) {
            await _repo.save(
              'sale_line_batches',
              {'sale_line_id': lineId, 'batch_id': t.batchId, 'qty': t.qty, 'cost_price': t.costPrice},
              txn: txn,
            );
          }
        }
        await _repo.save(
          'sales',
          {
            'id': saleId,
            'sale_date': _repo.now(),
            'shift_id': shift.id,
            'cashier_id': user.id,
            'payment': paymentCode(payment),
            'customer_id': payment == Payment.debt ? customerId : null,
            'due_date': payment == Payment.debt ? dueDate!.millisecondsSinceEpoch : null,
            'comment': (comment?.trim().isEmpty ?? true) ? null : comment!.trim(),
            'total': total,
            'cost_total': costTotal,
            'paid_cash': paidCash,
            'paid_kaspi': paidKaspi,
          },
          txn: txn,
        );
      });
      if (payment == Payment.debt) await NotificationService.instance.rescheduleDebts();
      return SaleResult(saleId: saleId, total: total, profit: total - costTotal);
    } on _StockError catch (e) {
      return SaleResult(error: 'Не хватает «${e.name}»: на складе ${_q(e.available)}');
    } on _BelowCost catch (e) {
      return SaleResult(
          error: 'Цена «${e.name}» ниже закупочной (${e.cost.round()} ₸). Попросите хозяина изменить цену.');
    }
  }

  String _q(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// Продажи текущей смены (для списка в кассе).
  Future<List<Map<String, Object?>>> shiftSales(String shiftId) async {
    final db = await AppDatabase.instance.db;
    return db.rawQuery('''
      SELECT s.id, s.sale_date, s.payment, s.total, s.cost_total, c.name AS customer
      FROM sales s LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.shift_id = ? AND s.deleted = 0
      ORDER BY s.sale_date DESC''', [shiftId]);
  }
}

class _BelowCost implements Exception {
  final String name;
  final double cost;
  const _BelowCost(this.name, this.cost);
}

class _StockError implements Exception {
  final String name;
  final double available;
  const _StockError(this.name, this.available);
}

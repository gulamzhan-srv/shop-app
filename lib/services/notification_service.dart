// Уведомления о долгах.
//
// По каждой неоплаченной продаже в долг ставятся 3 уведомления — в 10:00
// за 3, 2 и 1 день до даты оплаты. Когда долг оплачен, при следующем
// пересчёте его уведомления исчезают. Пересчёт делается при запуске,
// после продажи, оплаты, возврата и синхронизации — поэтому уведомления
// приходят и хозяину, и кассиру (на каждом телефоне свои).

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../db/database.dart';
import 'auth_service.dart';
import 'supplier_debt_service.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'debts',
    'Долги покупателей',
    channelDescription: 'Напоминания о сроке оплаты долга',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Almaty'));
    }
    await _plugin.initialize(InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  static NotificationDetails _sales(String text) => NotificationDetails(
        android: AndroidNotificationDetails(
          'sales',
          'Продажи',
          channelDescription: 'Продажи кассиров на других телефонах',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(text),
        ),
      );

  /// Уведомить хозяина / администратора о новых продажах с других телефонов.
  /// Показывается только на телефоне, где последним входил хозяин или администратор,
  /// и только по свежим продажам (не при восстановлении старой базы).
  Future<void> notifySales(List<String> saleIds) async {
    try {
      final me = AuthService.instance.current;
      final p = await SharedPreferences.getInstance();
      final manager = me?.isManager ?? (p.getBool('last_manager') ?? false);
      if (!manager || saleIds.isEmpty) return;
      if (!_ready) await init();
      final db = await AppDatabase.instance.db;
      final since = DateTime.now().subtract(Duration(hours: 12)).millisecondsSinceEpoch;
      final fresh = <Map<String, Object?>>[];
      for (final id in saleIds) {
        final r = await db.rawQuery('''
          SELECT s.id, s.total, s.payment, s.sale_date, COALESCE(e.name, '') AS cashier
          FROM sales s LEFT JOIN employees e ON e.id = s.cashier_id
          WHERE s.id = ? AND s.deleted = 0 AND s.opening = 0 AND s.sale_date >= ?''', [id, since]);
        if (r.isNotEmpty) fresh.add(r.first);
      }
      if (fresh.isEmpty) return;
      if (fresh.length > 5) {
        final sum = fresh.fold<double>(0, (a, r) => a + (r['total'] as num).toDouble());
        await _plugin.show(0x7FFFFFF0, 'Новые продажи: ${fresh.length}',
            'На сумму ${sum.round()} ₸', _sales('На сумму ${sum.round()} ₸'));
        return;
      }
      for (final r in fresh) {
        final lines = await db.rawQuery('''
          SELECT p.name, l.qty, l.sum FROM sale_lines l JOIN products p ON p.id = l.product_id
          WHERE l.sale_id = ? AND l.deleted = 0''', [r['id']]);
        String q(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
        final body = lines.isEmpty
            ? 'Чек на ${(r['total'] as num).round()} ₸'
            : lines.map((l) => '${l['name']} × ${q(l['qty'] as num)} = ${(l['sum'] as num).round()} ₸').join('\n');
        final pay = switch (r['payment']) {
          'cash' => 'наличные',
          'kaspi' => 'Kaspi',
          'mixed' => 'наличные + Kaspi',
          'debt' => 'в долг',
          _ => '',
        };
        await _plugin.show(
          ((r['id'] as String).hashCode & 0x0FFFFFFF) | 0x10000000,
          'Продажа ${(r['total'] as num).round()} ₸ · ${r['cashier']}',
          '$body\nОплата: $pay',
          _sales('$body\nОплата: $pay'),
        );
      }
    } catch (_) {}
  }

  /// Пересоздать все напоминания о долгах.
  Future<void> rescheduleDebts() async {
    if (!_ready) await init();
    // Снимаем только запланированные напоминания (уведомления о продажах не трогаем).
    try {
      for (final r in await _plugin.pendingNotificationRequests()) {
        await _plugin.cancel(r.id);
      }
    } catch (_) {
      // На некоторых сборках список запланированных недоступен — снимаем все разом.
      await _plugin.cancelAll();
    }

    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT s.id, s.due_date, c.name,
        s.total
        - COALESCE((SELECT SUM(p.amount) FROM debt_payments p WHERE p.sale_id = s.id AND p.deleted = 0), 0)
        - COALESCE((SELECT SUM(r.refund) FROM returns r WHERE r.sale_id = s.id AND r.deleted = 0
                    AND r.status = 'approved' AND r.refund_payment = 'debt'), 0) AS remaining
      FROM sales s LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.deleted = 0 AND s.payment = 'debt' AND s.due_date IS NOT NULL''');

    final now = tz.TZDateTime.now(tz.local);
    for (final r in rows) {
      final remaining = (r['remaining'] as num).toDouble();
      if (remaining < 0.5) continue; // оплачено — уведомлений нет
      final due = DateTime.fromMillisecondsSinceEpoch(r['due_date'] as int);
      final name = (r['name'] as String?) ?? 'Покупатель';
      final dueText = '${due.day.toString().padLeft(2, '0')}.${due.month.toString().padLeft(2, '0')}';
      for (var daysBefore = 3; daysBefore >= 1; daysBefore--) {
        final d = due.subtract(Duration(days: daysBefore));
        final at = tz.TZDateTime(tz.local, d.year, d.month, d.day, 10);
        if (!at.isAfter(now)) continue;
        final id = ((r['id'] as String).hashCode & 0x0FFFFFFF) * 4 + daysBefore;
        await _plugin.zonedSchedule(
          id,
          'Срок долга: $name',
          'Должен ${remaining.round()} ₸, оплатить до $dueText'
              '${daysBefore == 1 ? ' (завтра)' : ' (через $daysBefore дн.)'}',
          at,
          NotificationDetails(android: _channel),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }

    // Долги перед поставщиками: тоже за 3, 2 и 1 день до срока.
    try {
      for (final s in await SupplierDebtService.instance.bySupplier(onlyOwing: true)) {
        for (final d in await SupplierDebtService.instance.docsOf(s.supplierId)) {
          if (d.remaining < 0.5 || d.due == null) continue;
          final due = d.due!;
          final dueText = '${due.day.toString().padLeft(2, '0')}.${due.month.toString().padLeft(2, '0')}';
          for (var daysBefore = 3; daysBefore >= 1; daysBefore--) {
            final x = due.subtract(Duration(days: daysBefore));
            final at = tz.TZDateTime(tz.local, x.year, x.month, x.day, 10);
            if (!at.isAfter(now)) continue;
            final id = (('sup${d.receiptId}').hashCode & 0x0FFFFFFF) * 4 + daysBefore;
            await _plugin.zonedSchedule(
              id,
              'Долг поставщику: ${s.name}',
              'Оплатить ${d.remaining.round()} ₸ до $dueText'
                  '${daysBefore == 1 ? ' (завтра)' : ' (через $daysBefore дн.)'}',
              at,
              NotificationDetails(android: _channel),
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
            );
          }
        }
      }
    } catch (_) {}
  }
}

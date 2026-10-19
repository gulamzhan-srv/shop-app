// Уведомления о долгах.
//
// По каждой неоплаченной продаже в долг ставятся 3 уведомления — в 10:00
// за 3, 2 и 1 день до даты оплаты. Когда долг оплачен, при следующем
// пересчёте его уведомления исчезают. Пересчёт делается при запуске,
// после продажи, оплаты, возврата и синхронизации — поэтому уведомления
// приходят и хозяину, и кассиру (на каждом телефоне свои).

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../db/database.dart';
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

  /// Пересоздать все напоминания о долгах.
  Future<void> rescheduleDebts() async {
    if (!_ready) await init();
    await _plugin.cancelAll();

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

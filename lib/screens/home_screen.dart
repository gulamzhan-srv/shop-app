// Главная: крупная дата, день недели, месяц и год; кнопки «Обновить», «Блокировать», «Закрыть»;
// курсы валют; у хозяина — аналитика; ниже — разделы приложения.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/auth_service.dart';
import '../services/rates_service.dart';
import '../services/sync_service.dart';
import '../ui/glass.dart';
import 'analytics_view.dart';
import 'checks_screen.dart';
import 'debts_screen.dart';
import 'employees_screen.dart';
import 'journal_screen.dart';
import 'kassa_screen.dart';
import 'pin_screen.dart';
import 'products_screen.dart';
import 'receipts_screen.dart';
import 'reports_screen.dart';
import 'returns_screen.dart';
import 'supplier_debts_screen.dart';
import 'sync_screen.dart';

class HomeScreen extends StatefulWidget {
  HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _analytics = GlobalKey<AnalyticsViewState>();
  Rates _rates = Rates();
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RatesService.instance.cached().then((r) {
      if (mounted) setState(() => _rates = r);
    });
    _refresh(silent: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Вернулись в приложение — подтягиваем изменения с других телефонов.
    if (state == AppLifecycleState.resumed) _refresh(silent: true);
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final rates = await RatesService.instance.refresh();
    final syncErr = await SyncService.instance.syncNow();
    if (!mounted) return;
    setState(() {
      _rates = rates;
      _refreshing = false;
    });
    await _analytics.currentState?.reload();
    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(syncErr == null ? 'Обновлено' : 'Обновлено. Google Диск: $syncErr')));
    }
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Future<void> _go(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _analytics.currentState?.reload();
  }

  Widget _iconBtn(IconData icon, String label, VoidCallback onTap, {bool busy = false}) => Padding(
        padding: EdgeInsets.only(left: 8),
        child: Tooltip(
          message: label,
          child: GlassCard(
            radius: 14,
            padding: EdgeInsets.all(8),
            onTap: onTap,
            child: busy
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, color: AppColors.text, size: 20, semanticLabel: label),
          ),
        ),
      );

  Widget _rate(String code, double? v, String unit, {int digits = 2}) => Expanded(
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: AppColors.overlay(0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            Text(code, style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 13)),
            SizedBox(height: 1),
            FittedBox(
              child: Text(v == null ? '—' : v.toStringAsFixed(digits).replaceAll('.', ','),
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 14)),
            ),
            Text(unit, style: TextStyle(color: AppColors.textDim, fontSize: 10)),
          ]),
        ),
      );

  Future<void> _pickTheme() async {
    final chosen = await showModalBottomSheet<AppPalette>(
      context: context,
      backgroundColor: AppColors.sheet,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: EdgeInsets.all(14),
            child: Text('Тема оформления',
                style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          for (final p in AppThemes.all)
            ListTile(
              onTap: () => Navigator.pop(c, p),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: p.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: p.accent, width: 3),
                ),
              ),
              title: Text(p.name, style: TextStyle(color: AppColors.text)),
              trailing: AppThemes.current.value.id == p.id
                  ? Icon(Icons.check_circle, color: AppColors.accent)
                  : null,
            ),
          SizedBox(height: 8),
        ]),
      ),
    );
    if (chosen != null && mounted) await AppThemes.set(context, chosen);
  }

  Widget _menuAction(IconData icon, String title, VoidCallback onTap) => GlassCard(
        radius: 20,
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        onTap: onTap,
        child: Column(children: [
          Icon(icon, color: AppColors.accent, size: 22),
          SizedBox(height: 4),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _menu(IconData icon, String title, Widget screen) => GlassCard(
        radius: 20,
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        onTap: () => _go(screen),
        child: Column(children: [
          Icon(icon, color: AppColors.accent, size: 22),
          SizedBox(height: 4),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.current;
    final owner = user?.isOwner ?? false;
    final now = DateTime.now();
    final weekday = _cap(DateFormat('EEEE', 'ru').format(now));
    final monthYear = _cap(DateFormat('LLLL yyyy', 'ru').format(now));

    final menu = [
      _menu(Icons.point_of_sale_outlined, 'Касса', KassaScreen()),
      _menu(Icons.inventory_2_outlined, 'Товары', ProductsScreen()),
      _menu(Icons.local_shipping_outlined, 'Поступления', ReceiptsScreen()),
      _menu(Icons.people_alt_outlined, 'Долги', DebtsScreen()),
      if (owner) _menu(Icons.request_quote_outlined, 'Долги поставщикам', SupplierDebtsScreen()),
      _menu(Icons.assignment_return_outlined, 'Возвраты', ReturnsScreen()),
      _menu(Icons.receipt_long_outlined, 'Чеки', ChecksScreen()),
      if (owner) _menu(Icons.bar_chart_outlined, 'Отчёты', ReportsScreen()),
      if (owner) _menu(Icons.badge_outlined, 'Сотрудники', EmployeesScreen()),
      // Google Диск и аккаунт хранения видят только хозяин и администратор.
      if (owner) _menu(Icons.cloud_sync_outlined, 'Google Диск', SyncScreen()),
      if (user?.isAdmin ?? false) _menu(Icons.manage_search_outlined, 'Журнал', JournalScreen()),
      _menuAction(Icons.palette_outlined, 'Тема', _pickTheme),
    ];

    return Scaffold(
      body: GlassBackground(
        child: RefreshIndicator(
          onRefresh: () => _refresh(),
          child: ListView(padding: EdgeInsets.fromLTRB(16, 4, 16, 20), children: [
            // ---- Дата и кнопки ----
            Row(children: [
              Text('${now.day}',
                  style: TextStyle(color: AppColors.text, fontSize: 44, fontWeight: FontWeight.w800, height: 1)),
              SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(weekday,
                      style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(monthYear, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                ]),
              ),
              _iconBtn(Icons.refresh, 'Обновить', () => _refresh(), busy: _refreshing),
              _iconBtn(Icons.lock_outline, 'Блокировать', () {
                AuthService.instance.lock();
                Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PinScreen()));
              }),
              _iconBtn(Icons.close, 'Закрыть', () => SystemNavigator.pop()),
            ]),
            SizedBox(height: 10),

            // ---- Курсы валют ----
            GlassCard(
              radius: 22,
              padding: EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    'Курс валют · Нацбанк РК'
                    '${_rates.date == null ? '' : ' · ${DateFormat('dd.MM').format(_rates.date!)}'}',
                    style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                SizedBox(height: 6),
                Row(children: [
                  _rate('USD', _rates.usd, '₸ за 1 \$'),
                  SizedBox(width: 8),
                  _rate('EUR', _rates.eur, '₸ за 1 €'),
                  SizedBox(width: 8),
                  _rate('RUB', _rates.rub, '₸ за 1 ₽'),
                  SizedBox(width: 8),
                  _rate('UZS', _rates.uzsPerTenge, 'сум за 1 ₸', digits: 1),
                ]),
              ]),
            ),
            SizedBox(height: 8),

            Text('${user?.name ?? ''} · ${user == null ? '' : roleName(user.role).toLowerCase()}',
                style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            SizedBox(height: 10),

            // ---- Аналитика (только хозяин) ----
            if (owner) ...[
              AnalyticsView(key: _analytics),
              SizedBox(height: 10),
            ],

            // ---- Разделы ----
            LayoutBuilder(builder: (c, box) {
              final w = (box.maxWidth - 20) / 3;
              return Wrap(spacing: 10, runSpacing: 10, children: [for (final m in menu) SizedBox(width: w, child: m)]);
            }),
          ]),
        ),
      ),
    );
  }
}

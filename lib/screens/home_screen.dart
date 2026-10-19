// Главный экран с нижним меню из разделов:
//   Главная   — дата, кнопки «Обновить / Блокировать / Закрыть», курсы валют, быстрые действия;
//   Продажа   — продажа, касса (смена), долги клиентов, чеки, возвраты;
//   Закупки   — товары, поступления, долги поставщикам, начальные остатки;
//   Отчёты    — дашборд (KPI, столбики, склад), подробные отчёты, автозаявка, анализ товаров
//               (только хозяин / администратор);
//   Настройки — Google Диск, сменить PIN, тема, сотрудники, журнал.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/auth_service.dart';
import '../services/rates_service.dart';
import '../services/sync_service.dart';
import '../ui/glass.dart';
import 'analytics_view.dart';
import 'change_pin_screen.dart';
import 'checks_screen.dart';
import 'debts_screen.dart';
import 'employees_screen.dart';
import 'insights_screen.dart';
import 'journal_screen.dart';
import 'kassa_screen.dart';
import 'opening_screen.dart';
import 'pin_screen.dart';
import 'products_screen.dart';
import 'receipts_screen.dart';
import 'reports_screen.dart';
import 'returns_screen.dart';
import 'sale_screen.dart';
import 'supplier_debts_screen.dart';
import 'sync_screen.dart' show SyncScreen, SyncProgressBar;

class HomeScreen extends StatefulWidget {
  HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _Tab {
  final IconData icon;
  final String label;
  final Widget Function() page;
  _Tab(this.icon, this.label, this.page);
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _analytics = GlobalKey<AnalyticsViewState>();
  Rates _rates = Rates();
  bool _refreshing = false;
  int _tab = 0;

  bool get _manager => AuthService.instance.current?.isManager ?? false;
  bool get _admin => AuthService.instance.current?.isAdmin ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SyncService.instance.dataChanged.addListener(_onRemoteData);
    RatesService.instance.cached().then((r) {
      if (mounted) setState(() => _rates = r);
    });
    _refresh(silent: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SyncService.instance.dataChanged.removeListener(_onRemoteData);
    super.dispose();
  }

  /// С других телефонов пришли изменения — сразу обновляем цифры на экране.
  void _onRemoteData() {
    _analytics.currentState?.reload();
    if (mounted) setState(() {});
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
    if (mounted) setState(() {});
  }

  // ---------------- Оформление ----------------

  Widget _iconBtn(IconData icon, String label, VoidCallback onTap, {bool busy = false}) => Padding(
        padding: EdgeInsets.only(left: 6),
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
          decoration: BoxDecoration(color: AppColors.overlay(0.06), borderRadius: BorderRadius.circular(8)),
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

  /// Плитка раздела — у всех одинаковая высота.
  Widget _tile(IconData icon, String title, VoidCallback onTap, {String? hint}) => GlassCard(
        radius: 20,
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: AppColors.accent, size: 24),
          SizedBox(height: 5),
          Text(title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700, height: 1.15)),
          if (hint != null)
            Text(hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textDim, fontSize: 10.5)),
        ]),
      );

  Widget _grid(List<Widget> tiles) => LayoutBuilder(builder: (c, box) {
        final w = (box.maxWidth - 16) / 3;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in tiles) SizedBox(width: w, height: 84, child: t),
        ]);
      });

  Widget _page(String title, List<Widget> children, {List<Widget> actions = const []}) => ListView(
        padding: EdgeInsets.fromLTRB(16, 6, 16, 20),
        children: [
          Row(children: [
            Expanded(
              child: Text(title,
                  style: TextStyle(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            ...actions,
          ]),
          SizedBox(height: 10),
          ...children,
        ],
      );

  Widget _section(String t) => Padding(
        padding: EdgeInsets.fromLTRB(2, 12, 0, 6),
        child: Text(t, style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.w700)),
      );

  // ---------------- Разделы ----------------

  Widget _homePage() {
    final user = AuthService.instance.current;
    final now = DateTime.now();
    final weekday = _cap(DateFormat('EEEE', 'ru').format(now));
    final monthYear = _cap(DateFormat('LLLL yyyy', 'ru').format(now));
    return RefreshIndicator(
      onRefresh: () => _refresh(),
      child: ListView(padding: EdgeInsets.fromLTRB(16, 4, 16, 20), children: [
        Row(children: [
          Text('${now.day}',
              style: TextStyle(color: AppColors.text, fontSize: 44, fontWeight: FontWeight.w800, height: 1)),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(weekday, style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
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
        SyncProgressBar(),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('${user?.name ?? ''} · ${user == null ? '' : roleName(user.role).toLowerCase()}',
              style: TextStyle(color: AppColors.textDim, fontSize: 13)),
        ),
        // Хозяин и администратор: сразу дашборд — продажи, KPI-блоки, сравнение с прошлым периодом.
        if (_manager) ...[
          AnalyticsView(key: _analytics),
          SizedBox(height: 4),
        ],
        _section('Быстрые действия'),
        _grid([
          _tile(Icons.shopping_cart_outlined, 'Продажа', () => _go(SaleScreen())),
          _tile(Icons.point_of_sale_outlined, 'Касса', () => _go(KassaScreen())),
          _tile(Icons.inventory_2_outlined, 'Товары', () => _go(ProductsScreen())),
          _tile(Icons.people_alt_outlined, 'Долги клиентов', () => _go(DebtsScreen())),
          _tile(Icons.local_shipping_outlined, 'Поступления', () => _go(ReceiptsScreen())),
          if (_manager) _tile(Icons.insights_outlined, 'Отчёты', () => setState(() => _tab = 3)),
        ]),
      ]),
    );
  }

  Widget _salesPage() => _page('Продажа', [
        _grid([
          _tile(Icons.shopping_cart_outlined, 'Продажа', () => _go(SaleScreen()), hint: 'пробить чек'),
          _tile(Icons.point_of_sale_outlined, 'Касса', () => _go(KassaScreen()), hint: 'открыть / закрыть'),
          _tile(Icons.people_alt_outlined, 'Долги клиентов', () => _go(DebtsScreen())),
          _tile(Icons.receipt_long_outlined, 'Чеки', () => _go(ChecksScreen())),
          _tile(Icons.assignment_return_outlined, 'Возвраты', () => _go(ReturnsScreen())),
        ]),
      ]);

  Widget _purchasePage() => _page('Закупки', [
        _grid([
          _tile(Icons.inventory_2_outlined, 'Товары', () => _go(ProductsScreen()), hint: 'группы, остатки'),
          _tile(Icons.local_shipping_outlined, 'Поступления', () => _go(ReceiptsScreen())),
          if (_manager)
            _tile(Icons.request_quote_outlined, 'Долги поставщикам', () => _go(SupplierDebtsScreen()),
                hint: 'взаиморасчёты'),
          if (_manager)
            _tile(Icons.auto_awesome_outlined, 'Автозаявка', () => _go(InsightsScreen(initialTab: 0)),
                hint: 'что докупить'),
          if (_manager)
            _tile(Icons.playlist_add_check_outlined, 'Начальные остатки', () => _go(OpeningScreen())),
        ]),
      ]);

  Widget _reportsPage() => RefreshIndicator(
        onRefresh: () => _refresh(),
        child: _page('Отчёты', [
          _section('Подробные отчёты'),
          _grid([
            _tile(Icons.bar_chart_outlined, 'Продажи и маржа', () => _go(ReportsScreen()),
                hint: 'товары, чеки, клиенты'),
            _tile(Icons.auto_awesome_outlined, 'Автозаявка', () => _go(InsightsScreen(initialTab: 0))),
            _tile(Icons.hourglass_bottom_outlined, 'Не продаются', () => _go(InsightsScreen(initialTab: 1)),
                hint: '30 дней без продаж'),
            _tile(Icons.local_fire_department_outlined, 'Ходовые товары', () => _go(InsightsScreen(initialTab: 2)),
                hint: 'как часто продаются'),
            _tile(Icons.leaderboard_outlined, 'Топ клиенты и поставщики',
                () => _go(InsightsScreen(initialTab: 3))),
            _tile(Icons.account_balance_wallet_outlined, 'Долги', () => _go(InsightsScreen(initialTab: 4)),
                hint: 'нам и мы должны'),
          ]),
        ]),
      );

  Widget _settingsPage() => _page('Настройки', [
        _grid([
          if (_manager) _tile(Icons.cloud_sync_outlined, 'Google Диск', () => _go(SyncScreen()), hint: 'синхронизация'),
          _tile(Icons.password, 'Сменить PIN', () => _go(ChangePinScreen())),
          _tile(Icons.palette_outlined, 'Тема', _pickTheme),
          if (_manager) _tile(Icons.badge_outlined, 'Сотрудники', () => _go(EmployeesScreen()), hint: 'роли, PIN'),
          if (_admin) _tile(Icons.manage_search_outlined, 'Журнал входов', () => _go(JournalScreen())),
          if (_manager) _tile(Icons.playlist_add_check_outlined, 'Начальные остатки', () => _go(OpeningScreen())),
        ]),
        SizedBox(height: 18),
        Center(
          child: Text('AVTOMAG GRS SOFT\nАвтор: Гуламжан Саттаркулович',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        ),
      ]);

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
              trailing: AppThemes.current.value.id == p.id ? Icon(Icons.check_circle, color: AppColors.accent) : null,
            ),
          SizedBox(height: 8),
        ]),
      ),
    );
    if (chosen != null && mounted) await AppThemes.set(context, chosen);
  }

  List<_Tab> get _tabs => [
        _Tab(Icons.home_outlined, 'Главная', _homePage),
        _Tab(Icons.shopping_cart_outlined, 'Продажа', _salesPage),
        _Tab(Icons.local_shipping_outlined, 'Закупки', _purchasePage),
        if (_manager) _Tab(Icons.insights_outlined, 'Отчёты', _reportsPage),
        _Tab(Icons.settings_outlined, 'Настройки', _settingsPage),
      ];

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    if (_tab >= tabs.length) _tab = 0;
    return Scaffold(
      body: GlassBackground(child: tabs[_tab].page()),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStatePropertyAll(
              TextStyle(color: AppColors.text, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ),
        child: NavigationBar(
          height: 62,
          backgroundColor: AppColors.sheet,
          indicatorColor: AppColors.accent.withOpacity(0.22),
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            for (final t in tabs)
              NavigationDestination(
                icon: Icon(t.icon, color: AppColors.textDim),
                selectedIcon: Icon(t.icon, color: AppColors.accent),
                label: t.label,
              ),
          ],
        ),
      ),
    );
  }
}

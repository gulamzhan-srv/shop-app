// Возвраты: кассир создаёт, хозяин подтверждает (на склад / брак) или отклоняет.

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/return_service.dart';
import '../services/sale_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';

class ReturnsScreen extends StatefulWidget {
  ReturnsScreen({super.key});
  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  List<ReturnInfo> _items = [];
  bool _loading = true;
  bool get _owner => AuthService.instance.current?.isOwner ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await ReturnService.instance.list();
    if (mounted) {
      setState(() {
        _items = l;
        _loading = false;
      });
    }
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _new() async {
    final sales = await ReturnService.instance.recentSales();
    if (!mounted) return;
    final sale = await showModalBottomSheet<SaleBrief>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.sheet,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SizedBox(
        height: MediaQuery.of(c).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('Выберите продажу (30 дней)',
                style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: sales.isEmpty
                ? Center(child: Text('Продаж нет', style: TextStyle(color: AppColors.textDim)))
                : ListView(children: [
                    for (final s in sales)
                      ListTile(
                        onTap: () => Navigator.pop(c, s),
                        title: Text('${dateTimeText(s.date)} · ${money(s.total)}',
                            style: TextStyle(color: AppColors.text)),
                        subtitle: Text(
                            '${_pay(s.payment)}${s.customer != null ? ' · ${s.customer}' : ''}',
                            style: TextStyle(color: AppColors.textDim)),
                      ),
                  ]),
          ),
        ]),
      ),
    );
    if (sale == null || !mounted) return;
    final created = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => _NewReturnScreen(sale: sale)));
    if (created == true) {
      _snack('Возврат отправлен хозяину на подтверждение');
      _load();
    }
  }

  static String _pay(String p) => paymentName(p);

  Future<void> _approve(ReturnInfo r) async {
    String type = 'to_stock';
    String refund = r.salePayment == 'kaspi' ? 'kaspi' : (r.salePayment == 'debt' ? 'debt' : 'cash');
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('Подтвердить возврат на ${money(r.total)}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Что с товаром?'),
            RadioListTile<String>(
              value: 'to_stock',
              groupValue: type,
              onChanged: (v) => setD(() => type = v!),
              title: Text('На склад — товар новый, можно продать'),
            ),
            RadioListTile<String>(
              value: 'defect',
              groupValue: type,
              onChanged: (v) => setD(() => type = v!),
              title: Text('Брак — заводской или испорчен, продавать нельзя'),
            ),
            SizedBox(height: 8),
            Text('Как вернуть деньги?'),
            SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'cash', label: Text('Наличные')),
                ButtonSegment(value: 'kaspi', label: Text('Kaspi')),
                if (r.salePayment == 'debt') ButtonSegment(value: 'debt', label: Text('Из долга')),
              ],
              selected: {refund},
              onSelectionChanged: (v) => setD(() => refund = v.first),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Подтвердить')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final err = await ReturnService.instance.approve(r.id, type, refund);
    _snack(err ?? 'Возврат подтверждён');
    _load();
  }

  Future<void> _reject(ReturnInfo r) async {
    await ReturnService.instance.reject(r.id);
    _snack('Возврат отклонён');
    _load();
  }

  Widget _status(ReturnInfo r) {
    final (text, color) = switch (r.status) {
      'pending' => ('ждёт подтверждения', AppColors.warn),
      'approved' => (r.returnType == 'defect' ? 'подтверждён · брак' : 'подтверждён · на склад', AppColors.accent),
      _ => ('отклонён', AppColors.danger),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        icon: Icon(Icons.assignment_return_outlined),
        label: Text('Новый возврат', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Возвраты'),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(child: Text('Возвратов нет', style: TextStyle(color: AppColors.textDim)))
                    : ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                        for (final r in _items)
                          Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: GlassCard(
                              borderColor: r.status == 'pending' ? AppColors.warn.withOpacity(0.5) : null,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(
                                    child: Text(money(r.total),
                                        style: TextStyle(
                                            color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
                                  ),
                                  _status(r),
                                ]),
                                SizedBox(height: 4),
                                Text('${dateTimeText(r.createdAt)} · ${r.createdBy} · продажа: ${_pay(r.salePayment)}',
                                    style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                                SizedBox(height: 6),
                                for (final l in r.lines)
                                  Text('• $l', style: TextStyle(color: AppColors.text)),
                                if (r.comment != null)
                                  Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text(r.comment!, style: TextStyle(color: AppColors.textDim)),
                                  ),
                                if (_owner && r.status == 'pending') ...[
                                  SizedBox(height: 10),
                                  Row(children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _reject(r),
                                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                                        child: Text('Отклонить'),
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: () => _approve(r),
                                        style: FilledButton.styleFrom(
                                            backgroundColor: AppColors.accent, foregroundColor: AppColors.onAccent),
                                        child: Text('Подтвердить'),
                                      ),
                                    ),
                                  ]),
                                ],
                              ]),
                            ),
                          ),
                      ]),
          ),
        ]),
      ),
    );
  }
}

/// Отметить, что и сколько возвращают по выбранной продаже.
class _NewReturnScreen extends StatefulWidget {
  final SaleBrief sale;
  const _NewReturnScreen({required this.sale});
  @override
  State<_NewReturnScreen> createState() => _NewReturnScreenState();
}

class _NewReturnScreenState extends State<_NewReturnScreen> {
  List<SaleLineInfo> _lines = [];
  final Map<String, double> _qty = {};
  final _comment = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    ReturnService.instance.saleLines(widget.sale.id).then((l) {
      if (mounted) setState(() => _lines = l);
    });
  }

  double get _total => _lines.fold(0, (s, l) => s + (_qty[l.id] ?? 0) * l.price);

  Future<void> _send() async {
    final err = await ReturnService.instance.create(widget.sale.id, _qty, _comment.text);
    if (!mounted) return;
    if (err != null) return setState(() => _error = err);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Новый возврат'),
          Expanded(
            child: ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              Text('Продажа ${dateTimeText(widget.sale.date)} на ${money(widget.sale.total)}',
                  style: TextStyle(color: AppColors.textDim)),
              SizedBox(height: 12),
              for (final l in _lines)
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: GlassCard(
                    radius: 16,
                    padding: EdgeInsets.all(10),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(l.productName,
                              style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                          Text('Куплено ${qtyText(l.qty)} ${l.unit} по ${money(l.price)}'
                              '${l.returned > 0 ? ' · уже возврат ${qtyText(l.returned)}' : ''}',
                              style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                        ]),
                      ),
                      IconButton(
                        onPressed: (_qty[l.id] ?? 0) <= 0
                            ? null
                            : () => setState(() => _qty[l.id] = (_qty[l.id] ?? 0) - 1),
                        icon: Icon(Icons.remove, color: AppColors.text),
                        tooltip: 'Меньше',
                      ),
                      Text(qtyText(_qty[l.id] ?? 0),
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 16)),
                      IconButton(
                        onPressed: (_qty[l.id] ?? 0) + 1 > l.canReturn + 1e-9
                            ? null
                            : () => setState(() => _qty[l.id] = (_qty[l.id] ?? 0) + 1),
                        icon: Icon(Icons.add, color: AppColors.text),
                        tooltip: 'Больше',
                      ),
                    ]),
                  ),
                ),
              TextField(
                controller: _comment,
                style: TextStyle(color: AppColors.text),
                decoration: glassInput('Причина возврата'),
              ),
              SizedBox(height: 12),
              GlassCard(
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('К возврату', style: TextStyle(color: AppColors.textDim)),
                  Text(money(_total),
                      style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
                ]),
              ),
              if (_error != null)
                Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(_error!, style: TextStyle(color: AppColors.danger)),
                ),
              SizedBox(height: 14),
              AccentButton(label: 'Отправить хозяину', onPressed: _total > 0 ? _send : null),
            ]),
          ),
        ]),
      ),
    );
  }
}

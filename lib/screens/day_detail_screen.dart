// Подробный отчёт по нажатию на столбик: список документов за день (или месяц).
// Продажи — чеки (нажатие открывает чек), поступления, расходы из кассы, возвраты.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../services/report_service.dart';
import '../services/sale_service.dart' show paymentName;
import '../ui/format.dart';
import '../ui/glass.dart';
import 'checks_screen.dart' show showCheck;

enum DayKind { sales, receipts, cashOut, returns }

class _Row {
  final DateTime t;
  final String title;
  final String sub;
  final double amount;
  final VoidCallback? onTap;
  _Row(this.t, this.title, this.sub, this.amount, [this.onTap]);
}

class DayDetailScreen extends StatefulWidget {
  final DayKind kind;
  final DateTime from; // включительно
  final DateTime to; // не включительно
  final String title;
  DayDetailScreen({super.key, required this.kind, required this.from, required this.to, required this.title});

  @override
  State<DayDetailScreen> createState() => _DayDetailScreenState();
}

class _DayDetailScreenState extends State<DayDetailScreen> {
  List<_Row>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _hm(int ms) => DateFormat('dd.MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));

  Future<void> _load() async {
    try {
      final db = await AppDatabase.instance.db;
      final a = widget.from.millisecondsSinceEpoch;
      final b = widget.to.millisecondsSinceEpoch;
      final out = <_Row>[];
      switch (widget.kind) {
        case DayKind.sales:
          final checks = await ReportService.instance.checks(widget.from, widget.to);
          for (final c in checks) {
            out.add(_Row(c.date, '${DateFormat('dd.MM HH:mm').format(c.date)} · ${c.cashier}',
                '${paymentName(c.payment)}${c.customer != null ? ' · ${c.customer}' : ''}', c.total, () async {
              await showCheck(context, c);
            }));
          }
        case DayKind.receipts:
          final rows = await db.rawQuery('''
            SELECT r.doc_date AS t, r.total AS v, COALESCE(s.name, 'без поставщика') AS who, r.comment AS cm
            FROM receipts r LEFT JOIN suppliers s ON s.id = r.supplier_id
            WHERE r.deleted = 0 AND r.opening = 0 AND r.doc_date >= ? AND r.doc_date < ?
            ORDER BY r.doc_date DESC''', [a, b]);
          for (final r in rows) {
            out.add(_Row(DateTime.fromMillisecondsSinceEpoch(r['t'] as int), '${_hm(r['t'] as int)} · ${r['who']}',
                (r['cm'] as String?) ?? '', ((r['v'] as num?) ?? 0).toDouble()));
          }
        case DayKind.cashOut:
          final rows = await db.rawQuery('''
            SELECT op_date AS t, amount AS v, counterparty AS who, comment AS cm
            FROM cash_ops WHERE deleted = 0 AND kind = 'out' AND op_date >= ? AND op_date < ?
            ORDER BY op_date DESC''', [a, b]);
          for (final r in rows) {
            final who = (r['who'] as String?) ?? '';
            out.add(_Row(DateTime.fromMillisecondsSinceEpoch(r['t'] as int),
                '${_hm(r['t'] as int)}${who.isEmpty ? '' : ' · $who'}', (r['cm'] as String?) ?? '',
                ((r['v'] as num?) ?? 0).toDouble()));
          }
        case DayKind.returns:
          final rows = await db.rawQuery('''
            SELECT approved_at AS t, refund AS v, comment AS cm
            FROM returns WHERE deleted = 0 AND status = 'approved' AND approved_at >= ? AND approved_at < ?
            ORDER BY approved_at DESC''', [a, b]);
          for (final r in rows) {
            out.add(_Row(DateTime.fromMillisecondsSinceEpoch(r['t'] as int), 'Возврат · ${_hm(r['t'] as int)}',
                (r['cm'] as String?) ?? '', ((r['v'] as num?) ?? 0).toDouble()));
          }
      }
      if (mounted) setState(() => _rows = out);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final total = rows == null ? 0.0 : rows.fold<double>(0, (s, r) => s + r.amount);
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: widget.title),
          Expanded(
            child: _error != null
                ? Padding(padding: EdgeInsets.all(16), child: Text(_error!, style: TextStyle(color: AppColors.warn)))
                : rows == null
                    ? Center(child: CircularProgressIndicator())
                    : ListView(padding: EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                        GlassCard(
                          radius: 20,
                          child: Row(children: [
                            Expanded(
                              child: Text('Документов: ${rows.length}',
                                  style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
                            ),
                            Text(money(total),
                                style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
                          ]),
                        ),
                        SizedBox(height: 8),
                        if (rows.isEmpty)
                          Padding(
                            padding: EdgeInsets.all(30),
                            child: Center(child: Text('За этот период ничего нет', style: TextStyle(color: AppColors.textDim))),
                          ),
                        for (final r in rows)
                          Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: GlassCard(
                              radius: 16,
                              onTap: r.onTap,
                              child: Row(children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(r.title, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                                    if (r.sub.isNotEmpty)
                                      Text(r.sub, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                                  ]),
                                ),
                                Text(money(r.amount),
                                    style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 15)),
                                if (r.onTap != null) Icon(Icons.chevron_right, color: AppColors.textDim),
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

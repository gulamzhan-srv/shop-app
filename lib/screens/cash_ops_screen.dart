// Детальный отчёт «Приход и расход денег из кассы» за период.

import 'package:flutter/material.dart';

import '../db/database.dart';
import '../ui/format.dart';
import '../ui/glass.dart';

class CashOpsScreen extends StatefulWidget {
  /// 'out' — только расходы, 'in' — только приходы, null — всё.
  final String? kind;
  CashOpsScreen({super.key, this.kind = 'out'});
  @override
  State<CashOpsScreen> createState() => _CashOpsScreenState();
}

class _CashOpsScreenState extends State<CashOpsScreen> {
  late String? _kind = widget.kind;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _to = DateTime.now();
  List<Map<String, Object?>>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance.db;
    final to = DateTime(_to.year, _to.month, _to.day).add(Duration(days: 1));
    final rows = await db.rawQuery('''
      SELECT o.op_date, o.kind, o.amount, o.counterparty, o.comment, COALESCE(e.name, '') AS author
      FROM cash_ops o LEFT JOIN employees e ON e.id = o.author_id
      WHERE o.deleted = 0 AND o.op_date >= ? AND o.op_date < ? AND (? = '' OR o.kind = ?)
      ORDER BY o.op_date DESC''', [_from.millisecondsSinceEpoch, to.millisecondsSinceEpoch, _kind ?? '', _kind ?? '']);
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _period() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (r == null) return;
    _from = r.start;
    _to = r.end;
    _load();
  }

  Widget _chip(String? k, String label) => Padding(
        padding: EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: _kind == k,
          onSelected: (_) {
            _kind = k;
            _load();
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final outSum = (rows ?? []).where((r) => r['kind'] == 'out').fold<double>(0, (s, r) => s + (r['amount'] as num).toDouble());
    final inSum = (rows ?? []).where((r) => r['kind'] == 'in').fold<double>(0, (s, r) => s + (r['amount'] as num).toDouble());
    return Scaffold(
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Деньги кассы'),
          Expanded(
            child: rows == null
                ? Center(child: CircularProgressIndicator())
                : ListView(padding: EdgeInsets.fromLTRB(14, 0, 14, 24), children: [
                    Row(children: [
                      _chip('out', 'Расходы'),
                      _chip('in', 'Приходы'),
                      _chip(null, 'Все'),
                      Spacer(),
                      TextButton.icon(
                        onPressed: _period,
                        icon: Icon(Icons.event_outlined, size: 18),
                        label: Text('${dateText(_from).substring(0, 5)} – ${dateText(_to).substring(0, 5)}'),
                      ),
                    ]),
                    SizedBox(height: 8),
                    GlassCard(
                      radius: 16,
                      padding: EdgeInsets.all(14),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Расход', style: TextStyle(color: AppColors.textDim)),
                            Text(money(outSum),
                                style: TextStyle(color: AppColors.danger, fontSize: 20, fontWeight: FontWeight.w800)),
                          ]),
                        ),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Приход', style: TextStyle(color: AppColors.textDim)),
                            Text(money(inSum),
                                style: TextStyle(color: Color(0xFF16A34A), fontSize: 20, fontWeight: FontWeight.w800)),
                          ]),
                        ),
                      ]),
                    ),
                    SizedBox(height: 10),
                    if (rows.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(child: Text('Операций нет', style: TextStyle(color: AppColors.textDim))),
                      )
                    else
                      GlassCard(
                        radius: 16,
                        padding: EdgeInsets.symmetric(vertical: 2),
                        child: Column(children: [
                          for (var i = 0; i < rows.length; i++) ...[
                            if (i > 0) Divider(height: 1, color: AppColors.overlay(0.08)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              child: Row(children: [
                                Icon(rows[i]['kind'] == 'out' ? Icons.arrow_upward : Icons.arrow_downward,
                                    color: rows[i]['kind'] == 'out' ? AppColors.danger : Color(0xFF16A34A), size: 20),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(
                                        [rows[i]['counterparty'], rows[i]['comment']]
                                                .where((x) => x != null && '$x'.isNotEmpty)
                                                .join(' · ')
                                                .isEmpty
                                            ? (rows[i]['kind'] == 'out' ? 'Расход' : 'Приход')
                                            : [rows[i]['counterparty'], rows[i]['comment']]
                                                .where((x) => x != null && '$x'.isNotEmpty)
                                                .join(' · '),
                                        style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                                    Text(
                                        '${dateTimeText(DateTime.fromMillisecondsSinceEpoch(rows[i]['op_date'] as int))} · ${rows[i]['author']}',
                                        style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                                  ]),
                                ),
                                Text(money((rows[i]['amount'] as num).toDouble()),
                                    style: TextStyle(
                                        color: rows[i]['kind'] == 'out' ? AppColors.danger : Color(0xFF16A34A),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16)),
                              ]),
                            ),
                          ],
                        ]),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

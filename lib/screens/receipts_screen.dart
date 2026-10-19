// Список поступлений: дата, поставщик, автор, количество строк, сумма.

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/receipt_service.dart';
import '../ui/format.dart';
import '../ui/glass.dart';
import 'receipt_edit_screen.dart';

class ReceiptsScreen extends StatefulWidget {
  ReceiptsScreen({super.key});
  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  final bool _manager = AuthService.instance.current?.isManager ?? false;
  List<ReceiptRow> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ReceiptService.instance.list();
    if (mounted) {
      setState(() {
        _items = list;
        _loading = false;
      });
    }
  }

  Future<void> _open(String? id) async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => ReceiptEditScreen(receiptId: id)));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: !_manager ? null : FloatingActionButton.extended(
        onPressed: () => _open(null),
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        icon: Icon(Icons.add),
        label: Text('Поступление', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: GlassBackground(
        child: Column(children: [
          GlassHeader(title: 'Поступления'),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Text('Поступлений пока нет', style: TextStyle(color: AppColors.textDim)))
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final r = _items[i];
                          return GlassCard(
                            radius: 18,
                            padding: EdgeInsets.all(14),
                            onTap: () => _open(r.id),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(r.supplier,
                                      style: TextStyle(
                                          color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 15)),
                                  SizedBox(height: 3),
                                  Text('${dateText(r.date)} · ${r.linesCount} поз. · ${r.author}',
                                      style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                                ]),
                              ),
                              if (_manager)
                              Text(money(r.total),
                                  style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
                            ]),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}

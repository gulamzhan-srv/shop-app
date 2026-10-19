// Красивое окно оплаты: размытый фон, крупная сумма, способы оплаты со значками,
// кнопки «Отмена» и «Принять» по центру. Значки: наличные — золотая монета с ₸,
// Kaspi — красный объёмный круглый значок.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'format.dart';
import 'glass.dart';

/// Золотая монета с ₸ (наличные).
class CoinIcon extends StatelessWidget {
  final double size;
  CoinIcon({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 0.9,
          colors: [Color(0xFFFFF3B0), Color(0xFFF5C542), Color(0xFFB8860B)],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: Color(0xFF9A6E08), width: size * 0.05),
        boxShadow: [BoxShadow(color: Color(0x66B8860B), blurRadius: size * 0.25, offset: Offset(0, size * 0.08))],
      ),
      alignment: Alignment.center,
      child: Text('₸',
          style: TextStyle(
            fontFamily: 'DejaVuSans',
            color: Color(0xFF7A5200),
            fontSize: size * 0.56,
            fontWeight: FontWeight.w700,
            height: 1,
            shadows: [Shadow(color: Color(0x88FFFFFF), offset: Offset(0, 1))],
          )),
    );
  }
}

/// Красный объёмный круглый значок Kaspi.
class KaspiIcon extends StatelessWidget {
  final double size;
  KaspiIcon({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 0.95,
          colors: [Color(0xFFFF8A7A), Color(0xFFF14635), Color(0xFFB3200F)],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [BoxShadow(color: Color(0x66F14635), blurRadius: size * 0.25, offset: Offset(0, size * 0.08))],
      ),
      alignment: Alignment.center,
      child: Text('K',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.5,
            fontWeight: FontWeight.w900,
            height: 1,
            shadows: [Shadow(color: Color(0x55000000), offset: Offset(0, 1), blurRadius: 2)],
          )),
    );
  }
}

/// Значок «другое» (перевод и т.п.).
class OtherPayIcon extends StatelessWidget {
  final double size;
  OtherPayIcon({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [Color(0xFF8FA3B8), Color(0xFF4B5D70)]),
        ),
        child: Icon(Icons.account_balance_outlined, color: Colors.white, size: size * 0.55),
      );
}

class PayMethod {
  final String code; // 'cash', 'kaspi', 'other'
  final String label;
  final Widget icon;
  PayMethod(this.code, this.label, this.icon);

  static PayMethod cash([String label = 'Наличные']) => PayMethod('cash', label, CoinIcon());
  static PayMethod kaspi() => PayMethod('kaspi', 'Kaspi', KaspiIcon());
  static PayMethod other() => PayMethod('other', 'Другое', OtherPayIcon());
}

class PayResult {
  final double amount;
  final String method;
  final String comment;
  PayResult(this.amount, this.method, this.comment);
}

/// Показать окно оплаты. Возвращает сумму и способ, или null (отмена).
Future<PayResult?> showPayDialog(
  BuildContext context, {
  required String title,
  required double owed,
  required List<PayMethod> methods,
  String? note,
  bool withComment = false,
}) {
  return showGeneralDialog<PayResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Закрыть',
    barrierColor: Colors.black.withOpacity(0.25),
    transitionDuration: Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => _PayDialog(
        title: title, owed: owed, methods: methods, note: note, withComment: withComment),
    transitionBuilder: (_, a, __, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
    ),
  );
}

class _PayDialog extends StatefulWidget {
  final String title;
  final double owed;
  final List<PayMethod> methods;
  final String? note;
  final bool withComment;
  _PayDialog({required this.title, required this.owed, required this.methods, this.note, this.withComment = false});
  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  late final _amount = TextEditingController(text: qtyText(widget.owed.roundToDouble()));
  final _comment = TextEditingController();
  late String _method = widget.methods.first.code;
  String? _error;

  void _ok() {
    final v = parseNum(_amount.text) ?? 0;
    if (v <= 0) return setState(() => _error = 'Введите сумму');
    if (v > widget.owed + 0.5) return setState(() => _error = 'Больше долга (${money(widget.owed)})');
    Navigator.of(context).pop(PayResult(v, _method, _comment.text.trim()));
  }

  Widget _methodTile(PayMethod m) {
    final on = m.code == _method;
    return Expanded(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _method = m.code),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: on ? AppColors.accent.withOpacity(0.14) : AppColors.overlay(0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? AppColors.accent : AppColors.overlay(0.12), width: on ? 2 : 1),
            ),
            child: Column(children: [
              m.icon,
              SizedBox(height: 6),
              Text(m.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.text, fontSize: 14, fontWeight: on ? FontWeight.w800 : FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom * 0.5),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 340,
              margin: EdgeInsets.symmetric(horizontal: 20),
              padding: EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: BoxDecoration(
                color: AppColors.sheet.withOpacity(0.86),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.overlay(0.18)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 30, offset: Offset(0, 10))],
              ),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.text, fontSize: 19, fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text('Долг: ${money(widget.owed)}',
                      style: TextStyle(color: AppColors.warn, fontSize: 14, fontWeight: FontWeight.w700)),
                  SizedBox(height: 12),
                  TextField(
                    controller: _amount,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    onSubmitted: (_) => _ok(),
                    style: TextStyle(color: AppColors.text, fontSize: 34, fontWeight: FontWeight.w800),
                    decoration: InputDecoration(
                      suffixText: '₸',
                      suffixStyle: TextStyle(color: AppColors.textDim, fontSize: 24, fontWeight: FontWeight.w700),
                      filled: true,
                      fillColor: AppColors.overlay(0.06),
                      contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  SizedBox(height: 12),
                  Row(children: [for (final m in widget.methods) _methodTile(m)]),
                  if (widget.note != null) ...[
                    SizedBox(height: 8),
                    Text(widget.note!,
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ],
                  if (widget.withComment) ...[
                    SizedBox(height: 10),
                    TextField(
                      controller: _comment,
                      style: TextStyle(color: AppColors.text),
                      decoration: glassInput('Комментарий')
                          .copyWith(isDense: true, contentPadding: EdgeInsets.all(12)),
                    ),
                  ],
                  if (_error != null) ...[
                    SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                  ],
                  SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.text,
                            side: BorderSide(color: AppColors.overlay(0.3)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          child: Text('Отмена'),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: FilledButton(
                          onPressed: _ok,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.onAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          child: Text('Принять'),
                        ),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Клавиатура и точки PIN-кода (как на макете).

import 'package:flutter/material.dart';

import 'glass.dart';

class PinDots extends StatelessWidget {
  final int filled;
  final bool error;
  final int count;
  PinDots({super.key, required this.filled, this.error = false, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final on = i < filled;
        final c = error ? AppColors.danger : AppColors.text;
        return Container(
          margin: EdgeInsets.symmetric(horizontal: 7),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? c : Colors.transparent,
            border: Border.all(color: c.withOpacity(0.7), width: 2),
          ),
        );
      }),
    );
  }
}

class PinPad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  PinPad({super.key, required this.onDigit, required this.onBackspace, required this.onClear});

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'C', '0', '⌫'];
    return GlassCard(
      radius: 28,
      padding: EdgeInsets.all(20),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1.9,
        children: [
          for (final k in keys)
            Semantics(
              button: true,
              label: k == 'C' ? 'Очистить' : k == '⌫' ? 'Стереть' : k,
              child: Material(
                color: AppColors.overlay(0.07),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppColors.overlay(0.12)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    if (k == 'C') {
                      onClear();
                    } else if (k == '⌫') {
                      onBackspace();
                    } else {
                      onDigit(k);
                    }
                  },
                  child: Center(
                    child: Text(k,
                        style: TextStyle(
                            color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

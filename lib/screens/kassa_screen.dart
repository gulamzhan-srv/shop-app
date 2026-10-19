// Касса: только смена — открыть, приход/расход денег, итоги и закрыть кассу.
// Продажа товаров — отдельный раздел «Продажа» (sale_screen.dart).

import 'package:flutter/material.dart';

import 'shift_screen.dart';

class KassaScreen extends StatelessWidget {
  KassaScreen({super.key});

  @override
  Widget build(BuildContext context) => ShiftScreen();
}

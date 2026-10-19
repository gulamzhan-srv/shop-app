// Сканер штрихкода камерой. Возвращает прочитанный код (Navigator.pop(code)).

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../ui/glass.dart';

class BarcodeScanScreen extends StatefulWidget {
  BarcodeScanScreen({super.key});

  /// Удобный вызов: final code = await BarcodeScanScreen.scan(context);
  static Future<String?> scan(BuildContext context) =>
      Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => BarcodeScanScreen()));

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture c) {
    if (_done) return;
    for (final b in c.barcodes) {
      final v = b.rawValue;
      if (v != null && v.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(v);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        // Рамка в центре
        Center(
          child: Container(
            width: 260,
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.accent, width: 3),
            ),
          ),
        ),
        SafeArea(
          child: Column(children: [
            GlassHeader(title: 'Наведите на штрихкод'),
            Spacer(),
            Padding(
              padding: EdgeInsets.all(20),
              child: GlassCard(
                radius: 18,
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                onTap: () => _controller.toggleTorch(),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.flashlight_on_outlined, color: AppColors.text),
                  SizedBox(width: 8),
                  Text('Фонарик', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

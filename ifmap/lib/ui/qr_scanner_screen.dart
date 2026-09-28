// lib/qr_scanner_screen.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool isScanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('現在地のQRコードをスキャン'),
        backgroundColor: Colors.blueGrey,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (isScanned) return;

          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              isScanned = true;
              final String code = barcode.rawValue!;

              Navigator.pop(context, code);
              break;
            }
          }
        },
      ),
    );
  }
}
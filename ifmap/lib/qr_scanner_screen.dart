// lib/qr_scanner_screen.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; // カメラ用のパッケージ

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  // 連続で何度も読み込んでしまうのを防ぐフラグ
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
          if (isScanned) return; // すでに読み込み済みなら無視する

          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              isScanned = true; // 読み込み完了フラグを立てる
              final String code = barcode.rawValue!;
              
              // 読み取った文字（例: room_left）を持って、地図画面に戻る！
              Navigator.pop(context, code);
              break;
            }
          }
        },
      ),
    );
  }
}
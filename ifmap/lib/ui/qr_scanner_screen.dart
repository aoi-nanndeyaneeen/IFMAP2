// lib/ui/qr_scanner_screen.dart
//
// QRコードを読み取って、その中身（文字列）を返す画面。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool _scanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code == null) continue;
      _scanned = true;
      HapticFeedback.mediumImpact();
      Navigator.pop(context, code);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: (context, constraints) {
        final side = (constraints.maxWidth * 0.68).clamp(180.0, 320.0);
        final window = Rect.fromCenter(
          center: Offset(constraints.maxWidth / 2, constraints.maxHeight * 0.44),
          width: side,
          height: side,
        );
        return Stack(fit: StackFit.expand, children: [
          MobileScanner(onDetect: _onDetect),
          CustomPaint(painter: _ScanOverlayPainter(window)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                IconButton(
                  tooltip: '閉じる',
                  style: IconButton.styleFrom(backgroundColor: Colors.black45),
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                const Text('QRコードを読み取る',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          Positioned(
            left: 32,
            right: 32,
            top: window.bottom + 28,
            child: const Column(children: [
              Text('施設に貼られた QR コードを枠に合わせてください',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              SizedBox(height: 6),
              Text('読み取った場所が現在地になります',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ),
        ]);
      }),
    );
  }
}

/// 読み取り枠の外を暗くし、枠の四隅にかぎ形を描く。
class _ScanOverlayPainter extends CustomPainter {
  final Rect window;
  _ScanOverlayPainter(this.window);

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(window, const Radius.circular(20));
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(hole);
    canvas.drawPath(dim, Paint()..color = const Color(0x99000000));

    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 28.0, r = 20.0;
    final l = window.left, t = window.top, rt = window.right, b = window.bottom;
    for (final (x, y, sx, sy) in [(l, t, 1.0, 1.0), (rt, t, -1.0, 1.0), (l, b, 1.0, -1.0), (rt, b, -1.0, -1.0)]) {
      final p = Path()
        ..moveTo(x, y + sy * (r + len))
        ..lineTo(x, y + sy * r)
        ..arcToPoint(Offset(x + sx * r, y), radius: const Radius.circular(r), clockwise: sx * sy > 0)
        ..lineTo(x + sx * (r + len), y);
      canvas.drawPath(p, corner);
    }
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter old) => old.window != window;
}

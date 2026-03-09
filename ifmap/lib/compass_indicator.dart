// lib/compass_indicator.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'config.dart';

/// コンパス表示 + 初動方向案内ウィジェット（Stateless）
/// heading と routeAngleRad を外から受け取るだけでよい
class CompassIndicator extends StatelessWidget {
  final double? heading;       // flutter_compass から取得した方位角（度、磁北から時計回り）
  final double? routeAngleRad; // ルート最初のセグメントのキャンバス角（ラジアン）

  const CompassIndicator({super.key, this.heading, this.routeAngleRad});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.indigo.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        _CompassDial(heading: heading),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                heading != null ? '${heading!.toStringAsFixed(0)}° (磁北から)' : 'コンパス取得中...',
                style: TextStyle(fontSize: 11, color: Colors.indigo.shade700),
              ),
              if (heading != null && routeAngleRad != null) _turnInstruction(),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _turnInstruction() {
    // キャンバス角（右=0, 下=π/2）→ 地図上の角度（上=0, 右=90）→ コンパス方位
    // canvas角: 右が0、+時計回り。地図上「上」= canvas -π/2
    // 必要なコンパス方位 = canvas角をdegに変換し +90（右=east=90°）+ マップ北オフセット
    final requiredHeading = (routeAngleRad! * 180 / pi + 90 + AppConfig.mapNorthDegrees + 360) % 360;
    final diff = ((requiredHeading - heading!) + 360) % 360;

    final (String text, Color color, String icon) = switch (diff) {
      < 20             => ('まっすぐ進んでください',   Colors.green,       '↑'),
      < 70             => ('少し右方向へ',            Colors.lightGreen,  '↗'),
      < 110            => ('右へ曲がってください',     Colors.orange,      '→'),
      < 160            => ('大きく右へ曲がります',     Colors.deepOrange,  '↘'),
      <= 200           => ('逆方向です！',            Colors.red,         '↩'),
      < 250            => ('大きく左へ曲がります',     Colors.deepOrange,  '↙'),
      < 290            => ('左へ曲がってください',     Colors.orange,      '←'),
      < 340            => ('少し左方向へ',            Colors.lightGreen,  '↖'),
      _                => ('まっすぐ進んでください',   Colors.green,       '↑'),
    };
    return Text('$icon $text',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color));
  }
}

class _CompassDial extends StatelessWidget {
  final double? heading;
  const _CompassDial({this.heading});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52, height: 52,
    child: CustomPaint(painter: _DialPainter(heading: heading ?? 0)),
  );
}

class _DialPainter extends CustomPainter {
  final double heading;
  _DialPainter({required this.heading});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 2;
    canvas.drawCircle(c, r, Paint()..color = Colors.indigo.shade50);
    canvas.drawCircle(c, r, Paint()..color = Colors.indigo.shade300
        ..style = PaintingStyle.stroke..strokeWidth = 1.5);

    // N表示（常に上）
    final tp = TextPainter(
      text: TextSpan(text: 'N', style: TextStyle(fontSize: 9, color: Colors.indigo.shade700, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, 1));

    // 針: heading=0が上、時計回り
    final a = (heading - 90) * pi / 180;
    // 北針（赤）
    canvas.drawLine(c, Offset(c.dx + r * 0.75 * cos(a), c.dy + r * 0.75 * sin(a)),
        Paint()..color = Colors.red..strokeWidth = 2.5..strokeCap = StrokeCap.round);
    // 南針（グレー）
    canvas.drawLine(c, Offset(c.dx - r * 0.5 * cos(a), c.dy - r * 0.5 * sin(a)),
        Paint()..color = Colors.blueGrey..strokeWidth = 2..strokeCap = StrokeCap.round);
    // 中心点
    canvas.drawCircle(c, 3, Paint()..color = Colors.indigo.shade700);
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) => old.heading != heading;
}
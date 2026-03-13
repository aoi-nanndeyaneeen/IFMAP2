// ifmap_editor/lib/canvas_area.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'config.dart';
import 'map_cell.dart';

class CanvasArea extends StatelessWidget {
  final List<List<MapCell>> grid;
  final int brushType;
  final Uint8List? bgImageBytes;
  final int? dragStartX, dragStartY, dragCurrentX, dragCurrentY;
  final Function(int, int) onPointerDown;
  final Function(int, int) onPointerMove;
  final VoidCallback onPointerUp;

  const CanvasArea({
    super.key,
    required this.grid,
    required this.brushType,
    required this.bgImageBytes,
    this.dragStartX, this.dragStartY,
    this.dragCurrentX, this.dragCurrentY,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2)),
      child: LayoutBuilder(builder: (ctx, constraints) {
        final cw = constraints.maxWidth  / AppConfig.cols;
        final ch = constraints.maxHeight / AppConfig.rows;

        void resolve(PointerEvent e, Function(int, int) fn) {
          final x = (e.localPosition.dx / cw).floor().clamp(0, AppConfig.cols - 1);
          final y = (e.localPosition.dy / ch).floor().clamp(0, AppConfig.rows - 1);
          fn(y, x);
        }

        return Listener(
          onPointerDown: (e) => resolve(e, (y, x) => onPointerDown(y, x)),
          onPointerMove: (e) => resolve(e, onPointerMove),
          onPointerUp: (_) => onPointerUp(),
          child: Stack(fit: StackFit.expand, children: [
            if (bgImageBytes != null)
              Image.memory(bgImageBytes!, fit: BoxFit.fill),
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _GridPainter(
                grid: grid, cw: cw, ch: ch, brushType: brushType,
                dragStartX: dragStartX, dragStartY: dragStartY,
                dragCurrentX: dragCurrentX, dragCurrentY: dragCurrentY,
              ),
            ),
          ]),
        );
      }),
    );
  }
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final List<List<MapCell>> grid;
  final double cw, ch;
  final int brushType;
  final int? dragStartX, dragStartY, dragCurrentX, dragCurrentY;

  const _GridPainter({
    required this.grid, required this.cw, required this.ch,
    required this.brushType,
    this.dragStartX, this.dragStartY, this.dragCurrentX, this.dragCurrentY,
  });

  bool get _hasDrag => dragStartX != null && dragCurrentX != null;
  int get _x0 => _hasDrag ? (dragStartX! < dragCurrentX! ? dragStartX! : dragCurrentX!) : 0;
  int get _x1 => _hasDrag ? (dragStartX! > dragCurrentX! ? dragStartX! : dragCurrentX!) : 0;
  int get _y0 => _hasDrag ? (dragStartY! < dragCurrentY! ? dragStartY! : dragCurrentY!) : 0;
  int get _y1 => _hasDrag ? (dragStartY! > dragCurrentY! ? dragStartY! : dragCurrentY!) : 0;
  bool _inDrag(int x, int y) => _hasDrag && x >= _x0 && x <= _x1 && y >= _y0 && y <= _y1;

  Color get _dragColor => switch (brushType) {
    3 => Colors.yellow.withValues(alpha: 0.5),
    4 => Colors.green.withValues(alpha: 0.5),
    5 => Colors.deepPurple.withValues(alpha: 0.4),
    0 => Colors.white.withValues(alpha: 0.7),
    _ => Colors.blue.withValues(alpha: 0.4),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.4;
    final showBorder = cw >= AppConfig.gridLineMinCellPx;

    for (int y = 0; y < AppConfig.rows; y++) {
      for (int x = 0; x < AppConfig.cols; x++) {
        final cell   = grid[y][x];
        final inDrag = _inDrag(x, y);
        if (cell.type == 0 && !inDrag) continue;

        final rect = Rect.fromLTWH(x * cw, y * ch, cw, ch);
        canvas.drawRect(rect, Paint()..color = inDrag ? _dragColor : cell.color);
        if (showBorder) canvas.drawRect(rect, borderPaint);

        if (cell.name != null && cw >= 4) _drawLabel(canvas, cell, rect);
      }
    }

    // ドラッグ枠のアウトライン
    if (_hasDrag) {
      final outerRect = Rect.fromLTRB(
        _x0 * cw, _y0 * ch, (_x1 + 1) * cw, (_y1 + 1) * ch);
      canvas.drawRect(outerRect, Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    }
  }

  void _drawLabel(Canvas canvas, MapCell cell, Rect rect) {
    final icon = switch (cell.type) { 4 => '▲', 5 => '⇄', _ => '★' };
    final text = '$icon${cell.name}';
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: Colors.black87, fontSize: 7, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: cw * 6);

    final bg = Rect.fromCenter(center: rect.center, width: tp.width + 3, height: tp.height + 2);
    canvas.drawRect(bg, Paint()..color = Colors.white.withValues(alpha: 0.75));
    tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.grid != grid || old.dragCurrentX != dragCurrentX || old.dragCurrentY != dragCurrentY;
}
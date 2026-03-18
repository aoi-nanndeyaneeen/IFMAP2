// lib/canvas_area.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'config.dart';
import 'map_cell.dart';

class CanvasArea extends StatelessWidget {
  final List<List<MapCell>> grid;
  final int currentBrush;
  final Uint8List? bgImageBytes;
  final TransformationController? transformController;
  final int? dragStartX, dragStartY, dragCurrentX, dragCurrentY;
  final Function(int, int, int) onPointerDown;
  final Function(int, int, int) onPointerMove;
  final VoidCallback onPointerUp;

  const CanvasArea({
    super.key,
    required this.grid,
    required this.currentBrush,
    required this.bgImageBytes,
    this.transformController,
    this.dragStartX, this.dragStartY, this.dragCurrentX, this.dragCurrentY,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 基本の１マスサイズを計算（画面に収まるサイズ or 最小20px）
        double baseCellWidth = constraints.maxWidth / AppConfig.cols;
        double baseCellHeight = constraints.maxHeight / AppConfig.rows;
        double baseSize = baseCellWidth < baseCellHeight ? baseCellWidth : baseCellHeight;
        if (baseSize < 20.0) baseSize = 20.0;

        double cellSize = baseSize;
        double totalWidth = cellSize * AppConfig.cols;
        double totalHeight = cellSize * AppConfig.rows;

        void resolvePointer(PointerEvent event, Function(int, int, int) action) {
          int x = (event.localPosition.dx / cellSize).floor();
          int y = (event.localPosition.dy / cellSize).floor();
          if (x >= 0 && x < AppConfig.cols && y >= 0 && y < AppConfig.rows) action(y, x, event.buttons);
        }

        return Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2)),
          child: InteractiveViewer(
            transformationController: transformController,
            panEnabled: currentBrush == 5, // ブラシ5(手のひら)の時だけドラッグ移動
            scaleEnabled: true, // ピンチ・マウスホイールでの拡大縮小
            trackpadScrollCausesScale: true,
            constrained: false, // ★子要素（SizedBox）が画面より大きくなるのを許可する
            minScale: 0.1,
            maxScale: 20.0,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            child: Center(
              child: Listener(
                onPointerDown: (e) {
                  if (e.buttons == 4) return; // ホイールクリック
                  resolvePointer(e, onPointerDown);
                },
                onPointerMove: (e) {
                  if (e.buttons == 4) {
                    if (transformController != null) {
                      final matrix = transformController!.value.clone();
                      // ホイールクリック押し込み中は座標を直接移動する
                      matrix[12] += e.delta.dx;
                      matrix[13] += e.delta.dy;
                      transformController!.value = matrix;
                    }
                    return;
                  }
                  resolvePointer(e, onPointerMove);
                },
                onPointerUp: (_) => onPointerUp(),
                child: SizedBox(
                  width: totalWidth,
                  height: totalHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (bgImageBytes != null) 
                        SizedBox(
                          width: totalWidth,
                          height: totalHeight,
                          child: Image.memory(bgImageBytes!, fit: BoxFit.fill),
                        ),
                      SizedBox(
                        width: totalWidth,
                        height: totalHeight,
                        child: CustomPaint(
                          painter: GridPainter(
                            grid: grid,
                            cellSize: cellSize,
                            currentBrush: currentBrush,
                            dragStartX: dragStartX,
                            dragStartY: dragStartY,
                            dragCurrentX: dragCurrentX,
                            dragCurrentY: dragCurrentY,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class GridPainter extends CustomPainter {
  final List<List<MapCell>> grid;
  final double cellSize;
  final int currentBrush;
  final int? dragStartX, dragStartY, dragCurrentX, dragCurrentY;

  GridPainter({
    required this.grid,
    required this.cellSize,
    required this.currentBrush,
    this.dragStartX,
    this.dragStartY,
    this.dragCurrentX,
    this.dragCurrentY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    int rows = AppConfig.rows;
    int cols = AppConfig.cols;

    final Paint borderPaint = Paint()
      ..color = Colors.grey[500]! // 少し濃いグレーに変更（見やすくする）
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final Paint outerBorderPaint = Paint()
      ..color = Colors.black // 外枠は黒で太く
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final Paint cellPaint = Paint()..style = PaintingStyle.fill;
    
    int minX = -1, maxX = -1, minY = -1, maxY = -1;
    bool hasDrag = false;
    if (dragStartX != null && dragStartY != null && dragCurrentX != null && dragCurrentY != null) {
      hasDrag = true;
      minX = dragStartX! < dragCurrentX! ? dragStartX! : dragCurrentX!;
      maxX = dragStartX! > dragCurrentX! ? dragStartX! : dragCurrentX!;
      minY = dragStartY! < dragCurrentY! ? dragStartY! : dragCurrentY!;
      maxY = dragStartY! > dragCurrentY! ? dragStartY! : dragCurrentY!;
    }

    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        MapCell cell = grid[y][x];
        Color color = cell.color;

        if (hasDrag && x >= minX && x <= maxX && y >= minY && y <= maxY) {
          color = currentBrush == 2 ? Colors.blue.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.8);
        }

        if (color != Colors.transparent) {
          Rect rect = Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize);
          cellPaint.color = color;
          canvas.drawRect(rect, cellPaint);
        }

        if (cell.name != null) {
          Rect rect = Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize);
          IconData iconData = cell.type == 4 ? Icons.stairs : Icons.location_on;
          TextPainter iconPainter = TextPainter(
            text: TextSpan(
              text: String.fromCharCode(iconData.codePoint),
              style: TextStyle(
                fontSize: 14.0,
                fontFamily: iconData.fontFamily,
                color: Colors.black87,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          iconPainter.layout();

          String formatName(String name) {
            int limit = AppConfig.maxCharsPerLine;
            if (name.length <= limit) return name;
            RegExp regex = RegExp('.{1,$limit}');
            return regex.allMatches(name).map((m) => m.group(0)).join('\n');
          }

          TextPainter textPainter = TextPainter(
            text: TextSpan(
              text: formatName(cell.name!),
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 10, height: 1.1),
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
          );
          textPainter.layout();

          double totalHeight = iconPainter.height + textPainter.height;
          double startY = rect.center.dy - totalHeight / 2;
          iconPainter.paint(canvas, Offset(rect.center.dx - iconPainter.width / 2, startY));

          double textY = startY + iconPainter.height;
          Rect textBgRect = Rect.fromCenter(
            center: Offset(rect.center.dx, textY + textPainter.height / 2),
            width: textPainter.width + 4,
            height: textPainter.height + 2,
          );
          final Paint textBgPaint = Paint()..color = Colors.white.withValues(alpha: 0.6);
          canvas.drawRRect(RRect.fromRectAndRadius(textBgRect, const Radius.circular(2)), textBgPaint);

          textPainter.paint(canvas, Offset(rect.center.dx - textPainter.width / 2, textY + 1));
        }
      }
    }

    for (int x = 0; x <= cols; x++) {
      canvas.drawLine(Offset(x * cellSize, 0), Offset(x * cellSize, size.height), borderPaint);
    }
    for (int y = 0; y <= rows; y++) {
      canvas.drawLine(Offset(0, y * cellSize), Offset(size.width, y * cellSize), borderPaint);
    }

    // 一番外側の枠線を太く描画してはっきりとわかるようにする
    canvas.drawRect(Rect.fromLTWH(0, 0, cols * cellSize, rows * cellSize), outerBorderPaint);
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    return true;
  }
}
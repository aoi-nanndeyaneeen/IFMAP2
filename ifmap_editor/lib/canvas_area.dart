import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'config.dart';
import 'map_cell.dart';

class CanvasArea extends StatelessWidget {
  final List<List<MapCell>> grid;
  final List<List<MapCell>> roomGroups;
  final int brushType;
  final Uint8List? bgImageBytes;
  final GlobalKey? gridKey;
  final TransformationController? transformController;
  final int? dragStartX, dragStartY, dragCurrentX, dragCurrentY;
  final Function(int, int, int, Offset, Offset, double) onPointerDown;
  final Function(int, int, int, Offset, Offset, double) onPointerMove;
  final VoidCallback onPointerUp;

  const CanvasArea({
    super.key,
    required this.grid,
    required this.roomGroups,
    required this.brushType,
    required this.bgImageBytes,
    this.gridKey,
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
        double baseCellWidth = constraints.maxWidth / AppConfig.cols;
        double baseCellHeight = constraints.maxHeight / AppConfig.rows;
        double baseSize = baseCellWidth < baseCellHeight ? baseCellWidth : baseCellHeight;
        if (baseSize < 20.0) baseSize = 20.0;

        double cellSize = baseSize;
        double totalWidth = cellSize * AppConfig.cols;
        double totalHeight = cellSize * AppConfig.rows;

        void resolvePointer(PointerEvent event, Function(int, int, int, Offset, Offset, double) action) {
          int x = (event.localPosition.dx / cellSize).floor();
          int y = (event.localPosition.dy / cellSize).floor();
          if (x >= 0 && x < AppConfig.cols && y >= 0 && y < AppConfig.rows) action(y, x, event.buttons, event.localPosition, event.position, cellSize);
        }

        List<Widget> roomWidgets = [];
        for (var group in roomGroups) {
          if (group.isEmpty) continue;
          
          int minX = group.first.x, maxX = group.first.x;
          int minY = group.first.y, maxY = group.first.y;
          for (var c in group) {
            if (c.x < minX) minX = c.x;
            if (c.x > maxX) maxX = c.x;
            if (c.y < minY) minY = c.y;
            if (c.y > maxY) maxY = c.y;
          }
          
          double centerX = (minX + maxX + 1) / 2.0 * cellSize;
          double centerY = (minY + maxY + 1) / 2.0 * cellSize;
          
          MapCell rep = group.first;
          IconData iconData = Icons.meeting_room;
          if (rep.type == 3) iconData = Icons.meeting_room;
          if (rep.type == 4) iconData = Icons.stairs;
          if (rep.type == 5) iconData = Icons.sync_alt;

          double groupWidth = (maxX - minX + 1) * cellSize;
          double groupHeight = (maxY - minY + 1) * cellSize;
          
          double baseSizeLabel = groupWidth < groupHeight ? groupWidth : groupHeight;
          baseSizeLabel = baseSizeLabel * AppConfig.labelSizeRatio;
          if (baseSizeLabel < AppConfig.labelMinSize) baseSizeLabel = AppConfig.labelMinSize;
          if (baseSizeLabel > AppConfig.labelMaxSize) baseSizeLabel = AppConfig.labelMaxSize;

          String formatName(String name) {
            int limit = AppConfig.maxCharsPerLine;
            if (name.length <= limit) return name;
            RegExp regex = RegExp('.{1,$limit}');
            return regex.allMatches(name).map((m) => m.group(0)).join('\n');
          }

          roomWidgets.add(
            Positioned(
              left: centerX - groupWidth / 2,
              top: centerY - groupHeight / 2,
              width: groupWidth,
              height: groupHeight,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(iconData, size: baseSizeLabel, color: Colors.black87),
                        Text(
                          formatName(rep.name!),
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: baseSizeLabel * 0.7, height: 1.1),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2)),
          child: InteractiveViewer(
            transformationController: transformController,
            panEnabled: false,  // パンは中クリックのみ（Listener内で手動処理）
            scaleEnabled: true,
            trackpadScrollCausesScale: true,
            constrained: false, // 子要素が画面より大きくなるのを許可
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
                      matrix[12] += e.delta.dx;
                      matrix[13] += e.delta.dy;
                      transformController!.value = matrix;
                    }
                    return;
                  }
                  resolvePointer(e, onPointerMove);
                },
                onPointerUp: (_) => onPointerUp(),
                onPointerCancel: (_) => onPointerUp(),
                child: SizedBox(
                  key: gridKey,
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
                            brushType: brushType,
                            dragStartX: dragStartX,
                            dragStartY: dragStartY,
                            dragCurrentX: dragCurrentX,
                            dragCurrentY: dragCurrentY,
                          ),
                        ),
                      ),
                      ...roomWidgets,
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
  final int brushType;
  final int? dragStartX, dragStartY, dragCurrentX, dragCurrentY;

  GridPainter({
    required this.grid,
    required this.cellSize,
    required this.brushType,
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
      ..color = Colors.grey[500]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final Paint outerBorderPaint = Paint()
      ..color = Colors.black
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
          Color tempColor = MapCell(x: x, y: y, type: brushType).color;
          color = tempColor == Colors.transparent ? Colors.grey.withValues(alpha: 0.5) : tempColor;
        }

        if (color != Colors.transparent) {
          Rect rect = Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize);
          cellPaint.color = color;
          canvas.drawRect(rect, cellPaint);
        }
      }
    }

    for (int x = 0; x <= cols; x++) {
      canvas.drawLine(Offset(x * cellSize, 0), Offset(x * cellSize, size.height), borderPaint);
    }
    for (int y = 0; y <= rows; y++) {
      canvas.drawLine(Offset(0, y * cellSize), Offset(size.width, y * cellSize), borderPaint);
    }

    final Paint wallPaint = Paint()
      ..color = Colors.red.shade900
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.square;

    final Paint doorPaint = Paint()
      ..color = Colors.orange.shade800
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        MapCell cell = grid[y][x];
        if (cell.wallTop)    canvas.drawLine(Offset(x*cellSize, y*cellSize), Offset((x+1)*cellSize, y*cellSize), wallPaint);
        if (cell.wallBottom) canvas.drawLine(Offset(x*cellSize, (y+1)*cellSize), Offset((x+1)*cellSize, (y+1)*cellSize), wallPaint);
        if (cell.wallLeft)   canvas.drawLine(Offset(x*cellSize, y*cellSize), Offset(x*cellSize, (y+1)*cellSize), wallPaint);
        if (cell.wallRight)  canvas.drawLine(Offset((x+1)*cellSize, y*cellSize), Offset((x+1)*cellSize, (y+1)*cellSize), wallPaint);

        if (cell.doorTop)    canvas.drawLine(Offset(x*cellSize, y*cellSize), Offset((x+1)*cellSize, y*cellSize), doorPaint);
        if (cell.doorBottom) canvas.drawLine(Offset(x*cellSize, (y+1)*cellSize), Offset((x+1)*cellSize, (y+1)*cellSize), doorPaint);
        if (cell.doorLeft)   canvas.drawLine(Offset(x*cellSize, y*cellSize), Offset(x*cellSize, (y+1)*cellSize), doorPaint);
        if (cell.doorRight)  canvas.drawLine(Offset((x+1)*cellSize, y*cellSize), Offset((x+1)*cellSize, (y+1)*cellSize), doorPaint);
      }
    }

    canvas.drawRect(Rect.fromLTWH(0, 0, cols * cellSize, rows * cellSize), outerBorderPaint);
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    return true;
  }
}
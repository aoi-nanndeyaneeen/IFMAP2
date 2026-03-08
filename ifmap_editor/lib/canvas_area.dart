// lib/canvas_area.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'config.dart';
import 'map_cell.dart';

class CanvasArea extends StatelessWidget {
  final List<List<MapCell>> grid;
  final int currentBrush;
  final Uint8List? bgImageBytes;
  final int? dragStartX, dragStartY, dragCurrentX, dragCurrentY;
  final Function(int, int) onPointerDown;
  final Function(int, int) onPointerMove;
  final VoidCallback onPointerUp;

  const CanvasArea({
    super.key,
    required this.grid,
    required this.currentBrush,
    required this.bgImageBytes,
    this.dragStartX, this.dragStartY, this.dragCurrentX, this.dragCurrentY,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          double cellWidth = constraints.maxWidth / AppConfig.cols;
          double cellHeight = constraints.maxHeight / AppConfig.rows;

          void resolvePointer(PointerEvent event, Function(int, int) action) {
            int x = (event.localPosition.dx / cellWidth).floor();
            int y = (event.localPosition.dy / cellHeight).floor();
            if (x >= 0 && x < AppConfig.cols && y >= 0 && y < AppConfig.rows) action(y, x);
          }

          return Listener(
            onPointerDown: (e) => resolvePointer(e, onPointerDown),
            onPointerMove: (e) => resolvePointer(e, onPointerMove),
            onPointerUp: (_) => onPointerUp(),
            child: Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                if (bgImageBytes != null) Image.memory(bgImageBytes!, fit: BoxFit.contain),
                _buildGridView(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: AppConfig.cols,
        childAspectRatio: 1.0,
      ),
      itemCount: AppConfig.rows * AppConfig.cols,
      itemBuilder: (context, index) {
        int y = index ~/ AppConfig.cols;
        int x = index % AppConfig.cols;
        return _buildSingleCell(grid[y][x]);
      },
    );
  }

  Widget _buildSingleCell(MapCell cell) {
    Color cellColor = cell.color;
    if (dragStartX != null && dragStartY != null && dragCurrentX != null && dragCurrentY != null) {
      int minX = dragStartX! < dragCurrentX! ? dragStartX! : dragCurrentX!;
      int maxX = dragStartX! > dragCurrentX! ? dragStartX! : dragCurrentX!;
      int minY = dragStartY! < dragCurrentY! ? dragStartY! : dragCurrentY!;
      int maxY = dragStartY! > dragCurrentY! ? dragStartY! : dragCurrentY!;
      if (cell.x >= minX && cell.x <= maxX && cell.y >= minY && cell.y <= maxY) {
        cellColor = currentBrush == 2 ? Colors.blue.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.8);
      }
    }

    String formatName(String name) {
      int limit = AppConfig.maxCharsPerLine;
      if (name.length <= limit) return name;
      RegExp regex = RegExp('.{1,$limit}');
      return regex.allMatches(name).map((m) => m.group(0)).join('\n');
    }

    return Container(
      decoration: BoxDecoration(
        color: cellColor,
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3), width: 0.5),
      ),
      child: (cell.name != null)
          ? OverflowBox(
              maxWidth: 120, maxHeight: 80,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(cell.type == 4 ? Icons.stairs : Icons.location_on, size: 14, color: Colors.black87),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(2)),
                    child: Text(formatName(cell.name!), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 10, height: 1.1)),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
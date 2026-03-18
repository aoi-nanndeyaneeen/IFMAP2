// lib/tool_palette.dart
import 'package:flutter/material.dart';

class ToolPalette extends StatelessWidget {
  final int currentBrush;
  final Function(int) onBrushSelected;

  const ToolPalette({
    super.key,
    required this.currentBrush,
    required this.onBrushSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: Colors.grey[200],
      child: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('ブラシを選択', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          _buildBrushButton(1, '通路 (なぞり塗り)', Colors.blue, Icons.edit),
          _buildBrushButton(2, '通路 (長方形選択)', Colors.blue[800]!, Icons.crop_square),
          const Divider(),
          _buildBrushButton(3, '★ 目的地・QR (黄)', Colors.yellow.shade700, Icons.location_on),
          _buildBrushButton(4, '▲ 階段 (緑)', Colors.green, Icons.stairs), // 階段追加！
          const Divider(),
          _buildBrushButton(5, '手のひら (移動・拡大縮小)', Colors.orange, Icons.pan_tool),
          const Divider(),
          _buildBrushButton(0, '消しゴム (なぞり)', Colors.white, Icons.edit),
          _buildBrushButton(-1, '消しゴム (長方形)', Colors.grey[400]!, Icons.crop_square),
        ],
      ),
    );
  }

  Widget _buildBrushButton(int brushType, String label, Color color, IconData icon) {
    final isSelected = currentBrush == brushType;
    return InkWell(
      onTap: () => onBrushSelected(brushType),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        color: isSelected ? Colors.blue.withValues(alpha: 0.2) : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.6),
                border: Border.all(color: Colors.black54),
              ),
              child: Icon(icon, size: 18, color: Colors.black87),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );
  }
}
// ifmap_editor/lib/tool_palette.dart
import 'package:flutter/material.dart';
import 'config.dart';

class ToolPalette extends StatelessWidget {
  final int currentBrush;
  final Function(int) onBrushSelected;

  const ToolPalette({super.key, required this.currentBrush, required this.onBrushSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: Colors.grey[200],
      child: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text(
            '縮尺: 1マス=${AppConfig.metersPerCell}m\n'
            'キャンバス: ${AppConfig.cols}×${AppConfig.rows}マス\n'
            '= ${(AppConfig.cols*AppConfig.metersPerCell).toStringAsFixed(0)}m × ${(AppConfig.rows*AppConfig.metersPerCell).toStringAsFixed(0)}m',
            style: const TextStyle(fontSize: 10, color: Colors.black54),
          ),
        ),
        const Divider(),
        _btn(1,  '通路 (なぞり)',    Colors.blue,              Icons.edit),
        _btn(2,  '通路 (矩形)',      Colors.blue.shade800,     Icons.crop_square),
        const Divider(),
        _btn(3,  '★ 目的地/QR (黄)',Colors.yellow.shade700,   Icons.location_on),
        _btn(4,  '▲ 階段 (緑)',      Colors.green,             Icons.stairs),
        _btn(5,  '⇄ 接続点 (紫)',    Colors.deepPurple,        Icons.sync_alt),
        const Divider(),
        _btn(0,  '消しゴム (なぞり)', Colors.white,             Icons.edit_off),
        _btn(-1, '消しゴム (矩形)',   Colors.grey.shade400,     Icons.crop_square),
      ]),
    );
  }

  Widget _btn(int brush, String label, Color color, IconData icon) {
    final sel = currentBrush == brush;
    return InkWell(
      onTap: () => onBrushSelected(brush),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        color: sel ? Colors.blue.withValues(alpha: 0.2) : Colors.transparent,
        child: Row(children: [
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.7), border: Border.all(color: Colors.black45)),
            child: Icon(icon, size: 16, color: Colors.black87),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
          if (sel) const Icon(Icons.check, size: 14, color: Colors.blue),
        ]),
      ),
    );
  }
}
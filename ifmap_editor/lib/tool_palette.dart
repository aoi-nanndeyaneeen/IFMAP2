import 'package:flutter/material.dart';
import 'config.dart';

class ToolPalette extends StatelessWidget {
  final int brushType;
  final String drawMode;
  final bool fillMode;
  final Function(int) onTypeSelected;
  final Function(String) onModeSelected;
  final VoidCallback onFillToggled;

  const ToolPalette({
    super.key,
    required this.brushType,
    required this.drawMode,
    required this.fillMode,
    required this.onTypeSelected,
    required this.onModeSelected,
    required this.onFillToggled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      color: Colors.grey[200],
      child: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text(
            'キャンバス: ${AppConfig.cols}×${AppConfig.rows}マス',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        const Divider(),

        // ─── 描画モード切替 ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            Expanded(child: _modeBtn('stroke', Icons.edit, 'なぞり')),
            const SizedBox(width: 6),
            Expanded(child: _modeBtn('rect',   Icons.crop_square, '範囲')),
          ]),
        ),

        // ─── 塗りモードトグル ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: InkWell(
            onTap: onFillToggled,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
              decoration: BoxDecoration(
                color: fillMode ? Colors.green.withValues(alpha: 0.2) : Colors.white,
                border: Border.all(color: fillMode ? Colors.green.shade700 : Colors.grey.shade400),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                Icon(Icons.format_color_fill, size: 16,
                    color: fillMode ? Colors.green.shade700 : Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(child: Text('空白のみ塗る',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: fillMode ? FontWeight.bold : FontWeight.normal,
                        color: fillMode ? Colors.green.shade800 : Colors.grey.shade700))),
                Icon(fillMode ? Icons.toggle_on : Icons.toggle_off,
                    size: 20,
                    color: fillMode ? Colors.green.shade700 : Colors.grey.shade500),
              ]),
            ),
          ),
        ),
        const Divider(),

        // ─── ブラシタイプ ────────────────────────────────────────────
        _typeBtn(1, '通路',         Colors.blue.shade600,    Icons.linear_scale),
        _typeBtn(3, '部屋 (★)',     Colors.yellow.shade700,  Icons.meeting_room),
        _typeBtn(4, '階段 (▲)',     Colors.green.shade600,   Icons.stairs),
        _typeBtn(5, '接続点 (⇄)',   Colors.deepPurple,       Icons.sync_alt),
        _typeBtn(6, '屋外(芝生)',   Colors.lightGreen.shade700, Icons.park),
        const Divider(),
        _typeBtn(0, '消しゴム',     Colors.grey.shade400,    Icons.delete_outline),
        const Divider(),
        _typeBtn(7, '壁 (境界)',    Colors.red.shade900,     Icons.border_outer),
        _typeBtn(8, '扉 (境界)',    Colors.orange.shade800,  Icons.door_front_door),
        const Divider(),
        _typeBtn(9, '名前の変更',   Colors.teal.shade600,    Icons.edit_note),
      ]),
    );
  }

  Widget _modeBtn(String mode, IconData icon, String label) {
    final sel = drawMode == mode;
    return InkWell(
      onTap: () => onModeSelected(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: sel ? Colors.blue.withValues(alpha: 0.2) : Colors.white,
          border: Border.all(color: sel ? Colors.blue : Colors.grey.shade400),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: sel ? Colors.blue : Colors.grey.shade600),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: sel ? FontWeight.bold : FontWeight.normal,
            color: sel ? Colors.blue : Colors.grey.shade700)),
        ]),
      ),
    );
  }

  Widget _typeBtn(int type, String label, Color color, IconData icon) {
    final sel = brushType == type;
    return InkWell(
      onTap: () => onTypeSelected(type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        color: sel ? Colors.blue.withValues(alpha: 0.15) : Colors.transparent,
        child: Row(children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.75),
              border: Border.all(color: sel ? Colors.blue : Colors.black38, width: sel ? 2 : 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label,
            style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.bold : FontWeight.normal))),
          if (sel) const Icon(Icons.check, size: 14, color: Colors.blue),
        ]),
      ),
    );
  }
}
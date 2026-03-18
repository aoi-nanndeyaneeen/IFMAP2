// lib/waypoint_panel.dart
import 'package:flutter/material.dart';
import 'step_tracker.dart'; // GateInfo

/// 入退室ゲートをTodoリスト式で表示するウィジェット。
/// 現在のゲート（nextGate）の確認ボタンが押されるまでセンサーはそこで停止する。
class WaypointPanel extends StatelessWidget {
  final List<GateInfo> orderedGates; // ルート順のゲート一覧
  final Set<String>    passed;       // 確認済みゲートのkey集合
  final GateInfo?      nextGate;     // 現在止まっているゲート（nullなら自由移動中）
  final void Function(String gateKey) onConfirm;
  final VoidCallback? onArrived;

  const WaypointPanel({
    super.key,
    required this.orderedGates,
    required this.passed,
    required this.nextGate,
    required this.onConfirm,
    this.onArrived,
  });

  @override
  Widget build(BuildContext context) {
    if (orderedGates.isEmpty && onArrived == null) return const SizedBox.shrink();
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (orderedGates.isNotEmpty) ...[
            const Text('🚪 経路チェックポイント',
                style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ...orderedGates.map((g) => _buildRow(g)),
            const SizedBox(height: 4),
          ],
          if (onArrived != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onArrived,
                icon: const Icon(Icons.flag_rounded),
                label: const Text('目的地に到着しました！'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(GateInfo g) {
    final done   = passed.contains(g.key);
    final isNext = g.key == nextGate?.key;

    // ── 確認済み ───────────────────────────────────────────────
    if (done) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(Icons.check_circle, size: 18, color: Colors.green.shade400),
          const SizedBox(width: 8),
          Text(g.label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500,
                  decoration: TextDecoration.lineThrough)),
        ]),
      );
    }

    // ── 現在のゲート（確認ボタン） ─────────────────────────────
    if (isNext) {
      Color btnColor = Colors.blue.shade600;
      if (g.isDoor) btnColor = Colors.orange.shade800;
      else if (!g.isEnter) btnColor = Colors.teal.shade600;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => onConfirm(g.key),
            icon: Icon(g.isDoor ? Icons.door_front_door : (g.isEnter ? Icons.login : Icons.logout), size: 18),
            label: Text('${g.label}  →  タップ',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: btnColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      );
    }

    // ── 未来のゲート ───────────────────────────────────────────
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(g.isDoor ? Icons.door_front_door : (g.isEnter ? Icons.login : Icons.logout),
            size: 16, color: Colors.grey.shade400),
        const SizedBox(width: 8),
        Text(g.label, style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
      ]),
    );
  }
}
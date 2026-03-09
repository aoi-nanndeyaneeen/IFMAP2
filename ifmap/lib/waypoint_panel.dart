// lib/waypoint_panel.dart
import 'package:flutter/material.dart';

/// ルート上の名前付きノードを通過チップ＋到着ボタンで表示するウィジェット
class WaypointPanel extends StatelessWidget {
  final List<String> waypoints; // 経路上の名前付きノード（node_xxx 以外）
  final Set<String> passed;     // 通過済みノード
  final void Function(String) onTap;
  final VoidCallback? onArrived; // nullなら到着ボタン非表示

  const WaypointPanel({
    super.key,
    required this.waypoints,
    required this.passed,
    required this.onTap,
    this.onArrived,
  });

  @override
  Widget build(BuildContext context) {
    if (waypoints.isEmpty && onArrived == null) return const SizedBox.shrink();

    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 通過点チップ ──────────────────────────────────────
          if (waypoints.isNotEmpty) ...[
            const Text(
              '📌 経路上の場所を通過したらタップ → 現在地が更新されます',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
            const SizedBox(height: 2),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: waypoints.map((wp) {
                  final done = passed.contains(wp);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 2),
                    child: FilterChip(
                      label: Text(wp, style: const TextStyle(fontSize: 12)),
                      selected: done,
                      selectedColor: Colors.green.shade200,
                      checkmarkColor: Colors.green.shade800,
                      avatar: done ? null : const Icon(Icons.place_outlined, size: 14),
                      showCheckmark: true,
                      onSelected: (_) => onTap(wp),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // ── 到着ボタン ────────────────────────────────────────
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
}
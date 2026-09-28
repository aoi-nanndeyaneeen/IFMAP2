// lib/ui/waypoint_panel.dart
import 'package:flutter/material.dart';

import '../sensors/step_tracker.dart'; // GateInfo

/// 次に通るチェックポイントを1つだけ出すパネル。
///
/// 歩数だけで推測した現在地は必ずずれていくので、部屋の出入口や扉を
/// 通ったところでタップしてもらい、そこで位置を確定させる。
/// タップされるまで歩数は次のチェックポイントより先へ進まない。
///
/// 一覧をぜんぶ出さないのは、歩きながら見る画面で選択肢を増やすと
/// 「今どれを押せばいいのか」が分からなくなるため。
class WaypointPanel extends StatelessWidget {
  /// ルート順のチェックポイント一覧。進捗の分母に使う。
  final List<GateInfo> orderedGates;

  /// 確認済みのチェックポイントのkey集合。進捗の分子に使う。
  final Set<String> passed;

  /// いま止まっているチェックポイント。null なら自由に進んでよい。
  final GateInfo? nextGate;

  final void Function(String gateKey) onConfirm;

  /// 目的地が別フロアで、このフロアでやることが終わっているとき、
  /// 次に進むフロアのラベル。
  final String? crossFloorLabel;
  final VoidCallback? onCrossFloor;

  const WaypointPanel({
    super.key,
    required this.orderedGates,
    required this.passed,
    required this.nextGate,
    required this.onConfirm,
    this.crossFloorLabel,
    this.onCrossFloor,
  });

  @override
  Widget build(BuildContext context) {
    final gate = nextGate;
    final showCrossFloor = crossFloorLabel != null && gate == null;
    if (gate == null && !showCrossFloor) return const SizedBox.shrink();

    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (gate != null) ...[
            Text(
              '🚪 経路チェックポイント '
              '(${passed.length + 1}/${orderedGates.length})',
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            _GateButton(gate: gate, onConfirm: onConfirm),
          ],
          if (showCrossFloor)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onCrossFloor,
                icon: const Icon(Icons.sync_alt),
                label: Text('接続点に到達 → $crossFloorLabel へ進む'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
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

class _GateButton extends StatelessWidget {
  final GateInfo gate;
  final void Function(String gateKey) onConfirm;

  const _GateButton({required this.gate, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final color = gate.isDoor
        ? Colors.orange.shade800
        : (gate.isEnter ? Colors.blue.shade600 : Colors.teal.shade600);
    final icon = gate.isDoor
        ? Icons.door_front_door
        : (gate.isEnter ? Icons.login : Icons.logout);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => onConfirm(gate.key),
          icon: Icon(icon, size: 18),
          label: Text('${gate.label}  →  タップ',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
    );
  }
}

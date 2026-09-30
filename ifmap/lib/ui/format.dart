// lib/ui/format.dart
//
// 距離・時間の表記と、案内の種類ごとのアイコン。
import 'package:flutter/material.dart';

import '../navigation/route_guide.dart';

/// 距離の表記。近いほど細かく、遠いほど丸める（歩数の推定なので
/// 1m 単位の精度はない。細かすぎる数字は信用を落とす）。
String formatMeters(double m) {
  if (m < 1) return '1 m';
  if (m < 20) return '${m.round()} m';
  if (m < 100) return '${(m / 5).round() * 5} m';
  if (m < 1000) return '${(m / 10).round() * 10} m';
  return '${(m / 1000).toStringAsFixed(1)} km';
}

/// 所要時間の表記（切り上げ、最低1分）。
String formatMinutes(double seconds) {
  final min = (seconds / 60).ceil().clamp(1, 999);
  if (min < 60) return '$min 分';
  return '${min ~/ 60} 時間 ${min % 60} 分';
}

/// 到着予定の時刻（例: 10:42 着）。
String formatArrival(double seconds, {DateTime? now}) {
  // 分に四捨五入する（10:41:30 着 → 10:42 着）。
  final t = (now ?? DateTime.now()).add(Duration(seconds: seconds.round() + 30));
  return '${t.hour}:${t.minute.toString().padLeft(2, '0')} 着';
}

/// 次の案内までの距離の言い方。
String formatStepDistance(double m) {
  if (m < 3) return 'まもなく';
  return '${formatMeters(m)} 先';
}

IconData maneuverIcon(Maneuver m) => switch (m) {
      Maneuver.depart => Icons.navigation,
      Maneuver.slightLeft => Icons.turn_slight_left,
      Maneuver.left => Icons.turn_left,
      Maneuver.sharpLeft => Icons.turn_sharp_left,
      Maneuver.slightRight => Icons.turn_slight_right,
      Maneuver.right => Icons.turn_right,
      Maneuver.sharpRight => Icons.turn_sharp_right,
      Maneuver.uTurn => Icons.u_turn_left,
      Maneuver.enterRoom => Icons.login,
      Maneuver.exitRoom => Icons.logout,
      Maneuver.door => Icons.door_front_door,
      Maneuver.checkpoint => Icons.pin_drop,
      Maneuver.exitBuilding => Icons.park,
      Maneuver.enterBuilding => Icons.apartment,
      Maneuver.connector => Icons.swap_horiz,
      Maneuver.stairsUp => Icons.stairs,
      Maneuver.stairsDown => Icons.stairs,
      Maneuver.transfer => Icons.swap_horiz,
      Maneuver.arrive => Icons.sports_score,
    };

/// チェックポイントの種類ごとの色（地図の印と案内でそろえる）。
Color checkpointColor(Maneuver m) => switch (m) {
      Maneuver.door => const Color(0xFFE37400),
      Maneuver.checkpoint => const Color(0xFF5F6368),
      Maneuver.slightLeft ||
      Maneuver.left ||
      Maneuver.sharpLeft ||
      Maneuver.slightRight ||
      Maneuver.right ||
      Maneuver.sharpRight ||
      Maneuver.uTurn =>
        const Color(0xFF1A73E8),
      Maneuver.enterRoom => const Color(0xFF1A73E8),
      Maneuver.exitRoom => const Color(0xFF0B7A83),
      Maneuver.exitBuilding || Maneuver.enterBuilding => const Color(0xFF188038),
      _ => const Color(0xFF7B4FC9),
    };

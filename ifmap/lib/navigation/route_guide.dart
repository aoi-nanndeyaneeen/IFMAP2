// lib/navigation/route_guide.dart
//
// 経路から「次に何をすればいいか」の案内文を組み立てる。UIを知らない。
//
// 材料は3つ。
//   曲がり角     … turn_matching の extractCorners（線をならした後の角）
//   チェックポイント … StepTracker のゲート（部屋・扉・屋外の出入り）
//   フロアの終わり   … 目的地に着く、または階段で次の階へ
// これを経路上の距離の順に並べたものが案内の一覧になる。
//
// チェックポイントは歩数がそこで止まる（通過をタップしてもらう）ので、
// 距離ではなく「確認されたか」で済んだかどうかを決める。
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../sensors/step_tracker.dart' show GateInfo;
import '../sensors/turn_matching.dart' show RouteCorner;

enum Maneuver {
  depart,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
  uTurn,
  enterRoom,
  exitRoom,
  door,
  checkpoint,
  exitBuilding,
  enterBuilding,
  connector,
  stairsUp,
  stairsDown,
  transfer,
  arrive,
}

@immutable
class GuideStep {
  final Maneuver maneuver;

  /// 経路の始点からの距離(JSON-px)。
  final double at;

  /// 大きく出す一言（例: 右へ曲がる）。
  final String title;

  /// 補足（例: 「211講義室」に入る）。
  final String? subtitle;

  /// チェックポイントなら、その通過確認に使うキー。
  final String? gateKey;

  const GuideStep({
    required this.maneuver,
    required this.at,
    required this.title,
    this.subtitle,
    this.gateKey,
  });

  bool get isCheckpoint => gateKey != null;

  bool get isFinal =>
      maneuver == Maneuver.arrive ||
      maneuver == Maneuver.stairsUp ||
      maneuver == Maneuver.stairsDown ||
      maneuver == Maneuver.transfer;

  @override
  String toString() => 'GuideStep($maneuver @${at.toStringAsFixed(0)} $title)';
}

class RouteGuide {
  RouteGuide._();

  /// 始点・終点のすぐそばの曲がり角は案内しない（JSON-px）。
  /// 部屋の中心から扉へ向かう最初の曲がりや、着く直前の曲がりは
  /// 見ればわかるし、案内が細かすぎると読まれなくなる。
  static const double _edgeMarginPx = 1.0 / AppConfig.metersPerPx;

  static List<GuideStep> build({
    required List<RouteCorner> corners,
    required List<GateInfo> gates,
    required double totalPx,
    required GuideStep end,
  }) {
    final steps = <GuideStep>[];
    for (final c in corners) {
      if (c.distance < _edgeMarginPx || c.distance > totalPx - _edgeMarginPx) {
        continue;
      }
      final m = _turnManeuver(c.turn);
      if (m == null) continue;
      steps.add(GuideStep(maneuver: m, at: c.distance, title: _turnTitle(m)));
    }
    for (final g in gates) {
      // 「現在地を確認」は案内ではなく、位置を合わせる目印でしかない。
      // 案内の手順に混ぜると、次に曲がる場所が見えなくなる。
      if (g.isCheck) continue;
      steps.add(gateStep(g));
    }
    // 同じ距離ならチェックポイントを先に（先に確認してもらう）。
    steps.sort((a, b) {
      final d = a.at.compareTo(b.at);
      if (d != 0) return d;
      return (a.isCheckpoint ? 0 : 1).compareTo(b.isCheckpoint ? 0 : 1);
    });
    steps.add(end);
    return steps;
  }

  /// いま案内すべき手順の番号。
  ///
  /// チェックポイントは確認されるまで「いまの手順」のまま残る
  /// （歩数はそこで止まるので、距離では済んだと判定できない）。
  static int currentIndex(
      List<GuideStep> steps, double traveledPx, Set<String> passedGates) {
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      if (s.isCheckpoint) {
        if (!passedGates.contains(s.gateKey)) return i;
        continue;
      }
      if (s.isFinal) return i;
      // 角を曲がり終えた（少し過ぎた）ら次へ。
      if (s.at > traveledPx - 10) return i;
    }
    return steps.isEmpty ? -1 : steps.length - 1;
  }

  static Maneuver? _turnManeuver(double turn) {
    final a = turn.abs();
    if (a < 30) return null;
    final right = turn > 0;
    if (a < 65) return right ? Maneuver.slightRight : Maneuver.slightLeft;
    if (a < 135) return right ? Maneuver.right : Maneuver.left;
    if (a < 170) return right ? Maneuver.sharpRight : Maneuver.sharpLeft;
    return Maneuver.uTurn;
  }

  static String _turnTitle(Maneuver m) => switch (m) {
        Maneuver.slightRight => '斜め右へ',
        Maneuver.slightLeft => '斜め左へ',
        Maneuver.right => '右へ曲がる',
        Maneuver.left => '左へ曲がる',
        Maneuver.sharpRight => '大きく右へ',
        Maneuver.sharpLeft => '大きく左へ',
        Maneuver.uTurn => '引き返す',
        _ => '',
      };

  /// チェックポイント1つぶんの手順（地図の印やタップのボタンにも使う）。
  static GuideStep gateStep(GateInfo g) {
    final at = g.px ?? 0;
    final Maneuver m;
    final String title;
    String? subtitle;
    if (g.isCheck) {
      m = Maneuver.checkpoint;
      title = '現在地を確認';
      subtitle = '地図の印の場所に来たらタップ';
    } else if (g.turn != null) {
      m = _turnManeuver(g.turn!) ?? (g.turn! > 0 ? Maneuver.right : Maneuver.left);
      title = _turnTitle(m);
    } else if (g.isDoor) {
      m = Maneuver.door;
      title = '扉を通る';
    } else if (g.id == '外' && !g.isEnter) {
      m = Maneuver.exitBuilding;
      title = '建物の外に出る';
    } else if (g.id == '建物' && g.isEnter) {
      m = Maneuver.enterBuilding;
      title = '建物に入る';
    } else if (g.id == '接続点') {
      m = Maneuver.connector;
      title = '接続口に着く';
    } else if (g.isEnter) {
      m = Maneuver.enterRoom;
      title = '部屋に入る';
      subtitle = g.id.replaceAll('_', ' ');
    } else {
      m = Maneuver.exitRoom;
      title = '部屋から出る';
      subtitle = g.id.replaceAll('_', ' ');
    }
    return GuideStep(
        maneuver: m, at: at, title: title, subtitle: subtitle, gateKey: g.key);
  }
}

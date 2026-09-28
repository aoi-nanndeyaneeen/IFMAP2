// lib/routing/route_planner.dart
//
// フロアをまたぐ経路の組み立て。
//
// 1フロア内の最短経路は RouteCalculator（ダイクストラ法）に任せ、
// ここは「どのフロアをどの順に通り、どこで階をまたぐか」を決める。
//
//   例: 1F → 3F
//     1F: 出発地 → 1F/2F の接続点(または階段)
//     2F: 1F から上がってきた地点 → 2F/3F の接続点
//     3F: 上がってきた地点 → 目的地
//
// 階のまたぎ方は2通りある。
//   isConnector: エディタで connectsToMap / connectsToNode を指定した接続点。
//                行き先が明示されているので最優先。
//   isStairs   : 接続点がないときの代替。両フロアで name が一致する階段を
//                同じ階段とみなして対応づける。
import 'package:flutter/foundation.dart';

import 'route_calculator.dart';

/// 経路計算の入力。compute() を通すのでプリミティブだけで構成する。
@immutable
class RoutePlanRequest {
  /// フロアラベル -> そのフロアのノード。
  final Map<String, Map<String, dynamic>> nodesByLabel;

  /// 階移動の探索順。AppConfig.mapSections の並び。
  final List<String> sectionLabels;

  final String startId;
  final String goalId;
  final String startLabel;
  final String goalLabel;

  const RoutePlanRequest({
    required this.nodesByLabel,
    required this.sectionLabels,
    required this.startId,
    required this.goalId,
    required this.startLabel,
    required this.goalLabel,
  });

  /// 出発フロアと目的フロアの間にあるフロアだけを残す。
  ///
  /// 関係ないフロアのノードまで compute() に渡すと、ネイティブでは
  /// Isolate へのコピーが、Web では単に無駄なメモリ参照が発生する。
  /// 現状 1フロアに2万ノードあるので、この絞り込みの効果は大きい。
  RoutePlanRequest trimmed() {
    final sIdx = sectionLabels.indexOf(startLabel);
    final gIdx = sectionLabels.indexOf(goalLabel);
    if (sIdx == -1 || gIdx == -1) return this;

    final lo = sIdx < gIdx ? sIdx : gIdx;
    final hi = sIdx < gIdx ? gIdx : sIdx;
    final needed = sectionLabels.sublist(lo, hi + 1);

    return RoutePlanRequest(
      nodesByLabel: {
        for (final label in needed)
          if (nodesByLabel.containsKey(label)) label: nodesByLabel[label]!,
      },
      sectionLabels: needed,
      startId: startId,
      goalId: goalId,
      startLabel: startLabel,
      goalLabel: goalLabel,
    );
  }

  Map<String, dynamic> toMessage() => {
        'nodesByLabel': nodesByLabel,
        'sectionLabels': sectionLabels,
        'startId': startId,
        'goalId': goalId,
        'startLabel': startLabel,
        'goalLabel': goalLabel,
      };

  static RoutePlanRequest fromMessage(Map<String, dynamic> m) => RoutePlanRequest(
        nodesByLabel: (m['nodesByLabel'] as Map).cast<String, Map<String, dynamic>>(),
        sectionLabels: (m['sectionLabels'] as List).cast<String>(),
        startId: m['startId'] as String,
        goalId: m['goalId'] as String,
        startLabel: m['startLabel'] as String,
        goalLabel: m['goalLabel'] as String,
      );
}

class RoutePlanner {
  RoutePlanner._();

  /// フロアラベル -> そのフロア上で通るノードIDの並び。
  ///
  /// 重い計算なのでネイティブでは別 Isolate に逃がす。
  /// （Web に Isolate はなく compute() は同期実行になるが、
  /// 呼び出し側の書き方を分けずに済むので compute() を通す。）
  static Future<Map<String, List<String>>> planAsync(RoutePlanRequest request) {
    return compute(planFromMessage, request.trimmed().toMessage());
  }

  /// compute() 用のトップレベル相当エントリ。
  static Map<String, List<String>> planFromMessage(Map<String, dynamic> message) =>
      plan(RoutePlanRequest.fromMessage(message));

  /// 同期版。テストから直接呼ぶ。
  static Map<String, List<String>> plan(RoutePlanRequest r) {
    final result = <String, List<String>>{};

    if (r.startLabel == r.goalLabel) {
      final path = RouteCalculator.dijkstra(
          r.startId, r.goalId, r.nodesByLabel[r.startLabel] ?? const {});
      if (path.isNotEmpty) result[r.startLabel] = path;
      return result;
    }

    final sIdx = r.sectionLabels.indexOf(r.startLabel);
    final gIdx = r.sectionLabels.indexOf(r.goalLabel);
    if (sIdx == -1 || gIdx == -1) return result;

    final direction = gIdx > sIdx ? 1 : -1;
    var entryId = r.startId;

    for (var i = sIdx; direction > 0 ? i <= gIdx : i >= gIdx; i += direction) {
      final label = r.sectionLabels[i];
      final nodes = r.nodesByLabel[label] ?? const <String, dynamic>{};

      if (i == gIdx) {
        final path = RouteCalculator.dijkstra(entryId, r.goalId, nodes);
        if (path.isNotEmpty) result[label] = path;
        break;
      }

      final nextLabel = r.sectionLabels[i + direction];
      final nextNodes = r.nodesByLabel[nextLabel] ?? const <String, dynamic>{};

      // 接続点があればそれを使い、なければ名前の一致する階段を使う。
      final connectors = connectorsTo(nodes, nextLabel);
      final exits = connectors.isNotEmpty
          ? connectors
          : matchingStairs(nodes, nextNodes);
      if (exits.isEmpty) break;

      final path = RouteCalculator.dijkstraToAny(entryId, exits, nodes);
      if (path.isEmpty) break;
      result[label] = path;

      final exitId = path.last;
      final nextEntry = connectors.contains(exitId)
          ? _connectorEntry(nextNodes, label, nodes[exitId]?['name'] as String?)
          : _stairsEntry(nextNodes, nodes[exitId]?['name'] as String?);
      if (nextEntry == null) break;
      entryId = nextEntry;
    }

    return result;
  }

  /// [toLabel] へ抜ける接続点のノードID。
  @visibleForTesting
  static Set<String> connectorsTo(Map<String, dynamic> nodes, String toLabel) {
    final out = <String>{};
    for (final e in nodes.entries) {
      final v = e.value;
      if (v is! Map || v['isConnector'] != true) continue;
      if (v['connectsToMap'] == toLabel || v['connectsToNode'] == toLabel) {
        out.add(e.key);
      }
    }
    return out;
  }

  /// 両フロアに同じ name で存在する階段のノードID（[from] 側）。
  /// 一致するものがなければ [from] 側の階段すべてを候補にする。
  @visibleForTesting
  static Set<String> matchingStairs(
      Map<String, dynamic> from, Map<String, dynamic> to) {
    final fromNames = <String>{};
    for (final v in from.values) {
      if (v is Map && v['isStairs'] == true && v['name'] != null) {
        fromNames.add(v['name'] as String);
      }
    }
    final shared = <String>{};
    for (final v in to.values) {
      if (v is Map &&
          v['isStairs'] == true &&
          v['name'] != null &&
          fromNames.contains(v['name'])) {
        shared.add(v['name'] as String);
      }
    }

    final out = <String>{};
    for (final e in from.entries) {
      final v = e.value;
      if (v is! Map || v['isStairs'] != true) continue;
      if (shared.isEmpty || shared.contains(v['name'])) out.add(e.key);
    }
    return out;
  }

  /// 接続点で上がった先のフロアでの降り口。
  /// 同じ name の接続点を優先し、なければ同じフロアを指す接続点を拾う。
  static String? _connectorEntry(
      Map<String, dynamic> nextNodes, String fromLabel, String? exitName) {
    String? fallback;
    for (final e in nextNodes.entries) {
      final v = e.value;
      if (v is! Map || v['isConnector'] != true) continue;
      if (v['connectsToMap'] != fromLabel && v['connectsToNode'] != fromLabel) {
        continue;
      }
      if (exitName != null && v['name'] == exitName) return e.key;
      fallback ??= e.key;
    }
    return fallback;
  }

  /// 階段で上がった先のフロアでの降り口（同じ name の階段）。
  static String? _stairsEntry(Map<String, dynamic> nextNodes, String? exitName) {
    if (exitName == null) return null;
    for (final e in nextNodes.entries) {
      final v = e.value;
      if (v is Map && v['isStairs'] == true && v['name'] == exitName) {
        return e.key;
      }
    }
    return null;
  }
}

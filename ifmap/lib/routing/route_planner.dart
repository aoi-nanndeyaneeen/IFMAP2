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
//
// どの階段を使うかは、通るフロアを「フロア番号つきの1つのグラフ」として
// まとめて最短経路を探して決める。フロアごとに最寄りの階段を選ぶと、
// 降りた先のフロアで目的地側へ歩いて行けない（同じフロアでも通路が
// つながっていない棟がある）ときに行き止まりへ案内してしまうため。
// 階移動の辺は次のフロアへの一方通行なので、各フロアは経路上に
// ひと続きで1回だけ現れる。
import 'dart:math' as math;

import 'package:collection/collection.dart';
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
    final labels = <String>[
      for (var i = sIdx; direction > 0 ? i <= gIdx : i >= gIdx; i += direction)
        r.sectionLabels[i],
    ];
    final floors = <Map<String, dynamic>>[
      for (final label in labels) r.nodesByLabel[label] ?? const <String, dynamic>{},
    ];
    final transitions = <Map<String, String>>[
      for (var i = 0; i < labels.length - 1; i++)
        _transitions(floors[i], labels[i], floors[i + 1], labels[i + 1]),
    ];

    final path = _layeredDijkstra(floors, transitions, r.startId, r.goalId);
    if (path == null) return result;
    for (final (floor, id) in path) {
      result.putIfAbsent(labels[floor], () => <String>[]).add(id);
    }
    return result;
  }

  /// [from] フロアから [to] フロアへ抜ける出口と、そこから出た先の降り口。
  /// 出口ノードID -> [to] 側の降り口ノードID。
  static Map<String, String> _transitions(Map<String, dynamic> from,
      String fromLabel, Map<String, dynamic> to, String toLabel) {
    final out = <String, String>{};

    final connectors = connectorsTo(from, toLabel);
    if (connectors.isNotEmpty) {
      for (final id in connectors) {
        final entry =
            _connectorEntry(to, fromLabel, from[id]?['name'] as String?);
        if (entry != null) out[id] = entry;
      }
      return out;
    }

    // 同じ名前の階段はフロア内で何マスもあるので、降り口は名前ごとに
    // 最初に見つかったマスにそろえる。
    final arrivalByName = <String, String>{};
    for (final e in to.entries) {
      final v = e.value;
      if (v is Map && v['isStairs'] == true && v['name'] is String) {
        arrivalByName.putIfAbsent(v['name'] as String, () => e.key);
      }
    }
    for (final id in matchingStairs(from, to)) {
      final entry = arrivalByName[from[id]?['name']];
      if (entry != null) out[id] = entry;
    }
    return out;
  }

  /// フロア番号つきのノード (floor, id) を状態にしたダイクストラ法。
  /// フロア内は通常の辺（ユークリッド距離）、フロア間は [transitions] の
  /// 一方通行の辺（コスト0）でつなぐ。行けなければ null。
  static List<(int, String)>? _layeredDijkstra(
    List<Map<String, dynamic>> floors,
    List<Map<String, String>> transitions,
    String startId,
    String goalId,
  ) {
    final last = floors.length - 1;
    if (!floors.first.containsKey(startId) || !floors[last].containsKey(goalId)) {
      return null;
    }

    final dist = [for (var i = 0; i <= last; i++) <String, double>{}];
    final prev = [for (var i = 0; i <= last; i++) <String, (int, String)>{}];
    final done = [for (var i = 0; i <= last; i++) <String>{}];
    final queue = PriorityQueue<(double, int, String)>((a, b) => a.$1.compareTo(b.$1));

    void relax(int floor, String id, double d, (int, String) from) {
      if (d < (dist[floor][id] ?? double.infinity)) {
        dist[floor][id] = d;
        prev[floor][id] = from;
        queue.add((d, floor, id));
      }
    }

    dist[0][startId] = 0;
    queue.add((0, 0, startId));

    while (queue.isNotEmpty) {
      final (d, floor, id) = queue.removeFirst();
      if (!done[floor].add(id)) continue;
      if (floor == last && id == goalId) break;

      final nodes = floors[floor];
      final node = nodes[id];
      if (node is! Map) continue;

      for (final e in (node['edges'] as List? ?? const [])) {
        final next = nodes[e];
        if (next is! Map) continue;
        relax(floor, e as String, d + _distance(node, next), (floor, id));
      }

      if (floor < last) {
        final arrival = transitions[floor][id];
        if (arrival != null && floors[floor + 1].containsKey(arrival)) {
          relax(floor + 1, arrival, d, (floor, id));
        }
      }
    }

    if (!done[last].contains(goalId)) return null;

    final path = <(int, String)>[];
    (int, String)? cur = (last, goalId);
    while (cur != null) {
      path.add(cur);
      cur = prev[cur.$1][cur.$2];
    }
    return path.reversed.toList();
  }

  static double _distance(Map a, Map b) {
    final dx = (a['x'] as num) - (b['x'] as num);
    final dy = (a['y'] as num) - (b['y'] as num);
    return math.sqrt(dx * dx + dy * dy);
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
}

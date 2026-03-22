// lib/route_calculator.dart
import 'dart:math';

class RouteCalculator {
  // 2点間の距離を計算
  static double _getDistance(String node1, String node2, Map<String, dynamic> nodes) {
    final double x1 = (nodes[node1]['x'] as num).toDouble();
    final double y1 = (nodes[node1]['y'] as num).toDouble();
    final double x2 = (nodes[node2]['x'] as num).toDouble();
    final double y2 = (nodes[node2]['y'] as num).toDouble();
    return sqrt(pow(x1 - x2, 2) + pow(y1 - y2, 2));
  }

  // ダイクストラ法による最短ルート計算
  static List<String> dijkstra(String start, String goal, Map<String, dynamic> nodes) {
    Map<String, double> distances = {for (var node in nodes.keys) node: double.infinity};
    Map<String, String?> previousNodes = {for (var node in nodes.keys) node: null};
    List<String> unvisitedNodes = nodes.keys.toList();

    distances[start] = 0;

    while (unvisitedNodes.isNotEmpty) {
      unvisitedNodes.sort((a, b) => distances[a]!.compareTo(distances[b]!));
      String currentNode = unvisitedNodes.first;
      unvisitedNodes.remove(currentNode);

      if (currentNode == goal) break;

      if (nodes[currentNode] is! Map || nodes[currentNode]['edges'] == null) continue;
      for (String neighbor in nodes[currentNode]['edges']) {
        if (!unvisitedNodes.contains(neighbor)) continue;

        double altDistance = distances[currentNode]! + _getDistance(currentNode, neighbor, nodes);
        if (altDistance < distances[neighbor]!) {
          distances[neighbor] = altDistance;
          previousNodes[neighbor] = currentNode;
        }
      }
    }

    List<String> path = [];
    String? current = goal;
    while (current != null) {
      path.insert(0, current);
      // ゴールマスの手前（ドアのあるマス）で案内を終える処理
      // もし current が goal で、その previous があるなら、それを採用するが
      // 現在の IFMAP のデータ構造では goal 自体が部屋マス。
      // 部屋マスに入る直前のマスを終点としたい場合は path から goal を取り除く。
      current = previousNodes[current];
    }
    
    if (path.isNotEmpty && path.first == start) {
      // 目的地が部屋(nameあり)の場合、部屋の中心や左上マス自体をゴールにするのではなく、
      // 部屋に入るための直前のマス（通路やドア）を終点とする。
      // これにより「部屋に入ったら到着」という判定になる。
      if (path.length > 1 && nodes[goal]?['name'] != null) {
         // path.removeLast(); はしない。なぜなら WaypointPanel で最後のゲート判定（〇〇に入る）を使うため。
         // 描画上だけゴールマスの中心座標に向かわせるか、手前で終わらせるか…
         // 実は描画は MapPainter で path 全体をなぞっている。
         // ここでは素直に path を返す。到着判定は MapScreen 側で調整する。
      }
      return path;
    }
    return [];
  }
}
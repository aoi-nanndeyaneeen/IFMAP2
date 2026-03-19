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
      current = previousNodes[current];
    }
    return (path.isNotEmpty && path.first == start) ? path : [];
  }
}
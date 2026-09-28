// lib/route_calculator.dart
import 'package:collection/collection.dart';
import 'dart:math';

class RouteCalculator {
  static double _getDistance(String node1, String node2, Map<String, dynamic> nodes) {
    final double x1 = (nodes[node1]['x'] as num).toDouble();
    final double y1 = (nodes[node1]['y'] as num).toDouble();
    final double x2 = (nodes[node2]['x'] as num).toDouble();
    final double y2 = (nodes[node2]['y'] as num).toDouble();
    return sqrt(pow(x1 - x2, 2) + pow(y1 - y2, 2));
  }

  static List<String> dijkstra(String start, String goal, Map<String, dynamic> nodes) {
    if (!nodes.containsKey(start) || !nodes.containsKey(goal)) return [];
    if (start == goal) return [start];

    Map<String, double> distances = {};
    Map<String, String> previousNodes = {};
    var pq = PriorityQueue<MapEntry<String, double>>((a, b) => a.value.compareTo(b.value));

    for (String node in nodes.keys) {
      distances[node] = double.infinity;
    }
    distances[start] = 0;
    pq.add(MapEntry(start, 0.0));
    Set<String> visited = {};

    while (pq.isNotEmpty) {
      final entry = pq.removeFirst();
      final currentNode = entry.key;

      if (!visited.add(currentNode)) continue;
      if (currentNode == goal) break;

      var nodeData = nodes[currentNode];
      if (nodeData is! Map || nodeData['edges'] == null) continue;

      List<dynamic> edges = nodeData['edges'];
      for (String neighbor in edges) {
        if (!nodes.containsKey(neighbor)) continue;

        double weight = _getDistance(currentNode, neighbor, nodes);
        double tentativeDistance = distances[currentNode]! + weight;

        if (tentativeDistance < distances[neighbor]!) {
          distances[neighbor] = tentativeDistance;
          previousNodes[neighbor] = currentNode;
          pq.add(MapEntry(neighbor, tentativeDistance));
        }
      }
    }

    if (distances[goal] == double.infinity) return [];

    List<String> path = [];
    String? current = goal;
    while (current != null) {
      path.add(current);
      current = previousNodes[current];
    }
    return path.reversed.toList();
  }

  static List<String> dijkstraToAny(String start, Set<String> goals, Map<String, dynamic> nodes) {
    if (!nodes.containsKey(start) || goals.isEmpty) return [];
    if (goals.contains(start)) return [start];

    Map<String, double> distances = {};
    Map<String, String> previousNodes = {};
    var pq = PriorityQueue<MapEntry<String, double>>((a, b) => a.value.compareTo(b.value));

    for (String node in nodes.keys) {
      distances[node] = double.infinity;
    }
    distances[start] = 0;
    pq.add(MapEntry(start, 0.0));
    Set<String> visited = {};
    String? reachedGoal;

    while (pq.isNotEmpty) {
      final entry = pq.removeFirst();
      final currentNode = entry.key;

      if (!visited.add(currentNode)) continue;
      if (goals.contains(currentNode)) {
        reachedGoal = currentNode;
        break;
      }

      var nodeData = nodes[currentNode];
      if (nodeData is! Map || nodeData['edges'] == null) continue;

      List<dynamic> edges = nodeData['edges'];
      for (String neighbor in edges) {
        if (!nodes.containsKey(neighbor)) continue;

        double weight = _getDistance(currentNode, neighbor, nodes);
        double tentativeDistance = distances[currentNode]! + weight;

        if (tentativeDistance < distances[neighbor]!) {
          distances[neighbor] = tentativeDistance;
          previousNodes[neighbor] = currentNode;
          pq.add(MapEntry(neighbor, tentativeDistance));
        }
      }
    }

    if (reachedGoal == null) return [];

    List<String> path = [];
    String? current = reachedGoal;
    while (current != null) {
      path.add(current);
      current = previousNodes[current];
    }
    return path.reversed.toList();
  }
}
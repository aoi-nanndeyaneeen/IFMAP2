import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() {
  runApp(const IfMapApp());
}

class IfMapApp extends StatelessWidget {
  const IfMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ifmap',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Map<String, dynamic> nodes = {};
  Map<String, dynamic> edges = {}; // エッジ情報も読み込むように追加
  
  String? startNode;
  String? goalNode;
  List<String> currentPath = [];

  @override
  void initState() {
    super.initState();
    _loadMapData();
  }

  Future<void> _loadMapData() async {
    final String jsonString = await rootBundle.loadString('assets/map_data.json');
    final Map<String, dynamic> data = jsonDecode(jsonString);
    
    setState(() {
      nodes = data['nodes'];
      edges = data['edges'];
    });
  }

  // タップされた座標から一番近いノードを探す（Pythonの find_nearest_node と同じ）
  void _handleTap(Offset tapPosition) {
    double minDist = double.infinity;
    String? nearestNodeId;

    nodes.forEach((id, data) {
      final double dx = data['x'] - tapPosition.dx;
      final double dy = data['y'] - tapPosition.dy;
      final double dist = sqrt(dx * dx + dy * dy);

      if (dist < minDist) {
        minDist = dist;
        nearestNodeId = id;
      }
    });

    // タップ位置から半径50ピクセル以内なら選択とみなす
    if (minDist < 50 && nearestNodeId != null) {
      setState(() {
        if (startNode == null) {
          startNode = nearestNodeId;
        } else if (goalNode == null) {
          goalNode = nearestNodeId;
          _calculatePath(); // 目的地が決まったらルート計算
        } else {
          // 3回目以降のタップでリセット
          startNode = nearestNodeId;
          goalNode = null;
          currentPath = [];
        }
      });
    }
  }

  // 2点間の距離を計算
  double _getDistance(String n1, String n2) {
    final double dx = nodes[n1]['x'] - nodes[n2]['x'];
    final double dy = nodes[n1]['y'] - nodes[n2]['y'];
    return sqrt(dx * dx + dy * dy);
  }

  // ダイクストラ法（Dart版）
  void _calculatePath() {
    if (startNode == null || goalNode == null) return;

    Map<String, double> distances = {};
    Map<String, String?> previous = {};
    List<String> unvisited = nodes.keys.toList();

    for (var node in nodes.keys) {
      distances[node] = double.infinity;
    }
    distances[startNode!] = 0;

    while (unvisited.isNotEmpty) {
      // 距離が最小のノードを取り出す
      unvisited.sort((a, b) => distances[a]!.compareTo(distances[b]!));
      String current = unvisited.first;
      unvisited.remove(current);

      if (current == goalNode) break;
      if (distances[current] == double.infinity) break;

      // 繋がっているノードの距離を更新
      for (String neighbor in edges[current]) {
        double alt = distances[current]! + _getDistance(current, neighbor);
        if (alt < distances[neighbor]!) {
          distances[neighbor] = alt;
          previous[neighbor] = current;
        }
      }
    }

    // ゴールからスタートへ経路を遡る
    List<String> path = [];
    String? curr = goalNode;
    while (curr != null) {
      path.insert(0, curr);
      curr = previous[curr];
    }

    setState(() {
      currentPath = (path.isNotEmpty && path.first == startNode) ? path : [];
    });
  }

  @override
  Widget build(BuildContext context) {
    // 読み込み前はローディングぐるぐるを表示
    if (nodes.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ifmap Prototype'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        // InteractiveViewer：これで拡大縮小・スワイプ移動が可能に！
        child: InteractiveViewer(
          maxScale: 5.0, // 最大5倍まで拡大可能
          minScale: 0.1,
          constrained: false, // 画像の元のサイズ（絶対座標）を維持する設定
          child: GestureDetector(
            // タップ位置の検知（ローカル座標を取得）
            onTapUp: (details) => _handleTap(details.localPosition),
            child: CustomPaint(
              foregroundPainter: MapPainter(
                nodes: nodes,
                startNode: startNode,
                goalNode: goalNode,
                path: currentPath,
              ),
              child: Image.asset('assets/map.png'),
            ),
          ),
        ),
      ),
    );
  }
}

// 描画クラス
class MapPainter extends CustomPainter {
  final Map<String, dynamic> nodes;
  final String? startNode;
  final String? goalNode;
  final List<String> path;

  MapPainter({
    required this.nodes,
    required this.startNode,
    required this.goalNode,
    required this.path,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nodePaint = Paint()..color = Colors.grey..style = PaintingStyle.fill;
    final startPaint = Paint()..color = Colors.red..style = PaintingStyle.fill;
    final goalPaint = Paint()..color = Colors.blue..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke;

    // 1. ルートの線を引く
    if (path.length > 1) {
      for (int i = 0; i < path.length - 1; i++) {
        final p1 = Offset(nodes[path[i]]['x'].toDouble(), nodes[path[i]]['y'].toDouble());
        final p2 = Offset(nodes[path[i+1]]['x'].toDouble(), nodes[path[i+1]]['y'].toDouble());
        canvas.drawLine(p1, p2, linePaint);
      }
    }

    // 2. ノードの丸を描く
    nodes.forEach((key, value) {
      final offset = Offset(value['x'].toDouble(), value['y'].toDouble());
      
      if (key == startNode) {
        canvas.drawCircle(offset, 10.0, startPaint); // 出発地は赤で大きく
      } else if (key == goalNode) {
        canvas.drawCircle(offset, 10.0, goalPaint); // 目的地は青で大きく
      } else {
        canvas.drawCircle(offset, 5.0, nodePaint);  // その他はグレー
      }
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mobile_scanner/mobile_scanner.dart'; // ← スキャナーをインポート
import 'map_painter.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Map<String, dynamic> nodes = {};
  Map<String, dynamic> edges = {};
  
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

    if (minDist < 50 && nearestNodeId != null) {
      setState(() {
        if (startNode == null) {
          startNode = nearestNodeId;
        } else if (goalNode == null) {
          goalNode = nearestNodeId;
          _calculatePath();
        } else {
          startNode = nearestNodeId;
          goalNode = null;
          currentPath = [];
        }
      });
    }
  }

// === 修正版：2点間の距離を計算する関数 ===
  double _getDistance(String node1, String node2) {
    // (as num).toDouble() を使うことで、整数(100)でも小数(100.0)でも安全に変換します！
    final double x1 = (nodes[node1]['x'] as num).toDouble();
    final double y1 = (nodes[node1]['y'] as num).toDouble();
    final double x2 = (nodes[node2]['x'] as num).toDouble();
    final double y2 = (nodes[node2]['y'] as num).toDouble();
    
    return sqrt(pow(x1 - x2, 2) + pow(y1 - y2, 2));
  }

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
      unvisited.sort((a, b) => distances[a]!.compareTo(distances[b]!));
      String current = unvisited.first;
      unvisited.remove(current);

      if (current == goalNode) break;
      if (distances[current] == double.infinity) break;

      for (String neighbor in edges[current]) {
        double alt = distances[current]! + _getDistance(current, neighbor);
        if (alt < distances[neighbor]!) {
          distances[neighbor] = alt;
          previous[neighbor] = current;
        }
      }
    }

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

  // === QRコードスキャン画面を開く関数 ===
  // === QRコードスキャン画面を開く関数（大画面バージョン） ===
  void _openScanner() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // 現在の画面のサイズを取得
        final size = MediaQuery.of(context).size;
        
        return Dialog(
          insetPadding: const EdgeInsets.all(20), // 画面端からの余白を小さくする
          child: SizedBox(
            width: size.width * 0.9,   // 横幅は画面の90%
            height: size.height * 0.8, // 高さは画面の80%
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('現在地のQRコードをスキャン', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                // Expandedで、残りのスペースをすべてカメラに割り当てる
                Expanded(
                  child: MobileScanner(
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        final String? qrData = barcode.rawValue;
                        
                        if (qrData != null && nodes.containsKey(qrData)) {
                          Navigator.of(context).pop(); 
                          
                          setState(() {
                            startNode = qrData; 
                            if (goalNode != null) {
                              _calculatePath();
                            }
                          });
                          
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('現在地を設定しました: ${nodes[qrData]['name']}')),
                          );
                          break;
                        }
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('キャンセル', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ifmap Prototype'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              maxScale: 5.0,
              minScale: 0.1,
              constrained: false,
              child: GestureDetector(
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
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.grey),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          hint: const Text('目的地を選択してください'),
                          value: goalNode,
                          items: nodes.entries.map((entry) {
                            return DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value['name']),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            setState(() {
                              goalNode = newValue;
                              if (startNode != null) {
                                _calculatePath();
                              }
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      // === 画面右下にカメラ起動ボタンを配置 ===
      floatingActionButton: FloatingActionButton(
        onPressed: _openScanner,
        tooltip: 'QRコードをスキャン',
        child: const Icon(Icons.qr_code_scanner),
      ),
    );
  }
}
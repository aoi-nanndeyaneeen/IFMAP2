// lib/map_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'route_calculator.dart';
import 'map_painter.dart';
import 'qr_scanner_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Map<String, dynamic> nodes1F = {};
  Map<String, dynamic> nodes2F = {};
  
  String currentFloor = '1F'; 
  String? startNode;          
  String? goalNode;           
  List<String> currentPath = []; 
  
  final TransformationController _txController = TransformationController();

  @override
  void initState() {
    super.initState();
    _loadAllFloors();
  }

  Future<void> _loadAllFloors() async {
    nodes1F = jsonDecode(await rootBundle.loadString(AppConfig.map1FPath));
    nodes2F = jsonDecode(await rootBundle.loadString(AppConfig.map2FPath));
    setState(() {});
  }

  String? _getFloor(String? node) {
    if (node == null) return null;
    if (nodes1F.containsKey(node)) return '1F';
    if (nodes2F.containsKey(node)) return '2F';
    return null;
  }

  // ★修正：緑ブラシ以外でも、名前が「階段」なら階段として認識する最強の検索機能！
  String? _getStairs(String floor) {
    Map<String, dynamic> nodes = floor == '1F' ? nodes1F : nodes2F;
    for (var entry in nodes.entries) {
      if (entry.value['isStairs'] == true || entry.key == '階段' || entry.key.toLowerCase() == 'stairs') {
        return entry.key;
      }
    }
    return null;
  }

  List<String> _getAllDestinations() {
    List<String> dests = [];
    void add(Map<String, dynamic> n) => n.forEach((k, v) { if (!k.startsWith('node_') && v['isStairs'] != true) dests.add(k); });
    add(nodes1F); add(nodes2F);
    return dests.toSet().toList();
  }

  void _updatePath() {
    currentPath.clear();
    if (startNode == null || goalNode == null) return;

    String startF = _getFloor(startNode)!;
    String goalF = _getFloor(goalNode)!;
    Map<String, dynamic> currentNodes = currentFloor == '1F' ? nodes1F : nodes2F;

    if (startF == goalF) {
      if (currentFloor == startF) currentPath = RouteCalculator.dijkstra(startNode!, goalNode!, currentNodes);
    } else {
      if (currentFloor == startF) {
        String? stairs = _getStairs(startF);
        if (stairs != null) currentPath = RouteCalculator.dijkstra(startNode!, stairs, currentNodes);
      } else if (currentFloor == goalF) {
        String? stairs = _getStairs(goalF);
        if (stairs != null) currentPath = RouteCalculator.dijkstra(stairs, goalNode!, currentNodes);
      }
    }
    setState(() {});
  }

  void _focusOnNode(String nodeId) {
    Map<String, dynamic> nodes = currentFloor == '1F' ? nodes1F : nodes2F;
    if (!nodes.containsKey(nodeId)) return;
    
    double x = (nodes[nodeId]['x'] as num).toDouble();
    double y = (nodes[nodeId]['y'] as num).toDouble();
    final size = MediaQuery.of(context).size;
    double scale = 2.5; 

    _txController.value = Matrix4.identity()
      ..translate(-x * scale + size.width / 2, -y * scale + size.height / 2.5)
      ..scale(scale);
  }

  void _onQRScanned(String qrData) {
    String? floor = _getFloor(qrData);
    if (floor != null) {
      setState(() {
        startNode = qrData;
        currentFloor = floor;
        _updatePath();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusOnNode(qrData));
    }
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> currentNodes = currentFloor == '1F' ? nodes1F : nodes2F;
    String? startF = _getFloor(startNode);
    String? goalF = _getFloor(goalNode);

    return Scaffold(
      appBar: AppBar(title: Text('infacilityMAP - $currentFloor'), backgroundColor: Colors.blueGrey),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: DropdownButton<String>(
              isExpanded: true,
              hint: const Text('目的地を選択してください'),
              value: goalNode,
              items: _getAllDestinations().map((String val) => DropdownMenuItem(value: val, child: Text('$val (${_getFloor(val)})'))).toList(),
              onChanged: (String? val) => setState(() { goalNode = val; _updatePath(); }),
            ),
          ),
          
          if (startF != null && goalF != null && startF != goalF && currentFloor == startF)
            Container(
              width: double.infinity, color: Colors.green.shade100, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() { currentFloor = goalF; _updatePath(); });
                  String? stairs = _getStairs(goalF);
                  if (stairs != null) WidgetsBinding.instance.addPostFrameCallback((_) => _focusOnNode(stairs));
                },
                icon: const Icon(Icons.directions_walk),
                label: Text('階段に着いたら押して $goalF へ'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              ),
            ),

          Expanded(
            child: InteractiveViewer(
              transformationController: _txController,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              minScale: 0.1, maxScale: 5.0, constrained: false,
              child: Center(
                child: currentNodes.isEmpty ? const CircularProgressIndicator()
                    : CustomPaint(
                        size: const Size(AppConfig.mapCanvasSize, AppConfig.mapCanvasSize),
                        painter: MapPainter(nodes: currentNodes, path: currentPath, startNode: startNode, goalNode: goalNode),
                      ),
              ),
            ),
          ),
        ],
      ),
      
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: "btn1",
            onPressed: () => setState(() { currentFloor = currentFloor == '1F' ? '2F' : '1F'; _updatePath(); }),
            label: Text('$currentFloor 表示中 (切替)'),
            icon: const Icon(Icons.layers),
            backgroundColor: Colors.white,
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            heroTag: "btn2",
            onPressed: () async {
              final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const QRScannerScreen()));
              if (result != null) _onQRScanned(result);
            },
            label: const Text('QRスキャン'),
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
    );
  }
}
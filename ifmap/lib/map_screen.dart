// lib/map_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';

import 'config.dart';
import 'route_calculator.dart';
import 'map_painter.dart';
import 'qr_scanner_screen.dart';
import 'step_tracker.dart';
import 'waypoint_panel.dart';
import 'compass_indicator.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Map<String, dynamic> nodes1F = {}, nodes2F = {};
  String currentFloor = '1F';
  String? startNode, goalNode;
  List<String> currentPath = [];

  // 歩数推定
  late final StepTracker _stepTracker;
  Offset? _estimatedPosition;
  double _traveledPx = 0;
  StreamSubscription? _distSub;

  // 通過点
  List<String> _waypointsOnRoute = [];
  final Set<String> _passedWaypoints = {};

  // コンパス
  double? _heading;
  StreamSubscription? _compassSub;
  bool _showCompass = false;

  final _txController = TransformationController();

  // ─── ライフサイクル ─────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _stepTracker = StepTracker(stepLengthPx: AppConfig.stepLengthPx);
    _stepTracker.positionStream.listen((p) => setState(() => _estimatedPosition = p));
    _distSub = _stepTracker.traveledStream.listen((d) => setState(() => _traveledPx = d));
    _compassSub = FlutterCompass.events?.listen((e) {
      if (e.heading != null) setState(() => _heading = e.heading);
    });
    _loadAllFloors().then((_) => _checkUrlParameter());
  }

  @override
  void dispose() {
    _stepTracker.dispose();
    _distSub?.cancel();
    _compassSub?.cancel();
    super.dispose();
  }

  // ─── データ処理 ─────────────────────────────────────────────────

  void _checkUrlParameter() {
    try {
      final uri = Uri.base;
      if (uri.queryParameters.containsKey('start')) _onQRScanned(uri.queryParameters['start']!);
    } catch (_) {}
  }

  Future<void> _loadAllFloors() async {
    nodes1F = jsonDecode(await rootBundle.loadString(AppConfig.map1FPath));
    nodes2F = jsonDecode(await rootBundle.loadString(AppConfig.map2FPath));
    setState(() {});
  }

  Map<String, dynamic> get _cNodes => currentFloor == '1F' ? nodes1F : nodes2F;

  String? _getFloor(String? n) {
    if (n == null) return null;
    if (nodes1F.containsKey(n)) return '1F';
    if (nodes2F.containsKey(n)) return '2F';
    return null;
  }

  String? _getStairs(String floor) {
    final n = floor == '1F' ? nodes1F : nodes2F;
    for (final e in n.entries) {
      if (e.value['isStairs'] == true || e.key.toLowerCase() == 'stairs') return e.key;
    }
    return null;
  }

  List<String> _getAllDestinations() {
    final d = <String>[];
    void add(Map<String, dynamic> n) => n.forEach((k, v) {
      if (!k.startsWith('node_') && v['isStairs'] != true) d.add(k);
    });
    add(nodes1F); add(nodes2F);
    return d.toSet().toList();
  }

  void _updatePath() {
    currentPath.clear();
    _passedWaypoints.clear();
    if (startNode == null || goalNode == null) { setState(() {}); return; }

    final sF = _getFloor(startNode)!, gF = _getFloor(goalNode)!;
    if (sF == gF) {
      if (currentFloor == sF) currentPath = RouteCalculator.dijkstra(startNode!, goalNode!, _cNodes);
    } else {
      final stairs = _getStairs(currentFloor);
      if (stairs != null) {
        currentPath = currentFloor == sF
            ? RouteCalculator.dijkstra(startNode!, stairs, _cNodes)
            : RouteCalculator.dijkstra(stairs, goalNode!, _cNodes);
      }
    }

    // 経路上の名前付きノード（通過点チップに使う）
    _waypointsOnRoute = currentPath.where((id) =>
        !id.startsWith('node_') && id != startNode && id != goalNode &&
        _cNodes[id]?['isStairs'] != true).toList();

    _traveledPx = 0; _estimatedPosition = null;
    if (currentPath.isNotEmpty) _stepTracker.startTracking(currentPath, _cNodes);
    setState(() {});
  }

  void _focusOnNode(String nodeId) {
    if (!_cNodes.containsKey(nodeId)) return;
    final x = (_cNodes[nodeId]['x'] as num).toDouble();
    final y = (_cNodes[nodeId]['y'] as num).toDouble();
    final s = MediaQuery.of(context).size;
    const sc = 2.5;
    _txController.value = Matrix4.translationValues(-x * sc + s.width / 2, -y * sc + s.height / 2.5, 0)
      // ignore: deprecated_member_use
      ..scale(sc);
  }

  // ─── ユーザーアクション ──────────────────────────────────────────

  void _onQRScanned(String data) {
    final floor = _getFloor(data);
    if (floor != null) {
      setState(() { startNode = data; currentFloor = floor; _showCompass = true; });
      _updatePath();
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusOnNode(data));
    }
  }

  void _onWaypointTapped(String wp) {
    _passedWaypoints.add(wp);
    _stepTracker.advanceTo(wp);
    setState(() {});
  }

  void _onArrived() {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('🎉 到着！'),
      content: Text('「$goalNode」に到着しました！'),
      actions: [TextButton(
        onPressed: () { Navigator.pop(context); setState(() { goalNode = null; currentPath.clear(); }); },
        child: const Text('OK'),
      )],
    ));
  }

  // ─── 計算プロパティ ──────────────────────────────────────────────

  /// ルートの最初のセグメントのキャンバス角（コンパス方向案内に使用）
  double? get _routeAngleRad {
    if (currentPath.length < 2 || !_cNodes.containsKey(currentPath[0]) || !_cNodes.containsKey(currentPath[1])) return null;
    final dx = (_cNodes[currentPath[1]]['x'] as num) - (_cNodes[currentPath[0]]['x'] as num);
    final dy = (_cNodes[currentPath[1]]['y'] as num) - (_cNodes[currentPath[0]]['y'] as num);
    return atan2(dy.toDouble(), dx.toDouble());
  }

  String get _remainingText {
    if (currentPath.isEmpty || _stepTracker.totalRoutePx == 0) return '';
    final rem = (_stepTracker.totalRoutePx - _traveledPx).clamp(0.0, double.infinity);
    return 'あと約 ${(rem / AppConfig.stepLengthPx * 0.7).toStringAsFixed(0)} m';
  }

  // 85%以上進んだら到着ボタンを表示
  bool get _nearGoal => goalNode != null && _stepTracker.totalRoutePx > 0 && _traveledPx >= _stepTracker.totalRoutePx * 0.85;

  // ─── UI ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sF = _getFloor(startNode), gF = _getFloor(goalNode);
    return Scaffold(
      appBar: AppBar(title: Text('infacilityMAP - $currentFloor'), backgroundColor: Colors.blueGrey),
      body: Column(children: [
        // 目的地選択
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButton<String>(
            isExpanded: true, hint: const Text('目的地を選択してください'), value: goalNode,
            items: _getAllDestinations().map((v) => DropdownMenuItem(value: v, child: Text('$v (${_getFloor(v)})'))).toList(),
            onChanged: (v) => setState(() { goalNode = v; _updatePath(); }),
          ),
        ),

        // コンパス（QRスキャン後に表示、×で閉じる）
        if (_showCompass && currentPath.isNotEmpty)
          Row(children: [
            Expanded(child: CompassIndicator(heading: _heading, routeAngleRad: _routeAngleRad)),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _showCompass = false)),
          ]),

        // 残り距離バナー
        if (_remainingText.isNotEmpty)
          Container(
            width: double.infinity, color: Colors.cyan.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(_remainingText,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.cyan.shade800)),
          ),

        // 階段ボタン
        if (sF != null && gF != null && sF != gF && currentFloor == sF)
          Container(
            width: double.infinity, color: Colors.green.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() { currentFloor = gF; _updatePath(); });
                final s = _getStairs(gF);
                if (s != null) WidgetsBinding.instance.addPostFrameCallback((_) => _focusOnNode(s));
              },
              icon: const Icon(Icons.directions_walk),
              label: Text('階段に着いたら押して $gF へ'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            ),
          ),

        // 通過点チップ + 到着ボタン
        if (currentPath.isNotEmpty)
          WaypointPanel(
            waypoints: _waypointsOnRoute,
            passed: _passedWaypoints,
            onTap: _onWaypointTapped,
            onArrived: _nearGoal ? _onArrived : null,
          ),

        // マップ
        Expanded(
          child: InteractiveViewer(
            transformationController: _txController,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 0.1, maxScale: 5.0, constrained: false,
            child: Center(
              child: _cNodes.isEmpty
                  ? const CircularProgressIndicator()
                  : CustomPaint(
                      size: const Size(AppConfig.mapCanvasSize, AppConfig.mapCanvasSize),
                      painter: MapPainter(
                        nodes: _cNodes, path: currentPath,
                        startNode: startNode, goalNode: goalNode,
                        estimatedPosition: _estimatedPosition,
                        headingDeg: _heading,
                      ),
                    ),
            ),
          ),
        ),
      ]),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: "btn1",
            onPressed: () => setState(() { currentFloor = currentFloor == '1F' ? '2F' : '1F'; _updatePath(); }),
            label: Text('$currentFloor 表示中 (切替)'), icon: const Icon(Icons.layers), backgroundColor: Colors.white,
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            heroTag: "btn2",
            onPressed: () async {
              final r = await Navigator.push(context, MaterialPageRoute(builder: (_) => const QRScannerScreen()));
              if (r != null) _onQRScanned(r);
            },
            label: const Text('QRスキャン'), icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
    );
  }
}
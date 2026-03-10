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

  late final StepTracker _tracker;
  Offset?   _estPos;
  double    _traveled  = 0;
  GateInfo? _nextGate;
  final Set<String> _passed = {};

  double? _heading;
  bool    _showCompass = false, _followMode = false;

  final _tx     = TransformationController();
  final _mapKey = GlobalKey(); // ★ マップ領域の実サイズ取得用

  // ─── lifecycle ────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tracker = StepTracker(stepLengthPx: AppConfig.stepLengthPx);
    _tracker.positionStream.listen((p) {
      setState(() => _estPos = p);
      if (_followMode && p != null) WidgetsBinding.instance.addPostFrameCallback((_) => _centerOn(p));
    });
    _tracker.traveledStream.listen((d) => setState(() => _traveled = d));
    _tracker.nextGateStream.listen((g) => setState(() => _nextGate = g));
    FlutterCompass.events?.listen((e) { if (e.heading != null) setState(() => _heading = e.heading); });
    _loadAllFloors().then((_) => _checkUrlParameter());
  }

  @override
  void dispose() { _tracker.dispose(); super.dispose(); }

  // ─── data ─────────────────────────────────────────────────────

  void _checkUrlParameter() {
    try { final u = Uri.base; if (u.queryParameters.containsKey('start')) _onQRScanned(u.queryParameters['start']!); } catch (_) {}
  }

  Future<void> _loadAllFloors() async {
    nodes1F = jsonDecode(await rootBundle.loadString(AppConfig.map1FPath));
    nodes2F = jsonDecode(await rootBundle.loadString(AppConfig.map2FPath));
    setState(() {});
  }

  Map<String, dynamic> get _cn => currentFloor == '1F' ? nodes1F : nodes2F;
  String? _floor(String? n) { if (n==null) return null; if (nodes1F.containsKey(n)) return '1F'; if (nodes2F.containsKey(n)) return '2F'; return null; }
  String? _stairs(String f) { for (final e in (f=='1F'?nodes1F:nodes2F).entries) { if (e.value['isStairs']==true||e.key.toLowerCase()=='stairs') return e.key; } return null; }

  List<String> _destinations() {
    final d = <String>[];
    void add(Map<String, dynamic> n) => n.forEach((k, v) { if (!k.startsWith('node_') && v['isStairs'] != true) d.add(k); });
    add(nodes1F); add(nodes2F);
    return d.toSet().toList();
  }

  List<String> _nearbyWaypoints(List<String> path) {
    final r = AppConfig.waypointRadiusPx;
    final coords = path.where(_cn.containsKey)
        .map((id) => Offset((_cn[id]['x'] as num).toDouble(), (_cn[id]['y'] as num).toDouble()))
        .toList();
    final res = <String>{};
    for (final e in _cn.entries) {
      final id = e.key;
      if (id.startsWith('node_') || e.value['isStairs']==true || id==startNode || id==goalNode) continue;
      final cx = (e.value['x'] as num).toDouble(), cy = (e.value['y'] as num).toDouble();
      if (coords.any((p) => sqrt(pow(cx-p.dx,2)+pow(cy-p.dy,2)) <= r)) res.add(id);
    }
    return res.toList();
  }

  void _updatePath() {
    currentPath.clear(); _passed.clear(); _nextGate = null;
    if (startNode == null || goalNode == null) { setState(() {}); return; }
    final sF = _floor(startNode)!, gF = _floor(goalNode)!;
    if (sF == gF) {
      if (currentFloor == sF) currentPath = RouteCalculator.dijkstra(startNode!, goalNode!, _cn);
    } else {
      final s = _stairs(currentFloor);
      if (s != null) currentPath = currentFloor == sF
          ? RouteCalculator.dijkstra(startNode!, s, _cn)
          : RouteCalculator.dijkstra(s, goalNode!, _cn);
    }
    _traveled = 0; _estPos = null;
    if (currentPath.isNotEmpty) {
      _tracker.startTracking(currentPath, _cn);
      _tracker.setGates(_nearbyWaypoints(currentPath), startNode);
      _nextGate = _tracker.nextGate;
    }
    setState(() {});
  }

  // ─── display ──────────────────────────────────────────────────

  /// GlobalKeyでマップ領域の実サイズを取得し、現在地を正確に中央に表示する
  void _centerOn(Offset p) {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    final vw = box?.size.width  ?? MediaQuery.of(context).size.width;
    final vh = box?.size.height ?? MediaQuery.of(context).size.height;
    final sc = AppConfig.focusScale;
    _tx.value = Matrix4.translationValues(
      -p.dx * sc + vw / 2,
      -p.dy * sc + vh * AppConfig.focusVerticalRatio, // ★ configで調整可能
      0,
    // ignore: deprecated_member_use
    )..scale(sc);
  }

  void _focusNode(String id) {
    if (_cn.containsKey(id)) _centerOn(Offset((_cn[id]['x'] as num).toDouble(), (_cn[id]['y'] as num).toDouble()));
  }

  // ─── actions ──────────────────────────────────────────────────

  void _onQRScanned(String data) {
    final f = _floor(data);
    if (f != null) {
      setState(() { startNode = data; currentFloor = f; _showCompass = true; });
      _updatePath();
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode(data));
    }
  }

  void _onArrived() {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('🎉 到着！'), content: Text('「$goalNode」に到着しました！'),
      actions: [TextButton(
        onPressed: () { Navigator.pop(context); setState(() { goalNode = null; currentPath.clear(); _followMode = false; }); },
        child: const Text('OK'),
      )],
    ));
  }

  // ─── computed ─────────────────────────────────────────────────

  double? get _routeAngle {
    if (currentPath.length < 2 || !_cn.containsKey(currentPath[0]) || !_cn.containsKey(currentPath[1])) return null;
    return atan2(((_cn[currentPath[1]]['y'] as num)-(_cn[currentPath[0]]['y'] as num)).toDouble(),
                 ((_cn[currentPath[1]]['x'] as num)-(_cn[currentPath[0]]['x'] as num)).toDouble());
  }

  String get _remText {
    if (currentPath.isEmpty || _tracker.totalRoutePx == 0) return '';
    final rem = (_tracker.totalRoutePx - _traveled).clamp(0.0, double.infinity);
    return 'あと約 ${(rem / AppConfig.stepLengthPx * 0.7).toStringAsFixed(0)} m';
  }

  bool get _nearGoal => goalNode != null && _tracker.totalRoutePx > 0 && _traveled >= _tracker.totalRoutePx * 0.85;

  // ─── build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sF = _floor(startNode), gF = _floor(goalNode);
    return Scaffold(
      appBar: AppBar(title: Text('infacilityMAP - $currentFloor'), backgroundColor: Colors.blueGrey),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButton<String>(
            isExpanded: true, hint: const Text('目的地を選択してください'), value: goalNode,
            items: _destinations().map((v) => DropdownMenuItem(value: v, child: Text('$v (${_floor(v)})'))).toList(),
            onChanged: (v) => setState(() { goalNode = v; _updatePath(); }),
          ),
        ),
        if (_showCompass && currentPath.isNotEmpty)
          Row(children: [
            Expanded(child: CompassIndicator(heading: _heading, routeAngleRad: _routeAngle)),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _showCompass = false)),
          ]),
        if (_remText.isNotEmpty)
          Container(
            width: double.infinity, color: Colors.cyan.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(_remText, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.cyan.shade800)),
          ),
        if (sF != null && gF != null && sF != gF && currentFloor == sF)
          Container(
            width: double.infinity, color: Colors.green.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: () { setState(() { currentFloor = gF; _updatePath(); }); final s = _stairs(gF); if (s != null) WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode(s)); },
              icon: const Icon(Icons.directions_walk), label: Text('階段に着いたら押して $gF へ'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            ),
          ),
        if (currentPath.isNotEmpty)
          WaypointPanel(
            orderedGates: _tracker.orderedGates,
            passed: _passed, nextGate: _nextGate,
            onConfirm: (key) { _passed.add(key); _tracker.confirmGate(key); setState(() {}); },
            onArrived: _nearGoal ? _onArrived : null,
          ),
        // ★ GlobalKey をここに設定
        Expanded(
          key: _mapKey,
          child: InteractiveViewer(
            transformationController: _tx,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 0.1, maxScale: 5.0, constrained: false,
            child: Center(
              child: _cn.isEmpty ? const CircularProgressIndicator()
                  : CustomPaint(
                      size: const Size(AppConfig.mapCanvasSize, AppConfig.mapCanvasSize),
                      painter: MapPainter(nodes: _cn, path: currentPath, startNode: startNode,
                          goalNode: goalNode, estimatedPosition: _estPos, headingDeg: _heading),
                    ),
            ),
          ),
        ),
      ]),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_estPos != null)
            FloatingActionButton(
              heroTag: "btn_follow", mini: true,
              backgroundColor: _followMode ? Colors.cyan.shade600 : Colors.white,
              foregroundColor: _followMode ? Colors.white : Colors.grey.shade700,
              onPressed: () { setState(() => _followMode = !_followMode); if (_followMode && _estPos != null) _centerOn(_estPos!); },
              child: Icon(_followMode ? Icons.gps_fixed : Icons.gps_not_fixed),
            ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: "btn1",
            onPressed: () => setState(() { currentFloor = currentFloor == '1F' ? '2F' : '1F'; _updatePath(); }),
            label: Text('$currentFloor 表示中 (切替)'), icon: const Icon(Icons.layers), backgroundColor: Colors.white,
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            heroTag: "btn2",
            onPressed: () async { final r = await Navigator.push(context, MaterialPageRoute(builder: (_) => const QRScannerScreen())); if (r != null) _onQRScanned(r); },
            label: const Text('QRスキャン'), icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
    );
  }
}
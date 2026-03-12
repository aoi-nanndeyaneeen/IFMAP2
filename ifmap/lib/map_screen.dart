// lib/map_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';

import 'config.dart';
import 'route_calculator.dart';
import 'step_tracker.dart';
import 'compass_indicator.dart';
import 'waypoint_panel.dart';
import 'map_painter.dart';
import 'qr_scanner_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Map<String, Map<String, dynamic>> _maps = {};
  String  _currentLabel = AppConfig.mapSections.first.label;
  String? startNode, goalNode;
  List<String> currentPath = [];

  late final StepTracker _tracker;
  Offset?   _estPos;
  double    _traveled = 0;
  GateInfo? _nextGate;
  final Set<String> _passed = {};

  double? _heading;
  bool _showCompass = false, _followMode = false;

  final _tx     = TransformationController();
  final _mapKey = GlobalKey();

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
    _loadAllMaps().then((_) => _checkUrlParameter());
  }

  @override
  void dispose() { _tracker.dispose(); super.dispose(); }

  // ─── データ ──────────────────────────────────────────────────

  Future<void> _loadAllMaps() async {
    for (final s in AppConfig.mapSections) {
      _maps[s.label] = jsonDecode(await rootBundle.loadString(s.path));
    }
    setState(() {});
  }

  void _checkUrlParameter() {
    try { final u = Uri.base; if (u.queryParameters.containsKey('start')) _onQRScanned(u.queryParameters['start']!); } catch (_) {}
  }

  Map<String, dynamic> get _cn => _maps[_currentLabel] ?? {};

  String? _labelOf(String? n) {
    if (n == null) return null;
    for (final e in _maps.entries) { if (e.value.containsKey(n)) return e.key; }
    return null;
  }

  String? _stairsIn(String label) {
    for (final e in (_maps[label] ?? {}).entries) {
      if (e.value['isStairs'] == true || e.key.toLowerCase() == 'stairs') return e.key;
    }
    return null;
  }

  String? _connectorTo(String fromLabel, String toLabel) {
    for (final e in (_maps[fromLabel] ?? {}).entries) {
      if (e.value['isConnector'] == true && e.value['connectsToMap'] == toLabel) return e.key;
    }
    return null;
  }

  List<String> _allDestinations() {
    final d = <String>[];
    for (final nodes in _maps.values) {
      nodes.forEach((k, v) {
        if (!k.startsWith('node_') && v['isStairs'] != true && v['isConnector'] != true) d.add(k);
      });
    }
    return d.toSet().toList();
  }

  /// 経路セグメントへの最短距離で近傍の名前付きノードを検出
  List<String> _nearbyWaypoints(List<String> path) {
    final r = AppConfig.waypointRadiusPx;
    final res = <String>{};
    for (final e in _cn.entries) {
      final id = e.key;
      if (id.startsWith('node_') || e.value['isStairs']==true ||
          e.value['isConnector']==true || id==startNode || id==goalNode) continue;
      final cx = (e.value['x'] as num).toDouble(), cy = (e.value['y'] as num).toDouble();
      for (int i = 0; i < path.length - 1; i++) {
        if (!_cn.containsKey(path[i]) || !_cn.containsKey(path[i+1])) continue;
        final x1 = (_cn[path[i]  ]['x'] as num).toDouble(), y1 = (_cn[path[i]  ]['y'] as num).toDouble();
        final x2 = (_cn[path[i+1]]['x'] as num).toDouble(), y2 = (_cn[path[i+1]]['y'] as num).toDouble();
        final dx = x2-x1, dy = y2-y1; final lsq = dx*dx+dy*dy;
        final t = lsq==0 ? 0.0 : ((cx-x1)*dx+(cy-y1)*dy)/lsq;
        if (sqrt(pow(cx-(x1+t.clamp(0,1)*dx),2)+pow(cy-(y1+t.clamp(0,1)*dy),2)) <= r) { res.add(id); break; }
      }
    }
    return res.toList();
  }

  void _updatePath() {
    currentPath.clear(); _passed.clear(); _nextGate = null;
    if (startNode == null || goalNode == null) { setState(() {}); return; }
    final sL = _labelOf(startNode)!, gL = _labelOf(goalNode)!;

    if (sL == gL) {
      if (_currentLabel == sL) currentPath = RouteCalculator.dijkstra(startNode!, goalNode!, _cn);
    } else {
      if (_currentLabel == sL) {
        final conn = _connectorTo(sL, gL) ?? _stairsIn(sL);
        if (conn != null) currentPath = RouteCalculator.dijkstra(startNode!, conn, _cn);
      } else if (_currentLabel == gL) {
        final conn = _connectorTo(gL, sL) ?? _stairsIn(gL);
        if (conn != null) currentPath = RouteCalculator.dijkstra(conn, goalNode!, _cn);
      }
    }

    _traveled = 0; _estPos = null;
    if (currentPath.isNotEmpty) {
      _tracker.startTracking(currentPath, _cn);
      _tracker.setGates(_nearbyWaypoints(currentPath), startNode);
      _nextGate = _tracker.nextGate;
    }
    setState(() {});
  }

  // ─── 表示操作 ─────────────────────────────────────────────────

  void _centerOn(Offset p) {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    final vw = box?.size.width  ?? MediaQuery.of(context).size.width;
    final vh = box?.size.height ?? MediaQuery.of(context).size.height;
    final sc = AppConfig.focusScale;
    _tx.value = Matrix4.translationValues(-p.dx*sc + vw/2, -p.dy*sc + vh*AppConfig.focusVerticalRatio, 0)
      // ignore: deprecated_member_use
      ..scale(sc);
  }

  void _focusNode(String id) {
    if (_cn.containsKey(id)) _centerOn(Offset((_cn[id]['x'] as num).toDouble(), (_cn[id]['y'] as num).toDouble()));
  }

  // ─── アクション ───────────────────────────────────────────────

  void _onQRScanned(String data) {
    final label = _labelOf(data);
    if (label != null) {
      setState(() { startNode = data; _currentLabel = label; _showCompass = true; });
      _updatePath();
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode(data));
    }
  }

  void _onArrived() {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('🎉 到着！'), content: Text('「$goalNode」に到着しました！'),
      actions: [TextButton(onPressed: () {
        Navigator.pop(context);
        setState(() { goalNode=null; currentPath.clear(); _followMode=false; });
      }, child: const Text('OK'))],
    ));
  }

  // ─── 計算プロパティ ───────────────────────────────────────────

  double? get _routeAngle {
    if (currentPath.length < 2 || !_cn.containsKey(currentPath[0]) || !_cn.containsKey(currentPath[1])) return null;
    return atan2(
      ((_cn[currentPath[1]]['y'] as num) - (_cn[currentPath[0]]['y'] as num)).toDouble(),
      ((_cn[currentPath[1]]['x'] as num) - (_cn[currentPath[0]]['x'] as num)).toDouble(),
    );
  }

  String get _remText {
    if (currentPath.isEmpty || _tracker.totalRoutePx == 0) return '';
    final remPx = (_tracker.totalRoutePx - _traveled).clamp(0.0, double.infinity);
    final remM  = (remPx * AppConfig.metersPerPx).toStringAsFixed(0);
    return 'あと約 $remM m';
  }

  bool get _nearGoal => goalNode != null && _tracker.totalRoutePx > 0 && _traveled >= _tracker.totalRoutePx * 0.85;

  String? get _connectorDestLabel {
    if (currentPath.isEmpty) return null;
    final last = _cn[currentPath.last];
    if (last?['isConnector'] == true) return last?['connectsToMap'] as String?;
    if (last?['isStairs'] == true) {
      final gL = _labelOf(goalNode);
      return (gL != null && gL != _currentLabel) ? gL : null;
    }
    return null;
  }

  // ─── build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final destLabel = _connectorDestLabel;
    final sF = _labelOf(startNode), gF = _labelOf(goalNode);

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(startNode == null ? '現在地: 未設定 (QRをスキャン)' : '現在地: $startNode',
              style: const TextStyle(fontSize: 13)),
          Row(children: [
            const Text('目的地: ', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Expanded(child: DropdownButton<String>(
              isExpanded: true, value: goalNode,
              hint: const Text('選択してください', style: TextStyle(fontSize: 13)),
              items: _allDestinations().map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (val) {
                if (val == null) return;
                setState(() { goalNode = val; _updatePath(); });
                if (startNode != null) WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode(startNode!));
              },
            )),
          ]),
        ]),
        backgroundColor: Colors.blueGrey.shade50,
        toolbarHeight: 80,
      ),
      body: Column(children: [
        // マップ切替チップ（マップが2つ以上のとき）
        if (_maps.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: _maps.keys.map((label) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: ChoiceChip(
                label: Text(label), selected: _currentLabel == label,
                onSelected: (_) => setState(() { _currentLabel = label; _updatePath(); }),
              ),
            )).toList()),
          ),

        // コンパス
        if (_showCompass && currentPath.isNotEmpty)
          Row(children: [
            Expanded(child: CompassIndicator(heading: _heading, routeAngleRad: _routeAngle)),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _showCompass = false)),
          ]),

        // 残り距離
        if (_remText.isNotEmpty)
          Container(
            width: double.infinity, color: Colors.cyan.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(_remText, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.cyan.shade800)),
          ),

        // 階段・接続点ボタン
        if (sF != null && gF != null && sF != gF && _currentLabel == sF && destLabel == null)
          _sectionButton('階段に着いたら → $gF へ', Colors.green, Icons.directions_walk, () {
            setState(() { _currentLabel = gF; _updatePath(); });
            final s = _stairsIn(gF);
            if (s != null) WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode(s));
          }),
        if (destLabel != null)
          _sectionButton('接続点に到達 → $destLabel へ進む', Colors.deepPurple, Icons.sync_alt, () {
            final conn = _cn[currentPath.last];
            final nextNode = conn?['connectsToNode'] as String?;
            setState(() { _currentLabel = destLabel; });
            if (nextNode != null) setState(() { startNode = nextNode; });
            _updatePath();
            if (nextNode != null) WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode(nextNode));
          }),

        // チェックポイントTodoリスト
        if (currentPath.isNotEmpty)
          WaypointPanel(
            orderedGates: _tracker.orderedGates, passed: _passed, nextGate: _nextGate,
            onConfirm: (key) { _passed.add(key); _tracker.confirmGate(key); setState(() {}); },
            onArrived: _nearGoal ? _onArrived : null,
          ),

        // マップ本体
        Expanded(
          key: _mapKey,
          child: InteractiveViewer(
            transformationController: _tx,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 0.1, maxScale: 5.0, constrained: false,
            child: Center(child: _cn.isEmpty
              ? const CircularProgressIndicator()
              : CustomPaint(
                  size: const Size(AppConfig.mapCanvasSize, AppConfig.mapCanvasSize),
                  painter: MapPainter(
                    nodes: _cn, path: currentPath,
                    startNode: startNode, goalNode: goalNode,
                    estimatedPosition: _estPos, headingDeg: _heading,
                  ),
                )),
          ),
        ),
      ]),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_estPos != null)
            FloatingActionButton(
              heroTag: 'follow', mini: true,
              backgroundColor: _followMode ? Colors.cyan.shade600 : Colors.white,
              foregroundColor: _followMode ? Colors.white : Colors.grey.shade700,
              onPressed: () { setState(() => _followMode = !_followMode); if (_followMode && _estPos != null) _centerOn(_estPos!); },
              child: Icon(_followMode ? Icons.gps_fixed : Icons.gps_not_fixed),
            ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'floor',
            onPressed: () {
              final labels = _maps.keys.toList();
              setState(() { _currentLabel = labels[(labels.indexOf(_currentLabel)+1) % labels.length]; _updatePath(); });
            },
            label: Text('$_currentLabel (切替)'), icon: const Icon(Icons.layers), backgroundColor: Colors.white,
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            heroTag: 'qr',
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

  Widget _sectionButton(String label, Color color, IconData icon, VoidCallback onPressed) {
    return Container(
      width: double.infinity, color: color.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton.icon(
        onPressed: onPressed, icon: Icon(icon), label: Text(label),
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
      ),
    );
  }
}
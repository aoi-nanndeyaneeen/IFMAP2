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
      final data = jsonDecode(await rootBundle.loadString(s.path)) as Map<String, dynamic>;
      data.remove('_editorData'); // エディタ用のメタデータを破棄（クラッシュ防止とメモリ解放）
      _maps[s.label] = data;
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

  String? _findMatchingStairs(String fromLabel, String toLabel) {
    final fromStairs = <String>{};
    _maps[fromLabel]?.forEach((k, v) {
      if (v['isStairs'] == true && v['name'] != null) fromStairs.add(v['name']);
    });

    String? matchingStairsName;
    _maps[toLabel]?.forEach((k, v) {
      if (v['isStairs'] == true && v['name'] != null && fromStairs.contains(v['name'])) matchingStairsName = v['name'];
    });

    if (matchingStairsName != null) {
       for (final e in (_maps[fromLabel] ?? {}).entries) {
         if (e.value['isStairs'] == true && e.value['name'] == matchingStairsName) return e.key;
       }
    }

    for (final e in (_maps[fromLabel] ?? {}).entries) {
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

  void _updatePath() {
    currentPath.clear(); _passed.clear(); _nextGate = null;
    if (startNode == null || goalNode == null) { setState(() {}); return; }
    final sL = _labelOf(startNode)!, gL = _labelOf(goalNode)!;

    if (sL == gL) {
      if (_currentLabel == sL) currentPath = RouteCalculator.dijkstra(startNode!, goalNode!, _cn);
    } else {
      if (_currentLabel == sL) {
        final conn = _connectorTo(sL, gL) ?? _findMatchingStairs(sL, gL);
        if (conn != null) currentPath = RouteCalculator.dijkstra(startNode!, conn, _cn);
      } else if (_currentLabel == gL) {
        final conn = _connectorTo(gL, sL) ?? _findMatchingStairs(gL, sL);
        if (conn != null) currentPath = RouteCalculator.dijkstra(conn, goalNode!, _cn);
      }
    }

    _traveled = 0; 
    if (currentPath.isNotEmpty) {
      _tracker.startTracking(currentPath, _cn);
      _tracker.setGates();
      _nextGate = _tracker.nextGate;
    }
    setState(() {});
  }

  void _onMapTap(Offset localPos) {
    debugPrint('Map Tapped at (local): $localPos');
    final double mapX = localPos.dx;
    final double mapY = localPos.dy;

    String? closestNode;
    double minDist = AppConfig.waypointRadiusPx;

    _cn.forEach((k, v) {
      if (k.startsWith('node_')) {
        return;
      }
      final dx = (v['x'] as num).toDouble() - mapX;
      final dy = (v['y'] as num).toDouble() - mapY;
      final d = sqrt(dx * dx + dy * dy);
      if (d < minDist) {
        minDist = d;
        closestNode = k;
      }
    });

    if (closestNode != null) {
      debugPrint('Closest destination found: $closestNode');
      setState(() {
        goalNode = closestNode;
        _updatePath();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('目的地を「$closestNode」に設定しました'),
        duration: const Duration(seconds: 1),
      ));
    } else {
      debugPrint('No destination node near the tap point.');
    }
  }

  // ─── 表示操作 ─────────────────────────────────────────────────

  void _centerOn(Offset p) {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    final vw = box?.size.width  ?? MediaQuery.of(context).size.width;
    final vh = box?.size.height ?? MediaQuery.of(context).size.height;
    const sc = AppConfig.focusScale;
    _tx.value = Matrix4.translationValues(-p.dx * sc + vw / 2, -p.dy * sc + vh * AppConfig.focusVerticalRatio, 0)
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
    // 最終目的地が現在の階にある場合のみポップアップを表示
    // 階段到着・フロア移動中はここに来ない（_nearGoalでガード済み）
    if (goalNode == null || _labelOf(goalNode) != _currentLabel) return;

    // 既にダイアログが出ている場合は出さない
    if (ModalRoute.of(context)?.isCurrent == false) return;

    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('🎉 到着！'),
      content: Text('「$goalNode」に到着しました！'),
      actions: [TextButton(onPressed: () {
        Navigator.pop(context);
        setState(() { goalNode = null; currentPath.clear(); _followMode = false; });
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

  /// 最終目的地が現在のフロアにあり、かつ経路の85%以上を歩いた場合のみtrue
  bool get _nearGoal =>
      goalNode != null &&
      _labelOf(goalNode) == _currentLabel && // 現在フロアの目的地のみ
      _tracker.totalRoutePx > 0 &&
      _traveled >= _tracker.totalRoutePx * 0.85;

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
        title: Text(goalNode == null ? '目的地をタップして設定' : '目的地: $goalNode', style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () => _showDestinationPicker(),
          ),
        ],
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
          () {
            bool hasMatchingStairs = false;
            final fStairs = <String>{};
            _maps[sF]?.forEach((k, v) { if (v['isStairs'] == true && v['name'] != null) fStairs.add(v['name']); });
            _maps[gF]?.forEach((k, v) { if (v['isStairs'] == true && v['name'] != null && fStairs.contains(v['name'])) hasMatchingStairs = true; });

            return _sectionButton(hasMatchingStairs ? '階段がつながっています → $gF へ' : '階段に着いたら → $gF へ', Colors.green, Icons.directions_walk, () {
              setState(() { _currentLabel = gF; _updatePath(); });
              final s = _findMatchingStairs(gF, sF);
              if (s != null) WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode(s));
            });
          }(),
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
            minScale: 0.1,
            maxScale: 5.0,
            constrained: false,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => _onMapTap(details.localPosition),
              child: _cn.isEmpty
                  ? const SizedBox(
                      width: AppConfig.mapCanvasSize,
                      height: AppConfig.mapCanvasSize,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : CustomPaint(
                      size: const Size(AppConfig.mapCanvasSize, AppConfig.mapCanvasSize),
                      painter: MapPainter(
                        nodes: _cn,
                        path: currentPath,
                        startNode: startNode,
                        goalNode: goalNode,
                        estimatedPosition: _estPos,
                        headingDeg: _heading,
                      ),
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

  void _showDestinationPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('目的地を選択', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView(
              children: _allDestinations().map((v) => ListTile(
                title: Text(v),
                onTap: () {
                  setState(() { goalNode = v; _updatePath(); });
                  Navigator.pop(ctx);
                  if (startNode != null) WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode(startNode!));
                },
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionButton(String label, Color color, IconData icon, VoidCallback onPressed) {
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
    );
  }
}
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
  final Map<String, Map<String, dynamic>> _nodes = {};
  final Map<String, List<dynamic>> _cells = {}; // 背景描画用のセルデータ
  final Map<String, List<dynamic>> _rooms = {}; // 部屋の中心点データ
  String  _currentLabel = AppConfig.mapSections.first.label;
  String? startNode, goalNode; // これらは「部屋名」も入る
  Offset? _goalCenter; // 目的地の部屋中心座標（マーカー表示用）
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
      final String content = await rootBundle.loadString(s.path);
      final fullData = jsonDecode(content) as Map<String, dynamic>;
      
      if (fullData.containsKey('_editorData')) {
        final editorData = fullData['_editorData'] as Map<String, dynamic>;
        _cells[s.label] = (editorData['cells'] as List<dynamic>?) ?? [];
        _rooms[s.label] = (editorData['rooms'] as List<dynamic>?) ?? [];
      }
      
      final nodes = Map<String, dynamic>.from(fullData);
      nodes.remove('_editorData');
      _nodes[s.label] = nodes;
    }
    setState(() {});
  }

  void _checkUrlParameter() {
    try { final u = Uri.base; if (u.queryParameters.containsKey('start')) _onQRScanned(u.queryParameters['start']!); } catch (_) {}
  }

  Map<String, dynamic> get _cn => _nodes[_currentLabel] ?? {};
  List<dynamic> get _cc => _cells[_currentLabel] ?? [];
  List<dynamic> get _cr => _rooms[_currentLabel] ?? [];

  String? _labelOf(String? n) {
    if (n == null) return null;
    for (final e in _nodes.entries) { 
      if (e.value.containsKey(n)) return e.key; 
      for (final node in e.value.values) {
        if (node is Map && node['name'] == n) return e.key;
      }
    }
    return null;
  }

  String? _findIdByName(String name, String label) {
    final nodes = _nodes[label];
    if (nodes == null) return null;
    if (nodes.containsKey(name)) return name;
    for (final e in nodes.entries) {
      if (e.value is Map && e.value['name'] == name) return e.key;
    }
    return null;
  }

  String? _findMatchingStairs(String fromLabel, String toLabel) {
    final fromStairs = <String>{};
    _nodes[fromLabel]?.forEach((k, v) {
      if (v is Map && v['isStairs'] == true && v['name'] != null) fromStairs.add(v['name']);
    });

    String? matchingStairsName;
    _nodes[toLabel]?.forEach((k, v) {
      if (v is Map && v['isStairs'] == true && v['name'] != null && fromStairs.contains(v['name'])) matchingStairsName = v['name'];
    });

    if (matchingStairsName != null) {
       for (final e in (_nodes[fromLabel] ?? {}).entries) {
         if (e.value is Map && e.value['isStairs'] == true && e.value['name'] == matchingStairsName) return e.key;
       }
    }

    for (final e in (_nodes[fromLabel] ?? {}).entries) {
      if (e.value is Map && (e.value['isStairs'] == true || e.key.toLowerCase() == 'stairs')) return e.key;
    }
    return null;
  }

  String? _connectorTo(String fromLabel, String toLabel) {
    for (final e in (_nodes[fromLabel] ?? {}).entries) {
      if (e.value is Map && e.value['isConnector'] == true && e.value['connectsToMap'] == toLabel) return e.key;
    }
    return null;
  }

  List<String> _allDestinations({String? floorLabel}) {
    final d = <String>[];
    for (final entry in _nodes.entries) {
      if (floorLabel != null && entry.key != floorLabel) continue;
      entry.value.forEach((k, v) {
        if (v is Map && v['name'] != null && v['isStairs'] != true && v['isConnector'] != true) d.add(v['name']!);
      });
    }
    return d.toSet().toList();
  }

  /// 目的地名から対応する部屋中心座標を返す
  Offset? _findRoomCenter(String? roomName) {
    if (roomName == null) return null;
    final gL = _labelOf(roomName);
    if (gL == null) return null;
    for (final room in (_rooms[gL] ?? [])) {
      if (room is Map && room['name'] == roomName) {
        final cx = (room['centerX'] as num?)?.toDouble();
        final cy = (room['centerY'] as num?)?.toDouble();
        if (cx != null && cy != null) return Offset(cx, cy);
      }
    }
    return null;
  }

  void _updatePath() {
    currentPath.clear(); _passed.clear(); _nextGate = null;
    // 目的地の部屋中心を取得
    _goalCenter = _findRoomCenter(goalNode);
    if (goalNode != null) {
      _followMode = true; // 自動追従開始
    }
    
    if (startNode == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('出発地が設定されていません。QRコードをスキャンしてください。'),
        backgroundColor: Colors.orange,
      ));
      setState(() {});
      return;
    }

    final sL = _labelOf(startNode);
    final gL = _labelOf(goalNode);
    
    if (sL == null || gL == null) {
      if (goalNode != null) _showError('場所の名前を特定できませんでした ($goalNode)');
      return;
    }

    final sId = _findIdByName(startNode!, sL);
    final gId = _findIdByName(goalNode!, gL);
    if (sId == null || gId == null) {
      _showError('場所に対応するノードが見つかりません: ${startNode ?? ""}/${goalNode ?? ""}');
      return;
    }

    debugPrint('Calculating Path: $sId ($sL) -> $gId ($gL) | Currently on: $_currentLabel');

    if (sL == gL) {
      if (_currentLabel == sL) {
        currentPath = RouteCalculator.dijkstra(sId, gId, _cn);
        if (currentPath.isNotEmpty) _showInfo('目的地までの経路を表示しました');
        else _showError('経路が見つかりませんでした');
      }
    } else {
      final sections = AppConfig.mapSections;
      final sIdx = sections.indexWhere((s) => s.label == sL);
      final gIdx = sections.indexWhere((s) => s.label == gL);
      final cIdx = sections.indexWhere((s) => s.label == _currentLabel);
      if (cIdx == -1) return;

      if (cIdx == gIdx) {
        final prevFloorLabel = sections[gIdx + (sIdx > gIdx ? 1 : -1)].label;
        final conn = _connectorTo(_currentLabel, prevFloorLabel) ?? _findMatchingStairs(_currentLabel, prevFloorLabel);
        if (conn != null) {
          currentPath = RouteCalculator.dijkstra(conn, gId, _cn);
          if (currentPath.isNotEmpty) _showInfo('目的地への経路を表示しました');
        }
      } else {
        final direction = (gIdx > cIdx ? 1 : -1);
        final nextLabel = sections[cIdx + direction].label;
        final conn = _connectorTo(_currentLabel, nextLabel) ?? _findMatchingStairs(_currentLabel, nextLabel);
        if (conn != null) {
          final incomingDir = (sIdx > cIdx ? 1 : -1);
          final prevLabel = (cIdx + incomingDir >= 0 && cIdx + incomingDir < sections.length) ? sections[cIdx + incomingDir].label : null;
          final sEntry = (_currentLabel == sL) ? sId : (prevLabel != null ? (_connectorTo(_currentLabel, prevLabel) ?? _findMatchingStairs(_currentLabel, prevLabel)) : null);
          if (sEntry != null) {
            currentPath = RouteCalculator.dijkstra(sEntry, conn, _cn);
            if (currentPath.isNotEmpty) _showInfo('$nextLabel 階への案内を開始します');
          }
        }
      }
    }

    _traveled = 0; 
    if (currentPath.isNotEmpty) {
      debugPrint('Path found: ${currentPath.length} nodes');
      _tracker.startTracking(currentPath, _cn);
      _tracker.setGates();
      _nextGate = _tracker.nextGate;
    } else {
      debugPrint('No path found between $startNode and $goalNode');
    }
    setState(() {});
  }

  void _onMapTap(Offset localPos) {
    debugPrint('Map Tapped at (local): $localPos');
    final double mapX = localPos.dx;
    final double mapY = localPos.dy;

    String? closestName;
    double minDist = 30.0; // 30px 以内ならヒットとする

    _cn.forEach((k, v) {
      if (v is! Map || v['name'] == null) return;
      if (v['isStairs'] == true || v['isConnector'] == true) return;

      final x = (v['x'] as num).toDouble() + 5.0; // セル中心で判定
      final y = (v['y'] as num).toDouble() + 5.0;
      final dist = sqrt(pow(x - mapX, 2) + pow(y - mapY, 2));

      if (dist < minDist) {
        minDist = dist;
        closestName = v['name'] as String?;
      }
    });

    if (closestName != null) {
      _showInfo('目的地を「$closestName」に設定しました');
      setState(() { goalNode = closestName; _updatePath(); });
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

  void _focusNode(String idOrName) {
    final id = _findIdByName(idOrName, _currentLabel);
    if (id != null) {
      final n = _cn[id];
      if (n is Map) {
        final x = (n['x'] as num?)?.toDouble();
        final y = (n['y'] as num?)?.toDouble();
        if (x != null && y != null) _centerOn(Offset(x, y));
      }
    }
  }

  // ─── アクション ───────────────────────────────────────────────

  void _showInfo(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

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
      _tracker.traveledPx >= _tracker.totalRoutePx * 0.85;

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
        if (_nodes.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: _nodes.keys.map((label) => Padding(
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
        if (sF != null && gF != null && sF != gF && _currentLabel != gF && destLabel == null)
          (() {
            final sections = AppConfig.mapSections;
            final cIdx = sections.indexWhere((s) => s.label == _currentLabel);
            final gIdx = sections.indexWhere((s) => s.label == gF);
            if (cIdx == -1 || gIdx == -1) return const SizedBox.shrink();
            
            final nextLabel = sections[cIdx + (gIdx > cIdx ? 1 : -1)].label;
            bool hasMatchingStairs = false;
            final fStairs = <String>{};
            _nodes[_currentLabel]?.forEach((k, v) { if (v is Map && v['isStairs'] == true && v['name'] != null) fStairs.add(v['name']); });
            _nodes[nextLabel]?.forEach((k, v) { if (v is Map && v['isStairs'] == true && v['name'] != null && fStairs.contains(v['name'])) hasMatchingStairs = true; });

            return _sectionButton(hasMatchingStairs ? '階段がつながっています → $nextLabel へ' : '階段に着いたら → $nextLabel へ', Colors.green, Icons.directions_walk, () {
              setState(() { _currentLabel = nextLabel; _updatePath(); });
            });
          })(),
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
            onConfirm: (key) { 
              _passed.add(key); 
              _tracker.confirmGate(key);
              
              // 改善: 目的地に入るボタンが押されたらそのまま到着とする
              if (goalNode != null && _tracker.nextGate == null && _nearGoal) {
                 _onArrived();
              }
              setState(() {}); 
            },
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
                            cells: _cc,
                            rooms: _cr,
                            path: (startNode != null && _labelOf(startNode) == _currentLabel) ? currentPath : [],
                            startNode: startNode,
                            goalNode: goalNode,
                            goalCenter: _goalCenter,
                            currentLabel: _currentLabel,
                            estimatedPosition: _estPos,
                            headingDeg: _heading,
                            showUserDot: startNode != null && _labelOf(startNode) == _currentLabel,
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
              onPressed: () { 
                if (!_followMode) {
                  final sFloor = _labelOf(startNode);
                  if (sFloor != null && sFloor != _currentLabel) {
                    setState(() { _currentLabel = sFloor; _updatePath(); });
                  }
                }
                setState(() => _followMode = !_followMode); 
                if (_followMode && _estPos != null) _centerOn(_estPos!); 
              },
              child: Icon(_followMode ? Icons.gps_fixed : Icons.gps_not_fixed),
            ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'floor',
            onPressed: () {
              final labels = _nodes.keys.toList();
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
    String filter = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('目的地検索', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: '部屋名や番号を入力...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setLocalState(() => filter = v),
                ),
              ),
              Expanded(
                child: ListView(
                  children: (() {
                    final currentRoomName = _cn[startNode]?['name'] as String?;
                    final list = (filter.isEmpty 
                        ? _allDestinations(floorLabel: _currentLabel) 
                        : _allDestinations());
                    return list.toSet().where((v) => v != currentRoomName && v.toLowerCase().contains(filter.toLowerCase())).toList();
                  })()
                    .map((v) => ListTile(
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
        ),
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
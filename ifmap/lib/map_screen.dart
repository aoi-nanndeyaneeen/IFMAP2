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
  final Map<String, List<dynamic>> _cells = {};
  final Map<String, List<dynamic>> _rooms = {};
  String _currentLabel = AppConfig.mapSections.first.label;
  String? startNode, goalNode;
  Offset? _goalCenter, _startCenter;
  List<String> currentPath = [];

  // ─── ★ NEW: フロア分離のための2つの新フィールド ───────────────
  //
  // [_floorPaths]
  //   全フロア分のパスを一括で事前計算して保持する Map。
  //   キー = フロアラベル, 値 = そのフロア上のノードIDリスト。
  //   _calculateGlobalRoute() で全フロア分を一度に埋める。
  //   _calculateViewRoute() はここから _currentLabel のパスを取るだけでよい。
  //
  // [_trackerLabel]
  //   センサートラッカーが物理的に動いているフロアのラベル。
  //   ユーザーが表示フロアを自由に切り替えても、
  //   こちらは「実際に歩いている階」を指し続ける。
  //   showUserDot など「今いる階だけ有効」な判定にはこちらを使う。
  // ──────────────────────────────────────────────────────────────
  Map<String, List<String>> _floorPaths = {};
  String _trackerLabel = AppConfig.mapSections.first.label;

  /// startNode が属するフロアを明示的に保持する。
  /// _labelOf(startNode) は同一IDが複数フロアに存在すると誤判定するため、
  /// このフィールドで正確なフロアを管理する。
  String? _startLabel; // ★ 追加

  late final StepTracker _tracker;
  Offset? _estPos;
  double _traveled = 0;
  GateInfo? _nextGate;
  final Set<String> _passed = {};

  double? _heading;
  bool _showCompass = false, _followMode = false;

  final _tx = TransformationController();
  final _mapKey = GlobalKey();

  // ─── lifecycle ────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tracker = StepTracker(stepLengthPx: AppConfig.stepLengthPx);
    _tracker.positionStream.listen((p) {
      setState(() => _estPos = p);
      if (_followMode && p != null)
        WidgetsBinding.instance.addPostFrameCallback((_) => _centerOn(p));
    });
    _tracker.traveledStream.listen((d) => setState(() => _traveled = d));
    _tracker.nextGateStream.listen((g) => setState(() => _nextGate = g));
    FlutterCompass.events?.listen((e) {
      if (e.heading != null) setState(() => _heading = e.heading);
    });
    _loadAllMaps().then((_) => _checkUrlParameter());
  }

  @override
  void dispose() {
    _tracker.dispose();
    super.dispose();
  }

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
    try {
      final u = Uri.base;
      if (u.queryParameters.containsKey('start'))
        _onQRScanned(u.queryParameters['start']!);
    } catch (_) {}
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

  /// 指定した名前を持つノードのうち、部屋の centerX/Y に最も近いノードIDを返す。
  /// rooms[] に center情報がない場合は _findIdByName() にフォールバック。
  String? _findIdNearestToCenter(String name, String label) {
    final nodes = _nodes[label];
    if (nodes == null) return null;

    final center = _findRoomCenter(name); // rooms[] から centerX/Y を取得
    if (center == null) return _findIdByName(name, label); // フォールバック

    String? bestId;
    double bestDist = double.infinity;

    for (final e in nodes.entries) {
      if (e.value is! Map || e.value['name'] != name) continue;
      // ノード座標はJSONの x/y (pxPerCell 単位)。セル中央に+5する。
      final nx = (e.value['x'] as num).toDouble() + 5.0;
      final ny = (e.value['y'] as num).toDouble() + 5.0;
      final dist = sqrt(pow(nx - center.dx, 2) + pow(ny - center.dy, 2));
      if (dist < bestDist) {
        bestDist = dist;
        bestId = e.key;
      }
    }

    return bestId ?? _findIdByName(name, label);
  }

  String? _findMatchingStairs(String fromLabel, String toLabel) {
    final fromStairs = <String>{};
    _nodes[fromLabel]?.forEach((k, v) {
      if (v is Map && v['isStairs'] == true && v['name'] != null)
        fromStairs.add(v['name']);
    });

    String? matchingStairsName;
    _nodes[toLabel]?.forEach((k, v) {
      if (v is Map &&
          v['isStairs'] == true &&
          v['name'] != null &&
          fromStairs.contains(v['name'])) matchingStairsName = v['name'];
    });

    if (matchingStairsName != null) {
      for (final e in (_nodes[fromLabel] ?? {}).entries) {
        if (e.value is Map &&
            e.value['isStairs'] == true &&
            e.value['name'] == matchingStairsName) return e.key;
      }
    }

    for (final e in (_nodes[fromLabel] ?? {}).entries) {
      if (e.value is Map &&
          (e.value['isStairs'] == true || e.key.toLowerCase() == 'stairs'))
        return e.key;
    }
    return null;
  }

  String? _connectorTo(String fromLabel, String toLabel) {
    for (final e in (_nodes[fromLabel] ?? {}).entries) {
      if (e.value is Map &&
          e.value['isConnector'] == true &&
          e.value['connectsToMap'] == toLabel) return e.key;
    }
    return null;
  }

  List<String> _allDestinations({String? floorLabel}) {
    final d = <String>[];
    for (final entry in _nodes.entries) {
      if (floorLabel != null && entry.key != floorLabel) continue;
      entry.value.forEach((k, v) {
        if (v is Map &&
            v['name'] != null &&
            v['isStairs'] != true &&
            v['isConnector'] != true) d.add(v['name']!);
      });
    }
    return d.toSet().toList();
  }

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

  // ─── ★ REWRITTEN: _calculateGlobalRoute ──────────────────────
  //
  //  【旧】出発フロアのパスのみ計算 → トラッカーにセット
  //  【新】全フロア分のパスを _floorPaths に一括計算してから
  //       出発フロア分だけトラッカーにセット。
  //
  //  ループの流れ（例: 1F → 3F）
  //    i=0(1F): start → 1F↔2F 接続点(exitId)       → _floorPaths["1F"]
  //             2F の入口 = _connectorTo/findMatchingStairs("2F","1F") → currentEntryId
  //    i=1(2F): currentEntryId → 2F↔3F 接続点(exitId) → _floorPaths["2F"]
  //             3F の入口 → currentEntryId
  //    i=2(3F): currentEntryId → goal               → _floorPaths["3F"]
  //
  // ─────────────────────────────────────────────────────────────
  List<String> _physicalPath = []; // WaypointPanel 判定用に残す
  String? _crossFloorLabelForTracker;

  void _updatePath() {
    _passed.clear();
    _goalCenter = _findRoomCenter(goalNode);
    _startCenter = _findRoomCenter(startNode);

    if (goalNode != null) {
      _followMode = true;
    }

    if (startNode == null) {
      if (goalNode != null) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('出発地が設定されていません。マップをタップ等してください。'),
          backgroundColor: Colors.orange,
        ));
        goalNode = null;
        _goalCenter = null;
      }
      setState(() {});
      return;
    }

    _calculateGlobalRoute();
    _calculateViewRoute();

    _traveled = 0;
    setState(() {});
  }

// ─── _calculateGlobalRoute ────────────────────────────────────
  void _calculateGlobalRoute() {
    _floorPaths.clear();
    _physicalPath.clear();
    _crossFloorLabelForTracker = null;

    if (startNode == null || goalNode == null) {
      _tracker.clear();
      _nextGate = null;
      return;
    }

    final sL = _startLabel ?? _labelOf(startNode);
    final gL = _labelOf(goalNode);
    if (sL == null || gL == null) return;

    _trackerLabel = sL;

    // ★ 変更: _findIdByName → _findIdNearestToCenter
    //   部屋の場合は中心に最も近いノード、階段・接続点はそのまま
    final sId = _findIdNearestToCenter(startNode!, sL) ?? _findIdByName(startNode!, sL);
    final gId = _findIdNearestToCenter(goalNode!, gL) ?? _findIdByName(goalNode!, gL);
    if (sId == null || gId == null) return;

    if (sL == gL) {
      final path = RouteCalculator.dijkstra(sId, gId, _nodes[sL] ?? {});
      if (path.isNotEmpty) _floorPaths[sL] = path;
    } else {
      final sections = AppConfig.mapSections;
      final sIdx = sections.indexWhere((s) => s.label == sL);
      final gIdx = sections.indexWhere((s) => s.label == gL);
      if (sIdx == -1 || gIdx == -1) return;

      final direction = gIdx > sIdx ? 1 : -1;
      String currentEntryId = sId;

      for (int i = sIdx;
          direction > 0 ? i <= gIdx : i >= gIdx;
          i += direction) {
        final floorLabel = sections[i].label;
        final nodes = _nodes[floorLabel] ?? {};

        if (i == gIdx) {
          final path = RouteCalculator.dijkstra(currentEntryId, gId, nodes);
          if (path.isNotEmpty) _floorPaths[floorLabel] = path;
        } else {
          final nextFloor = sections[i + direction].label;
          final exitId = _connectorTo(floorLabel, nextFloor)
              ?? _findMatchingStairs(floorLabel, nextFloor);
          if (exitId == null) break;

          final path = RouteCalculator.dijkstra(currentEntryId, exitId, nodes);
          if (path.isNotEmpty) _floorPaths[floorLabel] = path;

          final nextEntry = _connectorTo(nextFloor, floorLabel)
              ?? _findMatchingStairs(nextFloor, floorLabel);
          if (nextEntry == null) break;
          currentEntryId = nextEntry;
        }
      }

      final nextIdx = sIdx + direction;
      if (nextIdx >= 0 && nextIdx < sections.length) {
        _crossFloorLabelForTracker = sections[nextIdx].label;
      }
    }

    _physicalPath = _floorPaths[sL] ?? [];

    if (_physicalPath.isNotEmpty) {
      _tracker.startTracking(_physicalPath, _nodes[sL] ?? {});
      _tracker.setGates();
      _nextGate = _tracker.nextGate;
    } else {
      _tracker.clear();
      _nextGate = null;
      _showError('経路が見つかりませんでした');
    }
  }

// ─── _calculateViewRoute ──────────────────────────────────────
  void _calculateViewRoute() {
    currentPath = _floorPaths[_currentLabel] ?? [];
    // ★ ここで currentPath が空なら「_floorPaths に _currentLabel のキーがない」
    debugPrint(
        '[View] _currentLabel=$_currentLabel → currentPath=${currentPath.length}ノード '
        '(利用可能フロア: ${_floorPaths.keys.toList()})');
  }

// ─── _handleCrossFloor ────────────────────────────────────────
  void _handleCrossFloor(String nextFloor) {
    final nextPath = _floorPaths[nextFloor];
    debugPrint(
        '[CrossFloor] nextFloor=$nextFloor, nextPath=${nextPath?.length}ノード');

    if (nextPath == null || nextPath.isEmpty) {
      _showError('次の階への経路が見つかりませんでした ($nextFloor)\n'
          'JSONのisStairs/connectsToMapを確認してください');
      return;
    }

    final nextStartId = nextPath.first;
    debugPrint(
        '[CrossFloor] nextStartId=$nextStartId, _labelOf=${_labelOf(nextStartId)}');

    setState(() {
      startNode = nextStartId;
      _startLabel = nextFloor; // ★ フロアを明示セット
      _currentLabel = nextFloor;
      _updatePath();
    });

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode(nextStartId));
  }

  void _onMapTap(Offset localPos) {
    debugPrint('Map Tapped at (local): $localPos');
    final double mapX = localPos.dx;
    final double mapY = localPos.dy;

    String? closestName;
    double minDist = 30.0;

    _cn.forEach((k, v) {
      if (v is! Map || v['name'] == null) return;
      if (v['isStairs'] == true || v['isConnector'] == true) return;

      final x = (v['x'] as num).toDouble() + 5.0;
      final y = (v['y'] as num).toDouble() + 5.0;
      final dist = sqrt(pow(x - mapX, 2) + pow(y - mapY, 2));

      if (dist < minDist) {
        minDist = dist;
        closestName = v['name'] as String?;
      }
    });

    if (closestName != null) {
      if (startNode == null) {
        setState(() {
          startNode = closestName;
          _startLabel = _labelOf(closestName) ?? _currentLabel; // ★
          _currentLabel = _startLabel!;
          _showCompass = true;
          _updatePath();
        });
        _showInfo('現在地を「$closestName」に設定しました');
      } else {
        setState(() {
          goalNode = closestName;
          if (_startLabel != null && _startLabel != _currentLabel) {
            _currentLabel = _startLabel!;
          }
          _updatePath();
        });
        _showInfo('目的地を「$closestName」に設定しました');
      }
    }
  }

  // ─── 表示操作 ─────────────────────────────────────────────────

  void _centerOn(Offset p) {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    final vw = box?.size.width ?? MediaQuery.of(context).size.width;
    final vh = box?.size.height ?? MediaQuery.of(context).size.height;
    const sc = AppConfig.focusScale;
    _tx.value = Matrix4.translationValues(
        -p.dx * sc + vw / 2, -p.dy * sc + vh * AppConfig.focusVerticalRatio, 0)
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
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _onQRScanned(String data) {
    final label = _labelOf(data);
    if (label != null) {
      setState(() {
        startNode = data;
        _startLabel = label; // ★
        _currentLabel = label;
        _showCompass = true;
      });
      _updatePath();
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode(data));
    }
  }

  void _onArrived() {
    if (goalNode == null || _labelOf(goalNode) != _currentLabel) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;

    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('🎉 到着！'),
              content: Text('「$goalNode」に到着しました！'),
              actions: [
                TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        goalNode = null;
                        currentPath.clear();
                        _floorPaths.clear();
                        _followMode = false;
                      });
                    },
                    child: const Text('OK'))
              ],
            ));
  }

  // ─── 計算プロパティ ───────────────────────────────────────────

  double? get _routeAngle {
    if (currentPath.length < 2 ||
        !_cn.containsKey(currentPath[0]) ||
        !_cn.containsKey(currentPath[1])) return null;
    return atan2(
      ((_cn[currentPath[1]]['y'] as num) - (_cn[currentPath[0]]['y'] as num))
          .toDouble(),
      ((_cn[currentPath[1]]['x'] as num) - (_cn[currentPath[0]]['x'] as num))
          .toDouble(),
    );
  }

  String get _remText {
    if (currentPath.isEmpty || _tracker.totalRoutePx == 0) return '';
    final remPx =
        (_tracker.totalRoutePx - _traveled).clamp(0.0, double.infinity);
    final remM = (remPx * AppConfig.metersPerPx).toStringAsFixed(0);
    return 'あと約 $remM m';
  }

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
    return Scaffold(
      appBar: AppBar(
        title: Text(
            startNode == null
                ? '現在地を選択 (マップタップ or リスト)'
                : (goalNode == null
                    ? '目的地を選択 (マップタップ or リスト)'
                    : '目的地: $goalNode'),
            style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () => _showDestinationPicker(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(children: [
            // マップ切替チップ
            if (_nodes.length > 1)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                    children: _nodes.keys
                        .map((label) => Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
                              child: ChoiceChip(
                                label: Text(label),
                                selected: _currentLabel == label,
                                // ★ 表示フロアを切り替えるだけ。
                                //    _floorPaths から引くので再計算不要。
                                onSelected: (_) => setState(() {
                                  _currentLabel = label;
                                  _calculateViewRoute();
                                }),
                              ),
                            ))
                        .toList()),
              ),

            // コンパス
            if (_showCompass && currentPath.isNotEmpty)
              Row(children: [
                Expanded(
                    child: CompassIndicator(
                        heading: _heading, routeAngleRad: _routeAngle)),
                IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _showCompass = false)),
              ]),

            // 残り距離
            if (_remText.isNotEmpty)
              Container(
                width: double.infinity,
                color: Colors.cyan.shade50,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(_remText,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.cyan.shade800)),
              ),

            // チェックポイントパネル
            if (_physicalPath.isNotEmpty)
              WaypointPanel(
                orderedGates: _tracker.orderedGates,
                passed: _passed,
                nextGate: _nextGate,
                onConfirm: (key) {
                  _passed.add(key);
                  _tracker.confirmGate(key);
                  setState(() {});

                  // ★ 課題C修正: _trackerLabel で判定（_labelOf に依存しない）
                  if (goalNode != null &&
                      _tracker.nextGate == null &&
                      _labelOf(goalNode) == _trackerLabel) {
                    _onArrived();
                  }
                },
                onArrived: null,
                // ★ 課題C修正: nextGate==null かつ goalが別フロアのときのみ表示
                //   （以前は _crossFloorLabelForTracker を常にそのまま渡していた）
                crossFloorLabel: (_nextGate == null &&
                        _crossFloorLabelForTracker != null &&
                        _labelOf(goalNode) != _trackerLabel)
                    ? _crossFloorLabelForTracker
                    : null,
                onCrossFloor: (_nextGate == null &&
                        _crossFloorLabelForTracker != null &&
                        _labelOf(goalNode) != _trackerLabel)
                    ? () => _handleCrossFloor(_crossFloorLabelForTracker!)
                    : null,
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
                          size: const Size(
                              AppConfig.mapCanvasSize, AppConfig.mapCanvasSize),
                          painter: MapPainter(
                            nodes: _cn,
                            cells: _cc,
                            rooms: _cr,
                            path: currentPath,
                            startNode: startNode,
                            goalNode: goalNode,
                            goalCenter: _goalCenter,
                            startCenter: _startCenter,
                            currentLabel: _currentLabel,
                            estimatedPosition: _estPos,
                            headingDeg: _heading,
                            // ★ _trackerLabel == _currentLabel のときだけ
                            //    現在地ドットを表示する。
                            //    表示フロアと物理フロアが一致するときのみ有効。
                            showUserDot: startNode != null &&
                                _trackerLabel == _currentLabel,
                            isGoalOnCurrentFloor: goalNode != null &&
                                _labelOf(goalNode) == _currentLabel,
                            isStartOnCurrentFloor: startNode != null &&
                                _labelOf(startNode) == _currentLabel,
                          ),
                        ),
                ),
              ),
            ),
          ]),

          // リセットボタン
          Positioned(
            left: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'reset',
              mini: true,
              backgroundColor: Colors.white,
              foregroundColor: Colors.red.shade700,
              onPressed: () {
                setState(() {
                  startNode = null;
                  _startLabel = null; // ★ 追加
                  goalNode = null;
                  _startCenter = null;
                  _goalCenter = null;
                  currentPath.clear();
                  _floorPaths.clear();
                  _passed.clear();
                  _nextGate = null;
                  _followMode = false;
                  _showCompass = false;
                  _trackerLabel = _currentLabel;
                });
                _showInfo('位置を全てリセットしました。現在地を選択してください。');
              },
              child: const Icon(Icons.location_off),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_estPos != null)
            FloatingActionButton(
              heroTag: 'follow',
              mini: true,
              backgroundColor:
                  _followMode ? Colors.cyan.shade600 : Colors.white,
              foregroundColor:
                  _followMode ? Colors.white : Colors.grey.shade700,
              onPressed: () {
                if (!_followMode) {
                  // ★ follow ボタンで _trackerLabel のフロアに自動ジャンプ
                  if (_trackerLabel != _currentLabel) {
                    setState(() {
                      _currentLabel = _trackerLabel;
                      _calculateViewRoute();
                    });
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
              setState(() {
                _currentLabel =
                    labels[(labels.indexOf(_currentLabel) + 1) % labels.length];
                _calculateViewRoute();
              });
            },
            label: Text('$_currentLabel (切替)'),
            icon: const Icon(Icons.layers),
            backgroundColor: Colors.white,
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            heroTag: 'qr',
            onPressed: () async {
              final r = await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const QRScannerScreen()));
              if (r != null) _onQRScanned(r);
            },
            label: const Text('QRスキャン'),
            icon: const Icon(Icons.qr_code_scanner),
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
        builder: (ctx, setLocalState) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(startNode == null ? '出発地を選択' : '目的地検索',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
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
                    return list
                        .toSet()
                        .where((v) =>
                            v != currentRoomName &&
                            v.toLowerCase().contains(filter.toLowerCase()))
                        .toList();
                  })()
                      .map((v) => ListTile(
                            title: Text(v),
                            onTap: () {
                              if (startNode == null) {
                                setState(() {
                                  startNode = v;
                                  _startLabel =
                                      _labelOf(v) ?? _currentLabel; // ★
                                  _currentLabel = _startLabel!;
                                  _showCompass = true;
                                  _updatePath();
                                });
                                _showInfo('現在地を「$v」に設定しました');
                              } else {
                                setState(() {
                                  goalNode = v;
                                  if (_startLabel != null &&
                                      _startLabel != _currentLabel) {
                                    _currentLabel = _startLabel!;
                                  }
                                  _updatePath();
                                });
                                _showInfo('目的地を「$v」に設定しました');
                              }
                              Navigator.pop(ctx);
                              if (startNode != null)
                                WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => _focusNode(startNode!));
                            },
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

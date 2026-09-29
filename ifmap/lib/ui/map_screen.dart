// lib/ui/map_screen.dart
//
// ナビゲーション画面。状態は NavigationController が持ち、
// ここは「描く」「触られたら伝える」だけを担当する。
//
// 通知の出し方の方針:
//   スナックバー  … 結果の報告（現在地を設定した、など）。消えてよい。
//   バナー        … 提案（階を移動した？ 別の建物に来た？）。
//                   歩きながら見るものなので操作を止めない。
//   ダイアログ    … 到着だけ。ナビが終わる区切りなので止めてよい。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config.dart';
import '../data/map_data.dart';
import '../navigation/navigation_controller.dart';
import '../navigation/suggestion_policy.dart';
import 'compass_indicator.dart';
import 'map_view.dart';
import 'qr_scanner_screen.dart';
import 'sensor_debug_sheet.dart';
import 'waypoint_panel.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _controller = NavigationController();
  final _transformation = TransformationController();
  final _mapKey = GlobalKey();

  final _subs = <StreamSubscription<dynamic>>[];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _subs.add(_controller.messages.listen(_showMessage));
    _subs.add(_controller.arrivals.listen(_showArrivalDialog));
    _subs.add(_controller.focusRequests.listen(_centerOn));
    _controller.position.addListener(_onPositionChanged);
    _controller.suggestion.addListener(_onSuggestionChanged);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _controller.position.removeListener(_onPositionChanged);
    _controller.suggestion.removeListener(_onSuggestionChanged);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _transformation.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onPositionChanged() {
    final p = _controller.position.value;
    if (_controller.followMode && p != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerOn(p));
    }
  }

  // ─── 通知 ─────────────────────────────────────────────────────

  void _showMessage(AppMessage message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(message.text),
      duration: const Duration(seconds: 2),
      backgroundColor:
          message.kind == MessageKind.error ? Colors.red.shade700 : null,
    ));
  }

  /// 提案はバナーで出す。以前はダイアログだったが、歩いている最中に
  /// 画面を塞いでしまい、無視するにも操作が要るのでバナーに変えた。
  void _onSuggestionChanged() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final s = _controller.suggestion.value;
    if (s == null) {
      messenger.hideCurrentMaterialBanner();
      return;
    }
    messenger.hideCurrentMaterialBanner();
    messenger.showMaterialBanner(MaterialBanner(
      content: Text('${s.title}\n${s.message}'),
      leading: Icon(s.kind == SuggestionKind.floorChange
          ? Icons.stairs
          : Icons.apartment),
      backgroundColor: Colors.amber.shade50,
      actions: [
        TextButton(
          onPressed: () {
            messenger.hideCurrentMaterialBanner();
            _controller.dismissSuggestion(s);
          },
          child: const Text('あとで'),
        ),
        FilledButton(
          onPressed: () {
            messenger.hideCurrentMaterialBanner();
            _controller.acceptSuggestion(s);
          },
          child: const Text('切り替える'),
        ),
      ],
    ));
  }

  void _showArrivalDialog(PlaceRef goal) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🎉 到着！'),
        content: Text('「${goal.name}」に到着しました！'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _controller.reset();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ─── 表示操作 ─────────────────────────────────────────────────

  Size get _viewportSize {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size ?? MediaQuery.of(context).size;
  }

  void _centerOn(Offset p) {
    final size = _viewportSize;
    const scale = AppConfig.focusScale;
    _transformation.value = Matrix4.identity()
      ..translateByDouble(
        -p.dx * scale + size.width / 2,
        -p.dy * scale + size.height * AppConfig.focusVerticalRatio,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  /// フロアを切り替えたとき、そのフロアのマップが画面に入るよう寄せる。
  /// マップごとに使っている範囲が違うので、原点合わせだと外れることがある。
  void _centerOnFloorExtent() {
    final floor = _controller.currentFloor;
    if (floor == null) return;

    var minX = double.infinity, maxX = double.negativeInfinity;
    var minY = double.infinity, maxY = double.negativeInfinity;
    for (final v in floor.nodes.values) {
      if (v is! Map) continue;
      final x = (v['x'] as num?)?.toDouble();
      final y = (v['y'] as num?)?.toDouble();
      if (x == null || y == null) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    var cx = AppConfig.mapCanvasSize / 2;
    var cy = AppConfig.mapCanvasSize / 2;
    if (minX <= maxX && minY <= maxY) {
      cx = (minX + maxX) / 2;
      cy = (minY + maxY) / 2;
    }

    final size = _viewportSize;
    final scale = _transformation.value.getMaxScaleOnAxis();
    _transformation.value = Matrix4.identity()
      ..translateByDouble(
          -cx * scale + size.width / 2, -cy * scale + size.height / 2, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _showFloor(String label) {
    _controller.showFloor(label);
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnFloorExtent());
  }

  // ─── build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    // 最初に画面を触ったときにセンサー許可を自動で求める（Web のみ意味がある）。
    // iOS はタッチを離した瞬間しか「ユーザー操作」と認めないので onPointerUp。
    return Listener(
      onPointerUp: (_) => c.autoEnableWebSensors(),
      child: _buildScaffold(c),
    );
  }

  Widget _buildScaffold(NavigationController c) {
    return Scaffold(
      drawer: _buildDrawer(),
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          Column(children: [
            if (c.loadState == LoadState.loading) _buildLoadingBar(),
            if (c.repo.labels.length > 1) _buildFloorChips(),
            if (c.showCompass && c.currentPath.isNotEmpty) _buildCompass(),
            _buildRemainingDistance(),
            if (c.physicalPath.isNotEmpty) _buildWaypoints(),
            Expanded(
              key: _mapKey,
              child: c.loadState == LoadState.failed
                  ? const Center(child: Text('マップを読み込めませんでした'))
                  : MapView(
                      controller: c,
                      transformation: _transformation,
                      onPlaceTapped: c.selectPlaceFromMap,
                    ),
            ),
          ]),
          Positioned(left: 16, bottom: 16, child: _buildResetButton()),
        ],
      ),
      floatingActionButton: _buildActionButtons(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final c = _controller;
    final title = c.start == null
        ? '現在地を選択 (マップタップ or リスト)'
        : (c.goal == null ? '目的地を選択 (マップタップ or リスト)' : '目的地: ${c.goal!.name}');
    return AppBar(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      backgroundColor: Colors.white,
      elevation: 0,
      actions: [
        IconButton(
          tooltip: 'センサー診断',
          icon: const Icon(Icons.bug_report, color: Colors.orange),
          onPressed: () => showSensorDebugSheet(context, c),
        ),
        IconButton(
          tooltip: '一覧から選ぶ',
          icon: const Icon(Icons.list),
          onPressed: _showPlacePicker,
        ),
      ],
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.cyan),
            child: Text('設定',
                style: TextStyle(color: Colors.white, fontSize: 24)),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AppSettings.barometerEnabled,
            builder: (_, value, __) => SwitchListTile(
              title: const Text('気圧センサ (フロア移動検知)'),
              subtitle: const Text('未対応機種ではオフにしてください'),
              value: value,
              onChanged: (v) => AppSettings.barometerEnabled.value = v,
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AppSettings.gpsEnabled,
            builder: (_, value, __) => SwitchListTile(
              title: const Text('GPS (建物接近検知)'),
              subtitle: const Text('屋内でGPSが誤作動する場合はオフに'),
              value: value,
              onChanged: (v) => AppSettings.gpsEnabled.value = v,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingBar() {
    final c = _controller;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Text('マップを読み込み中… (${c.floorsLoaded}/${c.floorsTotal})',
              style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: c.floorsTotal == 0 ? null : c.floorsLoaded / c.floorsTotal,
          ),
        ],
      ),
    );
  }

  Widget _buildFloorChips() {
    final c = _controller;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final label in c.repo.labels)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: ChoiceChip(
                label: Text(label),
                selected: c.currentLabel == label,
                // 表示を切り替えるだけ。経路は全フロア分すでに計算済み。
                onSelected: (_) => _showFloor(label),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompass() {
    final c = _controller;
    return Row(children: [
      Expanded(
        child: ValueListenableBuilder<double?>(
          valueListenable: c.heading,
          builder: (_, heading, __) => CompassIndicator(
            heading: heading,
            routeAngleRad: _routeAngleRad(),
            onEnable: c.sensorPermissionNeeded ? c.enableWebSensors : null,
          ),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.close, size: 18),
        onPressed: c.hideCompass,
      ),
    ]);
  }

  /// 経路の最初の区間がキャンバス上でどちらを向いているか。
  double? _routeAngleRad() {
    final c = _controller;
    final path = c.currentPath;
    final floor = c.currentFloor;
    if (floor == null || path.length < 2) return null;
    final a = floor.nodes[path[0]];
    final b = floor.nodes[path[1]];
    if (a is! Map || b is! Map) return null;
    final dx = (b['x'] as num).toDouble() - (a['x'] as num).toDouble();
    final dy = (b['y'] as num).toDouble() - (a['y'] as num).toDouble();
    return math.atan2(dy, dx);
  }

  Widget _buildRemainingDistance() {
    return ValueListenableBuilder<double>(
      valueListenable: _controller.traveledPx,
      builder: (_, __, ___) {
        final meters = _controller.remainingMeters;
        if (meters == null) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: Colors.cyan.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text('あと約 ${meters.toStringAsFixed(0)} m',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.cyan.shade800)),
        );
      },
    );
  }

  Widget _buildWaypoints() {
    final c = _controller;
    return WaypointPanel(
      orderedGates: c.orderedGates,
      passed: c.passedGates,
      nextGate: c.nextGate,
      onConfirm: c.confirmGate,
      crossFloorLabel: c.canAdvanceFloor ? c.nextFloorLabel : null,
      onCrossFloor: c.canAdvanceFloor
          ? () => _controller.advanceToFloor(c.nextFloorLabel!)
          : null,
    );
  }

  Widget _buildResetButton() {
    return FloatingActionButton(
      heroTag: 'reset',
      mini: true,
      tooltip: '現在地と目的地をリセット',
      backgroundColor: Colors.white,
      foregroundColor: Colors.red.shade700,
      onPressed: _controller.reset,
      child: const Icon(Icons.location_off),
    );
  }

  Widget _buildActionButtons() {
    final c = _controller;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ValueListenableBuilder<Offset?>(
          valueListenable: c.position,
          builder: (_, pos, __) => pos == null
              ? const SizedBox.shrink()
              : FloatingActionButton(
                  heroTag: 'follow',
                  mini: true,
                  tooltip: '現在地を追いかける',
                  backgroundColor:
                      c.followMode ? Colors.cyan.shade600 : Colors.white,
                  foregroundColor:
                      c.followMode ? Colors.white : Colors.grey.shade700,
                  onPressed: () => c.setFollowMode(!c.followMode),
                  child: Icon(
                      c.followMode ? Icons.gps_fixed : Icons.gps_not_fixed),
                ),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.extended(
          heroTag: 'floor',
          onPressed: () {
            c.showNextFloor();
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _centerOnFloorExtent());
          },
          label: Text('${c.currentLabel} (切替)'),
          icon: const Icon(Icons.layers),
          backgroundColor: Colors.white,
        ),
        const SizedBox(height: 16),
        FloatingActionButton.extended(
          heroTag: 'qr',
          onPressed: _scanQr,
          label: const Text('QRスキャン'),
          icon: const Icon(Icons.qr_code_scanner),
        ),
      ],
    );
  }

  Future<void> _scanQr() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerScreen()),
    );
    if (code != null) await _controller.handleScannedCode(code);
  }

  // ─── 場所の一覧 ───────────────────────────────────────────────

  void _showPlacePicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PlacePicker(
        controller: _controller,
        onSelected: (place) {
          Navigator.pop(ctx);
          unawaited(_controller.start == null
              ? _controller.setStart(place)
              : _controller.setGoal(place));
        },
      ),
    );
  }

}

/// 出発地・目的地の一覧。
///
/// 何も入力していないときは表示中のフロアだけを出す。検索を始めたら
/// 全フロアを対象にし、どのフロアの場所かをその場で見せる。
/// 同じ名前の部屋が複数フロアにあるので、名前だけ返すと取り違える。
class _PlacePicker extends StatefulWidget {
  final NavigationController controller;
  final void Function(PlaceRef place) onSelected;

  const _PlacePicker({required this.controller, required this.onSelected});

  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final query = _search.text.trim().toLowerCase();
    final showAllFloors = query.isNotEmpty;

    final places = c
        .repo.destinations(label: showAllFloors ? null : c.currentLabel)
        .where((p) => p != c.start)
        .where((p) => p.name.toLowerCase().contains(query))
        .toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(c.start == null ? '出発地を選択' : '目的地を選択',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              autofocus: false,
              decoration: const InputDecoration(
                hintText: '部屋名や番号を入力... (全フロアから検索)',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: places.isEmpty
                ? const Center(child: Text('見つかりませんでした'))
                : ListView.builder(
                    itemCount: places.length,
                    itemBuilder: (_, i) {
                      final place = places[i];
                      return ListTile(
                        title: Text(place.name),
                        // 同名の部屋を取り違えないよう、検索中は必ず階を出す。
                        subtitle: showAllFloors ? Text(place.label) : null,
                        onTap: () => widget.onSelected(place),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// lib/ui/map_screen.dart
//
// ナビゲーション画面。状態は NavigationController が持ち、
// ここは「描く」「触られたら伝える」「カメラをどこへ向けるか」を担当する。
//
// 画面の組み立て（Google マップと同じ考え方）:
//   地図      … 全画面。UIはすべてその上に浮かべる。
//   上        … 検索欄と分類チップ。案内中は「次にすること」のバナー。
//   右        … 階の切り替え。回転しているときは方位磁針。
//   右下      … 現在地ボタン（追従 → 進行方向を上 の切り替え）。
//   下のシート … いまの状況でできること（場所の情報・経路・案内・到着）。
//
// 通知の出し方の方針:
//   トースト … 結果の報告（現在地を設定した、など）。消えてよい。
//   提案カード … 階を移動した？ 別の建物に来た？ 操作を止めない。
//   到着     … シートを到着の表示に切り替える。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../data/map_data.dart';
import '../navigation/navigation_controller.dart';
import '../navigation/route_guide.dart';
import 'format.dart';
import 'map/floor_geometry.dart';
import 'map/map_camera.dart';
import 'map/map_painter.dart';
import 'map/map_viewport.dart';
import 'place_category.dart';
import 'qr_scanner_screen.dart';
import 'search_screen.dart';
import 'sensor_debug_sheet.dart';
import 'theme.dart';
import 'widgets/map_overlays.dart';
import 'widgets/nav_banner.dart';
import 'widgets/sheets.dart';

enum _Mode { loading, failed, setLocation, located, place, preview, navigating, arrived }

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _controller = NavigationController();
  final _view = MapViewController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _rightControlsKey = GlobalKey();
  final _locationButtonKey = GlobalKey();
  final _subs = <StreamSubscription<dynamic>>[];

  @visibleForTesting
  NavigationController get debugController => _controller;

  @visibleForTesting
  MapViewController get debugView => _view;

  /// 地図上の場所をタップしたのと同じ（画面の確認・テスト用）。
  @visibleForTesting
  void debugSelect(PlaceRef place) => _selectPlace(place);

  /// 地図や検索で選んだ場所（まだ現在地にも目的地にもしていない）。
  PlaceRef? _selected;

  /// 「案内を開始」を押した後か。押す前は経路の確認画面。
  bool _navigating = false;

  /// カメラが現在地を追いかけているか。
  bool _follow = false;

  /// 追従中、進む方向を画面の上に向けるか（北を上にしない）。
  bool _courseUp = false;

  bool _stepsExpanded = false;

  /// 進む向きと反対を向いている（方位が分かるときだけ）。
  bool _wrongWay = false;

  double _topHeight = 132;
  double _sheetHeight = 0;

  String? _toast;
  bool _toastError = false;
  Timer? _toastTimer;

  bool _fittedInitial = false;

  /// 起動後、何かがカメラを動かした（URLの ?start= で現在地へ寄せた など）。
  /// そのときは起動時の「全体を表示」で上書きしない。
  bool _cameraClaimed = false;
  (PlaceRef?, PlaceRef?)? _fittedRoute;
  String? _userLabel;

  /// 直前の「全体を見せる」操作。シートの高さが変わった直後にやり直す
  /// （シートが伸びて経路が隠れるのを防ぐ）。
  VoidCallback? _lastFit;
  DateTime _lastFitAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    final c = _controller;
    c.addListener(_onControllerChanged);
    _subs.add(c.messages.listen(_showMessage));
    _subs.add(c.arrivals.listen(_onArrived));
    _subs.add(c.focusRequests.listen(_onFocusRequest));
    c.traveledPx.addListener(_onProgress);
    c.position.addListener(_onProgress);
    c.heading.addListener(_onHeading);
    c.suggestion.addListener(_rebuild);
    _view.onUserMove = _onUserMove;
    unawaited(c.initialize());
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    final c = _controller;
    c.traveledPx.removeListener(_onProgress);
    c.position.removeListener(_onProgress);
    c.heading.removeListener(_onHeading);
    c.suggestion.removeListener(_rebuild);
    c.removeListener(_onControllerChanged);
    c.dispose();
    _view.dispose();
    _toastTimer?.cancel();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  // ─── コントローラからの知らせ ─────────────────────────────────

  void _onControllerChanged() {
    if (!mounted) return;
    final c = _controller;
    if (!_fittedInitial && c.currentFloor != null) {
      _fittedInitial = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_cameraClaimed) _fitFloor(animate: false);
      });
    }
    if (c.goal == null && _navigating) _exitNavigation();

    // 経路が出たら全体を見せる（案内を始める前の確認）。
    final key = (c.start, c.goal);
    if (c.goal != null && c.floorPaths.isNotEmpty && _fittedRoute != key) {
      _fittedRoute = key;
      if (!_navigating) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitRoute());
      }
    }
    _syncUser();
    setState(() {});
  }

  void _onProgress() {
    if (!mounted) return;
    _syncUser();
    setState(() {});
  }

  void _onHeading() {
    final h = _controller.heading.value;
    _view.setHeading(
        h == null ? null : (h - AppConfig.mapNorthDegrees) * math.pi / 180);
    final wrong = _computeWrongWay();
    if (wrong != _wrongWay && mounted) setState(() => _wrongWay = wrong);
  }

  bool _computeWrongWay() {
    final c = _controller;
    final h = c.heading.value;
    if (!_navigating || h == null || c.goal == null) return false;
    final geo = c.routeGeometry(c.trackerLabel);
    if (geo == null) return false;
    final route = geo.headingAt(c.traveledPx.value);
    final facing = (h - AppConfig.mapNorthDegrees) * math.pi / 180;
    return wrapAngle(route - facing).abs() > 2.4; // 約137°
  }

  void _onUserMove() {
    if (_follow && mounted) setState(() => _follow = false);
  }

  void _onFocusRequest(Offset p) {
    _cameraClaimed = true;
    if (_navigating && _follow) return;
    _view.moveTo(p, zoom: math.max(_view.camera.zoom, _roomZoom));
  }

  /// 部屋を見せるときのズーム。部屋とそのまわり（約40m四方）が入るくらい。
  static const double _roomZoom = 0.5;

  /// 地図の上に浮いている UI の場所。部屋名をその下に出さないために使う。
  List<Rect> get _obstacles => [
        for (final key in [_rightControlsKey, _locationButtonKey])
          if (key.currentContext?.findRenderObject() case final RenderBox box
              when box.hasSize && box.attached)
            box.localToGlobal(Offset.zero) & box.size,
      ];

  void _onArrived(PlaceRef goal) {
    HapticFeedback.heavyImpact();
    setState(() {
      _follow = false;
      _stepsExpanded = false;
    });
    final center = _controller.repo.floor(goal.label)?.centerOf(goal.name);
    if (center != null) _view.moveTo(center, bearing: 0);
  }

  void _showMessage(AppMessage m) {
    if (!mounted) return;
    _toastTimer?.cancel();
    setState(() {
      _toast = m.text;
      _toastError = m.kind == MessageKind.error;
    });
    _toastTimer = Timer(Duration(milliseconds: _toastError ? 4000 : 2600), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  // ─── 現在地とカメラ ───────────────────────────────────────────

  void _syncUser() {
    final c = _controller;
    final loc = c.currentLocation;
    if (loc == null) {
      _userLabel = null;
      _view.setUserPosition(null);
      return;
    }
    final (p, label) = loc;
    final jumped = label != _userLabel;
    _userLabel = label;
    _view.setUserPosition(p, animate: !jumped);
    if (_follow && label == c.currentLabel) _followCamera(p);
  }

  void _followCamera(Offset p, {double? zoom}) {
    final c = _controller;
    var bearing = 0.0;
    if (_courseUp) {
      final geo = c.goal == null ? null : c.routeGeometry(c.trackerLabel);
      bearing = geo?.headingAt(c.traveledPx.value) ?? _view.camera.bearing;
    }
    _view.moveTo(p,
        zoom: zoom,
        bearing: bearing,
        duration: const Duration(milliseconds: 750),
        curve: Curves.easeOutCubic);
  }

  EdgeInsets get _mapPadding =>
      EdgeInsets.only(top: _topHeight + 4, bottom: _sheetHeight + 4);

  void _fitFloor({bool animate = true}) {
    final floor = _controller.currentFloor;
    if (floor == null) return;
    final geo = FloorGeometry.of(floor);
    _remember(() => _view.fitBounds(geo.extent,
        bearing: 0, maxZoom: 1.0, animate: animate));
  }

  void _fitRoute() {
    final c = _controller;
    final geo = c.routeGeometry(c.currentLabel);
    if (geo == null) return;
    var bounds = geo.bounds;
    final g = c.goal;
    if (g != null && g.label == c.currentLabel) {
      final center = c.currentFloor?.centerOf(g.name);
      if (center != null) bounds = bounds.expandToInclude(Rect.fromCircle(center: center, radius: 20));
    }
    _remember(() => _view.fitBounds(bounds.inflate(30), bearing: 0, maxZoom: 1.4));
  }

  void _remember(VoidCallback fit) {
    _lastFit = fit;
    _lastFitAt = DateTime.now();
    fit();
  }

  void _onSheetSize(Size size) {
    if (!mounted || size.height == _sheetHeight) return;
    setState(() => _sheetHeight = size.height);
    if (DateTime.now().difference(_lastFitAt) < const Duration(milliseconds: 900)) {
      // 余白を反映した次のフレームでやり直す。
      WidgetsBinding.instance.addPostFrameCallback((_) => _lastFit?.call());
    }
  }

  void _onTopSize(Size size) {
    if (!mounted || size.height == _topHeight) return;
    setState(() => _topHeight = size.height);
  }

  // ─── 操作 ─────────────────────────────────────────────────────

  void _showFloor(String label) {
    final c = _controller;
    if (label == c.currentLabel) return;
    final before = c.currentFloor;
    c.showFloor(label);
    setState(() => _follow = false);
    final after = c.currentFloor;
    if (before == null || after == null) return;
    // 同じ建物の別の階は同じ座標で描いてあるので、見ている場所を保つ
    // （上の階の同じ位置が見える）。建物や縮尺が違う図なら全体を見せる。
    final sameBuilding = before.section.buildingName == after.section.buildingName &&
        before.section.outdoor == after.section.outdoor;
    final ext = FloorGeometry.of(after).extent;
    if (!sameBuilding || !_view.visibleMapRect.overlaps(ext)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitFloor());
    }
  }

  void _onMapTap(Offset mapPoint, Offset screenPoint) {
    final mode = _mode;
    if (mode == _Mode.navigating || mode == _Mode.preview || mode == _Mode.arrived) {
      return;
    }
    final floor = _controller.currentFloor;
    if (floor == null) return;
    final geo = FloorGeometry.of(floor);
    var name = geo.nameAt(mapPoint);
    if (name == null) {
      // 小さな部屋はマスを狙いにくいので、ラベルの近くを押してもよい。
      var best = 26.0 * 26.0;
      for (final room in geo.rooms) {
        if (room.name.isEmpty) continue;
        final d = (_view.toScreen(room.anchor) - screenPoint).distanceSquared;
        if (d < best) {
          best = d;
          name = room.name;
        }
      }
    }
    final room = name == null ? null : geo.roomByName[name];
    if (name == null ||
        room?.isConnector == true ||
        floor.nodeIdOf(name) == null) {
      if (_selected != null) setState(() => _selected = null);
      return;
    }
    HapticFeedback.selectionClick();
    _selectPlace(PlaceRef(name, floor.label), fly: false);
  }

  void _selectPlace(PlaceRef place, {bool fly = true}) {
    _cameraClaimed = true;
    final c = _controller;
    setState(() {
      _selected = place;
      _follow = false;
    });
    if (c.currentLabel != place.label) {
      c.showFloor(place.label);
      fly = true;
    }
    final floor = c.repo.floor(place.label);
    if (floor == null) return;
    final room = FloorGeometry.of(floor).roomByName[place.name];
    final center = floor.centerOf(place.name);
    if (fly) {
      if (room != null) {
        final grow = math.max(room.bounds.width, room.bounds.height) * 1.2 + 60;
        _remember(() => _view.fitBounds(room.bounds.inflate(grow), maxZoom: 1.6));
      } else if (center != null) {
        _remember(() => _view.moveTo(center, zoom: math.max(_view.camera.zoom, _roomZoom)));
      }
    } else if (center != null) {
      // シートに隠れる位置なら少しずらして見せる。
      _remember(() {
        final s = _view.toScreen(center);
        final size = _view.size;
        if (s.dy > size.height - _sheetHeight - 60 || s.dy < _topHeight + 20) {
          _view.moveTo(center);
        }
      });
    }
  }

  Future<void> _scanQr() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerScreen()),
    );
    if (code == null) return;
    setState(() => _selected = null);
    await _controller.handleScannedCode(code);
  }

  Future<void> _openSearch({PlaceCategory? category, bool pickingStart = false}) async {
    final place = await Navigator.push<PlaceRef>(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) => PlaceSearchScreen(
          controller: _controller,
          initialCategory: category,
          pickingStart: pickingStart,
        ),
        transitionsBuilder: (_, a, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
    if (place == null || !mounted) return;
    if (pickingStart) {
      setState(() => _selected = null);
      await _controller.setStart(place);
    } else {
      _selectPlace(place);
    }
  }

  void _setHere(PlaceRef place) {
    setState(() => _selected = null);
    unawaited(_controller.setStart(place));
  }

  void _routeTo(PlaceRef place) {
    setState(() {
      _selected = null;
      _stepsExpanded = false;
    });
    unawaited(_controller.setGoal(place));
  }

  void _startNavigation() {
    final c = _controller;
    HapticFeedback.mediumImpact();
    setState(() {
      _navigating = true;
      _follow = true;
      _courseUp = true;
      _stepsExpanded = false;
    });
    c.showFloor(c.trackerLabel);
    _view.setFocusRatio(0.64);
    final loc = c.currentLocation;
    if (loc != null) _followCamera(loc.$1, zoom: math.max(_view.camera.zoom, 1.1));
  }

  void _exitNavigation() {
    _navigating = false;
    _follow = false;
    _courseUp = false;
    _stepsExpanded = false;
    _wrongWay = false;
    _view.setFocusRatio(0.5);
    if (_view.camera.bearing != 0) _view.resetBearing();
  }

  void _endNavigation() {
    setState(_exitNavigation);
    unawaited(_controller.cancelNavigation());
  }

  void _finishNavigation() {
    setState(_exitNavigation);
    unawaited(_controller.finishNavigation());
  }

  void _onLocationButton() {
    final c = _controller;
    final loc = c.currentLocation;
    if (loc == null) {
      unawaited(_scanQr());
      return;
    }
    if (!_follow) {
      setState(() => _follow = true);
      if (c.currentLabel != loc.$2) c.showFloor(loc.$2);
      _followCamera(loc.$1, zoom: math.max(_view.camera.zoom, _roomZoom));
      return;
    }
    if (c.goal != null) {
      setState(() => _courseUp = !_courseUp);
      _followCamera(loc.$1);
    } else {
      _view.moveTo(loc.$1, zoom: math.min(_view.camera.zoom * 1.8, 2.5));
    }
  }

  void _chooseBuilding() {
    final c = _controller;
    final buildings = <String, List<MapSection>>{};
    for (final s in AppConfig.mapSections) {
      if (c.repo.floor(s.label) == null) continue;
      buildings.putIfAbsent(s.buildingName, () => []).add(s);
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      // 建物は20以上あるので、画面の高さを超えたらスクロールする。
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      builder: (ctx) => SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
            child: Row(children: [
              const Expanded(
                child: Text('建物を選ぶ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: '閉じる',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ]),
          ),
          const Divider(),
          Expanded(
            child: ListView(children: [
              for (final e in buildings.entries)
                ListTile(
                  leading: const Icon(Icons.apartment, color: AppColors.textSecondary),
                  title: Text(e.key),
                  subtitle: Text(e.value.map((s) => s.floorDisplayName).join(' · ')),
                  trailing: e.key == c.currentFloor?.section.buildingName
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    final target = e.value.firstWhere(
                        (s) => s.label == c.trackerLabel || s.label == c.goal?.label,
                        orElse: () => e.value.firstWhere((s) => !s.outdoor, orElse: () => e.value.first));
                    _showFloor(target.label);
                  },
                ),
              const SizedBox(height: 8),
            ]),
          ),
        ]),
      ),
    );
  }

  bool get _dismissible => _selected != null || (_controller.goal != null && !_navigating);

  void _dismiss() {
    if (_selected != null) {
      setState(() => _selected = null);
    } else if (_controller.goal != null && !_navigating) {
      unawaited(_controller.cancelNavigation());
    }
  }

  // ─── 状態 ─────────────────────────────────────────────────────

  _Mode get _mode {
    final c = _controller;
    if (c.loadState == LoadState.failed) return _Mode.failed;
    if (c.goal != null) {
      if (c.arrived) return _Mode.arrived;
      return _navigating ? _Mode.navigating : _Mode.preview;
    }
    if (_selected != null) return _Mode.place;
    if (c.loadState == LoadState.loading) return _Mode.loading;
    return c.start == null ? _Mode.setLocation : _Mode.located;
  }

  // ─── 地図に描くもの ───────────────────────────────────────────

  MapScene? _scene(BuildContext context) {
    final c = _controller;
    final floor = c.currentFloor;
    if (floor == null) return null;
    final label = floor.label;
    final labels = c.routeLabels;
    final here = labels.indexOf(label);
    final walking = labels.indexOf(c.trackerLabel);
    final route = c.goal == null ? null : c.routeGeometry(label);

    final leg = here == walking
        ? RouteLeg.active
        : (here > walking ? RouteLeg.upcoming : RouteLeg.done);

    final checkpoints = <MapCheckpoint>[];
    if (route != null && leg == RouteLeg.active) {
      final next = c.nextGate?.key;
      // 目印は案内の手順にないもの（30mごとの「現在地を確認」）も出す。
      for (final g in c.checkpoints) {
        if (c.passedGates.contains(g.key)) continue;
        final s = RouteGuide.gateStep(g);
        checkpoints.add(MapCheckpoint(
          route.pointAt(s.at),
          maneuverIcon(s.maneuver),
          checkpointColor(s.maneuver),
          isNext: s.gateKey == next,
        ));
      }
    }

    MapTransfer? transfer;
    if (route != null && here != -1 && here < labels.length - 1) {
      final to = labels[here + 1];
      final a = AppConfig.sectionOf(label), b = AppConfig.sectionOf(to);
      final stairs = a != null && b != null && a.buildingName == b.buildingName && !a.outdoor && !b.outdoor;
      final up = (b?.floorLevel ?? 0) > (a?.floorLevel ?? 0);
      transfer = MapTransfer(
        route.display.last,
        stairs ? '${AppConfig.floorNameOf(to)}へ${up ? '上る' : '下りる'}' : '${AppConfig.displayNameOf(to)}へ',
        stairs ? Icons.stairs : Icons.swap_horiz,
      );
    }

    final loc = c.currentLocation;
    final showUser = loc != null && loc.$2 == label;
    final start = c.start;
    final goal = c.goal;
    final selected = _selected;

    return MapScene(
      floor: floor,
      labelStyle: Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
      route: route,
      leg: leg,
      traveledPx: c.traveledPx.value,
      checkpoints: checkpoints,
      transfer: transfer,
      startPoint: route != null && !showUser && start?.label == label
          ? floor.centerOf(start!.name)
          : null,
      goalPoint: goal != null && goal.label == label ? floor.centerOf(goal.name) : null,
      goalName: goal != null && goal.label == label ? goal.name : null,
      pinPoint: selected != null && selected.label == label ? floor.centerOf(selected.name) : null,
      highlightName: selected != null && selected.label == label ? selected.name : null,
      showUser: showUser,
      // 誤差の円は歩いている最中だけ（止まっているときは点だけでよい）。
      uncertaintyPx: !_navigating
          ? 0
          : c.positionUncertaintyMeters / AppConfig.metersPerPx,
      obstacles: _obstacles,
    );
  }

  // ─── build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    // 最初に画面を触ったときにセンサー許可を自動で求める（Web のみ意味がある）。
    // iOS はタッチを離した瞬間しか「ユーザー操作」と認めないので onPointerUp。
    return Listener(
      onPointerUp: (_) => c.autoEnableWebSensors(),
      child: PopScope(
        canPop: !_dismissible,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _dismiss();
        },
        child: Scaffold(
          key: _scaffoldKey,
          drawer: _buildDrawer(),
          body: Stack(children: [
            Positioned.fill(
              child: MapViewport(
                view: _view,
                scene: _scene(context),
                padding: _mapPadding,
                onTap: _onMapTap,
              ),
            ),
            _buildTop(),
            _buildRightControls(),
            _buildBottomRightControls(),
            _buildRecenter(),
            _buildToast(),
            Positioned(left: 0, right: 0, bottom: 0, child: _buildSheet()),
          ]),
        ),
      ),
    );
  }

  Widget _buildTop() {
    final c = _controller;
    final mode = _mode;
    final suggestion = c.suggestion.value;

    Widget content;
    if (mode == _Mode.navigating) {
      content = _buildBanner() ?? const SizedBox.shrink();
    } else if (mode == _Mode.preview || mode == _Mode.arrived) {
      content = _RouteHeader(
        from: c.start == null ? '現在地' : c.placeTitle(c.start!),
        to: c.goal == null ? '' : c.placeTitle(c.goal!),
        onBack: _dismiss,
      );
    } else {
      content = Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: MapSearchBar(
            onMenu: () => _scaffoldKey.currentState?.openDrawer(),
            onSearch: () => _openSearch(pickingStart: c.start == null),
            onScan: _scanQr,
            hint: c.start == null ? 'いまいる場所を検索' : '場所・部屋を検索',
          ),
        ),
        const SizedBox(height: 8),
        CategoryChipsRow(
          categories: const [
            PlaceCategories.restroom,
            PlaceCategories.stairs,
            PlaceCategories.classroom,
            PlaceCategories.lab,
            PlaceCategories.office,
            PlaceCategories.workshop,
            PlaceCategories.library,
          ],
          onTap: (cat) => _openSearch(category: cat),
        ),
      ]);
    }

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: MeasureSize(
        onChange: _onTopSize,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(
                  key: ValueKey(mode == _Mode.navigating
                      ? 'nav'
                      : (mode == _Mode.preview || mode == _Mode.arrived ? 'route' : 'search')),
                  child: mode == _Mode.navigating
                      ? Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: content)
                      : content,
                ),
              ),
              if (suggestion != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: SuggestionCard(
                    suggestion: suggestion,
                    onAccept: () => c.acceptSuggestion(suggestion),
                    onDismiss: () => c.dismissSuggestion(suggestion),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget? _buildBanner() {
    final c = _controller;
    final steps = c.guideSteps;
    final i = c.currentStepIndex;
    if (i < 0 || i >= steps.length) return null;
    final step = steps[i];
    final next = i + 1 < steps.length ? steps[i + 1] : null;
    final meters = math.max(0.0, (step.at - c.traveledPx.value) * AppConfig.metersPerPx);
    final fix = c.suggestFix ? c.nearbyCheckpoint : null;

    String? advanceLabel;
    VoidCallback? onAdvance;
    if (step.isFinal && step.maneuver != Maneuver.arrive && c.canAdvanceFloor) {
      advanceLabel = '${AppConfig.floorNameOf(c.nextFloorLabel!)}に着いた';
      onAdvance = () => c.advanceToFloor(c.nextFloorLabel!);
    } else if (step.maneuver == Maneuver.arrive && meters < 15) {
      advanceLabel = '到着した';
      onAdvance = c.markArrived;
    }

    return NavBanner(
      step: step,
      distanceM: meters,
      next: next,
      // タップは任意。ずれが溜まっていそうなとき（最後に位置を合わせてから
      // しばらく歩いた）に、近くの目印でだけ出す。
      fixStep: fix == null ? null : RouteGuide.gateStep(fix),
      onConfirmCheckpoint: fix == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              c.confirmGate(fix.key);
            },
      advanceLabel: advanceLabel,
      onAdvance: onAdvance,
      warning: _wrongWay ? '進む方向と反対を向いています' : null,
    );
  }

  Widget _buildRightControls() {
    final c = _controller;
    final floor = c.currentFloor;
    if (floor == null) return const SizedBox.shrink();
    final building = floor.section.buildingName;
    final floors = [
      for (final s in AppConfig.mapSections)
        if (s.buildingName == building && c.repo.floor(s.label) != null) s,
    ];
    final buildings = {
      for (final s in AppConfig.mapSections)
        if (c.repo.floor(s.label) != null) s.buildingName,
    };
    final loc = c.currentLocation;

    return Positioned(
      key: _rightControlsKey,
      right: 12,
      top: _topHeight + 12,
      child: ListenableBuilder(
        listenable: _view,
        builder: (_, __) {
          final bearing = _view.camera.bearing;
          return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: wrapAngle(bearing).abs() > 0.02
                  ? Padding(
                      key: const ValueKey('compass'),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: CompassButton(
                        bearing: bearing,
                        onPressed: () {
                          setState(() => _courseUp = false);
                          _view.resetBearing();
                        },
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('no-compass')),
            ),
            if (floors.length > 1 || buildings.length > 1)
              FloorPicker(
                floors: floors,
                current: c.currentLabel,
                userLabel: loc?.$2,
                goalLabel: c.goal?.label,
                routeLabels: c.floorPaths.keys.toSet(),
                onSelect: _showFloor,
                buildingName: buildings.length > 1 ? building : null,
                onBuildingTap: _chooseBuilding,
              ),
          ]);
        },
      ),
    );
  }

  Widget _buildBottomRightControls() {
    final c = _controller;
    if (c.currentFloor == null) return const SizedBox.shrink();
    final hasLocation = c.currentLocation != null;
    final IconData icon;
    final Color color;
    if (!hasLocation) {
      icon = Icons.location_searching;
      color = AppColors.textSecondary;
    } else if (!_follow) {
      icon = Icons.my_location;
      color = AppColors.textSecondary;
    } else {
      icon = _courseUp ? Icons.navigation : Icons.my_location;
      color = AppColors.primary;
    }

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      right: 12,
      bottom: _sheetHeight + 14,
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (c.sensorPermissionNeeded && c.heading.value == null) ...[
          Material(
            color: Colors.white,
            shape: const StadiumBorder(),
            elevation: 3,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: c.enableWebSensors,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.explore, size: 18, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text('方位をオンにする',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.primary)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        RoundMapButton(
          key: _locationButtonKey,
          tooltip: !hasLocation
              ? 'QRコードで現在地を設定'
              : (_follow ? (c.goal != null ? '進む方向を上にする / 北を上にする' : '拡大') : '現在地を表示'),
          onPressed: _onLocationButton,
          child: Icon(icon, color: color, size: 26),
        ),
      ]),
    );
  }

  /// 案内中に地図を動かして追従が外れたとき、元に戻すボタン。
  Widget _buildRecenter() {
    final show = _mode == _Mode.navigating && !_follow;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: 12,
      bottom: _sheetHeight + 18,
      child: AnimatedScale(
        scale: show ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Material(
          color: Colors.white,
          elevation: 3,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: show ? _onLocationButton : null,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.navigation, size: 18, color: AppColors.primary),
                SizedBox(width: 8),
                Text('現在地に戻る',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.primary)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToast() {
    final text = _toast;
    return Positioned(
      left: 16,
      right: 16,
      bottom: _sheetHeight + 80,
      child: IgnorePointer(
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a),
                child: child,
              ),
            ),
            child: text == null
                ? const SizedBox.shrink()
                : ToastView(key: ValueKey(text), text: text, error: _toastError),
          ),
        ),
      ),
    );
  }

  Widget _buildSheet() {
    final mode = _mode;
    final c = _controller;
    final Widget content = switch (mode) {
      _Mode.loading => LoadingSheet(loaded: c.floorsLoaded, total: c.floorsTotal),
      _Mode.failed => const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Text('マップを読み込めませんでした。通信状況を確かめて開き直してください。',
              style: TextStyle(fontSize: 15, color: AppColors.danger)),
        ),
      _Mode.setLocation => SetLocationSheet(
          onScan: _scanQr,
          onPickFromList: () => _openSearch(pickingStart: true),
        ),
      _Mode.located => LocatedSheet(
          here: c.placeTitle(c.start!),
          floorText: AppConfig.displayNameOf(c.start!.label),
          nearby: _nearby(),
          onChange: () => _openSearch(pickingStart: true),
          onSearch: () => _openSearch(),
          onNearby: _selectPlace,
        ),
      _Mode.place => PlaceSheet(
          place: _selected!,
          title: c.placeTitle(_selected!),
          isCurrentLocation: _selected == c.start,
          hasStart: c.start != null,
          walkingMeters: c.walkingMetersTo(_selected!),
          onClose: () => setState(() => _selected = null),
          onRoute: () => _routeTo(_selected!),
          onSetHere: () => _setHere(_selected!),
        ),
      _Mode.preview => RoutePreviewSheet(
          controller: c,
          expanded: _stepsExpanded,
          onToggleSteps: () => setState(() => _stepsExpanded = !_stepsExpanded),
          onStart: _startNavigation,
          onClose: _dismiss,
        ),
      _Mode.navigating => NavigatingSheet(
          controller: c,
          expanded: _stepsExpanded,
          onToggleSteps: () => setState(() => _stepsExpanded = !_stepsExpanded),
          onEnd: _endNavigation,
        ),
      _Mode.arrived => ArrivedSheet(
          placeName: c.goal == null ? '' : c.placeTitle(c.goal!),
          onDone: _finishNavigation,
        ),
    };

    return MeasureSize(
      onChange: _onSheetSize,
      child: GestureDetector(
        // シートを上下にはじくと手順の一覧を開け閉めできる。
        onVerticalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (mode != _Mode.preview && mode != _Mode.navigating) return;
          if (v < -200 && !_stepsExpanded) setState(() => _stepsExpanded = true);
          if (v > 200 && _stepsExpanded) setState(() => _stepsExpanded = false);
        },
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Color(0x24000000), blurRadius: 16, offset: Offset(0, -2)),
                ],
              ),
              child: SafeArea(
                top: false,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SheetHandle(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topCenter,
                        children: [...previous, if (current != null) current],
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(mode == _Mode.place ? 'place-$_selected' : mode.name),
                        child: content,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 現在地のフロアで、近くにある目印（トイレ・階段など）を種類ごとに1つずつ。
  List<NearbyPlace> _nearby() {
    final c = _controller;
    final start = c.start;
    if (start == null || c.placeDistancesLabel != start.label) return const [];
    final best = <PlaceKind, NearbyPlace>{};
    for (final e in c.placeDistances.entries) {
      if (e.key == start.name) continue;
      final cat = PlaceCategories.of(e.key);
      final kind = cat.kind;
      if (kind != PlaceKind.restroom &&
          kind != PlaceKind.stairs &&
          kind != PlaceKind.elevator &&
          kind != PlaceKind.food &&
          kind != PlaceKind.office &&
          kind != PlaceKind.medical &&
          kind != PlaceKind.library) {
        continue;
      }
      final prev = best[kind];
      if (prev == null || e.value < prev.meters) {
        best[kind] = NearbyPlace(PlaceRef(e.key, start.label), cat, displayPlaceName(e.key), e.value);
      }
    }
    final list = best.values.toList()..sort((a, b) => a.meters.compareTo(b.meters));
    return list;
  }

  Widget _buildDrawer() {
    final c = _controller;
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.map_outlined, color: Colors.white),
                ),
                const SizedBox(width: 14),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('infacilityMAP', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text('屋内ナビゲーション', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ]),
              ]),
            ),
            const Divider(),
            const _DrawerSection('現在地'),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('QR コードで現在地を設定'),
              onTap: () {
                Navigator.pop(context);
                unawaited(_scanQr());
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_off_outlined),
              title: const Text('現在地と経路をリセット'),
              enabled: c.start != null,
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _selected = null;
                  _exitNavigation();
                });
                c.reset();
              },
            ),
            const Divider(),
            const _DrawerSection('センサー'),
            ValueListenableBuilder<bool>(
              valueListenable: AppSettings.barometerEnabled,
              builder: (_, value, __) => SwitchListTile(
                secondary: const Icon(Icons.speed),
                title: const Text('気圧センサー'),
                subtitle: const Text('階の移動を検知します。未対応の機種ではオフに'),
                value: value,
                onChanged: (v) => AppSettings.barometerEnabled.value = v,
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: AppSettings.gpsEnabled,
              builder: (_, value, __) => SwitchListTile(
                secondary: const Icon(Icons.satellite_alt_outlined),
                title: const Text('GPS'),
                subtitle: const Text('建物に近づいたことを検知します。屋内で誤作動するならオフに'),
                value: value,
                onChanged: (v) => AppSettings.gpsEnabled.value = v,
              ),
            ),
            const Divider(),
            const _DrawerSection('開発者向け'),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('センサー診断'),
              subtitle: const Text('歩数・方位・気圧・GPS の状態を確認'),
              onTap: () {
                Navigator.pop(context);
                unawaited(showSensorDebugSheet(context, c));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerSection extends StatelessWidget {
  final String text;
  const _DrawerSection(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
      );
}

/// 経路の確認中に上に出す「出発 → 目的地」。
class _RouteHeader extends StatelessWidget {
  final String from;
  final String to;
  final VoidCallback onBack;
  const _RouteHeader({required this.from, required this.to, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: floatingShadow,
        ),
        padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
        child: Row(children: [
          IconButton(
            tooltip: '戻る',
            icon: const Icon(Icons.arrow_back, color: AppColors.textSecondary),
            onPressed: onBack,
          ),
          const SizedBox(width: 2),
          const Column(children: [
            Icon(Icons.trip_origin, size: 14, color: AppColors.primary),
            SizedBox(height: 2),
            _DotsLine(),
            SizedBox(height: 2),
            Icon(Icons.place, size: 16, color: AppColors.destination),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(from,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, color: AppColors.textSecondary)),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(height: 1),
              ),
              Text(to,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _DotsLine extends StatelessWidget {
  const _DotsLine();

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 3,
            height: 3,
            margin: const EdgeInsets.symmetric(vertical: 1.5),
            decoration: const BoxDecoration(color: AppColors.textTertiary, shape: BoxShape.circle),
          ),
      ]);
}

// lib/navigation/navigation_controller.dart
//
// ナビゲーションの状態を全部ここに集める。UI（MapScreen）は
// このコントローラを購読して描くだけにする。
//
// 分けた理由:
//   以前は1つの State に「JSON読み込み・経路計算・センサー購読・
//   ダイアログ表示・描画」が同居していて、1フレームごとに全走査が走ったり、
//   購読が解除されなかったりしていた。状態と副作用をここへ寄せることで、
//   UI 側は build するだけ、テストは context なしで書けるようになる。
//
// 更新の流し方は2系統ある。
//   notifyListeners() … 経路や目的地など、画面の構造が変わるもの。
//   ValueNotifier     … 現在地・方位など毎秒何度も来るもの。
//                       マップの一部だけを描き直したいので分けてある。
import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../config.dart';
import '../data/map_data.dart';
import '../routing/route_calculator.dart';
import '../routing/route_planner.dart';
import '../sensors/heading_source.dart';
import '../sensors/step_tracker.dart';
import 'route_geometry.dart';
import 'route_guide.dart';
import 'suggestion_policy.dart';

/// 画面に一度だけ出す短いお知らせ。
enum MessageKind { info, error }

@immutable
class AppMessage {
  final String text;
  final MessageKind kind;
  const AppMessage(this.text, {this.kind = MessageKind.info});
}

enum LoadState { loading, ready, failed }

class NavigationController extends ChangeNotifier {
  NavigationController({MapRepository? repository, StepTracker? tracker})
      : repo = repository ?? MapRepository(),
        _tracker = tracker ?? StepTracker() {
    _policy = SuggestionPolicy(distanceBetween: Geolocator.distanceBetween);
  }

  final MapRepository repo;
  final StepTracker _tracker;
  late final SuggestionPolicy _policy;

  final List<StreamSubscription<dynamic>> _subs = [];

  /// 読み込みの途中で画面を離れることがある。閉じたあとに
  /// notifyListeners() や StreamController.add() を呼ぶと例外になるので、
  /// 発火は必ずここを通す。
  bool _disposed = false;

  // ─── 読み込み ─────────────────────────────────────────────────
  LoadState loadState = LoadState.loading;
  int floorsLoaded = 0;
  int floorsTotal = AppConfig.mapSections.length;

  // ─── 表示と現在地 ─────────────────────────────────────────────

  /// いま画面に出しているフロア。ユーザーは自由に切り替えられる。
  String currentLabel = AppConfig.mapSections.first.label;

  /// 実際に歩いているフロア。表示フロアを切り替えても動かない。
  /// 現在地ドットや到着判定はこちらで行う。
  String trackerLabel = AppConfig.mapSections.first.label;

  PlaceRef? start;
  PlaceRef? goal;

  /// 出発地の呼び名。QRコードの場所や案内を中断した地点のように、
  /// [start] の name がノードID（node_12-34 など）になるときに使う。
  String? _startDisplayName;

  /// フロアラベル -> そのフロア上で通るノードID。全フロア分を一度に持つ。
  Map<String, List<String>> floorPaths = {};

  /// 階をまたぐとき、次に進むフロア。
  String? nextFloorLabel;

  /// 経路を計算している最中か。
  bool routing = false;

  /// 出発地と目的地があるのに経路が見つからなかった。
  bool get routeNotFound => !routing && goal != null && floorPaths.isEmpty;

  bool followMode = false;
  bool showCompass = false;
  bool arrived = false;
  /// Web でブラウザのセンサー許可がまだ取れていない。
  /// true のあいだコンパス欄に「方位を有効にする」ボタンを出す。
  bool sensorPermissionNeeded = false;

  final Set<String> passedGates = {};
  GateInfo? nextGate;

  /// 現在地を最後に確かめた（QR・チェックポイント・曲がり角）地点の、
  /// 経路に沿った距離(JSON-px)。ここから歩いた分だけ誤差が増えていく。
  double _fixPx = 0;

  /// 出発地のフロアで、出発地から各場所までの徒歩距離(m)。
  /// 検索結果や場所の情報に「ここから何m」を出すのに使う。
  Map<String, double> placeDistances = const {};
  String? placeDistancesLabel;
  int _distanceRequest = 0;

  final Map<String, RouteGeometry?> _geometryCache = {};
  List<GuideStep>? _guideCache;

  // 高頻度に流れる値。マップの一部だけを描き直すために分けている。
  final position = ValueNotifier<Offset?>(null);
  final heading = ValueNotifier<double?>(null);
  final traveledPx = ValueNotifier<double>(0);
  final altitude = ValueNotifier<double>(0);
  final gps = ValueNotifier<Position?>(null);

  /// 表示中の提案（階移動・建物接近）。null なら何も出さない。
  final suggestion = ValueNotifier<Suggestion?>(null);

  final _messages = StreamController<AppMessage>.broadcast();
  final _arrivals = StreamController<PlaceRef>.broadcast();
  final _focusRequests = StreamController<Offset>.broadcast();

  /// スナックバーに出す短いお知らせ。
  Stream<AppMessage> get messages => _messages.stream;

  /// 目的地に着いた。UI側でダイアログを出す。
  Stream<PlaceRef> get arrivals => _arrivals.stream;

  /// この座標へ画面を寄せてほしい、という要求。
  Stream<Offset> get focusRequests => _focusRequests.stream;

  // ─── 参照系 ───────────────────────────────────────────────────

  FloorMap? get currentFloor => repo.floor(currentLabel);

  /// 表示中のフロアに描くべき経路。
  List<String> get currentPath => floorPaths[currentLabel] ?? const [];

  /// 歩いているフロアの経路。チェックポイントの元になる。
  List<String> get physicalPath => floorPaths[trackerLabel] ?? const [];

  List<GateInfo> get orderedGates => _tracker.orderedGates;

  bool get isStartOnCurrentFloor => start?.label == currentLabel;
  bool get isGoalOnCurrentFloor => goal?.label == currentLabel;
  bool get showUserDot => start != null && trackerLabel == currentLabel;

  Offset? get startCenter =>
      start == null ? null : repo.floor(start!.label)?.roomCenters[start!.name];
  Offset? get goalCenter =>
      goal == null ? null : repo.floor(goal!.label)?.roomCenters[goal!.name];

  /// 目的地まであと何メートルか。経路がなければ null。
  double? get remainingMeters {
    if (currentPath.isEmpty || _tracker.totalRoutePx == 0) return null;
    final px = (_tracker.totalRoutePx - traveledPx.value).clamp(0.0, double.infinity);
    return px * AppConfig.metersPerPx;
  }

  /// 目的地が別フロアにあり、いまのフロアでやることが残っていない状態。
  /// このときだけ「次のフロアへ進む」ボタンを出す。
  bool get canAdvanceFloor =>
      nextGate == null && nextFloorLabel != null && goal?.label != trackerLabel;

  // ─── 起動 ─────────────────────────────────────────────────────

  Future<void> initialize() async {
    _listen(_tracker.positionStream, (Offset? p) => position.value = p);
    _listen(_tracker.traveledStream, _onTraveled);
    _listen(_tracker.nextGateStream, (GateInfo? g) {
      nextGate = g;
      _notify();
    });
    _listen(_tracker.altitudeStream, _onAltitude);
    _listen(_tracker.gpsStream, _onGps);
    _listen(headingStream(), (double h) {
      heading.value = h;
      // 曲がり角を目印にした位置の補正に使う
      _tracker.onHeading(h);
    });
    _listen(_tracker.correctionStream, (double px) {
      _fixPx = _tracker.traveledPx;
      final m = px * AppConfig.metersPerPx;
      _say(AppMessage('曲がり角で現在地を補正しました'
          '（${m >= 0 ? '+' : ''}${m.toStringAsFixed(1)}m）'));
    });

    sensorPermissionNeeded = needsSensorPermission();

    AppSettings.barometerEnabled.addListener(_onBarometerSetting);
    AppSettings.gpsEnabled.addListener(_onGpsSetting);

    await repo.loadAll(
      onFloorLoaded: (floor, loaded, total) {
        floorsLoaded = loaded;
        floorsTotal = total;
        // 最初の1枚が読めた時点で地図を出す。全部待たない。
        if (loaded == 1) {
          currentLabel = floor.label;
          trackerLabel = floor.label;
        }
        _notify();
      },
      onError: (section, error) {
        _say(AppMessage('${section.label} の読み込みに失敗しました',
            kind: MessageKind.error));
      },
    );

    loadState = repo.isEmpty ? LoadState.failed : LoadState.ready;
    _tracker.start();
    _notify();

    _applyUrlParameter();
  }

  /// センサー系のストリームは端末によってはエラーを流してくる
  /// （そのセンサーがない、権限がない、プラグインが未登録）。
  /// onError を付けないと未処理の非同期エラーになってアプリごと落ちるので、
  /// 購読は必ずここを通す。そのセンサーが黙るだけで他は動き続ける。
  void _listen<T>(Stream<T> stream, void Function(T) onData) {
    _subs.add(stream.listen(
      (v) {
        if (!_disposed) onData(v);
      },
      onError: (Object e) => debugPrint('センサー購読エラー: $e'),
      cancelOnError: false,
    ));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _say(AppMessage message) {
    if (!_disposed) _messages.add(message);
  }

  void _focus(Offset target) {
    if (!_disposed) _focusRequests.add(target);
  }

  /// QRコードを URL の形で踏んだ場合。
  /// - `?qr=ID`        エディタで置いたQRコード（設置位置で現在地を確定）
  /// - `?start=ノード名` 部屋名で出発地を決める古い形式
  void _applyUrlParameter() {
    try {
      final params = Uri.base.queryParameters;
      final qr = params['qr'];
      final name = params['start'];
      if (qr != null && qr.isNotEmpty) {
        unawaited(applyQr(qr));
      } else if (name != null && name.isNotEmpty) {
        unawaited(setStartByName(name));
      }
    } catch (_) {
      // Uri.base はネイティブでは意味を持たないことがある。無視してよい。
    }
  }

  /// アプリ内スキャナで読んだ文字列。QRの URL でも部屋名そのものでもよい。
  Future<void> handleScannedCode(String scanned) {
    final uri = Uri.tryParse(scanned);
    final qr = (uri != null && uri.hasScheme) ? uri.queryParameters['qr'] : null;
    if (qr != null && qr.isNotEmpty) return applyQr(qr);
    return setStartByName(scanned);
  }

  /// エディタで置いたQRコードを読んだ。
  ///
  /// 案内中で、QRが今の経路上（またはそのすぐ脇）にあれば、経路はそのままで
  /// 進んだ距離をそこに合わせる。歩数の推定で溜まった誤差をここで消す。
  /// 経路から外れていたり案内していなければ、そこを新しい現在地にする
  /// （目的地があれば経路を引き直す）。
  Future<void> applyQr(String id) async {
    final spot = repo.qrSpot(id);
    if (spot == null) {
      _say(AppMessage('このQRコード（$id）はマップに登録されていません',
          kind: MessageKind.error));
      return;
    }
    final where = spot.memo ?? 'QRコードの場所';

    if (goal != null && trackerLabel == spot.label) {
      final passed = _tracker.snapToNode(spot.nodeId);
      if (passed != null) {
        passedGates.addAll(passed);
        _fixPx = _tracker.traveledPx;
        currentLabel = spot.label;
        _say(AppMessage('「$where」で現在地を補正しました'));
        _requestFocus(PlaceRef(spot.nodeId, spot.label));
        _checkArrival();
        _notify();
        return;
      }
    }

    await setStart(PlaceRef(spot.nodeId, spot.label), displayName: where);
  }

  // ─── 出発地・目的地 ───────────────────────────────────────────

  /// QRスキャンや URL パラメータから出発地を決める。
  ///
  /// QRの中身はノード名そのものか、`https://.../?start=<ノード名>` の
  /// どちらもありうる。貼り紙用のQRは後者で作ることが多いので、
  /// アプリ内スキャナで読んだときも同じように扱えるようにしておく。
  Future<void> setStartByName(String scanned) async {
    final nameOrId = _startNameFrom(scanned);
    final place = repo.resolve(nameOrId, preferred: currentLabel);
    if (place == null) {
      _say(AppMessage('「$nameOrId」はマップ上に見つかりませんでした',
          kind: MessageKind.error));
      return;
    }
    await setStart(place);
  }

  String _startNameFrom(String scanned) {
    final uri = Uri.tryParse(scanned);
    if (uri == null || !uri.hasScheme) return scanned;
    return uri.queryParameters['start'] ?? scanned;
  }

  /// [displayName] は案内に出す名前。QRコードの場所のように [place] の
  /// name がノードID（node_12-34 など）になるときに渡す。
  Future<void> setStart(PlaceRef place, {String? displayName}) {
    start = place;
    _startDisplayName = displayName;
    currentLabel = place.label;
    trackerLabel = place.label;
    showCompass = true;
    _say(AppMessage('現在地を「${displayName ?? placeTitle(place)}」に設定しました'));
    _requestFocus(place);
    _computePlaceDistances();
    return _recalculate();
  }

  Future<void> setGoal(PlaceRef place) {
    if (start == null) {
      _say(const AppMessage('先に現在地を設定してください。マップをタップするか一覧から選べます。',
          kind: MessageKind.error));
      return Future<void>.value();
    }
    goal = place;
    arrived = false;
    // 経路は出発フロアから描き始めたいので表示を戻す。
    currentLabel = start!.label;
    return _recalculate();
  }

  /// マップをタップしたとき。1回目が現在地、2回目以降が目的地。
  void selectPlaceFromMap(String name) {
    final place = PlaceRef(name, currentLabel);
    unawaited(start == null ? setStart(place) : setGoal(place));
  }

  /// 目的地に着いて案内を終える。着いた場所をそのまま現在地にするので、
  /// 続けて次の目的地を選べる。
  Future<void> finishNavigation() {
    final g = goal;
    if (g == null) return Future<void>.value();
    start = g;
    _startDisplayName = null;
    goal = null;
    arrived = false;
    currentLabel = g.label;
    trackerLabel = g.label;
    _computePlaceDistances();
    return _recalculate();
  }

  /// 途中で案内をやめる。歩いた分だけ進んだ地点を現在地として残す。
  Future<void> cancelNavigation() {
    if (goal == null) return Future<void>.value();
    final here = _nodeAtTraveled();
    if (here != null && _tracker.traveledPx > 0) {
      start = PlaceRef(here, trackerLabel);
      _startDisplayName = '案内を中断した地点';
      currentLabel = trackerLabel;
      _computePlaceDistances();
    }
    goal = null;
    arrived = false;
    return _recalculate();
  }

  /// 経路上で、いま推定している位置にいちばん近いノード。
  String? _nodeAtTraveled() {
    final path = physicalPath;
    final geo = routeGeometry(trackerLabel);
    if (path.isEmpty || geo == null) return null;
    final t = _tracker.traveledPx;
    var best = 0;
    for (var i = 1; i < geo.cum.length && i < path.length; i++) {
      if ((geo.cum[i] - t).abs() < (geo.cum[best] - t).abs()) best = i;
    }
    return path[best];
  }

  void reset() {
    start = null;
    _startDisplayName = null;
    placeDistances = const {};
    placeDistancesLabel = null;
    _distanceRequest++;
    goal = null;
    floorPaths = {};
    nextFloorLabel = null;
    passedGates.clear();
    nextGate = null;
    followMode = false;
    showCompass = false;
    arrived = false;
    trackerLabel = currentLabel;
    position.value = null;
    traveledPx.value = 0;
    suggestion.value = null;
    _policy.reset();
    _tracker.clearRoute();
    _say(const AppMessage('位置をリセットしました。現在地を選択してください。'));
    _notify();
  }

  // ─── 経路計算 ─────────────────────────────────────────────────

  Future<void> _recalculate() async {
    passedGates.clear();
    nextFloorLabel = null;
    traveledPx.value = 0;
    _fixPx = 0;
    _geometryCache.clear();
    _guideCache = null;

    final s = start;
    final g = goal;
    routing = false;
    if (s == null || g == null) {
      floorPaths = {};
      _tracker.clearRoute();
      _notify();
      return;
    }

    trackerLabel = s.label;

    final startId = repo.floor(s.label)?.nodeIdOf(s.name);
    final goalId = repo.floor(g.label)?.nodeIdOf(g.name);
    if (startId == null || goalId == null) {
      floorPaths = {};
      _tracker.clearRoute();
      _say(const AppMessage('経路が見つかりませんでした', kind: MessageKind.error));
      _notify();
      return;
    }

    routing = true;
    _notify();
    final planned = await RoutePlanner.planAsync(RoutePlanRequest(
      nodesByLabel: repo.nodesByLabel,
      sectionLabels: AppConfig.mapSections.map((e) => e.label).toList(),
      startId: startId,
      goalId: goalId,
      startLabel: s.label,
      goalLabel: g.label,
    ));
    // 計算している間に目的地が変わった・案内をやめた場合は捨てる。
    if (start != s || goal != g) return;
    routing = false;
    floorPaths = planned;
    _geometryCache.clear();
    _guideCache = null;

    if (s.label != g.label) nextFloorLabel = _floorAfter(s.label, g.label);

    final physical = floorPaths[s.label] ?? const <String>[];
    if (physical.isEmpty) {
      _tracker.clearRoute();
      _say(const AppMessage('経路が見つかりませんでした', kind: MessageKind.error));
    } else {
      _tracker.setRoute(physical, repo.floor(s.label)?.nodes ?? const {});
    }
    _notify();
  }

  /// [from] から [to] へ向かうとき、次に踏むフロア。
  String? _floorAfter(String from, String to) {
    final labels = AppConfig.mapSections.map((e) => e.label).toList();
    final fromIdx = labels.indexOf(from);
    final toIdx = labels.indexOf(to);
    if (fromIdx == -1 || toIdx == -1 || fromIdx == toIdx) return null;
    final next = fromIdx + (toIdx > fromIdx ? 1 : -1);
    return next >= 0 && next < labels.length ? labels[next] : null;
  }

  // ─── フロア操作 ───────────────────────────────────────────────

  /// 表示フロアだけを切り替える。経路は計算済みなので引き直さない。
  void showFloor(String label) {
    if (currentLabel == label) return;
    currentLabel = label;
    _notify();
  }

  void showNextFloor() {
    final labels = repo.labels;
    if (labels.isEmpty) return;
    final i = labels.indexOf(currentLabel);
    showFloor(labels[(i + 1) % labels.length]);
  }

  /// 実際に階を移動した。出発地を次のフロアの降り口に付け替えて引き直す。
  Future<void> advanceToFloor(String label) async {
    final path = floorPaths[label];
    if (path == null || path.isEmpty) {
      _say(
          AppMessage('$label への経路が見つかりませんでした', kind: MessageKind.error));
      return;
    }
    start = PlaceRef(path.first, label);
    _startDisplayName = '${AppConfig.floorNameOf(label)}の到着地点';
    currentLabel = label;
    trackerLabel = label;
    _tracker.resetAltitude();
    _computePlaceDistances();
    await _recalculate();
    _requestFocus(start!);
  }

  /// 経路上のチェックポイントをユーザーが通過確認した。
  void confirmGate(String gateKey) {
    passedGates.add(gateKey);
    _tracker.confirmGate(gateKey);
    _fixPx = _tracker.traveledPx;
    _checkArrival();
    _notify();
  }

  void setFollowMode(bool value) {
    followMode = value;
    // 追従を入れるなら、歩いているフロアを見せないと意味がない。
    if (value && trackerLabel != currentLabel) currentLabel = trackerLabel;
    if (value && position.value != null) _focus(position.value!);
    _notify();
  }

  void hideCompass() {
    showCompass = false;
    _notify();
  }

  // ─── センサーからの反応 ───────────────────────────────────────

  void _onTraveled(double distance) {
    traveledPx.value = distance;
    _checkArrival();
  }

  /// 利用者が「着いた」と知らせた。歩数を数え損ねて最後まで進まない
  /// ことがあるので、目的地のフロアにいれば自分で到着にできる。
  void markArrived() {
    if (arrived || goal == null || goal!.label != trackerLabel) return;
    arrived = true;
    if (!_disposed) _arrivals.add(goal!);
    _notify();
  }

  void _checkArrival() {
    if (arrived || goal == null) return;
    if (goal!.label != trackerLabel) return;
    if (!_tracker.isAtRouteEnd) return;
    arrived = true;
    if (!_disposed) _arrivals.add(goal!);
    _notify();
  }

  void _onAltitude(double relativeAltitude) {
    altitude.value = relativeAltitude;
    final s = _policy.onAltitude(relativeAltitude, trackerLabel);
    if (s != null) suggestion.value = s;
  }

  void _onGps(Position? p) {
    gps.value = p;
    if (p == null) return;
    final s = _policy.onPosition(p.latitude, p.longitude, trackerLabel);
    if (s != null) suggestion.value = s;
  }

  void acceptSuggestion(Suggestion s) {
    _policy.accept(s);
    suggestion.value = null;
    switch (s.kind) {
      case SuggestionKind.floorChange:
        // 経路の途中なら降り口へ、そうでなければ表示を切り替えるだけ。
        if (floorPaths.containsKey(s.targetLabel)) {
          unawaited(advanceToFloor(s.targetLabel));
        } else {
          _tracker.resetAltitude();
          _switchBuilding(s.targetLabel);
        }
      case SuggestionKind.buildingSwitch:
        _switchBuilding(s.targetLabel);
    }
  }

  void dismissSuggestion(Suggestion s) {
    _policy.snooze(s);
    suggestion.value = null;
    if (s.kind == SuggestionKind.floorChange) _tracker.resetAltitude();
  }

  void _switchBuilding(String label) {
    currentLabel = label;
    trackerLabel = label;
    _tracker.clearRoute();
    _notify();
  }

  // ─── 設定 ─────────────────────────────────────────────────────

  void _onBarometerSetting() =>
      _tracker.setBarometerEnabled(AppSettings.barometerEnabled.value);

  void _onGpsSetting() => _tracker.setGpsEnabled(AppSettings.gpsEnabled.value);

  bool _autoRequestedSensors = false;

  /// 起動後最初のタップで、センサー許可を1度だけ自動で求める。
  /// iOS はユーザー操作の中でしか許可ダイアログを出せないので、画面の
  /// タップ(ポインタを離した瞬間)から呼んでもらう。断られた後や2回目以降は
  /// 何もしない（コンパス欄のボタンからは何度でも求められる）。
  void autoEnableWebSensors() {
    if (_autoRequestedSensors || !sensorPermissionNeeded) return;
    _autoRequestedSensors = true;
    enableWebSensors();
  }

  Future<void> enableWebSensors() async {
    final granted = await requestSensorPermission();
    sensorPermissionNeeded = !granted;
    if (!granted) {
      _say(const AppMessage(
          '方位センサーが許可されませんでした。設定 > Safari > モーションと方位へのアクセス を確認してください',
          kind: MessageKind.error));
    }
    _notify();
  }

  // ─── 表示と案内のための情報 ───────────────────────────────────

  /// 場所の呼び名。ノードIDのままの出発地は、覚えている呼び名で返す。
  String placeTitle(PlaceRef place) {
    if (place == start && _startDisplayName != null) return _startDisplayName!;
    if (place.name.startsWith('node_')) {
      final spot = repo.qrSpotAt(place.label, place.name);
      return spot?.memo ?? '地図上の地点';
    }
    return place.name.replaceAll('_', ' ');
  }

  /// [label] のフロアの経路を線として。経路がなければ null。
  RouteGeometry? routeGeometry(String label) {
    if (_geometryCache.containsKey(label)) return _geometryCache[label];
    final path = floorPaths[label];
    final floor = repo.floor(label);
    RouteGeometry? geo;
    if (path != null && path.isNotEmpty && floor != null) {
      final s = start, g = goal;
      geo = RouteGeometry.build(
        path,
        floor.nodes,
        head: s != null && s.label == label ? floor.roomCenters[s.name] : null,
        tail: g != null && g.label == label ? floor.roomCenters[g.name] : null,
      );
    }
    return _geometryCache[label] = geo;
  }

  /// 経路が通るフロアを、通る順に。
  List<String> get routeLabels => floorPaths.keys.toList(growable: false);

  /// 歩いているフロアの案内の一覧。
  List<GuideStep> get guideSteps {
    final cached = _guideCache;
    if (cached != null) return cached;
    final geo = routeGeometry(trackerLabel);
    if (geo == null || goal == null) return const [];
    return _guideCache = RouteGuide.build(
      corners: _tracker.corners,
      gates: _tracker.orderedGates,
      totalPx: geo.length,
      end: _floorEndStep(geo.length),
    );
  }

  /// いま案内している手順の番号（[guideSteps] の中）。なければ -1。
  int get currentStepIndex =>
      RouteGuide.currentIndex(guideSteps, _tracker.traveledPx, passedGates);

  GuideStep _floorEndStep(double at) {
    final g = goal!;
    final next = nextFloorLabel;
    if (g.label == trackerLabel || next == null) {
      return GuideStep(
          maneuver: Maneuver.arrive,
          at: at,
          title: '目的地に到着',
          subtitle: placeTitle(g));
    }
    final here = AppConfig.sectionOf(trackerLabel);
    final there = AppConfig.sectionOf(next);
    final lastId = physicalPath.isEmpty ? null : physicalPath.last;
    final lastNode =
        lastId == null ? null : repo.floor(trackerLabel)?.nodes[lastId];
    final via = lastNode is Map ? lastNode['name'] as String? : null;
    final viaText = via?.replaceAll('_', ' ');
    final sameBuilding = here != null &&
        there != null &&
        here.buildingName == there.buildingName &&
        !here.outdoor &&
        !there.outdoor;
    if (sameBuilding && there.floorLevel != here.floorLevel) {
      final up = there.floorLevel > here.floorLevel;
      return GuideStep(
        maneuver: up ? Maneuver.stairsUp : Maneuver.stairsDown,
        at: at,
        title: '${there.floorDisplayName}へ${up ? '上る' : '下りる'}',
        subtitle: viaText,
      );
    }
    return GuideStep(
      maneuver: Maneuver.transfer,
      at: at,
      title: '${AppConfig.displayNameOf(next)}へ',
      subtitle: viaText,
    );
  }

  /// 目的地まで、残りのフロアも合わせた道のり(m)。経路がなければ null。
  double? get remainingTotalMeters {
    if (goal == null || floorPaths.isEmpty) return null;
    final labels = routeLabels;
    final here = labels.indexOf(trackerLabel);
    if (here == -1) return null;
    var px = 0.0;
    final geo = routeGeometry(trackerLabel);
    if (geo != null) {
      px += (geo.length - _tracker.traveledPx).clamp(0.0, geo.length);
    }
    for (final label in labels.skip(here + 1)) {
      px += routeGeometry(label)?.length ?? 0;
    }
    final floorChanges = labels.length - 1 - here;
    return px * AppConfig.metersPerPx +
        floorChanges * AppConfig.stairsEquivalentMeters;
  }

  /// 目的地までの所要時間の目安（秒）。
  double? get remainingSeconds {
    final m = remainingTotalMeters;
    return m == null ? null : m / AppConfig.walkingSpeed;
  }

  /// 経路全体の道のり(m)。案内を始める前の概要に使う。経路がなければ null。
  double? get totalRouteMeters {
    if (floorPaths.isEmpty) return null;
    var px = 0.0;
    for (final label in routeLabels) {
      px += routeGeometry(label)?.length ?? 0;
    }
    return px * AppConfig.metersPerPx +
        (floorPaths.length - 1) * AppConfig.stairsEquivalentMeters;
  }

  /// 歩いているフロアの経路上のチェックポイント。
  List<GateInfo> get checkpoints => _tracker.orderedGates;

  /// 推定した現在地の誤差の目安(m)。最後に現在地を確かめてから
  /// 歩いた距離の1割に、もとの誤差1mを足す。地図の青い円の大きさ。
  double get positionUncertaintyMeters {
    final walked = (_tracker.traveledPx - _fixPx).clamp(0.0, double.infinity);
    return 1.0 + 0.1 * walked * AppConfig.metersPerPx;
  }

  /// 現在地（JSON-px）と、そのフロア。わからなければ null。
  /// 案内中は歩数で進めた位置（表示用にならした経路の上）、
  /// そうでなければ出発地の位置。
  (Offset, String)? get currentLocation {
    final s = start;
    if (s == null) return null;
    final geo = routeGeometry(trackerLabel);
    if (geo != null && goal != null) {
      return (geo.pointAt(_tracker.traveledPx), trackerLabel);
    }
    final center = repo.floor(s.label)?.centerOf(s.name);
    return center == null ? null : (center, s.label);
  }

  /// 出発地から [place] までの徒歩距離(m)。出発地と同じフロアのときだけわかる。
  double? walkingMetersTo(PlaceRef place) {
    if (place.label != placeDistancesLabel) return null;
    return placeDistances[place.name];
  }

  /// 出発地のフロアで、出発地から各場所までの徒歩距離を求めておく。
  /// 画面の動きを止めないよう、少し遅らせてから計算する。
  void _computePlaceDistances() {
    final s = start;
    final floor = s == null ? null : repo.floor(s.label);
    final id = floor?.nodeIdOf(s!.name);
    final request = ++_distanceRequest;
    placeDistances = const {};
    placeDistancesLabel = null;
    if (floor == null || id == null) return;
    unawaited(() async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (_disposed || request != _distanceRequest) return;
      final byNode = await compute(RouteCalculator.distancesFromMessage,
          <String, dynamic>{'start': id, 'nodes': floor.nodes});
      if (_disposed || request != _distanceRequest) return;
      final out = <String, double>{};
      for (final e in floor.entryIdByName.entries) {
        final d = byNode[e.value];
        if (d != null) out[e.key] = d * AppConfig.metersPerPx;
      }
      placeDistances = out;
      placeDistancesLabel = floor.label;
      _notify();
    }());
  }

  // ─── デバッグ ─────────────────────────────────────────────────

  Map<String, String> get stepDiagnostics => _tracker.stepDiagnostics;
  Map<String, String> get turnDiagnostics => _tracker.turnDiagnostics;

  void debugInjectAltitude(double h) => _tracker.debugInjectAltitude(h);

  /// 歩いたことにする（画面の確認・テスト用）。
  void debugAdvanceSteps(int steps) => _tracker.debugAdvanceSteps(steps);
  void debugInjectGps(Position p) => _tracker.debugInjectGps(p);

  // ─── 後始末 ───────────────────────────────────────────────────

  void _requestFocus(PlaceRef place) {
    final center = repo.floor(place.label)?.centerOf(place.name);
    if (center != null) _focus(center);
  }

  @override
  void dispose() {
    _disposed = true;
    AppSettings.barometerEnabled.removeListener(_onBarometerSetting);
    AppSettings.gpsEnabled.removeListener(_onGpsSetting);
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _tracker.dispose();
    _messages.close();
    _arrivals.close();
    _focusRequests.close();
    position.dispose();
    heading.dispose();
    traveledPx.dispose();
    altitude.dispose();
    gps.dispose();
    suggestion.dispose();
    super.dispose();
  }
}

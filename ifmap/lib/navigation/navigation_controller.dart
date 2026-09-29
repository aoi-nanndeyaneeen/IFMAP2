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
import '../routing/route_planner.dart';
import '../sensors/heading_source.dart';
import '../sensors/step_tracker.dart';
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

  /// フロアラベル -> そのフロア上で通るノードID。全フロア分を一度に持つ。
  Map<String, List<String>> floorPaths = {};

  /// 階をまたぐとき、次に進むフロア。
  String? nextFloorLabel;

  bool followMode = false;
  bool showCompass = false;
  bool arrived = false;
  /// Web でブラウザのセンサー許可がまだ取れていない。
  /// true のあいだコンパス欄に「方位を有効にする」ボタンを出す。
  bool sensorPermissionNeeded = false;

  final Set<String> passedGates = {};
  GateInfo? nextGate;

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
    _listen(headingStream(), (double h) => heading.value = h);

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
    currentLabel = place.label;
    trackerLabel = place.label;
    showCompass = true;
    _say(AppMessage('現在地を「${displayName ?? place.name}」に設定しました'));
    _requestFocus(place);
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
    followMode = true;
    // 経路は出発フロアから描き始めたいので表示を戻す。
    currentLabel = start!.label;
    _say(AppMessage('目的地を「${place.name}」に設定しました'));
    return _recalculate();
  }

  /// マップをタップしたとき。1回目が現在地、2回目以降が目的地。
  void selectPlaceFromMap(String name) {
    final place = PlaceRef(name, currentLabel);
    unawaited(start == null ? setStart(place) : setGoal(place));
  }

  void reset() {
    start = null;
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

    final s = start;
    final g = goal;
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

    floorPaths = await RoutePlanner.planAsync(RoutePlanRequest(
      nodesByLabel: repo.nodesByLabel,
      sectionLabels: AppConfig.mapSections.map((e) => e.label).toList(),
      startId: startId,
      goalId: goalId,
      startLabel: s.label,
      goalLabel: g.label,
    ));

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
    currentLabel = label;
    trackerLabel = label;
    _tracker.resetAltitude();
    await _recalculate();
    _requestFocus(start!);
  }

  /// 経路上のチェックポイントをユーザーが通過確認した。
  void confirmGate(String gateKey) {
    passedGates.add(gateKey);
    _tracker.confirmGate(gateKey);
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

  // ─── デバッグ ─────────────────────────────────────────────────

  void debugInjectAltitude(double h) => _tracker.debugInjectAltitude(h);
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

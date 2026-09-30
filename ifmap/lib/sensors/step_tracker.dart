// lib/sensors/step_tracker.dart
//
// 屋内には使えるGPSがないので、現在地は「経路上をどれだけ進んだか」で推定する。
//   歩数 × 歩幅 = 進んだ距離 → 経路上の位置
// ずれが溜まるのを防ぐため、部屋の出入口や扉をチェックポイント（ゲート）とし、
// そこでユーザーがタップするまで進行を止めて位置を確定させる。
//
// センサーの購読と、経路上の距離計算は役割が別なので分けてある。
//   setRoute() … 経路とゲートの組み立て。センサー不要、テスト可能。
//   start()    … 加速度・気圧・GPSの購読開始。
import 'dart:async';
import 'dart:math';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../config.dart';
import '../data/map_data.dart';
import 'motion_source.dart';
import 'step_detector.dart';
import 'turn_matching.dart';

/// 経路上のチェックポイント1件。
@immutable
class GateInfo {
  final String id;
  final bool isEnter;
  final bool isDoor;
  final double? px;

  /// 曲がり角のチェックポイントなら曲がる角度(度、右折が正)。
  final double? turn;

  /// 距離が空いたところに挟む「現在地を確認」。
  final bool isCheck;

  const GateInfo(this.id,
      {this.isEnter = true,
      this.isDoor = false,
      this.px,
      this.turn,
      this.isCheck = false});

  String get key => isCheck
      ? '${id}_${px?.toInt()}_chk'
      : turn != null
          ? '${id}_${px?.toInt()}_turn'
          : isDoor
              ? '${id}_${px?.toInt()}_door'
              : (isEnter ? '${id}_${px?.toInt()}_in' : '${id}_${px?.toInt()}_out');

  String get label {
    if (isCheck) return '現在地を確認';
    if (turn != null) return turn! > 0 ? '右に曲がる' : '左に曲がる';
    final name = (id == '扉' || id.startsWith('node_')) ? (isDoor ? '扉' : '外') : id;
    if (isDoor) return '扉を通る';
    if (name == '接続点') return '接続点に到達';
    if (name == '建物' && isEnter) return '建物に入る';
    if (name == '外' && !isEnter) return '外に出る';
    if (isEnter) return '「$name」に入る';
    return '「$name」から出る';
  }
}

class _Gate {
  final GateInfo info;
  final double px;
  const _Gate(this.info, this.px);
}

class StepTracker {
  final double stepLengthPx;

  /// [clock] は秒を返す時計。テストで時間を進めるために差し替えられる。
  ///
  /// [turnCheckpoints] は曲がり角と、距離が空いたところにもチェックポイントを
  /// 置く。[cornerBoost] は曲がり角の前後で歩数の進みを何倍にするか（1で無効）。
  /// どちらも実際のアプリでだけ使う（テストの前提を変えないため既定は無効）。
  StepTracker({
    this.stepLengthPx = AppConfig.stepLengthPx,
    double Function()? clock,
    this.turnCheckpoints = false,
    this.cornerBoost = 1.0,
    this.autoAdvance = false,
    this.calibrateStride = false,
  }) : _now = clock ?? _stopwatchClock();

  final bool turnCheckpoints;
  final double cornerBoost;

  /// チェックポイントで歩数を止めず、通り過ぎたら自動で次へ進める。
  /// タップは「位置がずれていたら直す」ための任意の操作になる。
  /// 止めていた頃は、タップし忘れると地図が動かなくなっていた。
  final bool autoAdvance;

  /// 位置が確かめられるたびに（タップ・QR）、実際に進んだ距離と
  /// 歩数から見積もった距離を比べて歩幅を合わせていく。
  final bool calibrateStride;

  /// 歩幅の倍率。人によって歩くペースが違うので、確かめるたびに学ぶ。
  double _strideScale = 1.0;
  double get strideScale => _strideScale;

  /// 最後に位置を確かめた地点と、そこから歩数で進めた量（補正前）。
  double _fixPx = 0;
  double _stepPxSinceFix = 0;

  static double Function() _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsedMicroseconds / 1e6;
  }

  final double Function() _now;

  List<String> _path = [];
  Map<String, dynamic> _nodes = {};
  List<double> _cumDist = [];
  double _traveled = 0;
  final StepDetector _detector = StepDetector();
  List<_Gate> _gates = [];
  int _gateIdx = 0;

  // ── 曲がり角による補正 ────────────────────────────────────────
  final TurnDetector _turns = TurnDetector();
  List<RouteCorner> _corners = const [];

  /// (時刻, 進んだ距離) の記録。曲がったと判定するのは曲がり終えて
  /// 少し歩いた後なので、「曲がった瞬間にどこまで進んでいたか」を引く。
  final List<(double, double)> _progressLog = [];
  double? _lastStepT;
  TurnEvent? _pendingTurn;
  String _lastCorrection = 'なし';

  double? _refPressure;
  double? _filteredPressure;
  Position? _currentGps;

  StreamSubscription<dynamic>? _accelSub;
  StreamSubscription<dynamic>? _baroSub;
  StreamSubscription<Position>? _gpsSub;

  final _posCtrl = StreamController<Offset?>.broadcast();
  final _distCtrl = StreamController<double>.broadcast();
  final _gateCtrl = StreamController<GateInfo?>.broadcast();
  final _altCtrl = StreamController<double>.broadcast();
  final _gpsCtrl = StreamController<Position?>.broadcast();
  final _correctionCtrl = StreamController<double>.broadcast();

  Stream<Offset?> get positionStream => _posCtrl.stream;
  Stream<double> get traveledStream => _distCtrl.stream;
  Stream<GateInfo?> get nextGateStream => _gateCtrl.stream;
  Stream<double> get altitudeStream => _altCtrl.stream;
  Stream<Position?> get gpsStream => _gpsCtrl.stream;

  /// 曲がり角で位置を合わせたときの補正量(JSON-px)。前へ進めたら正。
  Stream<double> get correctionStream => _correctionCtrl.stream;

  /// 経路から取り出した曲がり角（テスト・診断用）。
  List<RouteCorner> get corners => _corners;

  Position? get currentGps => _currentGps;
  double get totalRoutePx => _cumDist.isEmpty ? 0 : _cumDist.last;
  double get traveledPx => _traveled;
  bool get hasRoute => _path.isNotEmpty;
  GateInfo? get nextGate => _gateIdx < _gates.length ? _gates[_gateIdx].info : null;
  List<GateInfo> get orderedGates => _gates.map((g) => g.info).toList();

  /// 残りの経路をすべて歩き終えたか（＝到着判定）。
  bool get isAtRouteEnd =>
      hasRoute &&
      nextGate == null &&
      _traveled >= totalRoutePx - AppConfig.arrivalTolerancePx;

  // ─── 経路 ────────────────────────────────────────────────────

  /// 経路を差し替え、チェックポイントを組み直す。
  ///
  /// 現在地は必ずここで送出する。これがないとフロアを切り替えたあと
  /// 前のフロアの座標が残り、現在地ドットが違う階に出たままになる。
  void setRoute(List<String> path, Map<String, dynamic> nodes) {
    _path = path;
    _nodes = nodes;
    _traveled = 0;
    _gateIdx = 0;
    _fixPx = 0;
    _stepPxSinceFix = 0;
    _buildCumDist();
    _corners = extractCorners(_pathPoints(), _cumDist);
    _buildGates();
    _progressLog.clear();
    _pendingTurn = null;
    _logProgress();
    _posCtrl.add(_calcPosition());
    _distCtrl.add(_traveled);
    _gateCtrl.add(nextGate);
  }

  /// 経路を捨てる。センサーは止めない（建物接近の検知は続けたい）。
  void clearRoute() {
    _path = [];
    _nodes = {};
    _cumDist = [];
    _gates = [];
    _corners = const [];
    _progressLog.clear();
    _pendingTurn = null;
    _traveled = 0;
    _gateIdx = 0;
    _posCtrl.add(null);
    _distCtrl.add(0);
    _gateCtrl.add(null);
  }

  /// チェックポイントの通過をユーザーが確認した。
  /// そこまで進んだものとして現在地を確定させる。
  ///
  /// [autoAdvance] のときは、自動で通過済みにしたものも確認できる
  /// （歩数を数えすぎて先へ進んでいた場合に、手前へ戻して合わせる）。
  void confirmGate(String gateKey) {
    final idx = _gates.indexWhere((g) => g.info.key == gateKey);
    if (idx == -1 || (idx < _gateIdx && !autoAdvance)) return;
    _traveled = _gates[idx].px;
    _gateIdx = idx + 1;
    _onFix();
    _logProgress();
    _gateCtrl.add(nextGate);
    _posCtrl.add(_calcPosition());
    _distCtrl.add(_traveled);
  }

  /// QRコードなどで現在地が確定した。経路上（またはそのすぐ脇）なら
  /// そこまで進んだものとして位置を合わせ、通り過ぎたチェックポイントの
  /// キーを返す。経路から離れていれば何もせず null を返す
  /// （呼び出し側で経路を引き直す）。
  ///
  /// 歩数の推定より手前に戻ることもある（数えすぎていた場合）。
  List<String>? snapToNode(String nodeId,
      {double tolerancePx = AppConfig.qrSnapTolerancePx}) {
    if (!hasRoute) return null;

    var idx = _path.indexOf(nodeId);
    if (idx == -1) {
      final target = _nodes[nodeId];
      if (target is! Map) return null;
      final tx = (target['x'] as num).toDouble();
      final ty = (target['y'] as num).toDouble();
      var best = double.infinity;
      for (var i = 0; i < _path.length; i++) {
        final n = _nodes[_path[i]];
        if (n is! Map) continue;
        final dx = (n['x'] as num) - tx, dy = (n['y'] as num) - ty;
        final d = sqrt(dx * dx + dy * dy);
        if (d < best) {
          best = d;
          idx = i;
        }
      }
      if (idx == -1 || best > tolerancePx) return null;
    }

    final target = _cumDist[idx];
    final passed = <String>[];
    while (_gateIdx < _gates.length && _gates[_gateIdx].px <= target) {
      passed.add(_gates[_gateIdx].info.key);
      _gateIdx++;
    }
    if (autoAdvance && _gateIdx > 0 && _gates[_gateIdx - 1].px > target) {
      // 数えすぎて先のチェックポイントまで通過済みにしていたら戻す。
      while (_gateIdx > 0 && _gates[_gateIdx - 1].px > target) {
        _gateIdx--;
      }
    }
    _traveled = target;
    _onFix();
    _logProgress();
    _posCtrl.add(_calcPosition());
    _distCtrl.add(_traveled);
    _gateCtrl.add(nextGate);
    return passed;
  }

  // ─── センサー ─────────────────────────────────────────────────

  /// 加速度（歩数）・気圧・GPSの購読を始める。多重呼び出ししても安全。
  void start() {
    _startAccelerometer();
    setBarometerEnabled(AppSettings.barometerEnabled.value);
    setGpsEnabled(AppSettings.gpsEnabled.value);
  }

  void stop() {
    _accelSub?.cancel();
    _accelSub = null;
    _baroSub?.cancel();
    _baroSub = null;
    _gpsSub?.cancel();
    _gpsSub = null;
    _currentGps = null;
  }

  void setBarometerEnabled(bool enable) {
    _baroSub?.cancel();
    _baroSub = null;
    if (!enable) return;
    try {
      _baroSub = barometerEventStream().listen(
        (e) => _updateAltitude(e.pressure),
        onError: (Object err) => debugPrint('気圧センサ: $err'),
      );
    } catch (e) {
      // 気圧センサを持たない端末。無効のまま進む。
      debugPrint('気圧センサ非対応: $e');
    }
  }

  void setGpsEnabled(bool enable) {
    if (!enable) {
      _gpsSub?.cancel();
      _gpsSub = null;
      _currentGps = null;
      _gpsCtrl.add(null);
      return;
    }
    unawaited(_startGps());
  }

  void _startAccelerometer() {
    if (_accelSub != null) return;
    try {
      // Web では sensors_plus の加速度が iPhone で動かないので motion_source 経由。
      _accelSub = accelerationSamples().listen(
        _onMotionSample,
        onError: (Object err) => debugPrint('加速度センサ: $err'),
      );
    } catch (e) {
      debugPrint('加速度センサ非対応: $e');
    }
  }

  void _onMotionSample(MotionSample s) {
    // 検出器は経路がなくても回し続ける（歩行の判定には数秒の履歴が要る）。
    final steps = _detector.addSample(s.t, s.magnitude);
    if (steps > 0) advanceSteps(steps);
  }

  /// [steps] 歩ぶん経路に沿って進める。経路がなければ何もしない。
  @visibleForTesting
  void advanceSteps(int steps) {
    if (!hasRoute || steps <= 0) return;
    _lastStepT = _now();
    final step = stepLengthPx * steps * _boostAt(_traveled) * _strideScale;
    _stepPxSinceFix += step;
    _traveled = (_traveled + step).clamp(0.0, _capPx);
    _autoPassGates();
    _logProgress();
    _posCtrl.add(_calcPosition());
    _distCtrl.add(_traveled);

    // 立ち止まっているときに検出した曲がりは、歩き出してから確かめる
    final pending = _pendingTurn;
    if (pending != null) {
      _pendingTurn = null;
      if (_now() - pending.t <= _turnWalkWindow) _applyTurn(pending);
    }
  }

  /// 曲がり角の近くでは、人は角を斜めに切るので歩数の進みを増やす。
  double _boostAt(double d) {
    if (cornerBoost == 1.0) return 1.0;
    for (final c in _corners) {
      if ((c.distance - d).abs() <= _cornerZonePx) return cornerBoost;
    }
    return 1.0;
  }

  static const double _cornerZonePx =
      AppConfig.cornerZoneMeters / AppConfig.metersPerPx;

  /// 次のチェックポイントより先へは進ませない。そこで位置を確定させるため。
  /// [autoAdvance] のときは止めない（終点までは進む）。
  double get _capPx => autoAdvance
      ? totalRoutePx
      : (_gateIdx < _gates.length ? _gates[_gateIdx].px : totalRoutePx);

  /// 確認済みのチェックポイントより手前へは戻さない。
  /// [autoAdvance] のときは、最後に位置を確かめた地点より手前へ戻さない。
  double get _floorPx => autoAdvance
      ? _fixPx
      : (_gateIdx > 0 ? _gates[_gateIdx - 1].px : 0);

  /// 通り過ぎたチェックポイントを通過済みにする（[autoAdvance] のとき）。
  void _autoPassGates() {
    if (!autoAdvance) return;
    var changed = false;
    while (_gateIdx < _gates.length && _gates[_gateIdx].px <= _traveled) {
      _gateIdx++;
      changed = true;
    }
    if (changed) _gateCtrl.add(nextGate);
  }

  /// 通過済みのチェックポイント（自動で通過したものも含む）。
  List<String> get passedGateKeys =>
      [for (var i = 0; i < _gateIdx; i++) _gates[i].info.key];

  /// 位置を確かめた（タップ・QR）。歩幅を学び、誤差の起点をここに置く。
  void _onFix() {
    if (calibrateStride) {
      final actual = _traveled - _fixPx;
      // 短すぎる区間や、戻ったときは学ばない（誤差のほうが大きい）。
      if (_stepPxSinceFix >= _calibrateMinPx && actual > 0) {
        final ratio = (actual / _stepPxSinceFix).clamp(0.6, 1.6);
        // 1回で決めずに半分だけ寄せる（たまたまの外れ値に引っぱられない）。
        _strideScale = (_strideScale * (1 + (ratio - 1) * 0.5)).clamp(0.7, 1.4);
      }
    }
    _fixPx = _traveled;
    _stepPxSinceFix = 0;
  }

  static const double _calibrateMinPx = 8.0 / AppConfig.metersPerPx;

  // ─── 曲がり角による補正 ─────────────────────────────────────────

  /// 曲がりの前後これだけの間に歩いていなければ、その場で向きを変えた
  /// （見回した）だけとみなす（秒）。
  static const double _turnWalkWindow = 3.0;

  /// 推定位置からこの距離以内の曲がり角だけを候補にする（5m）。
  static final double _cornerSearchPx = 5.0 / AppConfig.metersPerPx;

  /// 検出した曲がりと経路の曲がり角の角度の差の許容（度）。
  static const double _cornerAngleTolerance = 45;

  /// 方位のサンプルを入れる。コントローラがコンパスの値を流す。
  void onHeading(double heading) {
    final event = _turns.addHeading(_now(), heading);
    if (event == null || !hasRoute) return;
    final lastStep = _lastStepT;
    if (lastStep != null && event.t - lastStep <= _turnWalkWindow) {
      _applyTurn(event);
    } else {
      _pendingTurn = event;
    }
  }

  void _applyTurn(TurnEvent event) {
    // 曲がり終えた（新しい向きで安定し始めた）時点での進み具合
    final at = _progressAt(event.t - _turns.stableSeconds);

    RouteCorner? best;
    for (final c in _corners) {
      if (c.turn.sign != event.delta.sign) continue;
      if ((c.turn - event.delta).abs() > _cornerAngleTolerance) continue;
      if ((c.distance - at).abs() > _cornerSearchPx) continue;
      if (best == null || (c.distance - at).abs() < (best.distance - at).abs()) {
        best = c;
      }
    }
    if (best == null) {
      _lastCorrection = '${event.delta.toStringAsFixed(0)}° 曲がりを検出、'
          '近くに一致する曲がり角なし';
      return;
    }

    final offset = best.distance - at;
    final before = _traveled;
    _traveled = (_traveled + offset).clamp(_floorPx, _capPx);
    _autoPassGates();
    final applied = _traveled - before;
    _lastCorrection = '${event.delta.toStringAsFixed(0)}° 曲がりを '
        '${best.turn.toStringAsFixed(0)}° の角に一致、'
        '${(applied * AppConfig.metersPerPx).toStringAsFixed(1)} m 補正';
    if (applied.abs() < 1e-6) return;
    _logProgress();
    _posCtrl.add(_calcPosition());
    _distCtrl.add(_traveled);
    _correctionCtrl.add(applied);
  }

  void _logProgress() {
    _progressLog.add((_now(), _traveled));
    // 曲がりの判定にさかのぼるのはせいぜい数秒なので古いものは捨てる
    final limit = _now() - 10;
    while (_progressLog.length > 1 && _progressLog[1].$1 < limit) {
      _progressLog.removeAt(0);
    }
  }

  double _progressAt(double t) {
    var value = _progressLog.isEmpty ? _traveled : _progressLog.first.$2;
    for (final (time, traveled) in _progressLog) {
      if (time > t) break;
      value = traveled;
    }
    return value;
  }

  List<Offset> _pathPoints() => [
        for (final id in _path)
          if (_nodes[id] case final Map n)
            Offset((n['x'] as num).toDouble(), (n['y'] as num).toDouble())
          else
            Offset.zero,
      ];

  /// 曲がり角による補正の状態。デバッグ画面に出す。
  Map<String, String> get turnDiagnostics => {
        '経路の曲がり角': _corners.isEmpty
            ? 'なし'
            : _corners
                .map((c) => '${(c.distance * AppConfig.metersPerPx).toStringAsFixed(0)}m地点'
                    '${c.turn > 0 ? '右' : '左'}${c.turn.abs().toStringAsFixed(0)}°')
                .join(', '),
        '基準の向き': _turns.reference?.toStringAsFixed(0) ?? '—',
        '最後の補正': _lastCorrection,
      };

  /// 歩行検出の状態。デバッグ画面に出す。
  Map<String, String> get stepDiagnostics => {
        '歩行中': _detector.isWalking ? 'はい' : 'いいえ',
        '検出した歩数': '${_detector.totalSteps}',
        '揺れの大きさ(標準偏差)': '${_detector.lastStd.toStringAsFixed(2)} m/s²'
            '（${_detector.minStd} 未満は静止）',
        '周期': _detector.lastPeriod == 0
            ? '—'
            : '${_detector.lastPeriod.toStringAsFixed(2)} 秒'
                '（歩行は ${_detector.minPeriod}〜${_detector.maxPeriod}）',
        '周期性(自己相関)': '${_detector.lastCorrelation.toStringAsFixed(2)}'
            '（${_detector.minCorrelation} 以上で歩行）',
      };

  Future<void> _startGps() async {
    _gpsSub?.cancel();
    _gpsSub = null;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
        ),
      ).listen((p) {
        _currentGps = p;
        _gpsCtrl.add(p);
      }, onError: (Object err) => debugPrint('GPS: $err'));
    } catch (e) {
      debugPrint('GPS開始失敗: $e');
    }
  }

  void _updateAltitude(double pressure) {
    _filteredPressure = _filteredPressure == null
        ? pressure
        : _filteredPressure! * (1 - AppConfig.pressureFilterAlpha) +
            pressure * AppConfig.pressureFilterAlpha;

    if (_refPressure == null) {
      _refPressure = _filteredPressure;
      return;
    }

    // 国際標準大気の高度公式。基準気圧からの相対高度だけを使う。
    final h = 44330 * (1 - pow(_filteredPressure! / _refPressure!, 1 / 5.255));
    _altCtrl.add(h.toDouble());
  }

  /// いまの気圧を基準に取り直す。階を移動したあとに呼ぶ。
  void resetAltitude() {
    _refPressure = _filteredPressure;
    _altCtrl.add(0.0);
  }

  /// デバッグ画面からセンサー値を手で流し込む。実機に気圧計がない・
  /// 屋内でGPSが出ないときに提案まわりの動きを確かめるためのもの。
  void debugInjectAltitude(double h) => _altCtrl.add(h);

  /// デバッグ画面・画面の確認から歩いたことにする。
  void debugAdvanceSteps(int steps) => advanceSteps(steps);

  void debugInjectGps(Position p) {
    _currentGps = p;
    _gpsCtrl.add(p);
  }

  void dispose() {
    stop();
    _posCtrl.close();
    _distCtrl.close();
    _gateCtrl.close();
    _altCtrl.close();
    _gpsCtrl.close();
    _correctionCtrl.close();
  }

  // ─── 経路上の距離とチェックポイント ──────────────────────────

  void _buildCumDist() {
    _cumDist = [0.0];
    for (var i = 0; i < _path.length - 1; i++) {
      final a = _nodes[_path[i]];
      final b = _nodes[_path[i + 1]];
      if (a is! Map || b is! Map) {
        _cumDist.add(_cumDist.last);
        continue;
      }
      final dx = (b['x'] as num).toDouble() - (a['x'] as num).toDouble();
      final dy = (b['y'] as num).toDouble() - (a['y'] as num).toDouble();
      _cumDist.add(_cumDist.last + sqrt(dx * dx + dy * dy));
    }
  }

  /// 隣り合うノードの属性が変わる境目をチェックポイントにする。
  ///
  ///   部屋(type 3) の出入り      → 「◯◯に入る / から出る」
  ///   屋外(isOutdoor) の出入り   → 「外に出る / 建物に入る / 接続点に到達」
  ///   扉(doorXxx) のまたぎ       → 「扉を通る」
  void _buildGates() {
    _gates = [];
    if (_cumDist.length < 2) {
      _gateCtrl.add(null);
      return;
    }

    for (var i = 0; i < _path.length - 1; i++) {
      final a = _nodes[_path[i]];
      final b = _nodes[_path[i + 1]];
      if (a is! Map || b is! Map) continue;

      final halfway = (_cumDist[i] + _cumDist[i + 1]) / 2.0;

      final typeA = (a['type'] as num?)?.toInt() ?? CellType.corridor;
      final typeB = (b['type'] as num?)?.toInt() ?? CellType.corridor;
      final nameA = a['name'] as String?;
      final nameB = b['name'] as String?;

      // 部屋の出入り。
      if (typeA == CellType.room && typeB != CellType.room) {
        if (nameA != null) {
          _tryAdd(GateInfo(nameA, isEnter: false, px: halfway), halfway);
        }
      } else if (typeA != CellType.room && typeB == CellType.room) {
        if (nameB != null) {
          _tryAdd(GateInfo(nameB, isEnter: true, px: halfway), halfway);
        }
      } else if (typeA == CellType.room &&
          typeB == CellType.room &&
          nameA != nameB) {
        // 部屋から隣の部屋へ直接抜ける場合は「出る」「入る」を続けて出す。
        if (nameA != null) {
          _tryAdd(GateInfo(nameA, isEnter: false, px: halfway - 0.1), halfway - 0.1);
        }
        if (nameB != null) {
          _tryAdd(GateInfo(nameB, isEnter: true, px: halfway + 0.1), halfway + 0.1);
        }
      }

      // 屋外との出入り。
      final outdoorA = typeA == CellType.outdoor || a['isOutdoor'] == true;
      final outdoorB = typeB == CellType.outdoor || b['isOutdoor'] == true;
      if (!outdoorA && outdoorB) {
        _tryAdd(GateInfo('外', isEnter: false, px: halfway), halfway);
      } else if (outdoorA && !outdoorB) {
        final isConnector =
            b['isConnector'] == true || typeB == CellType.connector;
        _tryAdd(
            GateInfo(isConnector ? '接続点' : '建物', isEnter: true, px: halfway),
            halfway);
      }

      // 扉のまたぎ。廊下どうしのときだけ出す（部屋の出入りと二重にしない）。
      final structuralA = typeA == CellType.room ||
          typeA == CellType.stairs ||
          typeA == CellType.connector ||
          outdoorA;
      final structuralB = typeB == CellType.room ||
          typeB == CellType.stairs ||
          typeB == CellType.connector ||
          outdoorB;
      if (!structuralA && !structuralB && _hasDoorBetween(a, b)) {
        _tryAdd(GateInfo('扉', isEnter: true, isDoor: true, px: halfway), halfway);
      }
    }

    if (turnCheckpoints) _addTurnAndCheckGates();

    _gateIdx = 0;
    _gateCtrl.add(nextGate);
  }

  /// 曲がり角と、間が空きすぎたところの「現在地を確認」を足す。
  ///
  /// 扉や部屋の出入りは経路のどこにでもあるわけではない。長い廊下では
  /// 歩数の誤差が溜まる一方なので、少なくとも一定距離ごとに位置を
  /// 合わせられるようにしておく。近くに別のチェックポイントがあれば
  /// 重ねて出さない（1回のタップで済ませる）。
  void _addTurnAndCheckGates() {
    const near = 2.0 / AppConfig.metersPerPx;
    final all = <_Gate>[..._gates];
    bool nearOther(double px) => all.any((g) => (g.px - px).abs() < near);

    for (final c in _corners) {
      if (nearOther(c.distance)) continue;
      all.add(_Gate(GateInfo('曲がり', turn: c.turn, px: c.distance), c.distance));
    }
    all.sort((a, b) => a.px.compareTo(b.px));

    const maxGap = AppConfig.maxCheckpointGapMeters / AppConfig.metersPerPx;
    final out = <_Gate>[];
    var prev = 0.0;
    void fill(double to) {
      final n = ((to - prev) / maxGap).ceil() - 1;
      for (var i = 1; i <= n; i++) {
        final px = prev + (to - prev) * i / (n + 1);
        out.add(_Gate(GateInfo('確認', isCheck: true, px: px), px));
      }
    }

    for (final g in all) {
      fill(g.px);
      out.add(g);
      prev = g.px;
    }
    // 最後のチェックポイントから終点まで。終点は到着の操作があるので
    // ここには足さない（ただし長い区間には途中に挟む）。
    fill(totalRoutePx - near);
    _gates = out;
  }

  bool _hasDoorBetween(Map a, Map b) {
    final xA = (a['x'] as num).toDouble();
    final yA = (a['y'] as num).toDouble();
    final xB = (b['x'] as num).toDouble();
    final yB = (b['y'] as num).toDouble();

    if (yB == yA && xB > xA) {
      return a['doorRight'] == true || b['doorLeft'] == true;
    }
    if (yB == yA && xB < xA) {
      return a['doorLeft'] == true || b['doorRight'] == true;
    }
    if (xB == xA && yB > yA) {
      return a['doorBottom'] == true || b['doorTop'] == true;
    }
    if (xB == xA && yB < yA) {
      return a['doorTop'] == true || b['doorBottom'] == true;
    }
    return false;
  }

  /// チェックポイントは経路上で単調増加していなければならない
  /// （順番にタップしてもらう前提のため）。前より手前のものは捨てる。
  void _tryAdd(GateInfo info, double px) {
    if (totalRoutePx <= 0) return;
    final clamped = px.clamp(0.0, totalRoutePx);
    final prev = _gates.isEmpty ? -1.0 : _gates.last.px;
    if (clamped > prev) _gates.add(_Gate(info, clamped));
  }

  Offset? _calcPosition() {
    if (_path.isEmpty || _cumDist.isEmpty) return null;

    if (_traveled >= _cumDist.last) {
      final n = _nodes[_path.last];
      return n is Map ? _offsetOf(n) : null;
    }
    for (var i = 0; i < _cumDist.length - 1; i++) {
      if (_traveled > _cumDist[i + 1]) continue;
      final a = _nodes[_path[i]];
      final b = _nodes[_path[i + 1]];
      if (a is! Map || b is! Map) return null;
      final seg = _cumDist[i + 1] - _cumDist[i];
      final t = seg == 0 ? 0.0 : (_traveled - _cumDist[i]) / seg;
      final pa = _offsetOf(a);
      final pb = _offsetOf(b);
      return Offset(pa.dx + (pb.dx - pa.dx) * t, pa.dy + (pb.dy - pa.dy) * t);
    }
    return null;
  }

  Offset _offsetOf(Map n) =>
      Offset((n['x'] as num).toDouble(), (n['y'] as num).toDouble());
}

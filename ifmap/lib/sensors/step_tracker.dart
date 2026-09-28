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

/// 経路上のチェックポイント1件。
@immutable
class GateInfo {
  final String id;
  final bool isEnter;
  final bool isDoor;
  final double? px;

  const GateInfo(this.id, {this.isEnter = true, this.isDoor = false, this.px});

  String get key => isDoor
      ? '${id}_${px?.toInt()}_door'
      : (isEnter ? '${id}_${px?.toInt()}_in' : '${id}_${px?.toInt()}_out');

  String get label {
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

  StepTracker({this.stepLengthPx = AppConfig.stepLengthPx});

  List<String> _path = [];
  Map<String, dynamic> _nodes = {};
  List<double> _cumDist = [];
  double _traveled = 0;
  bool _cooldown = false;
  List<_Gate> _gates = [];
  int _gateIdx = 0;

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

  Stream<Offset?> get positionStream => _posCtrl.stream;
  Stream<double> get traveledStream => _distCtrl.stream;
  Stream<GateInfo?> get nextGateStream => _gateCtrl.stream;
  Stream<double> get altitudeStream => _altCtrl.stream;
  Stream<Position?> get gpsStream => _gpsCtrl.stream;

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
    _buildCumDist();
    _buildGates();
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
    _traveled = 0;
    _gateIdx = 0;
    _posCtrl.add(null);
    _distCtrl.add(0);
    _gateCtrl.add(null);
  }

  /// チェックポイントの通過をユーザーが確認した。
  /// そこまで進んだものとして現在地を確定させる。
  void confirmGate(String gateKey) {
    final idx = _gates.indexWhere((g) => g.info.key == gateKey);
    if (idx == -1 || idx < _gateIdx) return;
    _traveled = _gates[idx].px;
    _gateIdx = idx + 1;
    _gateCtrl.add(nextGate);
    _posCtrl.add(_calcPosition());
    _distCtrl.add(_traveled);
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
      _accelSub = userAccelerometerEventStream().listen(
        _onAcceleration,
        onError: (Object err) => debugPrint('加速度センサ: $err'),
      );
    } catch (e) {
      debugPrint('加速度センサ非対応: $e');
    }
  }

  void _onAcceleration(UserAccelerometerEvent e) {
    if (_cooldown || !hasRoute) return;
    final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (mag <= AppConfig.stepAccelThreshold) return;

    _cooldown = true;
    // 次のチェックポイントより先へは進ませない。そこで位置を確定させるため。
    final cap = _gateIdx < _gates.length ? _gates[_gateIdx].px : totalRoutePx;
    _traveled = (_traveled + stepLengthPx).clamp(0.0, cap);
    _posCtrl.add(_calcPosition());
    _distCtrl.add(_traveled);
    Future.delayed(AppConfig.stepCooldown, () => _cooldown = false);
  }

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

    _gateIdx = 0;
    _gateCtrl.add(nextGate);
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

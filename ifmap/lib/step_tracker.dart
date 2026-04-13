// lib/step_tracker.dart
// ★ 変更点: startTracking に _posCtrl.add(_calcPosition()) を追加
//   → フロア切替後すぐに新フロアの先頭座標を _estPos に反映する
//   → これにより showUserDot が true でも _estPos が前フロアの座標のままにならない

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'config.dart';

class GateInfo {
  final String id;
  final bool isEnter;
  final bool isDoor;
  final double? px;
  
  const GateInfo(this.id, {this.isEnter = true, this.isDoor = false, this.px});

  String get key   => isDoor ? '${id}_${px?.toInt()}_door' : (isEnter ? '${id}_${px?.toInt()}_in' : '${id}_${px?.toInt()}_out');
  
  String get label {
    final name = (id == '扉' || id.startsWith('node_')) ? (isDoor ? '扉' : '外') : id;
    if (isDoor) return '扉を通る';
    if (name == '建物' && isEnter) return '建物に入る';
    if (name == '外' && !isEnter) return '外に出る';
    if (isEnter) return '「$name」に入る';
    return '「$name」から出る';
  }
}

class _Gate {
  final GateInfo info;
  final double   px;
  _Gate(this.info, this.px);
}

class StepTracker {
  final double stepLengthPx;

  List<String>         _path     = [];
  Map<String, dynamic> _nodes    = {};
  List<double>         _cumDist  = [];
  double               _traveled = 0;
  bool                 _cooldown = false;
  List<_Gate>          _gates    = [];
  int                  _gateIdx  = 0;

  // Barometer & GPS
  double? _refPressure;
  double? _filteredPressure;
  Position? _currentGps;

  StreamSubscription?  _sub;
  StreamSubscription?  _baroSub;
  StreamSubscription?  _gpsSub;

  final _posCtrl  = StreamController<Offset?>.broadcast();
  final _distCtrl = StreamController<double>.broadcast();
  final _gateCtrl = StreamController<GateInfo?>.broadcast();
  final _altCtrl  = StreamController<double>.broadcast();
  final _gpsCtrl  = StreamController<Position?>.broadcast();

  Stream<Offset?>   get positionStream => _posCtrl.stream;
  Stream<double>    get traveledStream => _distCtrl.stream;
  Stream<GateInfo?> get nextGateStream => _gateCtrl.stream;
  Stream<double>    get altitudeStream => _altCtrl.stream;
  Stream<Position?> get gpsStream      => _gpsCtrl.stream;
  Position?         get currentGps     => _currentGps;

  double         get totalRoutePx => _cumDist.isEmpty ? 0 : _cumDist.last;
  double         get traveledPx   => _traveled;
  GateInfo?      get nextGate     => _gateIdx < _gates.length ? _gates[_gateIdx].info : null;
  List<GateInfo> get orderedGates => _gates.map((g) => g.info).toList();

  StepTracker({required this.stepLengthPx});

  void startTracking(List<String> path, Map<String, dynamic> nodes) {
    _sub?.cancel();
    _path = path; _nodes = nodes;
    _traveled = 0; _gates = []; _gateIdx = 0;
    _buildCumDist();

    // ★ FIX (Issue 2): フロア切替直後に新しいパスの先頭座標を即送出する。
    // これがないと _estPos が前フロアの座標のまま残り、
    // showUserDot=true でも現在位置が正しい階に表示されない。
    // ★ 修正: sensors_plus 7.0.0 の新しいイベントストリームの形式を使用
    _sub = userAccelerometerEventStream().listen((e) {
      final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      if (mag > AppConfig.stepAccelThreshold && !_cooldown) {
        _cooldown = true;
        final cap = _gateIdx < _gates.length ? _gates[_gateIdx].px : totalRoutePx;
        _traveled = (_traveled + stepLengthPx).clamp(0.0, cap);
        _posCtrl.add(_calcPosition());
        _distCtrl.add(_traveled);
        Future.delayed(const Duration(milliseconds: 400), () => _cooldown = false);
      }
    }, onError: (_) {});

    // 気圧センサー開始 (sensors_plus 7.0.0)
    toggleBarometer(AppConfig.enableBarometer);

    // GPS開始
    toggleGps(AppConfig.enableGps);
  }

  void toggleBarometer(bool enable) {
    _baroSub?.cancel();
    if (enable) {
      _baroSub = barometerEventStream().listen((e) {
        _updateAltitude(e.pressure);
      }, onError: (err) {
        debugPrint('Barometer error: $err');
      });
    }
  }

  void toggleGps(bool enable) {
    if (enable) {
      _startGps();
    } else {
      _gpsSub?.cancel();
      _currentGps = null;
    }
  }

  void _startGps() async {
    _gpsSub?.cancel();
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      
      if (permission == LocationPermission.deniedForever) return;

      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
        ),
      ).listen((p) {
        _currentGps = p;
        _gpsCtrl.add(p);
      });
    } catch (e) {
      debugPrint('GPS Error: $e');
    }
  }

  void _updateAltitude(double pressure) {
    if (_filteredPressure == null) {
      _filteredPressure = pressure;
    } else {
      _filteredPressure = _filteredPressure! * (1 - AppConfig.pressureFilterAlpha) +
                          pressure * AppConfig.pressureFilterAlpha;
    }

    if (_refPressure == null) {
      _refPressure = _filteredPressure;
      return;
    }

    // 高度計算 (Hypsometric formula)
    // h = 44330 * (1 - (P/P0)^(1/5.255))
    final h = 44330 * (1 - pow(_filteredPressure! / _refPressure!, 1 / 5.255));
    _altCtrl.add(h.toDouble());
  }

  void resetAltitude() {
    _refPressure = _filteredPressure;
    _altCtrl.add(0.0);
  }

  // デバッグ用: 手動で値を注入する
  void debugInjectAltitude(double h) {
    _altCtrl.add(h);
  }

  void debugInjectGps(Position p) {
    _currentGps = p;
    _gpsCtrl.add(p);
  }

  void clear() {
    _sub?.cancel();
    _baroSub?.cancel();
    _gpsSub?.cancel();
    _path = [];
    _nodes = {};
    _cumDist = [];
    _traveled = 0;
    _gates = [];
    _gateIdx = 0;
    _posCtrl.add(null);
    _distCtrl.add(0);
    _gateCtrl.add(null);
    _gpsCtrl.add(null);
  }

  void setGates() {
    _gates = [];

    for (int i = 0; i < _path.length - 1; i++) {
        String idA = _path[i];
        String idB = _path[i+1];
        var nodeA = _nodes[idA];
        var nodeB = _nodes[idB];
        if (nodeA == null || nodeB == null) continue;

        double halfwayPx = (_cumDist[i] + _cumDist[i+1]) / 2.0;

        int typeA = nodeA['type'] ?? 1;
        int typeB = nodeB['type'] ?? 1;
        String? nameA = nodeA['name'];
        String? nameB = nodeB['name'];

        if (typeA == 3 && typeB != 3) { 
            if (nameA != null) _tryAdd(GateInfo(nameA, isEnter: false, px: halfwayPx), halfwayPx);
        } else if (typeA != 3 && typeB == 3) {
            if (nameB != null) _tryAdd(GateInfo(nameB, isEnter: true, px: halfwayPx), halfwayPx);
        } else if (typeA == 3 && typeB == 3 && nameA != nameB) {
            if (nameA != null) _tryAdd(GateInfo(nameA, isEnter: false, px: halfwayPx - 0.1), halfwayPx - 0.1);
            if (nameB != null) _tryAdd(GateInfo(nameB, isEnter: true, px: halfwayPx + 0.1), halfwayPx + 0.1);
        }
        
        bool isOutdoorA = typeA == 6 || (nodeA['isOutdoor'] == true);
        bool isOutdoorB = typeB == 6 || (nodeB['isOutdoor'] == true);

        if (!isOutdoorA && isOutdoorB) {
            _tryAdd(GateInfo('外', isEnter: false, px: halfwayPx), halfwayPx);
        } else if (isOutdoorA && !isOutdoorB) {
            if (typeB == 1) {
                _tryAdd(GateInfo('建物', isEnter: true, px: halfwayPx), halfwayPx);
            }
        }

        double xA = (nodeA['x'] as num).toDouble();
        double yA = (nodeA['y'] as num).toDouble();
        double xB = (nodeB['x'] as num).toDouble();
        double yB = (nodeB['y'] as num).toDouble();

        bool hasDoor = false;
        if (yB == yA && xB > xA) {
            if (nodeA['doorRight'] == true || nodeB['doorLeft'] == true) hasDoor = true;
        } else if (yB == yA && xB < xA) {
            if (nodeA['doorLeft'] == true || nodeB['doorRight'] == true) hasDoor = true;
        } else if (xB == xA && yB > yA) {
            if (nodeA['doorBottom'] == true || nodeB['doorTop'] == true) hasDoor = true;
        } else if (xB == xA && yB < yA) {
            if (nodeA['doorTop'] == true || nodeB['doorBottom'] == true) hasDoor = true;
        }

        final bool bothCorridor = (typeA != 3 && typeA != 4 && typeA != 5 && !isOutdoorA) &&
                                   (typeB != 3 && typeB != 4 && typeB != 5 && !isOutdoorB);
        if (bothCorridor && hasDoor) {
            _tryAdd(GateInfo('扉', isEnter: true, isDoor: true, px: halfwayPx), halfwayPx);
        }
    }

    _gateIdx = 0;
    _gateCtrl.add(nextGate);
  }

  void confirmGate(String gateKey) {
    final idx = _gates.indexWhere((g) => g.info.key == gateKey);
    if (idx == -1 || idx < _gateIdx) return;
    _traveled = _gates[idx].px;
    _gateIdx  = idx + 1;
    _gateCtrl.add(nextGate);
    _posCtrl.add(_calcPosition());
    _distCtrl.add(_traveled);
  }

  void dispose() {
    _sub?.cancel();
    _baroSub?.cancel();
    _gpsSub?.cancel();
    _posCtrl.close(); _distCtrl.close(); _gateCtrl.close();
    _altCtrl.close(); _gpsCtrl.close();
  }

  void _tryAdd(GateInfo info, double px) {
    final clamped = px.clamp(0.0, totalRoutePx);
    final prevPx  = _gates.isEmpty ? -1.0 : _gates.last.px;
    if (clamped > prevPx) _gates.add(_Gate(info, clamped));
  }

  void _buildCumDist() {
    _cumDist = [0.0];
    for (int i = 0; i < _path.length - 1; i++) {
      if (!_nodes.containsKey(_path[i]) || !_nodes.containsKey(_path[i + 1])) {
        _cumDist.add(_cumDist.last); continue;
      }
      final x1 = (_nodes[_path[i]    ]['x'] as num).toDouble(), y1 = (_nodes[_path[i]    ]['y'] as num).toDouble();
      final x2 = (_nodes[_path[i + 1]]['x'] as num).toDouble(), y2 = (_nodes[_path[i + 1]]['y'] as num).toDouble();
      _cumDist.add(_cumDist.last + sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2)));
    }
  }

  Offset? _calcPosition() {
    if (_path.isEmpty || _cumDist.isEmpty) return null;
    if (_traveled >= _cumDist.last) {
      final last = _path.last;
      return _nodes.containsKey(last)
          ? Offset((_nodes[last]['x'] as num).toDouble(), (_nodes[last]['y'] as num).toDouble()) : null;
    }
    for (int i = 0; i < _cumDist.length - 1; i++) {
      if (_traveled <= _cumDist[i + 1]) {
        final seg = _cumDist[i + 1] - _cumDist[i];
        final t   = seg == 0 ? 0.0 : (_traveled - _cumDist[i]) / seg;
        final x1 = (_nodes[_path[i]    ]['x'] as num).toDouble(), y1 = (_nodes[_path[i]    ]['y'] as num).toDouble();
        final x2 = (_nodes[_path[i + 1]]['x'] as num).toDouble(), y2 = (_nodes[_path[i + 1]]['y'] as num).toDouble();
        return Offset(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
      }
    }
    return null;
  }
}
// lib/step_tracker.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'config.dart';

class GateInfo {
  final String id;
  final bool isEnter;
  final bool isDoor;
  const GateInfo(this.id, {this.isEnter = true, this.isDoor = false});
  String get key   => isDoor ? '${id}_door' : (isEnter ? '${id}_in' : '${id}_out');
  String get label => isDoor ? '扉を通る' : (isEnter ? '「$id」に入りました' : '「$id」を出ました');
}

class _Gate {
  final GateInfo info;
  final double   px; // ルート累積距離(px)でここに達したら停止
  _Gate(this.info, this.px);
}

/// 加速度センサーで歩数を検出し、ゲート境界で自動停止するトラッカー。
class StepTracker {
  final double stepLengthPx;

  List<String>         _path     = [];
  Map<String, dynamic> _nodes    = {};
  List<double>         _cumDist  = [];
  double               _traveled = 0;
  bool                 _cooldown = false;
  List<_Gate>          _gates    = [];
  int                  _gateIdx  = 0;

  StreamSubscription?  _sub;
  final _posCtrl  = StreamController<Offset?>.broadcast();
  final _distCtrl = StreamController<double>.broadcast();
  final _gateCtrl = StreamController<GateInfo?>.broadcast();

  Stream<Offset?>   get positionStream => _posCtrl.stream;
  Stream<double>    get traveledStream => _distCtrl.stream;
  Stream<GateInfo?> get nextGateStream => _gateCtrl.stream;

  double         get totalRoutePx => _cumDist.isEmpty ? 0 : _cumDist.last;
  double         get traveledPx   => _traveled;
  GateInfo?      get nextGate     => _gateIdx < _gates.length ? _gates[_gateIdx].info : null;
  List<GateInfo> get orderedGates => _gates.map((g) => g.info).toList();

  StepTracker({required this.stepLengthPx});

  // ─── 公開API ──────────────────────────────────────────────────

  void startTracking(List<String> path, Map<String, dynamic> nodes) {
    _sub?.cancel();
    _path = path; _nodes = nodes;
    _traveled = 0; _gates = []; _gateIdx = 0;
    _buildCumDist();

    _sub = userAccelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((e) {
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
  }

  /// ルート確定後に呼ぶ。経路のトポロジーに基づいて正確な境界(部屋の出入り、扉)でゲートを設定する。
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

        // 部屋の出入り判定
        if (typeA == 3 && typeB == 1) { 
            if (nameA != null) _tryAdd(GateInfo(nameA, isEnter: false), halfwayPx);
        } else if (typeA == 1 && typeB == 3) {
            if (nameB != null) _tryAdd(GateInfo(nameB, isEnter: true), halfwayPx);
        } else if (typeA == 3 && typeB == 3 && nameA != nameB) {
            if (nameA != null) _tryAdd(GateInfo(nameA, isEnter: false), halfwayPx - 0.1);
            if (nameB != null) _tryAdd(GateInfo(nameB, isEnter: true), halfwayPx + 0.1);
        }

        // 扉の通過判定 (通路と通路の間、もしくは部屋と通路の境界に設置された扉)
        double xA = (nodeA['x'] as num).toDouble();
        double yA = (nodeA['y'] as num).toDouble();
        double xB = (nodeB['x'] as num).toDouble();
        double yB = (nodeB['y'] as num).toDouble();

        bool hasDoor = false;
        if (yB == yA && xB > xA) { // 右へ移動
            if (nodeA['doorRight'] == true || nodeB['doorLeft'] == true) hasDoor = true;
        } else if (yB == yA && xB < xA) { // 左へ移動
            if (nodeA['doorLeft'] == true || nodeB['doorRight'] == true) hasDoor = true;
        } else if (xB == xA && yB > yA) { // 下へ移動
            if (nodeA['doorBottom'] == true || nodeB['doorTop'] == true) hasDoor = true;
        } else if (xB == xA && yB < yA) { // 上へ移動
            if (nodeA['doorTop'] == true || nodeB['doorBottom'] == true) hasDoor = true;
        }

        // 通路の間にある扉を通る時だけ「扉を通る」を独立して出す（部屋に入りながら扉を通る場合は、部屋に入るボタンを優先する）
        if (typeA == 1 && typeB == 1 && hasDoor) {
            _tryAdd(GateInfo('扉', isEnter: true, isDoor: true), halfwayPx);
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
    _posCtrl.close(); _distCtrl.close(); _gateCtrl.close();
  }

  // ─── 内部処理 ─────────────────────────────────────────────────

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
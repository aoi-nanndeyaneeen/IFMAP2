// lib/step_tracker.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'config.dart';

class GateInfo {
  final String id;
  final bool isEnter;
  const GateInfo(this.id, {required this.isEnter});
  String get key   => isEnter ? '${id}_in' : '${id}_out';
  String get label => isEnter ? '「$id」に入りました' : '「$id」を出ました';
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

  /// ルート確定後に呼ぶ。経路セグメント距離でゲートを設定する。
  /// startId: 出発ノード（名前付きなら最初に「出る」ゲートを追加）
  void setGates(List<String> waypointIds, String? startId) {
    _gates = [];
    final r = AppConfig.waypointRadiusPx;

    if (startId != null && !startId.startsWith('node_')) {
      _tryAdd(GateInfo(startId, isEnter: false), r);
    }

    // ★ セグメント(線分)への最短距離でゲート位置を決定
    // ノードがまばらな廊下でも、沿道の部屋を正確に検出できる
    final sorted = waypointIds
        .map((id) => MapEntry(id, _closestCumDistOnSegments(id)))
        .where((e) => e.value >= 0)
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    for (final e in sorted) {
      _tryAdd(GateInfo(e.key, isEnter: true),  e.value - r); // 部屋の手前で「入る」
      _tryAdd(GateInfo(e.key, isEnter: false), e.value + r); // 部屋の奥で「出る」
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

  /// 経路「セグメント（線分）」への最短距離でゲート位置を特定。
  /// 線分上の最近傍点の累積距離を返す。見つからなければ -1。
  double _closestCumDistOnSegments(String wpId) {
    if (!_nodes.containsKey(wpId)) return -1;
    final wx = (_nodes[wpId]['x'] as num).toDouble();
    final wy = (_nodes[wpId]['y'] as num).toDouble();
    double minD = double.infinity, bestPx = -1;

    for (int i = 0; i < _path.length - 1; i++) {
      if (!_nodes.containsKey(_path[i]) || !_nodes.containsKey(_path[i + 1])) continue;
      final x1 = (_nodes[_path[i]    ]['x'] as num).toDouble();
      final y1 = (_nodes[_path[i]    ]['y'] as num).toDouble();
      final x2 = (_nodes[_path[i + 1]]['x'] as num).toDouble();
      final y2 = (_nodes[_path[i + 1]]['y'] as num).toDouble();
      final dx = x2 - x1, dy = y2 - y1;
      final lenSq = dx * dx + dy * dy;
      final t  = lenSq == 0 ? 0.0 : ((wx - x1) * dx + (wy - y1) * dy) / lenSq;
      final tc = t.clamp(0.0, 1.0);
      final d  = sqrt(pow(wx - (x1 + tc * dx), 2) + pow(wy - (y1 + tc * dy), 2));
      if (d < minD) {
        minD   = d;
        bestPx = _cumDist[i] + tc * (_cumDist[i + 1] - _cumDist[i]);
      }
    }
    return bestPx;
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
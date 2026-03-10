// lib/step_tracker.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'config.dart';

/// WaypointPanel と map_screen でも使う公開クラス
class GateInfo {
  final String id;
  final bool isEnter; // true=入る, false=出る
  const GateInfo(this.id, {required this.isEnter});
  String get key   => isEnter ? '${id}_in' : '${id}_out';
  String get label => isEnter ? '「$id」に入りました' : '「$id」を出ました';
}

class _Gate {
  final GateInfo info;
  final double   px; // ルート上の累積距離（この距離で停止）
  _Gate(this.info, this.px);
}

/// 加速度センサーで歩数を検出し、ゲート（入退室境界）で停止するトラッカー。
class StepTracker {
  final double stepLengthPx;

  List<String>         _path    = [];
  Map<String, dynamic> _nodes   = {};
  List<double>         _cumDist = [];
  double               _traveled = 0;
  bool                 _cooldown = false;

  List<_Gate> _gates   = [];
  int         _gateIdx = 0;

  StreamSubscription? _sub;
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
        _posCtrl.add(_calcPosition()); _distCtrl.add(_traveled);
        Future.delayed(const Duration(milliseconds: 400), () => _cooldown = false);
      }
    }, onError: (_) {});
  }

  /// ルート確定後に呼ぶ。
  /// startId = 出発ノードID（名前付きなら「出る」ゲートを先頭に追加）
  /// waypointIds = 経路近傍の名前付きノードID群
  void setGates(List<String> waypointIds, String? startId) {
    _gates = [];
    final r = AppConfig.waypointRadiusPx;

    // 出発地点の「出る」ゲート（startIdが名前付きノードの場合のみ）
    if (startId != null && !startId.startsWith('node_')) {
      _tryAdd(GateInfo(startId, isEnter: false), r);
    }

    // 各ウェイポイントをルート順にソートし、入退室ゲートペアを追加
    final sorted = waypointIds
        .map((id) => MapEntry(id, _closestCumDist(id)))
        .where((e) => e.value >= 0)
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    for (final e in sorted) {
      _tryAdd(GateInfo(e.key, isEnter: true),  e.value - r); // 入る（手前）
      _tryAdd(GateInfo(e.key, isEnter: false), e.value + r); // 出る（奥）
    }

    _gateIdx = 0;
    _gateCtrl.add(nextGate);
  }

  /// ゲートを確認（タップ）: その地点まで位置ジャンプし次ゲートを有効化
  void confirmGate(String gateKey) {
    final idx = _gates.indexWhere((g) => g.info.key == gateKey);
    if (idx == -1 || idx < _gateIdx) return;
    _traveled = _gates[idx].px;
    _gateIdx  = idx + 1;
    _gateCtrl.add(nextGate);
    _posCtrl.add(_calcPosition()); _distCtrl.add(_traveled);
  }

  void dispose() {
    _sub?.cancel();
    _posCtrl.close(); _distCtrl.close(); _gateCtrl.close();
  }

  // ─── 内部処理 ─────────────────────────────────────────────────

  /// 前のゲートより後ろかつ範囲内のみ追加
  void _tryAdd(GateInfo info, double px) {
    final clamped = px.clamp(0.0, totalRoutePx);
    final prevPx  = _gates.isEmpty ? -1.0 : _gates.last.px;
    if (clamped > prevPx) _gates.add(_Gate(info, clamped));
  }

  /// ウェイポイントノードに最も近い経路ノードの累積距離を返す（見つからなければ -1）
  double _closestCumDist(String wpId) {
    if (!_nodes.containsKey(wpId)) return -1;
    final wx = (_nodes[wpId]['x'] as num).toDouble();
    final wy = (_nodes[wpId]['y'] as num).toDouble();
    double minD = double.infinity; int best = 0;
    for (int i = 0; i < _path.length; i++) {
      if (!_nodes.containsKey(_path[i])) continue;
      final px = (_nodes[_path[i]]['x'] as num).toDouble();
      final py = (_nodes[_path[i]]['y'] as num).toDouble();
      final d  = sqrt(pow(px - wx, 2) + pow(py - wy, 2));
      if (d < minD) { minD = d; best = i; }
    }
    return best < _cumDist.length ? _cumDist[best] : -1;
  }

  void _buildCumDist() {
    _cumDist = [0.0];
    for (int i = 0; i < _path.length - 1; i++) {
      if (!_nodes.containsKey(_path[i]) || !_nodes.containsKey(_path[i + 1])) { _cumDist.add(_cumDist.last); continue; }
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
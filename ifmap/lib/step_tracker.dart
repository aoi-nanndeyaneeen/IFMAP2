// lib/step_tracker.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'config.dart';

/// 加速度センサーで歩数を検出し、ルート上の推定位置を計算するクラス。
/// pedometer と違い、スマホをどの向きで持っても動作する。
class StepTracker {
  final double stepLengthPx;

  List<String> _path = [];
  Map<String, dynamic> _nodes = {};
  List<double> _cumDist = [];

  double _traveled = 0;
  bool _stepCooldown = false; // 連続誤検出を防ぐクールダウン

  StreamSubscription? _sub;
  final _posCtrl  = StreamController<Offset?>.broadcast();
  final _distCtrl = StreamController<double>.broadcast();

  /// マップ上の推定位置ストリーム
  Stream<Offset?> get positionStream => _posCtrl.stream;

  /// 移動距離(px)ストリーム（残り距離表示用）
  Stream<double> get traveledStream => _distCtrl.stream;

  double get totalRoutePx => _cumDist.isEmpty ? 0 : _cumDist.last;
  double get traveledPx   => _traveled;

  StepTracker({required this.stepLengthPx});

  // ─── 公開メソッド ──────────────────────────────────────────────

  /// QRスキャン・ルート確定後に呼ぶ。加速度センサーを起動。
  void startTracking(List<String> path, Map<String, dynamic> nodes) {
    _sub?.cancel();
    _path    = path;
    _nodes   = nodes;
    _traveled = 0;
    _buildCumDist();

    // userAccelerometer = 重力除去済み加速度
    // → スマホの向き（縦持ち・横持ち・前向き）に関係なく歩行を検出できる
    _sub = userAccelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen(
      (event) {
        final mag = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
        if (mag > AppConfig.stepAccelThreshold && !_stepCooldown) {
          _stepCooldown = true;
          _traveled = (_traveled + stepLengthPx).clamp(0, totalRoutePx);
          _posCtrl.add(_calcPosition());
          _distCtrl.add(_traveled);
          // 400ms は次の歩を受け付けない（最大 2.5歩/秒）
          Future.delayed(const Duration(milliseconds: 400), () => _stepCooldown = false);
        }
      },
      onError: (_) {},
    );
  }

  /// 通過点チップをタップしたとき: そのノードまで位置をジャンプ
  void advanceTo(String nodeId) {
    final idx = _path.indexOf(nodeId);
    if (idx >= 0 && idx < _cumDist.length) {
      _traveled = _cumDist[idx];
      _posCtrl.add(_calcPosition());
      _distCtrl.add(_traveled);
    }
  }

  void dispose() {
    _sub?.cancel();
    _posCtrl.close();
    _distCtrl.close();
  }

  // ─── 内部処理 ──────────────────────────────────────────────────

  void _buildCumDist() {
    _cumDist = [0.0];
    for (int i = 0; i < _path.length - 1; i++) {
      if (!_nodes.containsKey(_path[i]) || !_nodes.containsKey(_path[i + 1])) {
        _cumDist.add(_cumDist.last); continue;
      }
      final x1 = (_nodes[_path[i]]    ['x'] as num).toDouble();
      final y1 = (_nodes[_path[i]]    ['y'] as num).toDouble();
      final x2 = (_nodes[_path[i + 1]]['x'] as num).toDouble();
      final y2 = (_nodes[_path[i + 1]]['y'] as num).toDouble();
      _cumDist.add(_cumDist.last + sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2)));
    }
  }

  Offset? _calcPosition() {
    if (_path.isEmpty || _cumDist.isEmpty) return null;
    if (_traveled >= _cumDist.last) {
      final last = _path.last;
      return _nodes.containsKey(last)
          ? Offset((_nodes[last]['x'] as num).toDouble(), (_nodes[last]['y'] as num).toDouble())
          : null;
    }
    for (int i = 0; i < _cumDist.length - 1; i++) {
      if (_traveled <= _cumDist[i + 1]) {
        final seg = _cumDist[i + 1] - _cumDist[i];
        final t   = seg == 0 ? 0.0 : (_traveled - _cumDist[i]) / seg;
        final x1  = (_nodes[_path[i]]    ['x'] as num).toDouble();
        final y1  = (_nodes[_path[i]]    ['y'] as num).toDouble();
        final x2  = (_nodes[_path[i + 1]]['x'] as num).toDouble();
        final y2  = (_nodes[_path[i + 1]]['y'] as num).toDouble();
        return Offset(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
      }
    }
    return null;
  }
}
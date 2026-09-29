// lib/sensors/motion_sample.dart
import 'package:flutter/foundation.dart';

/// 加速度センサーの1サンプル。
@immutable
class MotionSample {
  /// 秒。基準はプラットフォームごとに違うが、差だけを使うので問題ない。
  final double t;

  /// 重力込みの加速度の大きさ(m/s²)。静止していれば約 9.8。
  final double magnitude;

  const MotionSample(this.t, this.magnitude);
}

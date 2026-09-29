// lib/sensors/motion_source.dart
//
// 歩行検出に使う加速度の取得口。プラットフォームごとに実装を差し替える。
//   ネイティブ(iOS/Android) → motion_source_io.dart  (sensors_plus)
//   Web                     → motion_source_web.dart (devicemotion イベント)
//
// sensors_plus の Web 実装は Generic Sensor API を使っており、これは
// Chromium 系にしかない。iPhone の WebKit では1件もイベントが来ず、
// 歩数が数えられなかった。そのため Web では iPhone でも動く devicemotion を
// 直接使う。
//
// 渡すのは重力込みの加速度の大きさ。理由は step_detector.dart の冒頭を参照。
import 'motion_sample.dart';
import 'motion_source_web.dart' if (dart.library.io) 'motion_source_io.dart' as impl;

export 'motion_sample.dart';

/// 時刻つきの加速度サンプルのストリーム。
Stream<MotionSample> accelerationSamples() => impl.accelerationSamples();

/// 加速度センサーの生の状態。デバッグ画面に出して原因を切り分けるためのもの。
Map<String, String> motionDiagnostics() => impl.motionDiagnostics();

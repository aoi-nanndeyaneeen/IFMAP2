// lib/sensors/motion_source.dart
//
// 歩数検出に使う加速度の取得口。プラットフォームごとに実装を差し替える。
//   ネイティブ(iOS/Android) → motion_source_io.dart  (sensors_plus)
//   Web                     → motion_source_web.dart (devicemotion イベント)
//
// sensors_plus の Web 実装は Generic Sensor API（LinearAccelerationSensor）を
// 使っており、これは Chromium 系にしかない。iPhone の WebKit では1件も
// イベントが来ず、歩数が数えられなかった。そのため Web では iPhone でも
// 動く devicemotion を直接使う。
import 'motion_source_web.dart' if (dart.library.io) 'motion_source_io.dart' as impl;

/// 重力を除いた加速度の大きさ(m/s²)のストリーム。
Stream<double> userAccelerationMagnitude() => impl.userAccelerationMagnitude();

/// 加速度センサーの生の状態。デバッグ画面に出して原因を切り分けるためのもの。
Map<String, String> motionDiagnostics() => impl.motionDiagnostics();

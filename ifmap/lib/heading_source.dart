// lib/heading_source.dart
//
// 方位角(コンパス)の取得口。プラットフォームごとに実装を差し替える。
//   ネイティブ(iOS/Android) → heading_source_io.dart  (flutter_compass)
//   Web                     → heading_source_web.dart (DeviceOrientationEvent)
//
// flutter_compass は Web 非対応で、Web では EventChannel にイベントが
// 一切流れてこない。そのため Web では DeviceOrientationEvent を直接使う。
import 'heading_source_web.dart' if (dart.library.io) 'heading_source_io.dart' as impl;

/// 方位角のストリーム。単位は度、磁北から時計回り(0〜360)。
/// flutter_compass の heading と同じ意味なので呼び出し側の計算は変えなくてよい。
Stream<double> headingStream() => impl.headingStream();

/// センサー利用に明示的な許可要求が必要か（= ブラウザが requestPermission を
/// 持っているか）。ネイティブは常に false。Web は iOS Safari と Chrome で true。
/// 呼び出し側はこれが true かつ方位が未取得のときだけボタンを出せばよい。
bool needsSensorPermission() => impl.needsSensorPermission();

/// センサー許可ダイアログを出す。**必ずボタン等のユーザー操作から呼ぶこと**
/// （iOS Safari はユーザー操作外からの呼び出しを拒否する）。
/// 方位(DeviceOrientationEvent)と加速度(DeviceMotionEvent)をまとめて要求する。
Future<bool> requestSensorPermission() => impl.requestSensorPermission();

// lib/heading_source_io.dart
//
// ネイティブ(iOS/Android)用の方位取得。flutter_compass をそのまま使う。
// 許可はプラグイン側/OS側で処理されるのでこちらでは何もしない。
import 'package:flutter_compass/flutter_compass.dart';

Stream<double> headingStream() {
  final events = FlutterCompass.events;
  if (events == null) return const Stream<double>.empty();
  return events
      .map((e) => e.heading)
      .where((h) => h != null)
      .cast<double>();
}

bool needsSensorPermission() => false;

Future<bool> requestSensorPermission() async => true;

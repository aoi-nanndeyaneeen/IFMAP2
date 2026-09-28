// lib/heading_source_io.dart
//
// ネイティブ(iOS/Android)用の方位取得。flutter_compass をそのまま使う。
// 許可はプラグイン側/OS側で処理されるのでこちらでは何もしない。
import 'dart:io' show Platform;

import 'package:flutter_compass/flutter_compass.dart';

int _eventCount = 0;
double? _lastHeading;

Stream<double> headingStream() {
  final events = FlutterCompass.events;
  if (events == null) return const Stream<double>.empty();
  return events.map((e) {
    _eventCount++;
    _lastHeading = e.heading;
    return e.heading;
  }).where((h) => h != null).cast<double>();
}

bool needsSensorPermission() => false;

Future<bool> requestSensorPermission() async => true;

Map<String, String> sensorDiagnostics() => {
      'platform': Platform.operatingSystem,
      'implementation': 'flutter_compass (native)',
      'FlutterCompass.events': FlutterCompass.events == null ? 'null' : 'available',
      'eventCount': '$_eventCount',
      'lastHeading': _lastHeading?.toStringAsFixed(1) ?? 'none',
    };

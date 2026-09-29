// lib/sensors/motion_source_io.dart
//
// ネイティブ(iOS/Android)用。sensors_plus の userAccelerometer をそのまま使う。
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

int _eventCount = 0;
double? _lastMagnitude;

Stream<double> userAccelerationMagnitude() =>
    userAccelerometerEventStream().map((e) {
      _eventCount++;
      return _lastMagnitude = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    });

Map<String, String> motionDiagnostics() => {
      'implementation': 'sensors_plus userAccelerometer (native)',
      'eventCount': '$_eventCount',
      'lastMagnitude': _lastMagnitude?.toStringAsFixed(2) ?? 'none',
    };

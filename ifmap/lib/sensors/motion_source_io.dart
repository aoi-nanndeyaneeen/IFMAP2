// lib/sensors/motion_source_io.dart
//
// ネイティブ(iOS/Android)用。sensors_plus の accelerometer（重力込み）を使う。
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

import 'motion_sample.dart';

int _eventCount = 0;
double? _lastMagnitude;

Stream<MotionSample> accelerationSamples() =>
    accelerometerEventStream().map((e) {
      _eventCount++;
      final m = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      _lastMagnitude = m;
      return MotionSample(e.timestamp.microsecondsSinceEpoch / 1e6, m);
    });

Map<String, String> motionDiagnostics() => {
      'implementation': 'sensors_plus accelerometer (native)',
      'rawEventCount': '$_eventCount',
      'last |a| (m/s²)': _lastMagnitude?.toStringAsFixed(2) ?? 'none',
    };

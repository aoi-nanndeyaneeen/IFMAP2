// lib/sensors/motion_source_web.dart
//
// Web用。devicemotion イベントの accelerationIncludingGravity（重力込み）と
// event.timeStamp を使う。
// iOS では DeviceMotionEvent.requestPermission() で許可を得るまでイベントが
// 来ない。許可は heading_source_web.dart が方位と一緒に取り、取れたら
// reattachMotionListener() でここの listener を張り直す。
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'motion_sample.dart';

final _controller = StreamController<MotionSample>.broadcast();

JSFunction? _listener;

// ── 診断用 ──────────────────────────────────────────────────────
int _eventCount = 0;
String _lastMagnitude = 'never seen';

Stream<MotionSample> accelerationSamples() {
  _attach();
  return _controller.stream;
}

/// 許可を得たあとに listener を張り直す。許可前に張ったものには
/// イベントが来ないことがあるため。
void reattachMotionListener() {
  _detach();
  _attach();
}

void _attach() {
  if (_listener != null) return;
  _listener = ((JSObject event) => _onMotion(event)).toJS;
  globalContext.callMethod('addEventListener'.toJS, 'devicemotion'.toJS, _listener!);
}

void _detach() {
  final listener = _listener;
  if (listener == null) return;
  globalContext.callMethod('removeEventListener'.toJS, 'devicemotion'.toJS, listener);
  _listener = null;
}

void _onMotion(JSObject event) {
  _eventCount++;

  final acc = event.getProperty<JSObject?>('accelerationIncludingGravity'.toJS);
  if (acc == null) {
    _lastMagnitude = 'accelerationIncludingGravity=null';
    return;
  }
  double axis(String name) =>
      acc.getProperty<JSNumber?>(name.toJS)?.toDartDouble ?? 0;
  final x = axis('x'), y = axis('y'), z = axis('z');
  final magnitude = math.sqrt(x * x + y * y + z * z);
  // timeStamp はページを開いてからのミリ秒（DOMHighResTimeStamp）。
  final ms = event.getProperty<JSNumber?>('timeStamp'.toJS)?.toDartDouble;
  if (ms == null) return;
  _lastMagnitude = magnitude.toStringAsFixed(2);
  _controller.add(MotionSample(ms / 1000, magnitude));
}

Map<String, String> motionDiagnostics() => {
      'implementation': 'devicemotion (web)',
      'listenerAttached': '${_listener != null}',
      'rawEventCount': '$_eventCount',
      'last |a| (m/s², 静止で約9.8)': _lastMagnitude,
    };

// lib/sensors/motion_source_web.dart
//
// Web用。devicemotion イベントの acceleration（重力を除いた加速度）を使う。
// iOS では DeviceMotionEvent.requestPermission() で許可を得るまでイベントが
// 来ない。許可は heading_source_web.dart が方位と一緒に取り、取れたら
// reattachMotionListener() でここの listener を張り直す。
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

final _controller = StreamController<double>.broadcast();

JSFunction? _listener;

// ── 診断用 ──────────────────────────────────────────────────────
int _eventCount = 0;
String _lastMagnitude = 'never seen';

Stream<double> userAccelerationMagnitude() {
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

  // acceleration は重力を除いた値。これを持たない端末もあり、その場合は
  // accelerationIncludingGravity しかないが、重力の 9.8 が乗っていて
  // しきい値判定に使えないので捨てる。
  final acc = event.getProperty<JSObject?>('acceleration'.toJS);
  if (acc == null) {
    _lastMagnitude = 'acceleration=null';
    return;
  }
  double axis(String name) =>
      acc.getProperty<JSNumber?>(name.toJS)?.toDartDouble ?? 0;
  final x = axis('x'), y = axis('y'), z = axis('z');
  final magnitude = math.sqrt(x * x + y * y + z * z);
  _lastMagnitude = magnitude.toStringAsFixed(2);
  _controller.add(magnitude);
}

Map<String, String> motionDiagnostics() => {
      'implementation': 'devicemotion (web)',
      'listenerAttached': '${_listener != null}',
      'rawEventCount': '$_eventCount',
      'last magnitude (m/s²)': _lastMagnitude,
    };

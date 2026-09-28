// lib/heading_source_web.dart
//
// Web用の方位取得。ブラウザの DeviceOrientationEvent から方位角を作る。
//
//   iOS Safari      : event.webkitCompassHeading が磁北基準の方位角(度)をそのまま返す。
//                     ただし DeviceOrientationEvent.requestPermission() を
//                     ユーザー操作起点で呼んで許可を得るまでイベントが流れない。
//   Android Chrome  : deviceorientationabsolute の alpha(反時計回り)から換算する。
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

final _controller = StreamController<double>.broadcast();

JSFunction? _listener;

/// iOS で許可を得たあとに listener を張り直す必要があるため、
/// 現在 window に listener を登録しているかを持っておく。
bool _attached = false;

const _events = ['deviceorientationabsolute', 'deviceorientation'];

JSObject? get _orientationEventClass =>
    globalContext.has('DeviceOrientationEvent')
        ? globalContext['DeviceOrientationEvent'] as JSObject?
        : null;

JSObject? get _motionEventClass => globalContext.has('DeviceMotionEvent')
    ? globalContext['DeviceMotionEvent'] as JSObject?
    : null;

Stream<double> headingStream() {
  _attach();
  return _controller.stream;
}

bool needsSensorPermission() {
  final cls = _orientationEventClass;
  // iOS Safari に加えて Chrome にも requestPermission が生えている（実機で確認）。
  // 許可が要るかまではここでは判別できないので、API の有無だけを返す。
  return cls != null && cls.has('requestPermission');
}

Future<bool> requestSensorPermission() async {
  var granted = true;

  // 方位。これが本命。
  granted = await _request(_orientationEventClass) && granted;
  // 加速度も同じ流儀の許可が必要。歩数トラッキング(sensors_plus)のために
  // 同じタップでまとめて要求しておく。
  await _request(_motionEventClass);

  if (granted) {
    // 許可前に張った listener にはイベントが来ないので張り直す
    _detach();
    _attach();
  }
  return granted;
}

Future<bool> _request(JSObject? cls) async {
  if (cls == null || !cls.has('requestPermission')) return true;
  try {
    final promise = cls.callMethod<JSPromise<JSString>>('requestPermission'.toJS);
    final result = (await promise.toDart).toDart;
    return result == 'granted';
  } catch (_) {
    // 非セキュアコンテキストや未対応ブラウザ。イベントが来ないだけなので潰す。
    return false;
  }
}

void _attach() {
  if (_attached) return;
  _attached = true;
  _listener = ((JSObject event) => _onOrientation(event)).toJS;
  for (final name in _events) {
    globalContext.callMethod('addEventListener'.toJS, name.toJS, _listener!);
  }
}

void _detach() {
  final listener = _listener;
  if (listener != null) {
    for (final name in _events) {
      globalContext.callMethod('removeEventListener'.toJS, name.toJS, listener);
    }
  }
  _listener = null;
  _attached = false;
}

void _onOrientation(JSObject event) {
  // iOS: 磁北から時計回りの方位角がそのまま入っている
  final webkit = event.getProperty<JSNumber?>('webkitCompassHeading'.toJS);
  if (webkit != null) {
    _controller.add(webkit.toDartDouble % 360);
    return;
  }

  // Android等: alpha は「上辺が北のとき0」で反時計回りなので反転する。
  // absolute が false の相対値は北の基準がないので方位としては使えない。
  final absolute = event.getProperty<JSBoolean?>('absolute'.toJS)?.toDart ?? false;
  if (!absolute) return;
  final alpha = event.getProperty<JSNumber?>('alpha'.toJS);
  if (alpha == null) return;
  _controller.add((360 - alpha.toDartDouble) % 360);
}

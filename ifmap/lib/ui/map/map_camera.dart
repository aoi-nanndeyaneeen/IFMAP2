// lib/ui/map/map_camera.dart
//
// 地図の「カメラ」。どこを（中心）、どれだけ拡大して（ズーム）、
// どちらを上にして（回転）見ているか。
//
// 以前は InteractiveViewer の行列を直接書き換えていたので、
// 回転ができず、移動もすべて瞬間移動だった。ここではカメラを値として持ち、
// 移動・拡大・回転をすべてアニメーションでつなぐ。現在地の点の動きと
// 方位のぶれの平滑化も同じ時計で回す。
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

@immutable
class MapCamera {
  /// 画面の注視点に来る地図上の点（JSON-px）。
  final Offset center;

  /// 地図の 1 JSON-px が画面の何ピクセルになるか。
  final double zoom;

  /// 画面の上に向ける方角。地図の上を 0 とした時計回りのラジアン。
  final double bearing;

  const MapCamera({required this.center, required this.zoom, this.bearing = 0});

  MapCamera copyWith({Offset? center, double? zoom, double? bearing}) =>
      MapCamera(
        center: center ?? this.center,
        zoom: zoom ?? this.zoom,
        bearing: bearing ?? this.bearing,
      );

  /// 地図の点を画面の点へ。[focal] は注視点の画面座標。
  Offset toScreen(Offset map, Offset focal) {
    final vx = (map.dx - center.dx) * zoom, vy = (map.dy - center.dy) * zoom;
    final c = math.cos(bearing), s = math.sin(bearing);
    return Offset(focal.dx + vx * c + vy * s, focal.dy - vx * s + vy * c);
  }

  /// 画面の点を地図の点へ。
  Offset toMap(Offset screen, Offset focal) {
    final vx = screen.dx - focal.dx, vy = screen.dy - focal.dy;
    final c = math.cos(bearing), s = math.sin(bearing);
    return Offset(
      center.dx + (vx * c - vy * s) / zoom,
      center.dy + (vx * s + vy * c) / zoom,
    );
  }

  /// 画面上のずれを、地図上のずれへ（回転と拡大を戻す）。
  Offset screenDeltaToMap(Offset d) {
    final c = math.cos(bearing), s = math.sin(bearing);
    return Offset((d.dx * c - d.dy * s) / zoom, (d.dx * s + d.dy * c) / zoom);
  }

  static MapCamera lerp(MapCamera a, MapCamera b, double t) {
    // ズームは比で補間する（等速で拡大していくように見える）。
    final zoom = a.zoom * math.pow(b.zoom / a.zoom, t);
    return MapCamera(
      center: Offset.lerp(a.center, b.center, t)!,
      zoom: zoom.toDouble(),
      bearing: a.bearing + wrapAngle(b.bearing - a.bearing) * t,
    );
  }
}

/// 角度を (-π, π] に丸める。
double wrapAngle(double a) {
  var x = a % (2 * math.pi);
  if (x > math.pi) x -= 2 * math.pi;
  if (x <= -math.pi) x += 2 * math.pi;
  return x;
}

class _CameraAnimation {
  final MapCamera from;
  final MapCamera to;
  final Duration duration;
  final Curve curve;
  Duration? startedAt;
  _CameraAnimation(this.from, this.to, this.duration, this.curve);
}

class MapViewController extends ChangeNotifier {
  MapViewController({
    MapCamera initial = const MapCamera(center: Offset(3000, 3000), zoom: 0.2),
  }) : _camera = initial;

  MapCamera _camera;
  MapCamera get camera => _camera;

  double minZoom = 0.04;
  double maxZoom = 6.0;

  Size _size = Size.zero;
  Size get size => _size;
  bool get hasSize => _size.width > 0 && _size.height > 0;

  /// 地図の上に重なっている UI（検索欄・下のシート）の分の余白。
  /// 注視点と「全体を表示」はこの内側で計算する。
  EdgeInsets _padding = EdgeInsets.zero;
  EdgeInsets get padding => _padding;

  /// 注視点を、余白の内側の上から何割の高さに置くか。
  /// ナビ中は少し下げて、進む先を広く見せる。
  double _focusRatio = 0.5;

  /// ユーザーが指で地図を動かした。追従をやめるのに使う。
  VoidCallback? onUserMove;

  Offset get focal => _focalFor(_padding, _focusRatio);

  Offset _focalFor(EdgeInsets p, double ratio) => Offset(
        p.left + (_size.width - p.horizontal) / 2,
        p.top + (_size.height - p.vertical) * ratio,
      );

  Offset toScreen(Offset map) => _camera.toScreen(map, focal);
  Offset toMap(Offset screen) => _camera.toMap(screen, focal);

  /// 画面に映っている地図の範囲（回転していれば外接する長方形）。
  Rect get visibleMapRect {
    final pts = [
      toMap(Offset.zero),
      toMap(Offset(_size.width, 0)),
      toMap(Offset(0, _size.height)),
      toMap(Offset(_size.width, _size.height)),
    ];
    var r = Rect.fromPoints(pts[0], pts[1]);
    for (final p in pts.skip(2)) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r;
  }

  // ─── 時計 ───────────────────────────────────────────────────

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  void attach(TickerProvider vsync) {
    _ticker?.dispose();
    _ticker = vsync.createTicker(_onTick);
  }

  void detach() {
    _ticker?.dispose();
    _ticker = null;
  }

  void _ensureTicking() {
    final t = _ticker;
    if (t != null && !t.isActive) {
      _lastTick = Duration.zero;
      t.start();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    var active = false;

    final anim = _anim;
    if (anim != null) {
      anim.startedAt ??= elapsed;
      final t = ((elapsed - anim.startedAt!).inMicroseconds /
              anim.duration.inMicroseconds)
          .clamp(0.0, 1.0);
      _camera = MapCamera.lerp(anim.from, anim.to, anim.curve.transform(t));
      if (t >= 1) {
        _anim = null;
      } else {
        active = true;
      }
    }

    if (_flingVelocity != Offset.zero) {
      final v = _flingVelocity;
      _camera = _camera.copyWith(
          center: _camera.center - _camera.screenDeltaToMap(v * dt));
      // 摩擦で減速する（0.3秒ほどで半分）
      _flingVelocity = v * math.exp(-dt * 3.2);
      if (_flingVelocity.distance < 25) {
        _flingVelocity = Offset.zero;
      } else {
        active = true;
      }
    }

    if (_stepDot(dt)) active = true;
    if (_stepHeading(dt)) active = true;

    notifyListeners();
    if (!active) _ticker?.stop();
  }

  // ─── カメラの操作 ─────────────────────────────────────────────

  _CameraAnimation? _anim;
  Offset _flingVelocity = Offset.zero;

  bool get isAnimating => _anim != null;

  void setViewport(Size size, EdgeInsets padding) {
    final first = !hasSize && size.width > 0;
    _size = size;
    _padding = padding;
    if (first && _pendingFit != null) {
      // build の途中なので、通知は次のフレームで。
      SchedulerBinding.instance.addPostFrameCallback((_) {
        final pending = _pendingFit;
        _pendingFit = null;
        pending?.call();
      });
    }
  }

  /// 余白（検索欄やシートの高さ）が変わった。注視点の位置が変わるので
  /// そのままだと地図が跳ねる。見えている中心を保ったまま余白だけ替える。
  ///
  /// build の途中（MapViewport の didUpdateWidget）から呼ばれるので通知しない。
  /// 地図は同じフレームで描き直される。
  void updatePadding(EdgeInsets padding) {
    if (padding == _padding) return;
    _moveFocal(padding, _focusRatio, notify: false);
  }

  void setFocusRatio(double ratio) {
    if (ratio == _focusRatio) return;
    _moveFocal(_padding, ratio);
  }

  void _moveFocal(EdgeInsets padding, double ratio, {bool notify = true}) {
    // 新しい注視点に、いまそこに映っている地図の点を合わせる。
    // 動いている最中のアニメーションは、行き先を新しい注視点に
    // 持ってくるものなのでそのままにする。
    if (hasSize && _anim == null) {
      _camera = _camera.copyWith(center: toMap(_focalFor(padding, ratio)));
    }
    _padding = padding;
    _focusRatio = ratio;
    if (notify) notifyListeners();
  }

  VoidCallback? _pendingFit;

  void jumpTo(MapCamera camera) {
    _anim = null;
    _flingVelocity = Offset.zero;
    _camera = _clamp(camera);
    notifyListeners();
  }

  void animateTo(
    MapCamera target, {
    Duration duration = const Duration(milliseconds: 550),
    Curve curve = Curves.easeInOutCubic,
  }) {
    _flingVelocity = Offset.zero;
    final to = _clamp(target);
    if (_ticker == null) {
      jumpTo(to);
      return;
    }
    // 遠くへ飛ぶときは長めにする（瞬間移動に見えないように）。
    final screenDist =
        (to.center - _camera.center).distance * math.min(_camera.zoom, to.zoom);
    final far = screenDist > _size.longestSide * 1.5;
    _anim = _CameraAnimation(
      _camera,
      to,
      far ? duration * 1.4 : duration,
      curve,
    );
    _ensureTicking();
  }

  /// [bounds]（地図上の範囲）が余白の内側に収まるように寄せる。
  void fitBounds(
    Rect bounds, {
    double? bearing,
    double maxZoom = 1.6,
    EdgeInsets margin = const EdgeInsets.all(28),
    bool animate = true,
  }) {
    if (!hasSize) {
      _pendingFit = () => fitBounds(bounds,
          bearing: bearing, maxZoom: maxZoom, margin: margin, animate: false);
      return;
    }
    final b = bearing ?? _camera.bearing;
    // 回転した状態で見たときの、範囲の幅と高さ。
    final c = math.cos(b).abs(), s = math.sin(b).abs();
    final w = bounds.width * c + bounds.height * s;
    final h = bounds.width * s + bounds.height * c;
    final area = _padding + margin;
    final availW = math.max(40.0, _size.width - area.horizontal);
    final availH = math.max(40.0, _size.height - area.vertical);
    final zoom = math
        .min(math.min(availW / math.max(w, 1), availH / math.max(h, 1)), maxZoom)
        .clamp(minZoom, this.maxZoom);

    // 範囲の中心が「余白の内側の中心」に来るよう、注視点とのずれを足す。
    final areaCenter = _focalFor(area, 0.5);
    final shift = MapCamera(center: Offset.zero, zoom: zoom, bearing: b)
        .screenDeltaToMap(areaCenter - focal);
    final target =
        MapCamera(center: bounds.center - shift, zoom: zoom, bearing: b);
    animate ? animateTo(target) : jumpTo(target);
  }

  /// [point] を注視点に持ってくる。ズームと回転は指定したものだけ変える。
  void moveTo(Offset point,
      {double? zoom,
      double? bearing,
      Duration duration = const Duration(milliseconds: 550),
      Curve curve = Curves.easeInOutCubic}) {
    animateTo(
      MapCamera(
        center: point,
        zoom: zoom ?? _camera.zoom,
        bearing: bearing ?? _camera.bearing,
      ),
      duration: duration,
      curve: curve,
    );
  }

  void zoomBy(double factor, Offset screenPoint, {bool animate = true}) {
    final target = _zoomedAt(_camera, factor, screenPoint);
    animate
        ? animateTo(target,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic)
        : jumpTo(target);
  }

  MapCamera _zoomedAt(MapCamera cam, double factor, Offset screenPoint) {
    final zoom = (cam.zoom * factor).clamp(minZoom, maxZoom);
    final anchor = cam.toMap(screenPoint, focal);
    final next = cam.copyWith(zoom: zoom);
    // 指の下の点が動かないように中心をずらす。
    final moved = next.toMap(screenPoint, focal);
    return next.copyWith(center: next.center + (anchor - moved));
  }

  void resetBearing() => animateTo(_camera.copyWith(bearing: 0),
      duration: const Duration(milliseconds: 400));

  MapCamera _clamp(MapCamera c) =>
      c.copyWith(zoom: c.zoom.clamp(minZoom, maxZoom));

  // ─── 指での操作（MapViewport から呼ぶ） ─────────────────────────

  MapCamera? _gestureStart;
  Offset? _gestureAnchor;
  Offset _gestureFocal = Offset.zero;
  bool _rotating = false;
  double _rotationOffset = 0;
  int _maxPointers = 0;

  void gestureStart(Offset focalPoint) {
    _anim = null;
    _flingVelocity = Offset.zero;
    _gestureStart = _camera;
    _gestureAnchor = toMap(focalPoint);
    _gestureFocal = focalPoint;
    _rotating = false;
    _rotationOffset = 0;
    _maxPointers = 0;
  }

  void gestureUpdate({
    required Offset focalPoint,
    required double scale,
    required double rotation,
    required int pointers,
  }) {
    final start = _gestureStart;
    final anchor = _gestureAnchor;
    if (start == null || anchor == null) return;
    _maxPointers = math.max(_maxPointers, pointers);
    // 指の本数が変わると焦点が飛ぶので、その時点で基準を取り直す。
    if (pointers != _lastPointers) {
      _lastPointers = pointers;
      _gestureStart = _camera;
      _gestureAnchor = toMap(focalPoint);
      _gestureFocal = focalPoint;
      _scaleBase = scale;
      _rotationBase = rotation;
      return;
    }
    scale = scale / _scaleBase;
    rotation = rotation - _rotationBase;
    if ((focalPoint - _gestureFocal).distance > 4 || scale != 1) {
      onUserMove?.call();
    }

    // 2本指でひねったときだけ回す。ピンチのつもりで少しねじれたくらいでは
    // 回らないよう、15°を超えてから回し始める。
    if (pointers >= 2 && !_rotating && rotation.abs() > 0.26) {
      _rotating = true;
      _rotationOffset = rotation;
    }
    final bearing = _rotating
        ? start.bearing - (rotation - _rotationOffset)
        : start.bearing;
    final zoom = (start.zoom * scale).clamp(minZoom, maxZoom);
    final cam = MapCamera(center: start.center, zoom: zoom, bearing: bearing);
    // 指を置いた地図上の点が、いまの指の位置に来るように中心を決める。
    final moved = cam.toMap(focalPoint, focal);
    _camera = cam.copyWith(center: cam.center + (anchor - moved));
    if (_rotating) onUserMove?.call();
    notifyListeners();
  }

  int _lastPointers = 0;
  double _scaleBase = 1;
  double _rotationBase = 0;

  void gestureEnd(Offset velocity) {
    _gestureStart = null;
    _gestureAnchor = null;
    _lastPointers = 0;
    // 北向きのすぐそばで止めたら北に合わせる（ほぼ真上なのに少し傾いて
    // いる、が一番気持ち悪い）。
    if (_rotating && wrapAngle(_camera.bearing).abs() < 0.12) {
      animateTo(_camera.copyWith(bearing: 0),
          duration: const Duration(milliseconds: 250));
    } else if (_maxPointers <= 1 && velocity.distance > 250) {
      _flingVelocity = velocity;
      _ensureTicking();
    }
    _rotating = false;
  }

  // ─── 現在地の点と方位（表示用に滑らかにする） ───────────────────

  Offset? _dotFrom;
  Offset? _dotTo;
  double _dotT = 1;
  static const _dotSeconds = 0.45;

  /// 表示している現在地（JSON-px）。歩数の更新は1歩ずつ飛ぶので、
  /// 間をつないで歩いているように動かす。
  Offset? get userDot {
    final to = _dotTo;
    final from = _dotFrom;
    if (to == null) return null;
    if (from == null || _dotT >= 1) return to;
    return Offset.lerp(from, to, Curves.easeOut.transform(_dotT));
  }

  void setUserPosition(Offset? p, {bool animate = true}) {
    if (p == _dotTo) return;
    if (p == null || _dotTo == null || !animate || _ticker == null) {
      _dotFrom = null;
      _dotTo = p;
      _dotT = 1;
      notifyListeners();
      return;
    }
    // 大きく飛んだ（QRで補正した・階を移った）ときはアニメーションしない。
    if ((p - _dotTo!).distance > 400) {
      _dotFrom = null;
      _dotTo = p;
      _dotT = 1;
      notifyListeners();
      return;
    }
    _dotFrom = userDot;
    _dotTo = p;
    _dotT = 0;
    _ensureTicking();
  }

  bool _stepDot(double dt) {
    if (_dotT >= 1) return false;
    _dotT = math.min(1, _dotT + dt / _dotSeconds);
    return _dotT < 1;
  }

  double? _headingTarget;
  double? _heading;

  /// 表示している方位（地図の上を 0 とした時計回りのラジアン）。
  double? get heading => _heading;

  void setHeading(double? radians) {
    _headingTarget = radians;
    if (radians == null) {
      _heading = null;
      notifyListeners();
      return;
    }
    _heading ??= radians;
    _ensureTicking();
  }

  bool _stepHeading(double dt) {
    final target = _headingTarget;
    final h = _heading;
    if (target == null || h == null) return false;
    final diff = wrapAngle(target - h);
    if (diff.abs() < 0.002) {
      _heading = target;
      return false;
    }
    // 0.12秒ほどで追いつく一次遅れ。手ぶれで扇がぷるぷるしないように。
    _heading = h + diff * (1 - math.exp(-dt / 0.12));
    return true;
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }
}

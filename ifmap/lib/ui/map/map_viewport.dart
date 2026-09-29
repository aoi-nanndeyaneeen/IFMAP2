// lib/ui/map/map_viewport.dart
//
// 地図を表示し、指の操作をカメラに伝える。
//
//   1本指でドラッグ … 移動（離すと慣性で滑る）
//   2本指でピンチ   … 拡大・縮小
//   2本指でひねる   … 回転（15°を超えてから）
//   ダブルタップ    … その場所を拡大
//   タップ          … その場所を選ぶ（画面へ地図座標で返す）
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'map_camera.dart';
import 'map_painter.dart';

class MapViewport extends StatefulWidget {
  final MapViewController view;
  final MapScene? scene;

  /// 地図の上に重なる UI の分の余白。注視点の計算に使う。
  final EdgeInsets padding;

  /// タップされた。[mapPoint] は地図座標、[screenPoint] は画面座標。
  final void Function(Offset mapPoint, Offset screenPoint)? onTap;

  const MapViewport({
    super.key,
    required this.view,
    required this.scene,
    this.padding = EdgeInsets.zero,
    this.onTap,
  });

  @override
  State<MapViewport> createState() => _MapViewportState();
}

class _MapViewportState extends State<MapViewport>
    with TickerProviderStateMixin {
  Offset? _doubleTapAt;

  @override
  void initState() {
    super.initState();
    widget.view.attach(this);
  }

  @override
  void didUpdateWidget(MapViewport old) {
    super.didUpdateWidget(old);
    if (old.view != widget.view) {
      old.view.detach();
      widget.view.attach(this);
    }
    if (old.padding != widget.padding) {
      widget.view.updatePadding(widget.padding);
    }
  }

  @override
  void dispose() {
    widget.view.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    return LayoutBuilder(builder: (context, constraints) {
      view.setViewport(constraints.biggest, widget.padding);
      final scene = widget.scene;
      return Listener(
        // マウスのホイール・トラックパッドでも拡大できるように（PCでの確認用）。
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            view.zoomBy(math.exp(-e.scrollDelta.dy / 400), e.localPosition,
                animate: false);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (d) => view.gestureStart(d.localFocalPoint),
          onScaleUpdate: (d) => view.gestureUpdate(
            focalPoint: d.localFocalPoint,
            scale: d.scale,
            rotation: d.rotation,
            pointers: d.pointerCount,
          ),
          onScaleEnd: (d) => view.gestureEnd(d.velocity.pixelsPerSecond),
          onTapUp: (d) =>
              widget.onTap?.call(view.toMap(d.localPosition), d.localPosition),
          onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
          onDoubleTap: () {
            final at = _doubleTapAt;
            if (at != null) view.zoomBy(2, at);
          },
          child: scene == null
              ? const SizedBox.expand()
              : RepaintBoundary(
                  child: CustomPaint(
                    size: Size.infinite,
                    isComplex: true,
                    willChange: true,
                    painter: MapPainter(scene: scene, view: view),
                  ),
                ),
        ),
      );
    });
  }
}

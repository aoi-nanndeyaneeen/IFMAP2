// lib/ui/map_view.dart
//
// マップ本体。拡大縮小・スクロールとタップ判定を持つ。
//
// 現在地と方位はコントローラの ValueNotifier から直接受け取る。
// センサーは毎秒何度も値を流してくるので、画面全体ではなく
// この CustomPaint だけを描き直したい。
import 'package:flutter/material.dart';

import '../config.dart';
import '../data/map_data.dart';
import '../navigation/navigation_controller.dart';
import 'map_painter.dart';

class MapView extends StatelessWidget {
  final NavigationController controller;
  final TransformationController transformation;

  /// マップ上の座標（JSON-px）で、押された場所にいちばん近い地点の名前。
  final void Function(String name) onPlaceTapped;

  const MapView({
    super.key,
    required this.controller,
    required this.transformation,
    required this.onPlaceTapped,
  });

  @override
  Widget build(BuildContext context) {
    final floor = controller.currentFloor;
    if (floor == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return InteractiveViewer(
      transformationController: transformation,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      minScale: 0.1,
      maxScale: 5.0,
      constrained: false, // これがないとマップが画面サイズに縮んでしまう
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _handleTap(floor, d.localPosition),
        child: RepaintBoundary(
          child: ValueListenableBuilder<Offset?>(
            valueListenable: controller.position,
            builder: (_, pos, __) => ValueListenableBuilder<double?>(
              valueListenable: controller.heading,
              builder: (_, heading, __) => CustomPaint(
                size: const Size(AppConfig.mapCanvasSize, AppConfig.mapCanvasSize),
                painter: MapPainter(
                  floor: floor,
                  path: controller.currentPath,
                  startName: controller.start?.name,
                  goalName: controller.goal?.name,
                  startCenter: controller.startCenter,
                  goalCenter: controller.goalCenter,
                  estimatedPosition: pos,
                  headingDeg: _canvasHeading(heading),
                  showUserDot: controller.showUserDot,
                  isStartOnCurrentFloor: controller.isStartOnCurrentFloor,
                  isGoalOnCurrentFloor: controller.isGoalOnCurrentFloor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 磁北基準の方位角を、キャンバス上の角度（右が0、時計回り）に直す。
  /// マップの「上」が磁北でない分を mapNorthDegrees で吸収する。
  double? _canvasHeading(double? heading) {
    if (heading == null) return null;
    return ((heading - AppConfig.mapNorthDegrees - 90) % 360 + 360) % 360;
  }

  /// タップ地点にいちばん近い「名前のある場所」を探す。
  ///
  /// ノード・セル・部屋ラベルの3つを順に見る。ノードだけだと
  /// 部屋の内側の何も置いていないマスを押したときに反応しないため。
  void _handleTap(FloorMap floor, Offset p) {
    // 比較は二乗距離のまま行う（平方根を取る必要がない）。
    const maxDistance = 30.0;
    var best = maxDistance * maxDistance;
    String? name;

    void consider(double x, double y, String? candidate) {
      if (candidate == null || candidate.isEmpty) return;
      final dx = x - p.dx;
      final dy = y - p.dy;
      final d = dx * dx + dy * dy;
      if (d < best) {
        best = d;
        name = candidate;
      }
    }

    for (final v in floor.nodes.values) {
      if (v is! Map) continue;
      if (v['isStairs'] == true || v['isConnector'] == true) continue;
      consider(
        (v['x'] as num).toDouble() + AppConfig.cellCenter,
        (v['y'] as num).toDouble() + AppConfig.cellCenter,
        v['name'] as String?,
      );
    }

    for (final c in floor.cells) {
      if (c is! Map) continue;
      final type = (c['type'] as num?)?.toInt() ?? 0;
      if (type == CellType.stairs || type == CellType.connector) continue;
      consider(
        (c['x'] as num).toDouble() * AppConfig.pxPerCell + AppConfig.cellCenter,
        (c['y'] as num).toDouble() * AppConfig.pxPerCell + AppConfig.cellCenter,
        c['name'] as String?,
      );
    }

    for (final entry in floor.roomCenters.entries) {
      consider(entry.value.dx, entry.value.dy, entry.key);
    }

    final hit = name;
    if (hit != null) onPlaceTapped(hit);
  }
}

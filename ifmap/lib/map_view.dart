// lib/widgets/map_view.dart
import 'package:flutter/material.dart';
import '../config.dart';
import '../map_painter.dart';

class MapView extends StatelessWidget {
  final TransformationController txController;
  final Map<String, dynamic> nodes;
  final List<dynamic> cells;
  final List<dynamic> rooms;
  final List<String> currentPath;
  final String? startNode;
  final String? goalNode;
  final String currentLabel;
  final Offset? goalCenter;
  final Offset? startCenter;
  final Offset? estimatedPosition;
  final double? headingDeg;
  final bool showUserDot;
  final bool isGoalOnCurrentFloor;
  final bool isStartOnCurrentFloor;

  const MapView({
    super.key,
    required this.txController,
    required this.nodes,
    required this.cells,
    required this.rooms,
    required this.currentPath,
    this.startNode,
    this.goalNode,
    required this.currentLabel,
    this.goalCenter,
    this.startCenter,
    this.estimatedPosition,
    this.headingDeg,
    required this.showUserDot,
    this.isGoalOnCurrentFloor = false,
    this.isStartOnCurrentFloor = false,
  });

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return InteractiveViewer(
      transformationController: txController,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      minScale: 0.1, maxScale: 5.0,
      constrained: false,   // ★ これがないとマップが画面に収縮する
      child: Center(
        child: CustomPaint(
          size: const Size(AppConfig.mapCanvasSize, AppConfig.mapCanvasSize),
          painter: MapPainter(
            nodes: nodes,
            cells: cells,
            rooms: rooms,
            path: currentPath,
            startNode: startNode,
            goalNode: goalNode,
            goalCenter: goalCenter,
            startCenter: startCenter,
            currentLabel: currentLabel,
            estimatedPosition: estimatedPosition,
            headingDeg: headingDeg,
            showUserDot: showUserDot,
            isGoalOnCurrentFloor: isGoalOnCurrentFloor,
            isStartOnCurrentFloor: isStartOnCurrentFloor,
          ),
        ),
      ),
    );
  }
}
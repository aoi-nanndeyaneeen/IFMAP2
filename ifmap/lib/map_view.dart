// lib/widgets/map_view.dart
import 'package:flutter/material.dart';
import '../config.dart';
import '../map_painter.dart';

class MapView extends StatelessWidget {
  final TransformationController txController;
  final Map<String, dynamic> nodes;
  final List<String> currentPath;
  final String? startNode;
  final String? goalNode;
  final Offset? estimatedPosition;
  final double? headingDeg;

  const MapView({
    super.key,
    required this.txController,
    required this.nodes,
    required this.currentPath,
    this.startNode,
    this.goalNode,
    this.estimatedPosition,
    this.headingDeg,
  });

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const Center(child: CircularProgressIndicator());
    return InteractiveViewer(
      transformationController: txController,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      minScale: 0.1, maxScale: 5.0,
      constrained: false,   // ★ これがないとマップが画面に収縮する
      child: Center(
        child: CustomPaint(
          size: const Size(AppConfig.mapCanvasSize, AppConfig.mapCanvasSize),
          painter: MapPainter(
            nodes: nodes, path: currentPath,
            startNode: startNode, goalNode: goalNode,
            estimatedPosition: estimatedPosition,
            headingDeg: headingDeg,
          ),
        ),
      ),
    );
  }
}
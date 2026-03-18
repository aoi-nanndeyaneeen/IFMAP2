// lib/main.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'config.dart';
import 'map_cell.dart';
import 'tool_palette.dart';
import 'json_exporter.dart';
import 'canvas_area.dart';

void main() {
  runApp(const MapEditorApp());
}

class MapEditorApp extends StatelessWidget {
  const MapEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'infacilityMAP Editor v9.1',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const EditorScreen(),
    );
  }
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late List<List<MapCell>> grid;
  int currentBrush = 1;
  Uint8List? bgImageBytes;
  int? dragStartX, dragStartY, dragCurrentX, dragCurrentY;
  final TransformationController _transformController = TransformationController();

  List<List<List<MapCell>>> undoHistory = [];
  List<List<List<MapCell>>> redoHistory = [];

  List<List<MapCell>> _cloneGrid(List<List<MapCell>> source) {
    return source.map((r) => r.map((c) => MapCell(x: c.x, y: c.y, type: c.type, name: c.name)).toList()).toList();
  }

  void _saveHistory() {
    undoHistory.add(_cloneGrid(grid));
    if (undoHistory.length > 50) undoHistory.removeAt(0);
    redoHistory.clear();
  }

  void _undo() {
    if (undoHistory.isNotEmpty) {
      redoHistory.add(_cloneGrid(grid));
      setState(() => grid = undoHistory.removeLast());
    }
  }

  void _redo() {
    if (redoHistory.isNotEmpty) {
      undoHistory.add(_cloneGrid(grid));
      setState(() => grid = redoHistory.removeLast());
    }
  }

  void _zoomIn() {
    _transformController.value = _transformController.value.clone()..scale(1.2);
  }

  void _zoomOut() {
    _transformController.value = _transformController.value.clone()..scale(1/1.2);
  }

  @override
  void initState() {
    super.initState();
    grid = List.generate(
      AppConfig.rows,
      (y) => List.generate(AppConfig.cols, (x) => MapCell(x: x, y: y)),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() => bgImageBytes = bytes);
    }
  }

  Future<void> _showNameDialog(MapCell cell, int brushType) async {
    String tempName = "";
    String typeName = brushType == 3 ? '目的地' : '階段';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$typeNameの名前を入力'),
        content: TextField(
          autofocus: true,
          onChanged: (val) => tempName = val,
          decoration: const InputDecoration(hintText: '例: room_left, stairs_up'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () {
              if (tempName.isNotEmpty) {
                _saveHistory();
                setState(() { cell.type = brushType; cell.name = tempName; });
              }
              Navigator.pop(context);
            },
            child: const Text('決定'),
          ),
        ],
      ),
    );
  }

  void _paintCellSingle(int y, int x, int brush) {
    if (x < 0 || x >= AppConfig.cols || y < 0 || y >= AppConfig.rows) return;
    MapCell cell = grid[y][x];
    if (cell.type != 3 && cell.type != 4) {
      cell.type = brush;
      if (brush == 0) cell.name = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('マップエディタ v9.1（完全分割版）'),
        backgroundColor: Colors.blueGrey,
        actions: [
          ElevatedButton.icon(onPressed: _pickImage, icon: const Icon(Icons.map), label: const Text('見取り図を読込')),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.undo),
            color: Colors.white,
            onPressed: undoHistory.isNotEmpty ? _undo : null,
            tooltip: '元に戻す',
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            color: Colors.white,
            onPressed: redoHistory.isNotEmpty ? _redo : null,
            tooltip: 'やり直し',
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            color: Colors.white,
            onPressed: _zoomOut,
            tooltip: '縮小',
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in),
            color: Colors.white,
            onPressed: _zoomIn,
            tooltip: '拡大',
          ),
          const Center(
            child: Text(
              '※手のひらツールで移動\n※スクロールで拡大縮小',
              style: TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: () => JsonExporter.export(context, grid),
            icon: const Icon(Icons.download), label: const Text('JSON出力'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white)
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          ToolPalette(currentBrush: currentBrush, onBrushSelected: (b) => setState(() => currentBrush = b)),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: CanvasArea(
                  grid: grid,
                  currentBrush: currentBrush,
                  bgImageBytes: bgImageBytes,
                  transformController: _transformController, // コントローラーを渡す
                  dragStartX: dragStartX, dragStartY: dragStartY,
                  dragCurrentX: dragCurrentX, dragCurrentY: dragCurrentY,
                  onPointerDown: (y, x, buttons) {
                    if (buttons == 2) {
                      _saveHistory();
                      setState(() => _paintCellSingle(y, x, 0)); // 右クリックは消しゴム
                    } else if (currentBrush == 3 || currentBrush == 4) {
                      _showNameDialog(grid[y][x], currentBrush);
                    } else if (currentBrush == 2 || currentBrush == -1) {
                      setState(() { dragStartX = x; dragStartY = y; dragCurrentX = x; dragCurrentY = y; });
                    } else {
                      _saveHistory();
                      setState(() => _paintCellSingle(y, x, currentBrush));
                    }
                  },
                  onPointerMove: (y, x, buttons) {
                    if (buttons == 2) {
                      setState(() => _paintCellSingle(y, x, 0));
                    } else if (currentBrush == 2 || currentBrush == -1) {
                      setState(() { dragCurrentX = x; dragCurrentY = y; });
                    } else if (currentBrush == 1 || currentBrush == 0) {
                      setState(() => _paintCellSingle(y, x, currentBrush));
                    }
                  },
                  onPointerUp: () {
                    if (currentBrush == 2 || currentBrush == -1) {
                      if (dragStartX != null && dragStartY != null && dragCurrentX != null && dragCurrentY != null) {
                        _saveHistory();
                        int minX = dragStartX! < dragCurrentX! ? dragStartX! : dragCurrentX!;
                        int maxX = dragStartX! > dragCurrentX! ? dragStartX! : dragCurrentX!;
                        int minY = dragStartY! < dragCurrentY! ? dragStartY! : dragCurrentY!;
                        int maxY = dragStartY! > dragCurrentY! ? dragStartY! : dragCurrentY!;
                        int brush = currentBrush == 2 ? 1 : 0;
                        setState(() {
                          for (int y = minY; y <= maxY; y++) {
                            // ↓ カッコ {} を追加して青い線を消しました！
                            for (int x = minX; x <= maxX; x++) {
                              _paintCellSingle(y, x, brush);
                            }
                          }
                          dragStartX = null; dragStartY = null; dragCurrentX = null; dragCurrentY = null;
                        });
                      }
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
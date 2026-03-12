// ifmap_editor/lib/main.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import 'map_cell.dart';
import 'tool_palette.dart';
import 'json_exporter.dart';
import 'canvas_area.dart';

void main() => runApp(const MapEditorApp());

class MapEditorApp extends StatelessWidget {
  const MapEditorApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'infacilityMAP Editor',
    theme: ThemeData(primarySwatch: Colors.blue),
    home: const EditorScreen(),
  );
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

  @override
  void initState() {
    super.initState();
    grid = List.generate(AppConfig.rows, (y) => List.generate(AppConfig.cols, (x) => MapCell(x: x, y: y)));
  }

  Future<void> _pickImage() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f != null) setState(() async => bgImageBytes = await f.readAsBytes());
  }

  // 目的地・階段の名前ダイアログ
  Future<void> _showNameDialog(MapCell cell, int brushType) async {
    String name = '';
    final typeName = brushType == 3 ? '目的地/QR' : '階段';
    await showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('$typeNameの名前'),
      content: TextField(autofocus: true, onChanged: (v) => name = v,
          decoration: const InputDecoration(hintText: '例: 会議室, stairs_1')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        ElevatedButton(onPressed: () {
          if (name.isNotEmpty) setState(() { cell.type = brushType; cell.name = name; });
          Navigator.pop(context);
        }, child: const Text('決定')),
      ],
    ));
  }

  // 接続点ダイアログ（3フィールド）
  Future<void> _showConnectorDialog(MapCell cell) async {
    String name = '', toMap = '', toNode = '';
    await showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('⇄ 接続点の設定'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(autofocus: true, decoration: const InputDecoration(labelText: 'このノードの名前', hintText: '例: connector_to_new'), onChanged: (v) => name = v),
        const SizedBox(height: 8),
        TextField(decoration: const InputDecoration(labelText: '接続先マップのラベル', hintText: '例: 新館1F'), onChanged: (v) => toMap = v),
        const SizedBox(height: 8),
        TextField(decoration: const InputDecoration(labelText: '接続先ノードID', hintText: '例: connector_from_main'), onChanged: (v) => toNode = v),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        ElevatedButton(onPressed: () {
          if (name.isNotEmpty) setState(() {
            cell.type = 5; cell.name = name;
            cell.connectsToMap  = toMap.isNotEmpty  ? toMap  : null;
            cell.connectsToNode = toNode.isNotEmpty ? toNode : null;
          });
          Navigator.pop(context);
        }, child: const Text('決定')),
      ],
    ));
  }

  void _paint(int y, int x, int brush) {
    if (x < 0 || x >= AppConfig.cols || y < 0 || y >= AppConfig.rows) return;
    final cell = grid[y][x];
    if (cell.type == 3 || cell.type == 4 || cell.type == 5) return; // 名前付きは上書きしない
    cell.type = brush;
    if (brush == 0) { cell.name = null; cell.connectsToMap = null; cell.connectsToNode = null; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('mapエディタ  [${AppConfig.cols}×${AppConfig.rows}マス / ${(AppConfig.cols * AppConfig.metersPerCell).toStringAsFixed(0)}m×${(AppConfig.rows * AppConfig.metersPerCell).toStringAsFixed(0)}m]'),
        backgroundColor: Colors.blueGrey,
        actions: [
          ElevatedButton.icon(onPressed: _pickImage, icon: const Icon(Icons.map), label: const Text('見取り図')),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => JsonExporter.export(context, grid),
            icon: const Icon(Icons.download), label: const Text('JSON出力'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(children: [
        ToolPalette(currentBrush: currentBrush, onBrushSelected: (b) => setState(() => currentBrush = b)),
        Expanded(child: Center(child: Padding(
          padding: const EdgeInsets.all(16),
          child: AspectRatio(
            aspectRatio: AppConfig.cols / AppConfig.rows,
            child: CanvasArea(
              grid: grid, currentBrush: currentBrush, bgImageBytes: bgImageBytes,
              dragStartX: dragStartX, dragStartY: dragStartY,
              dragCurrentX: dragCurrentX, dragCurrentY: dragCurrentY,
              onPointerDown: (y, x) {
                if (currentBrush == 3 || currentBrush == 4) {
                  _showNameDialog(grid[y][x], currentBrush);
                } else if (currentBrush == 5) {
                  _showConnectorDialog(grid[y][x]);
                } else if (currentBrush == 2 || currentBrush == -1) {
                  setState(() { dragStartX = x; dragStartY = y; dragCurrentX = x; dragCurrentY = y; });
                } else {
                  setState(() => _paint(y, x, currentBrush));
                }
              },
              onPointerMove: (y, x) {
                if (currentBrush == 2 || currentBrush == -1) {
                  setState(() { dragCurrentX = x; dragCurrentY = y; });
                } else if (currentBrush == 1 || currentBrush == 0) {
                  setState(() => _paint(y, x, currentBrush));
                }
              },
              onPointerUp: () {
                if ((currentBrush == 2 || currentBrush == -1) && dragStartX != null) {
                  final minX = dragStartX! < dragCurrentX! ? dragStartX! : dragCurrentX!;
                  final maxX = dragStartX! > dragCurrentX! ? dragStartX! : dragCurrentX!;
                  final minY = dragStartY! < dragCurrentY! ? dragStartY! : dragCurrentY!;
                  final maxY = dragStartY! > dragCurrentY! ? dragStartY! : dragCurrentY!;
                  final brush = currentBrush == 2 ? 1 : 0;
                  setState(() {
                    for (int y = minY; y <= maxY; y++) {
                      for (int x = minX; x <= maxX; x++) { _paint(y, x, brush); }
                    }
                    dragStartX = dragStartY = dragCurrentX = dragCurrentY = null;
                  });
                }
              },
            ),
          ),
        ))),
      ]),
    );
  }
}
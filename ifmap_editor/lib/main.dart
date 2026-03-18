import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
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

  int brushType = 1;
  String drawMode = 'stroke';
  bool isRightClickEraser = false;

  Uint8List? bgImageBytes;

  int? dragStartX, dragStartY, dragCurrentX, dragCurrentY;
  final TransformationController _transformController = TransformationController();

  List<List<List<MapCell>>> undoHistory = [];
  List<List<List<MapCell>>> redoHistory = [];

  Set<MapCell> currentStrokeCells = {};

  String? _pendingName;
  String? _pendingConnectsToMap;
  String? _pendingConnectsToNode;

  List<List<MapCell>> _cloneGrid(List<List<MapCell>> source) {
    return source.map((r) => r.map((c) => MapCell(
      x: c.x, y: c.y, type: c.type, name: c.name,
      connectsToMap: c.connectsToMap, connectsToNode: c.connectsToNode
    )).toList()).toList();
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
      setState(() => grid = undoHistory.removeLast());
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
    final f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f != null) {
      final bytes = await f.readAsBytes();
      setState(() {
        bgImageBytes = bytes;
      });
    }
  }

  bool _isNameDuplicate(String name, int type) {
    for (var row in grid) {
      for (var cell in row) {
        if (cell.type == type && cell.name == name) return true;
      }
    }
    return false;
  }

  Future<void> _importJson() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null && result.files.single.bytes != null) {
      try {
        final jsonStr = utf8.decode(result.files.single.bytes!);
        final decoded = jsonDecode(jsonStr);
        if (decoded['_editorData'] != null) {
          final editorData = decoded['_editorData'];
          final String? bgBase64 = editorData['bgImageBase64'];
          final List cellsData = editorData['cells'];

          setState(() {
            bgImageBytes = bgBase64 != null ? base64Decode(bgBase64) : null;
            for (int y = 0; y < AppConfig.rows; y++) {
              for (int x = 0; x < AppConfig.cols; x++) {
                final cData = cellsData[y][x];
                grid[y][x] = MapCell(
                  x: x, y: y,
                  type: cData['type'],
                  name: cData['name'],
                  connectsToMap: cData['connectsToMap'],
                  connectsToNode: cData['connectsToNode'],
                );
              }
            }
            undoHistory.clear();
            redoHistory.clear();
          });
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('プロジェクトを復元しました')));
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('エディタ用のデータ(_editorData)が見つかりません')));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('読出エラー: $e')));
      }
    }
  }

  Future<bool> _showNameDialog(int type) async {
    final ctrl = TextEditingController(text: _pendingName ?? '');
    final labelType = type == 3 ? '部屋' : type == 4 ? '階段' : '';
    bool confirmed = false;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$labelType名を入力'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: type == 3 ? '例: 会議室101' : '例: 南階段'),
          onSubmitted: (v) {
            if (v.isNotEmpty) {
              confirmed = true;
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                if (_isNameDuplicate(ctrl.text, type)) {
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: 「${ctrl.text}」は既に存在します')));
                   return;
                }
                confirmed = true;
                Navigator.pop(context);
              }
            },
            child: const Text('決定'),
          ),
        ],
      ),
    );

    if (confirmed && ctrl.text.isNotEmpty) {
      _pendingName = ctrl.text;
    }
    return confirmed && ctrl.text.isNotEmpty;
  }

  Future<bool> _showConnectorDialog() async {
    final nameCtrl  = TextEditingController(text: _pendingName ?? '');
    final mapCtrl   = TextEditingController(text: _pendingConnectsToMap  ?? '');
    final nodeCtrl  = TextEditingController(text: _pendingConnectsToNode ?? '');
    bool confirmed = false;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('⇄ 接続点の設定'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, autofocus: true,
            decoration: const InputDecoration(labelText: 'このノードの名前'),
            onSubmitted: (_) {}),
          const SizedBox(height: 8),
          TextField(controller: mapCtrl,
            decoration: const InputDecoration(labelText: '接続先マップのラベル', hintText: '例: 2F'),
            onSubmitted: (_) {}),
          const SizedBox(height: 8),
          TextField(controller: nodeCtrl,
            decoration: const InputDecoration(labelText: '接続先ノードID', hintText: '例: connector_from_1f'),
            onSubmitted: (_) {
              if (nameCtrl.text.isNotEmpty) {
                if (_isNameDuplicate(nameCtrl.text, 5)) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('エラー: すでに同じ名前が存在します')));
                   return;
                }
                confirmed = true;
                Navigator.pop(context);
              }
            }),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          ElevatedButton(onPressed: () {
            if (nameCtrl.text.isNotEmpty) {
                if (_isNameDuplicate(nameCtrl.text, 5)) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('エラー: すでに同じ名前が存在します')));
                   return;
                }
              confirmed = true;
              Navigator.pop(context);
            }
          }, child: const Text('決定')),
        ],
      ),
    );

    if (confirmed && nameCtrl.text.isNotEmpty) {
      _pendingName          = nameCtrl.text;
      _pendingConnectsToMap  = mapCtrl.text.isNotEmpty  ? mapCtrl.text  : null;
      _pendingConnectsToNode = nodeCtrl.text.isNotEmpty ? nodeCtrl.text : null;
    }
    return confirmed && nameCtrl.text.isNotEmpty;
  }

  Future<void> _onPointerDown(int y, int x, int buttons) async {
    isRightClickEraser = buttons == 2;
    int activeBrush = isRightClickEraser ? 0 : brushType;
    if (activeBrush == 6) return;

    _saveHistory();
    currentStrokeCells.clear();

    if (activeBrush == 3 || activeBrush == 4 || activeBrush == 5) {
       final clickedCell = grid[y][x];
       if (clickedCell.type == activeBrush && clickedCell.name != null) {
          _pendingName = clickedCell.name;
          _pendingConnectsToMap = clickedCell.connectsToMap;
          _pendingConnectsToNode = clickedCell.connectsToNode;
       }
    }

    if (isRightClickEraser || drawMode == 'stroke') {
      currentStrokeCells.add(grid[y][x]);
      setState(() => grid[y][x].type = activeBrush);
    } else {
      setState(() { dragStartX = x; dragStartY = y; dragCurrentX = x; dragCurrentY = y; });
    }
  }

  void _onPointerMove(int y, int x, int buttons) {
    int activeBrush = isRightClickEraser ? 0 : brushType;
    if (activeBrush == 6) return;

    if (isRightClickEraser || drawMode == 'stroke') {
      currentStrokeCells.add(grid[y][x]);
      setState(() => grid[y][x].type = activeBrush);
    } else {
      if (dragStartX != null) {
        setState(() { dragCurrentX = x; dragCurrentY = y; });
      }
    }
  }

  Future<void> _onPointerUp() async {
    int activeBrush = isRightClickEraser ? 0 : brushType;
    if (activeBrush == 6) return;

    if (!isRightClickEraser && drawMode == 'rect') {
      if (dragStartX != null && dragStartY != null && dragCurrentX != null && dragCurrentY != null) {
        int minX = dragStartX! < dragCurrentX! ? dragStartX! : dragCurrentX!;
        int maxX = dragStartX! > dragCurrentX! ? dragStartX! : dragCurrentX!;
        int minY = dragStartY! < dragCurrentY! ? dragStartY! : dragCurrentY!;
        int maxY = dragStartY! > dragCurrentY! ? dragStartY! : dragCurrentY!;
        for (int yy = minY; yy <= maxY; yy++) {
          for (int xx = minX; xx <= maxX; xx++) {
            currentStrokeCells.add(grid[yy][xx]);
            grid[yy][xx].type = activeBrush;
          }
        }
        setState(() { dragStartX = null; dragStartY = null; dragCurrentX = null; dragCurrentY = null; });
      }
    }

    if (currentStrokeCells.isEmpty) return;

    for (var c in currentStrokeCells) {
      c.name = null;
      c.connectsToMap = null;
      c.connectsToNode = null;
    }

    if (activeBrush == 3 || activeBrush == 4) {
      bool ok = true;
      if (_pendingName == null) {
        ok = await _showNameDialog(activeBrush);
      }
      if (ok && _pendingName != null) {
        for (var c in currentStrokeCells) {
          c.name = _pendingName;
        }
      } else {
        _undo();
      }
      _pendingName = null;
    } else if (activeBrush == 5) {
      bool ok = true;
      if (_pendingName == null) {
        ok = await _showConnectorDialog();
      }
      if (ok && _pendingName != null) {
        for (var c in currentStrokeCells) {
          c.name = _pendingName;
          c.connectsToMap = _pendingConnectsToMap;
          c.connectsToNode = _pendingConnectsToNode;
        }
      } else {
        _undo();
      }
      _pendingName = null;
      _pendingConnectsToMap = null;
      _pendingConnectsToNode = null;
    }

    setState(() {});
    currentStrokeCells.clear();
    isRightClickEraser = false;
  }

  void _onTypeSelected(int type) {
    setState(() {
      brushType = type;
      _pendingName = null;
      _pendingConnectsToMap = null;
      _pendingConnectsToNode = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'マップエディタ ${AppConfig.cols}×${AppConfig.rows}マス',
          style: const TextStyle(fontSize: 14),
        ),
        backgroundColor: Colors.blueGrey,
        actions: [
          ElevatedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.map),
            label: const Text('見取り図'),
          ),
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
            onPressed: _importJson,
            icon: const Icon(Icons.upload_file),
            label: const Text('JSON読込'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => JsonExporter.export(context, grid, bgImageBytes),
            icon: const Icon(Icons.download),
            label: const Text('JSON出力'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          ToolPalette(
            brushType: brushType,
            drawMode: drawMode,
            onTypeSelected: _onTypeSelected,
            onModeSelected: (m) => setState(() => drawMode = m),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: CanvasArea(
                  grid: grid,
                  brushType: brushType,
                  bgImageBytes: bgImageBytes,
                  transformController: _transformController,
                  dragStartX: dragStartX, dragStartY: dragStartY,
                  dragCurrentX: dragCurrentX, dragCurrentY: dragCurrentY,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
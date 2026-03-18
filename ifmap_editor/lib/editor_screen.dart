import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import 'map_editor_controller.dart';
import 'input_handler.dart';
import 'editor_dialogs.dart';
import 'json_importer.dart';
import 'tool_palette.dart';
import 'canvas_area.dart';
import 'json_exporter.dart';
import 'auto_wall_detector.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _ctrl          = MapEditorController();
  final _transformCtrl = TransformationController();
  final _viewportKey   = GlobalKey();
  final _gridKey       = GlobalKey();
  late final InputHandler _handler;

  @override
  void initState() {
    super.initState();
    _handler = InputHandler(
      ctrl: _ctrl,
      transformCtrl: _transformCtrl,
      canvasViewportKey: _viewportKey,
      gridKey: _gridKey,
    );
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _transformCtrl.dispose();
    super.dispose();
  }

  // ── ダイアログコールバック ─────────────────────────────
  Future<String?> _nameDialog(int type, String? oldName) =>
      EditorDialogs.showName(context, _ctrl, type, initialName: oldName);

  Future<ConnectorDialogResult?> _connectorDialog(String? oldName) {
    if (oldName != null) {
      for (int y = 0; y < AppConfig.rows; y++) {
        for (int x = 0; x < AppConfig.cols; x++) {
          final c = _ctrl.grid[y][x];
          if (c.type == 5 && c.name == oldName) {
            return EditorDialogs.showConnector(context, _ctrl,
              initialName: oldName,
              initialMap:  c.connectsToMap,
              initialNode: c.connectsToNode,
            );
          }
        }
      }
    }
    return EditorDialogs.showConnector(context, _ctrl);
  }

  // ── 画像・ズーム ───────────────────────────────────────
  Future<void> _pickImage() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f != null) _ctrl.setBgImage(await f.readAsBytes());
  }

  void _zoomIn()  => _transformCtrl.value = _transformCtrl.value.clone()..scale(1.2);
  void _zoomOut() => _transformCtrl.value = _transformCtrl.value.clone()..scale(1 / 1.2);

  // ── 自動生成 ───────────────────────────────────────────
  Future<void> _runAutoGenerator() async {
    if (_ctrl.bgImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('見取り図画像を先に読み込んでください')));
      return;
    }
    _ctrl.setIsAnalyzing(true);
    await Future.delayed(const Duration(milliseconds: 100));
    _ctrl.saveHistory();
    try {
      final detector = AutoWallDetector.init(
        _ctrl.bgImageBytes!, AppConfig.cols, AppConfig.rows);
      if (detector != null) {
        _ctrl.applyWalls(detector.detectWalls(1.0 - _ctrl.wallSensitivity));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('壁の自動生成が完了しました！')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e')));
    } finally {
      _ctrl.setIsAnalyzing(false);
    }
  }

  // ── ポインタコールバック ───────────────────────────────
  Future<void> _onPointerDown(
      int y, int x, int buttons, Offset local, Offset global, double cs) async {
    if (_ctrl.brushType == 9) {
      await _handler.handleRenameClick(y, x,
        onNeedNameDialog:      _nameDialog,
        onNeedConnectorDialog: _connectorDialog,
      );
      return;
    }
    _handler.onPointerDown(y, x, buttons, local, global, cs);
  }

  void _onPointerMove(
      int y, int x, int buttons, Offset local, Offset global, double cs) =>
      _handler.onPointerMove(y, x, buttons, local, global, cs);

  Future<void> _onPointerUp() => _handler.onPointerUp(
    onNeedNameDialog:      _nameDialog,
    onNeedConnectorDialog: _connectorDialog,
  );

  // ── build ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('マップエディタ ${AppConfig.cols}×${AppConfig.rows}マス',
          style: const TextStyle(fontSize: 14)),
        backgroundColor: Colors.blueGrey,
        actions: [
          ElevatedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.map), label: const Text('見取り図')),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.undo), color: Colors.white,
            onPressed: _ctrl.canUndo ? _ctrl.undo : null, tooltip: '元に戻す'),
          IconButton(icon: const Icon(Icons.redo), color: Colors.white,
            onPressed: _ctrl.canRedo ? _ctrl.redo : null, tooltip: 'やり直し'),
          IconButton(icon: const Icon(Icons.zoom_out), color: Colors.white,
            onPressed: _zoomOut, tooltip: '縮小'),
          IconButton(icon: const Icon(Icons.zoom_in), color: Colors.white,
            onPressed: _zoomIn, tooltip: '拡大'),
          const Center(
            child: Text('※手のひらツールで移動\n※スクロールで拡大縮小',
              style: TextStyle(fontSize: 12), textAlign: TextAlign.center)),
          ElevatedButton.icon(
            onPressed: () => JsonImporter.importJson(context, _ctrl),
            icon: const Icon(Icons.upload_file), label: const Text('JSON読込')),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => JsonExporter.export(
              context, _ctrl.grid, _ctrl.bgImageBytes, _ctrl.currentFileName),
            icon: const Icon(Icons.save),
            label: Text('上書き保存\n(${_ctrl.currentFileName})',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () async {
              final name = await EditorDialogs.showSaveAs(
                context, _ctrl.currentFileName);
              if (name != null && mounted) {
                _ctrl.setFileName(name);
                JsonExporter.export(context, _ctrl.grid, _ctrl.bgImageBytes, name);
              }
            },
            icon: const Icon(Icons.save_as),
            label: const Text('別名保存', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          Container(
            width: 140,
            color: Colors.grey.shade200,
            child: Column(children: [
              Expanded(
                child: ToolPalette(
                  brushType:      _ctrl.brushType,
                  drawMode:       _ctrl.drawMode,
                  onTypeSelected: _ctrl.setBrushType,
                  onModeSelected: _ctrl.setDrawMode,
                ),
              ),
              const Divider(),
              const Text('自動生成ツール',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(children: [
                  Text('壁検出感度: ${_ctrl.wallSensitivity.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 10)),
                  Slider(
                    value: _ctrl.wallSensitivity,
                    min: 0.05, max: 0.95, divisions: 18,
                    label: _ctrl.wallSensitivity.toStringAsFixed(2),
                    onChanged: _ctrl.setWallSensitivity,
                  ),
                  ElevatedButton.icon(
                    icon: _ctrl.isAnalyzing
                      ? const SizedBox(width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 14),
                    label: const Text('実行', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                    onPressed: _ctrl.isAnalyzing ? null : _runAutoGenerator,
                  ),
                  const SizedBox(height: 16),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CanvasArea(
                  key:              _viewportKey,
                  gridKey:          _gridKey,
                  grid:             _ctrl.grid,
                  roomGroups:       _ctrl.roomGroups,
                  brushType:        _ctrl.brushType,
                  bgImageBytes:     _ctrl.bgImageBytes,
                  transformController: _transformCtrl,
                  dragStartX:   _handler.dragStartX,
                  dragStartY:   _handler.dragStartY,
                  dragCurrentX: _handler.dragCurrentX,
                  dragCurrentY: _handler.dragCurrentY,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp:   _onPointerUp,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
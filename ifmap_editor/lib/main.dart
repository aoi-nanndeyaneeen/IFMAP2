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

  // ─── ブラシ状態 ──────────────────────────────────────────────────
  // brushType: 0=消しゴム, 1=通路, 3=部屋, 4=階段, 5=接続点
  int brushType = 1;
  String drawMode = 'stroke'; // 'stroke' | 'rect'

  Uint8List? bgImageBytes;

  // ─── ドラッグ（矩形モード）状態 ─────────────────────────────────
  int? dragStartX, dragStartY, dragCurrentX, dragCurrentY;

  // ─── 名前付きブラシ用: 現在選択中の名前 ─────────────────────────
  // null = まだ未設定 / 設定後はこの名前で塗り続ける
  String? _pendingName;
  String? _pendingConnectsToMap;
  String? _pendingConnectsToNode;

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
    if (f != null) setState(() async => bgImageBytes = await f.readAsBytes());
  }

  // ─── 部屋/階段の名前設定ダイアログ ──────────────────────────────
  Future<bool> _showNameDialog(int type) async {
    // brushType == 3(部屋) or 4(階段)
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
      setState(() => _pendingName = ctrl.text);
    }
    return confirmed && ctrl.text.isNotEmpty;
  }

  // ─── 接続点のダイアログ ──────────────────────────────────────────
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
                confirmed = true;
                Navigator.pop(context);
              }
            }),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          ElevatedButton(onPressed: () {
            if (nameCtrl.text.isNotEmpty) {
              confirmed = true;
              Navigator.pop(context);
            }
          }, child: const Text('決定')),
        ],
      ),
    );

    if (confirmed && nameCtrl.text.isNotEmpty) {
      setState(() {
        _pendingName          = nameCtrl.text;
        _pendingConnectsToMap  = mapCtrl.text.isNotEmpty  ? mapCtrl.text  : null;
        _pendingConnectsToNode = nodeCtrl.text.isNotEmpty ? nodeCtrl.text : null;
      });
    }
    return confirmed && nameCtrl.text.isNotEmpty;
  }

  // ─── 1セルを塗る ────────────────────────────────────────────────
  // 名前付きブラシ(3/4/5)のとき、_pendingNameが必要
  void _paint(int y, int x, int type) {
    if (x < 0 || x >= AppConfig.cols || y < 0 || y >= AppConfig.rows) return;
    final cell = grid[y][x];
    if (type == 0) {
      // 消しゴム
      cell.type = 0;
      cell.name = null;
      cell.connectsToMap = null;
      cell.connectsToNode = null;
    } else if (type == 1) {
      // 通路（既存の名前付きは上書きしない）
      if (cell.type == 3 || cell.type == 4 || cell.type == 5) return;
      cell.type = 1;
    } else if (type == 3 || type == 4) {
      // 部屋 or 階段: _pendingNameが必須
      final name = _pendingName;
      if (name == null) return;
      cell.type = type;
      cell.name = name;
    } else if (type == 5) {
      // 接続点
      final name = _pendingName;
      if (name == null) return;
      cell.type = 5;
      cell.name = name;
      cell.connectsToMap  = _pendingConnectsToMap;
      cell.connectsToNode = _pendingConnectsToNode;
    }
  }

  // ─── 矩形範囲を塗る ─────────────────────────────────────────────
  void _paintRect(int y0, int x0, int y1, int x1, int type) {
    final minX = x0 < x1 ? x0 : x1;
    final maxX = x0 > x1 ? x0 : x1;
    final minY = y0 < y1 ? y0 : y1;
    final maxY = y0 > y1 ? y0 : y1;
    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        _paint(y, x, type);
      }
    }
  }

  // ─── ポインターダウン ────────────────────────────────────────────
  Future<void> _onPointerDown(int y, int x) async {
    if (drawMode == 'rect') {
      // 矩形: 名前付きブラシは名前を取得してからドラッグ開始
      if (brushType == 3 || brushType == 4) {
        // 既にその色のセルに触れたなら名前を引継ぎ
        final tapped = grid[y][x];
        if (tapped.type == brushType && tapped.name != null) {
          setState(() { _pendingName = tapped.name; });
        } else if (_pendingName == null) {
          await _showNameDialog(brushType);
        }
      } else if (brushType == 5) {
        final tapped = grid[y][x];
        if (tapped.type == 5 && tapped.name != null) {
          setState(() {
            _pendingName          = tapped.name;
            _pendingConnectsToMap  = tapped.connectsToMap;
            _pendingConnectsToNode = tapped.connectsToNode;
          });
        } else if (_pendingName == null) {
          await _showConnectorDialog();
          if (_pendingName == null) return;
        }
      }
      setState(() { dragStartX = x; dragStartY = y; dragCurrentX = x; dragCurrentY = y; });
    } else {
      // なぞり: 名前付きブラシなら先に名前確認
      if (brushType == 3 || brushType == 4) {
        final tapped = grid[y][x];
        if (tapped.type == brushType && tapped.name != null) {
          setState(() { _pendingName = tapped.name; });
        } else if (_pendingName == null) {
          final ok = await _showNameDialog(brushType);
          if (!ok) return;
        }
      } else if (brushType == 5) {
        final tapped = grid[y][x];
        if (tapped.type == 5 && tapped.name != null) {
          setState(() {
            _pendingName          = tapped.name;
            _pendingConnectsToMap  = tapped.connectsToMap;
            _pendingConnectsToNode = tapped.connectsToNode;
          });
        } else if (_pendingName == null) {
          final ok = await _showConnectorDialog();
          if (!ok) return;
        }
      }
      setState(() => _paint(y, x, brushType));
    }
  }

  void _onPointerMove(int y, int x) {
    if (drawMode == 'rect') {
      if (dragStartX != null) {
        setState(() { dragCurrentX = x; dragCurrentY = y; });
      }
    } else {
      // なぞりで塗り
      setState(() => _paint(y, x, brushType));
    }
  }

  void _onPointerUp() {
    if (drawMode == 'rect' && dragStartX != null) {
      setState(() {
        _paintRect(dragStartY!, dragStartX!, dragCurrentY!, dragCurrentX!, brushType);
        dragStartX = dragStartY = dragCurrentX = dragCurrentY = null;
      });
    }
  }

  // ─── ブラシタイプ切替: 名前をリセット ───────────────────────────
  void _onTypeSelected(int type) {
    setState(() {
      brushType = type;
      // ブラシ変更時は保留中の名前をクリア（別種を誤引継ぎしないため）
      _pendingName          = null;
      _pendingConnectsToMap  = null;
      _pendingConnectsToNode = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 現在の保留中名前をアプリバーに表示
    final pendingLabel = brushType == 1 || brushType == 0
        ? ''
        : _pendingName != null
            ? ' 「$_pendingName」'
            : ' ← 名前未設定';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${AppConfig.cols}×${AppConfig.rows}マス / '
          '${(AppConfig.cols * AppConfig.metersPerCell).toStringAsFixed(0)}m×'
          '${(AppConfig.rows * AppConfig.metersPerCell).toStringAsFixed(0)}m$pendingLabel',
          style: const TextStyle(fontSize: 14),
        ),
        backgroundColor: Colors.blueGrey,
        actions: [
          // 選択中の名前をリセット
          if (_pendingName != null)
            TextButton.icon(
              onPressed: () => setState(() {
                _pendingName = null;
                _pendingConnectsToMap = null;
                _pendingConnectsToNode = null;
              }),
              icon: const Icon(Icons.cancel, color: Colors.white70),
              label: const Text('名前解除', style: TextStyle(color: Colors.white70)),
            ),
          ElevatedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.map),
            label: const Text('見取り図'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => JsonExporter.export(context, grid),
            icon: const Icon(Icons.download),
            label: const Text('JSON出力'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(children: [
        ToolPalette(
          brushType: brushType,
          drawMode: drawMode,
          onTypeSelected: _onTypeSelected,
          onModeSelected: (m) => setState(() => drawMode = m),
        ),
        Expanded(child: Center(child: Padding(
          padding: const EdgeInsets.all(16),
          child: AspectRatio(
            aspectRatio: AppConfig.cols / AppConfig.rows,
            child: CanvasArea(
              grid: grid,
              brushType: brushType,
              bgImageBytes: bgImageBytes,
              dragStartX: dragStartX, dragStartY: dragStartY,
              dragCurrentX: dragCurrentX, dragCurrentY: dragCurrentY,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
            ),
          ),
        ))),
      ]),
    );
  }
}
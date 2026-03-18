import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'config.dart';
import 'map_cell.dart';
import 'tool_palette.dart';
import 'json_exporter.dart';
import 'canvas_area.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BrowserContextMenu.disableContextMenu();
  runApp(const MapEditorApp());
}

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
  final GlobalKey _canvasViewportKey = GlobalKey();
  final GlobalKey _gridKey = GlobalKey();

  Timer? _edgePanTimer;
  Offset? _currentGlobalPointer;
  int _currentButtons = 0;
  
  String _currentFileName = 'map_data.json';

  List<List<List<MapCell>>> undoHistory = [];
  List<List<List<MapCell>>> redoHistory = [];

  Set<MapCell> currentStrokeCells = {};

  String? _pendingName;
  String? _pendingConnectsToMap;
  String? _pendingConnectsToNode;

  List<List<MapCell>> _cloneGrid(List<List<MapCell>> source) {
    return source.map((r) => r.map((c) => MapCell(
      x: c.x, y: c.y, type: c.type, name: c.name,
      connectsToMap: c.connectsToMap, connectsToNode: c.connectsToNode,
      wallTop: c.wallTop, wallBottom: c.wallBottom, 
      wallLeft: c.wallLeft, wallRight: c.wallRight,
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
            // "map_data (1).json" のようなブラウザ付与の連番を削除して本来の名前に戻す
            String importedName = result.files.single.name;
            importedName = importedName.replaceAll(RegExp(r'\s*\(\d+\)'), '');
            _currentFileName = importedName;
            bgImageBytes = bgBase64 != null ? base64Decode(bgBase64) : null;
            
            // 全体を初期化する
            for (int y = 0; y < AppConfig.rows; y++) {
              for (int x = 0; x < AppConfig.cols; x++) {
                grid[y][x] = MapCell(x: x, y: y);
              }
            }

            // データが存在するセルだけ上書きする
            for (var cData in cellsData) {
              int cx = cData['x'];
              int cy = cData['y'];
              if (cx >= 0 && cx < AppConfig.cols && cy >= 0 && cy < AppConfig.rows) {
                grid[cy][cx] = MapCell(
                  x: cx, y: cy,
                  type: cData['type'] ?? 0,
                  name: cData['name'],
                  connectsToMap: cData['connectsToMap'],
                  connectsToNode: cData['connectsToNode'],
                  wallTop: cData['wallTop'] == true,
                  wallBottom: cData['wallBottom'] == true,
                  wallLeft: cData['wallLeft'] == true,
                  wallRight: cData['wallRight'] == true,
                  doorTop: cData['doorTop'] == true,
                  doorBottom: cData['doorBottom'] == true,
                  doorLeft: cData['doorLeft'] == true,
                  doorRight: cData['doorRight'] == true,
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

  Future<bool> _showNameDialog(int type, {String? oldName}) async {
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
              if (v != oldName && _isNameDuplicate(v, type)) {
                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: 「$v」は既に存在します')));
                 return;
              }
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
                if (ctrl.text != oldName && _isNameDuplicate(ctrl.text, type)) {
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

  Future<bool> _showConnectorDialog({String? oldName}) async {
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
                if (nameCtrl.text != oldName && _isNameDuplicate(nameCtrl.text, 5)) {
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
                if (nameCtrl.text != oldName && _isNameDuplicate(nameCtrl.text, 5)) {
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

  // 指を離すまで同じ壁を何度も上書きしないためのセット
  final Set<String> _currentStrokeBoundaries = {};
  int? _lastVertexX;
  int? _lastVertexY;

  void _toggleEdge(int vx1, int vy1, int vx2, int vy2, bool erase, bool isDoor) {
      if (vx1 == vx2 && vy1 == vy2) return;
      int minX = vx1 < vx2 ? vx1 : vx2;
      int minY = vy1 < vy2 ? vy1 : vy2;
      
      String boundId = '${minX}_${minY}_${vx1==vx2 ? "v" : "h"}';
      if (_currentStrokeBoundaries.contains(boundId)) return;
      _currentStrokeBoundaries.add(boundId);

      setState(() {
         if (vx1 == vx2) {
             int x = vx1;
             int y = minY;
             if (y >= 0 && y < AppConfig.rows) {
                 if (x == 0) {
                     if (isDoor) { grid[y][0].doorLeft = !erase; grid[y][0].wallLeft = false; }
                     else { grid[y][0].wallLeft = !erase; grid[y][0].doorLeft = false; }
                 } else if (x == AppConfig.cols) {
                     if (isDoor) { grid[y][x-1].doorRight = !erase; grid[y][x-1].wallRight = false; }
                     else { grid[y][x-1].wallRight = !erase; grid[y][x-1].doorRight = false; }
                 } else {
                     if (isDoor) {
                         grid[y][x].doorLeft = !erase; grid[y][x].wallLeft = false;
                         grid[y][x-1].doorRight = !erase; grid[y][x-1].wallRight = false;
                     } else {
                         grid[y][x].wallLeft = !erase; grid[y][x].doorLeft = false;
                         grid[y][x-1].wallRight = !erase; grid[y][x-1].doorRight = false;
                     }
                 }
             }
         } else {
             int x = minX;
             int y = vy1;
             if (x >= 0 && x < AppConfig.cols) {
                 if (y == 0) {
                     if (isDoor) { grid[0][x].doorTop = !erase; grid[0][x].wallTop = false; }
                     else { grid[0][x].wallTop = !erase; grid[0][x].doorTop = false; }
                 } else if (y == AppConfig.rows) {
                     if (isDoor) { grid[y-1][x].doorBottom = !erase; grid[y-1][x].wallBottom = false; }
                     else { grid[y-1][x].wallBottom = !erase; grid[y-1][x].doorBottom = false; }
                 } else {
                     if (isDoor) {
                         grid[y][x].doorTop = !erase; grid[y][x].wallTop = false;
                         grid[y-1][x].doorBottom = !erase; grid[y-1][x].wallBottom = false;
                     } else {
                         grid[y][x].wallTop = !erase; grid[y][x].doorTop = false;
                         grid[y-1][x].wallBottom = !erase; grid[y-1][x].doorBottom = false;
                     }
                 }
             }
         }
      });
  }

  void _applyPointerMove(int y, int x, int buttons, Offset localPos, double cellSize) {
    int activeBrush = brushType;
    if (isRightClickEraser && activeBrush != 7 && activeBrush != 8) activeBrush = 0;
    if (activeBrush == 6) return;

    if (activeBrush == 7 || activeBrush == 8) {
       int curVx = (localPos.dx / cellSize).round().clamp(0, AppConfig.cols);
       int curVy = (localPos.dy / cellSize).round().clamp(0, AppConfig.rows);
       
       if (_lastVertexX != null && _lastVertexY != null) {
          int vx = _lastVertexX!;
          int vy = _lastVertexY!;
          
          while (vx != curVx || vy != curVy) {
             if ((curVx - vx).abs() > (curVy - vy).abs()) {
                 int nextVx = vx + (curVx > vx ? 1 : -1);
                 _toggleEdge(vx, vy, nextVx, vy, isRightClickEraser, activeBrush == 8);
                 vx = nextVx;
             } else {
                 int nextVy = vy + (curVy > vy ? 1 : -1);
                 _toggleEdge(vx, vy, vx, nextVy, isRightClickEraser, activeBrush == 8);
                 vy = nextVy;
             }
          }
       }
       _lastVertexX = curVx;
       _lastVertexY = curVy;
       return;
    }

    if (isRightClickEraser || drawMode == 'stroke') {
      currentStrokeCells.add(grid[y][x]);
      setState(() {
        grid[y][x].type = activeBrush;
        if (activeBrush == 0) {
          grid[y][x].name = null;
          grid[y][x].connectsToMap = null;
          grid[y][x].connectsToNode = null;
          grid[y][x].wallTop = false;
          grid[y][x].wallBottom = false;
          grid[y][x].wallLeft = false;
          grid[y][x].wallRight = false;
          grid[y][x].doorTop = false;
          grid[y][x].doorBottom = false;
          grid[y][x].doorLeft = false;
          grid[y][x].doorRight = false;
          if (y > 0) { grid[y-1][x].wallBottom = false; grid[y-1][x].doorBottom = false; }
          if (y < AppConfig.rows - 1) { grid[y+1][x].wallTop = false; grid[y+1][x].doorTop = false; }
          if (x > 0) { grid[y][x-1].wallRight = false; grid[y][x-1].doorRight = false; }
          if (x < AppConfig.cols - 1) { grid[y][x+1].wallLeft = false; grid[y][x+1].doorLeft = false; }
        }
      });
    } else {
      if (dragStartX != null) {
        setState(() { dragCurrentX = x; dragCurrentY = y; });
      }
    }
  }

  void _checkEdgePan() {
    if (_currentGlobalPointer == null) return;
    final RenderBox? canvasBox = _canvasViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (canvasBox == null) return;

    final localInViewport = canvasBox.globalToLocal(_currentGlobalPointer!);
    final size = canvasBox.size;
    const double threshold = 50.0;
    const double speed = 15.0;

    double dx = 0; double dy = 0;
    if (localInViewport.dx < threshold) dx = speed;
    else if (localInViewport.dx > size.width - threshold) dx = -speed;
    if (localInViewport.dy < threshold) dy = speed;
    else if (localInViewport.dy > size.height - threshold) dy = -speed;

    if (dx != 0 || dy != 0) {
      final matrix = _transformController.value.clone();
      matrix[12] += dx;
      matrix[13] += dy;
      _transformController.value = matrix;

      final RenderBox? gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
      if (gridBox != null) {
        final unscaledLocal = gridBox.globalToLocal(_currentGlobalPointer!);
        final cellSize = gridBox.size.width / AppConfig.cols;
        int x = (unscaledLocal.dx / cellSize).floor();
        int y = (unscaledLocal.dy / cellSize).floor();
        if (x >= 0 && x < AppConfig.cols && y >= 0 && y < AppConfig.rows) {
          _applyPointerMove(y, x, _currentButtons, unscaledLocal, cellSize);
        }
      }
    }
  }

  Future<void> _onPointerDown(int y, int x, int buttons, Offset localPos, Offset globalPos, double cellSize) async {
    _currentGlobalPointer = globalPos;
    _currentButtons = buttons;
    isRightClickEraser = buttons == 2;
    
    _edgePanTimer?.cancel();
    _edgePanTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _checkEdgePan());

    int activeBrush = brushType;
    if (isRightClickEraser && activeBrush != 7 && activeBrush != 8) activeBrush = 0;
    if (activeBrush == 6) return;

    _saveHistory();
    currentStrokeCells.clear();
    _currentStrokeBoundaries.clear();

    if (activeBrush == 7 || activeBrush == 8) {
      _lastVertexX = (localPos.dx / cellSize).round().clamp(0, AppConfig.cols);
      _lastVertexY = (localPos.dy / cellSize).round().clamp(0, AppConfig.rows);
      return;
    }

    if (activeBrush == 9) {
       final clickedCell = grid[y][x];
       if (clickedCell.name != null && (clickedCell.type == 3 || clickedCell.type == 4 || clickedCell.type == 5)) {
          String oldName = clickedCell.name!;
          int targetType = clickedCell.type;
          
          _pendingName = oldName;
          _pendingConnectsToMap = clickedCell.connectsToMap;
          _pendingConnectsToNode = clickedCell.connectsToNode;
          
          bool ok = false;
          if (targetType == 5) ok = await _showConnectorDialog(oldName: oldName);
          else ok = await _showNameDialog(targetType, oldName: oldName);
          
          if (ok && _pendingName != null && _pendingName!.isNotEmpty) {
             _saveHistory(); // save history before applying batch rename
             setState(() {
                for (int yy = 0; yy < AppConfig.rows; yy++) {
                   for (int xx = 0; xx < AppConfig.cols; xx++) {
                      if (grid[yy][xx].type == targetType && grid[yy][xx].name == oldName) {
                         grid[yy][xx].name = _pendingName;
                         if (targetType == 5) {
                            grid[yy][xx].connectsToMap = _pendingConnectsToMap;
                            grid[yy][xx].connectsToNode = _pendingConnectsToNode;
                         }
                      }
                   }
                }
             });
          }
          _pendingName = null;
          _pendingConnectsToMap = null;
          _pendingConnectsToNode = null;
       }
       return;
    }

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
      setState(() {
        grid[y][x].type = activeBrush;
        if (activeBrush == 0) {
          grid[y][x].name = null;
          grid[y][x].connectsToMap = null;
          grid[y][x].connectsToNode = null;
          grid[y][x].wallTop = false;
          grid[y][x].wallBottom = false;
          grid[y][x].wallLeft = false;
          grid[y][x].wallRight = false;
          grid[y][x].doorTop = false;
          grid[y][x].doorBottom = false;
          grid[y][x].doorLeft = false;
          grid[y][x].doorRight = false;
          if (y > 0) { grid[y-1][x].wallBottom = false; grid[y-1][x].doorBottom = false; }
          if (y < AppConfig.rows - 1) { grid[y+1][x].wallTop = false; grid[y+1][x].doorTop = false; }
          if (x > 0) { grid[y][x-1].wallRight = false; grid[y][x-1].doorRight = false; }
          if (x < AppConfig.cols - 1) { grid[y][x+1].wallLeft = false; grid[y][x+1].doorLeft = false; }
        }
      });
    } else {
      setState(() { dragStartX = x; dragStartY = y; dragCurrentX = x; dragCurrentY = y; });
    }
  }

  void _onPointerMove(int y, int x, int buttons, Offset localPos, Offset globalPos, double cellSize) {
    _currentGlobalPointer = globalPos;
    _currentButtons = buttons;
    _applyPointerMove(y, x, buttons, localPos, cellSize);
  }

  Future<void> _onPointerUp() async {
    _edgePanTimer?.cancel();
    _edgePanTimer = null;
    _currentGlobalPointer = null;

    int activeBrush = brushType;
    if (isRightClickEraser && activeBrush != 7 && activeBrush != 8) activeBrush = 0;
    if (activeBrush == 6 || activeBrush == 7 || activeBrush == 8) return;

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
            if (activeBrush == 0) {
              grid[yy][xx].name = null;
              grid[yy][xx].connectsToMap = null;
              grid[yy][xx].connectsToNode = null;
              grid[yy][xx].wallTop = false;
              grid[yy][xx].wallBottom = false;
              grid[yy][xx].wallLeft = false;
              grid[yy][xx].wallRight = false;
              grid[yy][xx].doorTop = false;
              grid[yy][xx].doorBottom = false;
              grid[yy][xx].doorLeft = false;
              grid[yy][xx].doorRight = false;
              if (yy > 0) { grid[yy-1][xx].wallBottom = false; grid[yy-1][xx].doorBottom = false; }
              if (yy < AppConfig.rows - 1) { grid[yy+1][xx].wallTop = false; grid[yy+1][xx].doorTop = false; }
              if (xx > 0) { grid[yy][xx-1].wallRight = false; grid[yy][xx-1].doorRight = false; }
              if (xx < AppConfig.cols - 1) { grid[yy][xx+1].wallLeft = false; grid[yy][xx+1].doorLeft = false; }
            }
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
          ElevatedButton.icon(
            onPressed: _importJson,
            icon: const Icon(Icons.upload_file),
            label: const Text('JSON読込'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => JsonExporter.export(context, grid, bgImageBytes, _currentFileName),
            icon: const Icon(Icons.save),
            label: Text('上書き保存\n($_currentFileName)', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () async {
              final nameCtrl = TextEditingController();
              final floorCtrl = TextEditingController();
              String base = _currentFileName.replaceAll('.json', '');
              if (base.contains('_')) {
                 int idx = base.lastIndexOf('_');
                 nameCtrl.text = base.substring(0, idx);
                 floorCtrl.text = base.substring(idx + 1);
              } else {
                 nameCtrl.text = base;
              }
              
              final newName = await showDialog<String>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('名前を設定して保存'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '建物・キャンパス名 (例: 本館)')),
                        TextField(controller: floorCtrl, decoration: const InputDecoration(labelText: '階数 (必須) (例: 1F, 2階)')),
                    ]
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c), child: const Text('キャンセル')),
                    ElevatedButton(onPressed: () {
                       if (floorCtrl.text.isEmpty) {
                          ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('エラー: 階数を入力してください')));
                          return;
                       }
                       String generatedName = '${nameCtrl.text}_${floorCtrl.text}.json';
                       Navigator.pop(c, generatedName);
                    }, child: const Text('保存')),
                  ],
                ),
              );
              if (newName != null && newName.isNotEmpty) {
                setState(() => _currentFileName = newName);
                if (mounted) JsonExporter.export(context, grid, bgImageBytes, _currentFileName);
              }
            },
            icon: const Icon(Icons.save_as),
            label: const Text('別名保存', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
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
                  key: _canvasViewportKey,
                  gridKey: _gridKey,
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
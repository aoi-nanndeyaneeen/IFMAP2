import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'config.dart';
import 'map_cell.dart';

/// グリッド状態・Undo/Redo・ルームグループを一元管理する ChangeNotifier。
/// UI (State) はこのクラスを listen するだけでよい。
class MapEditorController extends ChangeNotifier {
  // ───────────────────────── 状態 ─────────────────────────
  late List<List<MapCell>> grid;
  List<List<MapCell>> roomGroups = [];

  int brushType = 7;
  String drawMode = 'stroke';
  double wallSensitivity = AppConfig.autoWallSensitivity;
  bool isAnalyzing = false;

  Uint8List? bgImageBytes;
  String currentFileName = 'map_data.json';

  final List<List<List<MapCell>>> _undoHistory = [];
  final List<List<List<MapCell>>> _redoHistory = [];

  bool get canUndo => _undoHistory.isNotEmpty;
  bool get canRedo => _redoHistory.isNotEmpty;

  // ───────────────────────── 初期化 ───────────────────────
  MapEditorController() {
    _initGrid();
  }

  void _initGrid() {
    grid = List.generate(
      AppConfig.rows,
      (y) => List.generate(AppConfig.cols, (x) => MapCell(x: x, y: y)),
    );
  }

  // ───────────────────────── Undo / Redo ──────────────────
  void saveHistory() {
    _undoHistory.add(cloneGrid(grid));
    if (_undoHistory.length > 50) _undoHistory.removeAt(0);
    _redoHistory.clear();
  }

  void undo() {
    if (_undoHistory.isEmpty) return;
    _redoHistory.add(cloneGrid(grid));
    grid = _undoHistory.removeLast();
    calculateRoomGroups();
    notifyListeners();
  }

  void redo() {
    if (_redoHistory.isEmpty) return;
    _undoHistory.add(cloneGrid(grid));
    grid = _redoHistory.removeLast();
    calculateRoomGroups();
    notifyListeners();
  }

  // ───────────────────────── グリッド操作 ─────────────────
  List<List<MapCell>> cloneGrid(List<List<MapCell>> src) {
    return src.map((r) => r.map((c) => MapCell(
      x: c.x, y: c.y, type: c.type, name: c.name,
      connectsToMap: c.connectsToMap, connectsToNode: c.connectsToNode,
      wallTop: c.wallTop, wallBottom: c.wallBottom,
      wallLeft: c.wallLeft, wallRight: c.wallRight,
      doorTop: c.doorTop, doorBottom: c.doorBottom,
      doorLeft: c.doorLeft, doorRight: c.doorRight,
    )).toList()).toList();
  }

  void calculateRoomGroups() {
    final visited = List.generate(AppConfig.rows, (_) => List.filled(AppConfig.cols, false));
    final groups  = <List<MapCell>>[];

    for (int y = 0; y < AppConfig.rows; y++) {
      for (int x = 0; x < AppConfig.cols; x++) {
        final cell = grid[y][x];
        if (cell.name == null || cell.type == 0 || cell.type == 1) { visited[y][x] = true; continue; }
        if (visited[y][x]) continue;

        final group = <MapCell>[];
        final queue = [cell];
        visited[y][x] = true;
        int head = 0;
        while (head < queue.length) {
          final curr = queue[head++];
          group.add(curr);
          for (final d in [[-1,0],[1,0],[0,-1],[0,1]]) {
            final ny = curr.y + d[0], nx = curr.x + d[1];
            if (ny < 0 || ny >= AppConfig.rows || nx < 0 || nx >= AppConfig.cols) continue;
            if (visited[ny][nx]) continue;
            final nb = grid[ny][nx];
            if (nb.type == cell.type && nb.name == cell.name &&
                nb.connectsToMap == cell.connectsToMap && nb.connectsToNode == cell.connectsToNode) {
              visited[ny][nx] = true;
              queue.add(nb);
            }
          }
        }
        groups.add(group);
      }
    }
    roomGroups = groups;
  }

  bool isNameDuplicate(String name, int type) =>
      grid.any((row) => row.any((c) => c.type == type && c.name == name));

  void applyWalls(Set<String> walls) {
    for (final w in walls) {
      final p = w.split('_');
      final wx = int.parse(p[0]), wy = int.parse(p[1]), dir = p[2];
      if (dir == 'v') {
        if (wx >= 0 && wx < AppConfig.cols - 1) {
          grid[wy][wx].wallRight   = true;
          grid[wy][wx + 1].wallLeft = true;
        }
      } else {
        if (wy >= 0 && wy < AppConfig.rows - 1) {
          grid[wy][wx].wallBottom     = true;
          grid[wy + 1][wx].wallTop    = true;
        }
      }
    }
    calculateRoomGroups();
    notifyListeners();
  }

  // ───────────────────────── プロパティ変更 ────────────────
  void setBrushType(int t)        { brushType = t; notifyListeners(); }
  void setDrawMode(String m)      { drawMode  = m; notifyListeners(); }
  void setWallSensitivity(double v) { wallSensitivity = v; notifyListeners(); }
  void setIsAnalyzing(bool v)     { isAnalyzing = v; notifyListeners(); }
  void setBgImage(Uint8List b)    { bgImageBytes = b; notifyListeners(); }
  void setFileName(String n)      { currentFileName = n; notifyListeners(); }

  /// InputHandler など外部から setState 相当の通知を出したい時に使う
  void notify() => notifyListeners();

  // ───────────────────────── JSON 読み込み ─────────────────
  void loadFromEditorData(Map<String, dynamic> data, String rawFileName) {
    final bgBase64 = data['bgImageBase64'] as String?;
    final cellsData = data['cells'] as List;

    currentFileName = rawFileName.replaceAll(RegExp(r'\s*\(\d+\)'), '');
    bgImageBytes    = bgBase64 != null ? base64Decode(bgBase64) : null;

    for (int y = 0; y < AppConfig.rows; y++) {
      for (int x = 0; x < AppConfig.cols; x++) {
        grid[y][x] = MapCell(x: x, y: y);
      }
    }

    for (final c in cellsData) {
      final cx = c['x'] as int, cy = c['y'] as int;
      if (cx < 0 || cx >= AppConfig.cols || cy < 0 || cy >= AppConfig.rows) continue;
      grid[cy][cx] = MapCell(
        x: cx, y: cy,
        type: c['type'] ?? 0, name: c['name'],
        connectsToMap: c['connectsToMap'], connectsToNode: c['connectsToNode'],
        wallTop:    c['wallTop']    == true, wallBottom: c['wallBottom'] == true,
        wallLeft:   c['wallLeft']   == true, wallRight:  c['wallRight']  == true,
        doorTop:    c['doorTop']    == true, doorBottom: c['doorBottom'] == true,
        doorLeft:   c['doorLeft']   == true, doorRight:  c['doorRight']  == true,
      );
    }

    _undoHistory.clear();
    _redoHistory.clear();
    calculateRoomGroups();
    notifyListeners();
  }
}
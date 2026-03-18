import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'config.dart';
import 'map_cell.dart';
import 'map_editor_controller.dart';

/// ポインタ入力・壁描画・エッジパンを担当するクラス。
/// CanvasArea のコールバックを受け取り、controller に変更を書き込む。
class InputHandler {
  final MapEditorController ctrl;
  final TransformationController transformCtrl;
  final GlobalKey canvasViewportKey;
  final GlobalKey gridKey;

  // ドラッグ状態
  int? dragStartX, dragStartY, dragCurrentX, dragCurrentY;

  // 壁ツール用
  int? singleClickVx, singleClickVy;
  int? singleEdgeX1, singleEdgeY1, singleEdgeX2, singleEdgeY2;
  final Map<String, MapCell> _scratchpad = {};

  // ストローク管理
  Set<MapCell> currentStrokeCells = {};
  bool isRightClickEraser = false;

  // 名前の一時保持 (PointerDown → PointerUp 間)
  String? pendingName;
  String? pendingConnectsToMap;
  String? pendingConnectsToNode;

  // エッジパン
  Timer? _edgePanTimer;
  Offset? _globalPointer;
  int _buttons = 0;

  InputHandler({
    required this.ctrl,
    required this.transformCtrl,
    required this.canvasViewportKey,
    required this.gridKey,
  });

  // ───────────────────── エッジパン ────────────────────────
  void _startEdgePan() {
    _edgePanTimer?.cancel();
    _edgePanTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _checkEdgePan());
  }

  void _stopEdgePan() {
    _edgePanTimer?.cancel();
    _edgePanTimer = null;
    _globalPointer = null;
  }

  void _checkEdgePan() {
    if (_globalPointer == null) return;
    final box = canvasViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(_globalPointer!);
    final size = box.size;
    const th = 50.0, sp = 15.0;
    double dx = 0, dy = 0;
    if (local.dx < th) dx = sp;
    else if (local.dx > size.width - th) dx = -sp;
    if (local.dy < th) dy = sp;
    else if (local.dy > size.height - th) dy = -sp;
    if (dx == 0 && dy == 0) return;
    final m = transformCtrl.value.clone();
    m[12] += dx; m[13] += dy;
    transformCtrl.value = m;
    // パン後に現在位置で描画継続
    final gridBox = gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridBox != null) {
      final ul = gridBox.globalToLocal(_globalPointer!);
      final cs = gridBox.size.width / AppConfig.cols;
      final gx = (ul.dx / cs).floor(), gy = (ul.dy / cs).floor();
      if (gx >= 0 && gx < AppConfig.cols && gy >= 0 && gy < AppConfig.rows) {
        _applyMove(gy, gx, _buttons, ul, cs);
      }
    }
  }

  // ───────────────────── スクラッチパッド ──────────────────
  void _pushScratchpad(int y, int x) {
    final k = '${y}_$x';
    if (_scratchpad.containsKey(k)) return;
    final c = ctrl.grid[y][x];
    _scratchpad[k] = MapCell(x: x, y: y,
      wallTop: c.wallTop, wallBottom: c.wallBottom, wallLeft: c.wallLeft, wallRight: c.wallRight,
      doorTop: c.doorTop, doorBottom: c.doorBottom, doorLeft: c.doorLeft, doorRight: c.doorRight);
  }

  void _restoreScratchpad() {
    for (final e in _scratchpad.entries) {
      final p = e.key.split('_');
      final y = int.parse(p[0]), x = int.parse(p[1]);
      final bk = e.value, c = ctrl.grid[y][x];
      c.wallTop = bk.wallTop; c.wallBottom = bk.wallBottom;
      c.wallLeft = bk.wallLeft; c.wallRight = bk.wallRight;
      c.doorTop = bk.doorTop; c.doorBottom = bk.doorBottom;
      c.doorLeft = bk.doorLeft; c.doorRight = bk.doorRight;
    }
    _scratchpad.clear();
  }

  // ───────────────────── 壁 / 扉描画 ───────────────────────
  void _drawTempEdge(int x1, int y1, int x2, int y2, bool erase, bool door) {
    final g = ctrl.grid;
    if (x1 == x2) {
      final y = math.min(y1, y2);
      if (y >= 0 && y < AppConfig.rows && x1 > 0 && x1 < AppConfig.cols) {
        _pushScratchpad(y, x1); _pushScratchpad(y, x1 - 1);
        if (erase) {
          g[y][x1].wallLeft = false;   g[y][x1].doorLeft = false;
          g[y][x1-1].wallRight = false; g[y][x1-1].doorRight = false;
        } else if (door) {
          g[y][x1].doorLeft = true;   g[y][x1].wallLeft = false;
          g[y][x1-1].doorRight = true; g[y][x1-1].wallRight = false;
        } else {
          g[y][x1].wallLeft = true;   g[y][x1].doorLeft = false;
          g[y][x1-1].wallRight = true; g[y][x1-1].doorRight = false;
        }
      }
    } else {
      final x = math.min(x1, x2);
      if (x >= 0 && x < AppConfig.cols && y1 > 0 && y1 < AppConfig.rows) {
        _pushScratchpad(y1, x); _pushScratchpad(y1 - 1, x);
        if (erase) {
          g[y1][x].wallTop = false;      g[y1][x].doorTop = false;
          g[y1-1][x].wallBottom = false;  g[y1-1][x].doorBottom = false;
        } else if (door) {
          g[y1][x].doorTop = true;       g[y1][x].wallTop = false;
          g[y1-1][x].doorBottom = true;   g[y1-1][x].wallBottom = false;
        } else {
          g[y1][x].wallTop = true;       g[y1][x].doorTop = false;
          g[y1-1][x].wallBottom = true;   g[y1-1][x].doorBottom = false;
        }
      }
    }
  }

  // ───────────────────── ポインタ処理 ──────────────────────
  void _applyMove(int y, int x, int buttons, Offset local, double cs) {
    final ab = _activeBrush;
    if (ab == 6) return;

    if (ab == 7 || ab == 8) {
      final vx = (local.dx / cs).round().clamp(0, AppConfig.cols);
      final vy = (local.dy / cs).round().clamp(0, AppConfig.rows);
      if (singleClickVx != null) {
        _restoreScratchpad();
        if (vx == singleClickVx && vy == singleClickVy) {
          if (singleEdgeX1 != null) _drawTempEdge(singleEdgeX1!, singleEdgeY1!, singleEdgeX2!, singleEdgeY2!, isRightClickEraser, ab == 8);
        } else {
          if ((vx - singleClickVx!).abs() > (vy - singleClickVy!).abs()) {
            final mn = math.min(vx, singleClickVx!), mx = math.max(vx, singleClickVx!);
            for (int tx = mn; tx < mx; tx++) _drawTempEdge(tx, singleClickVy!, tx+1, singleClickVy!, isRightClickEraser, ab == 8);
          } else {
            final mn = math.min(vy, singleClickVy!), mx = math.max(vy, singleClickVy!);
            for (int ty = mn; ty < mx; ty++) _drawTempEdge(singleClickVx!, ty, singleClickVx!, ty+1, isRightClickEraser, ab == 8);
          }
        }
      }
      ctrl.notify(); return;
    }

    if (isRightClickEraser || ctrl.drawMode == 'stroke') {
      currentStrokeCells.add(ctrl.grid[y][x]);
      ctrl.grid[y][x].type = ab;
      if (ab == 0) _eraseCell(y, x);
      ctrl.notify();
    } else {
      if (dragStartX != null) { dragCurrentX = x; dragCurrentY = y; ctrl.notify(); }
    }
  }

  void _eraseCell(int y, int x) {
    final c = ctrl.grid[y][x];
    c.name = null; c.connectsToMap = null; c.connectsToNode = null;
    
    if (y > 0 && currentStrokeCells.contains(ctrl.grid[y-1][x])) { 
       c.wallTop = false; c.doorTop = false; 
       ctrl.grid[y-1][x].wallBottom = false; ctrl.grid[y-1][x].doorBottom = false; 
    }
    if (y < AppConfig.rows - 1 && currentStrokeCells.contains(ctrl.grid[y+1][x])) { 
       c.wallBottom = false; c.doorBottom = false; 
       ctrl.grid[y+1][x].wallTop = false; ctrl.grid[y+1][x].doorTop = false; 
    }
    if (x > 0 && currentStrokeCells.contains(ctrl.grid[y][x-1])) { 
       c.wallLeft = false; c.doorLeft = false; 
       ctrl.grid[y][x-1].wallRight = false; ctrl.grid[y][x-1].doorRight = false; 
    }
    if (x < AppConfig.cols - 1 && currentStrokeCells.contains(ctrl.grid[y][x+1])) { 
       c.wallRight = false; c.doorRight = false; 
       ctrl.grid[y][x+1].wallLeft = false; ctrl.grid[y][x+1].doorLeft = false; 
    }
  }

  int get _activeBrush {
    if (isRightClickEraser && ctrl.brushType != 7 && ctrl.brushType != 8) return 0;
    return ctrl.brushType;
  }

  // ───────────────────── 公開イベント ──────────────────────
  void onPointerDown(int y, int x, int buttons, Offset local, Offset global, double cs) {
    _globalPointer = global; _buttons = buttons;
    isRightClickEraser = buttons == 2;
    _startEdgePan();
    final ab = _activeBrush;
    if (ab == 6) return;
    ctrl.saveHistory();
    currentStrokeCells.clear();

    if (ab == 7 || ab == 8) {
      final dx = local.dx % cs, dy = local.dy % cs;
      final cx = (local.dx / cs).floor().clamp(0, AppConfig.cols-1);
      final cy = (local.dy / cs).floor().clamp(0, AppConfig.rows-1);
      final dTop = dy, dBottom = cs-dy, dLeft = dx, dRight = cs-dx;
      final minD = math.min(math.min(dTop, dBottom), math.min(dLeft, dRight));
      if (minD == dTop)    { singleEdgeX1=cx;   singleEdgeY1=cy;   singleEdgeX2=cx+1; singleEdgeY2=cy; }
      else if (minD==dBottom){ singleEdgeX1=cx; singleEdgeY1=cy+1; singleEdgeX2=cx+1; singleEdgeY2=cy+1; }
      else if (minD==dLeft)  { singleEdgeX1=cx; singleEdgeY1=cy;   singleEdgeX2=cx;   singleEdgeY2=cy+1; }
      else                   { singleEdgeX1=cx+1;singleEdgeY1=cy;  singleEdgeX2=cx+1; singleEdgeY2=cy+1; }
      singleClickVx = (local.dx/cs).round().clamp(0, AppConfig.cols);
      singleClickVy = (local.dy/cs).round().clamp(0, AppConfig.rows);
      _scratchpad.clear();
      _drawTempEdge(singleEdgeX1!, singleEdgeY1!, singleEdgeX2!, singleEdgeY2!, isRightClickEraser, ab==8);
      ctrl.notify(); return;
    }

    if (ab == 3 || ab == 4 || ab == 5) {
      final c = ctrl.grid[y][x];
      if (c.type == ab && c.name != null) {
        pendingName = c.name; pendingConnectsToMap = c.connectsToMap; pendingConnectsToNode = c.connectsToNode;
      }
    }

    if (isRightClickEraser || ctrl.drawMode == 'stroke') {
      currentStrokeCells.add(ctrl.grid[y][x]);
      ctrl.grid[y][x].type = ab;
      if (ab == 0) _eraseCell(y, x);
      ctrl.notify();
    } else {
      dragStartX = x; dragStartY = y; dragCurrentX = x; dragCurrentY = y;
      ctrl.notify();
    }
  }

  void onPointerMove(int y, int x, int buttons, Offset local, Offset global, double cs) {
    _globalPointer = global; _buttons = buttons;
    _applyMove(y, x, buttons, local, cs);
  }

  /// PointerUp 後の非同期処理（名前ダイアログ等）はコールバックで EditorScreen に委譲。
  /// [onNeedNameDialog] : (type, oldName?) -> confirmed name or null
  /// [onNeedConnectorDialog] : (oldName?) -> ConnectorResult? 
  Future<void> onPointerUp({
    required Future<String?> Function(int type, String? oldName) onNeedNameDialog,
    required Future<ConnectorDialogResult?> Function(String? oldName) onNeedConnectorDialog,
  }) async {
    _stopEdgePan();
    final ab = _activeBrush;

    if (ab == 7 || ab == 8) {
      singleClickVx = null; singleClickVy = null; _scratchpad.clear(); return;
    }
    if (ab == 6) return;

    if (!isRightClickEraser && ctrl.drawMode == 'rect') {
      _applyRectFill(ab);
    }

    if (currentStrokeCells.isEmpty) { isRightClickEraser = false; return; }

    // 名前リセット
    for (final c in currentStrokeCells) {
      c.name = null; c.connectsToMap = null; c.connectsToNode = null;
    }

    if (ab == 3 || ab == 4) {
      final name = pendingName ?? await onNeedNameDialog(ab, null);
      if (name != null) {
        for (final c in currentStrokeCells) c.name = name;
      } else {
        ctrl.undo();
      }
      pendingName = null;
    } else if (ab == 5) {
      ConnectorDialogResult? res;
      if (pendingName != null) {
        res = ConnectorDialogResult(name: pendingName!, connectsToMap: pendingConnectsToMap, connectsToNode: pendingConnectsToNode);
      } else {
        res = await onNeedConnectorDialog(null);
      }
      if (res != null) {
        for (final c in currentStrokeCells) {
          c.name = res.name; c.connectsToMap = res.connectsToMap; c.connectsToNode = res.connectsToNode;
        }
      } else {
        ctrl.undo();
      }
      pendingName = null; pendingConnectsToMap = null; pendingConnectsToNode = null;
    }

    ctrl.calculateRoomGroups();
    ctrl.notify();
    currentStrokeCells.clear();
    isRightClickEraser = false;
  }

  void _applyRectFill(int ab) {
    if (dragStartX == null || dragCurrentX == null) return;
    final mnX = math.min(dragStartX!, dragCurrentX!), mxX = math.max(dragStartX!, dragCurrentX!);
    final mnY = math.min(dragStartY!, dragCurrentY!), mxY = math.max(dragStartY!, dragCurrentY!);
    for (int yy = mnY; yy <= mxY; yy++) {
      for (int xx = mnX; xx <= mxX; xx++) {
        currentStrokeCells.add(ctrl.grid[yy][xx]);
        ctrl.grid[yy][xx].type = ab;
        if (ab == 0) _eraseCell(yy, xx);
      }
    }
    dragStartX = null; dragStartY = null; dragCurrentX = null; dragCurrentY = null;
    ctrl.notify();
  }

  /// brush=9 (名前変更) の処理。EditorScreen から呼ぶ。
  Future<void> handleRenameClick(int y, int x, {
    required Future<String?> Function(int type, String? oldName) onNeedNameDialog,
    required Future<ConnectorDialogResult?> Function(String? oldName) onNeedConnectorDialog,
  }) async {
    final c = ctrl.grid[y][x];
    if (c.name == null || (c.type != 3 && c.type != 4 && c.type != 5)) return;
    final oldName = c.name!, type = c.type;

    if (type == 5) {
      final res = await onNeedConnectorDialog(oldName);
      if (res == null) return;
      ctrl.saveHistory();
      for (int yy = 0; yy < AppConfig.rows; yy++) {
        for (int xx = 0; xx < AppConfig.cols; xx++) {
          final cell = ctrl.grid[yy][xx];
          if (cell.type == 5 && cell.name == oldName) {
            cell.name = res.name; cell.connectsToMap = res.connectsToMap; cell.connectsToNode = res.connectsToNode;
          }
        }
      }
    } else {
      final name = await onNeedNameDialog(type, oldName);
      if (name == null) return;
      ctrl.saveHistory();
      for (int yy = 0; yy < AppConfig.rows; yy++) {
        for (int xx = 0; xx < AppConfig.cols; xx++) {
          if (ctrl.grid[yy][xx].type == type && ctrl.grid[yy][xx].name == oldName) {
            ctrl.grid[yy][xx].name = name;
          }
        }
      }
    }
    ctrl.calculateRoomGroups();
    ctrl.notify();
  }
}

/// 接続点ダイアログの戻り値
class ConnectorDialogResult {
  final String name;
  final String? connectsToMap;
  final String? connectsToNode;
  const ConnectorDialogResult({required this.name, this.connectsToMap, this.connectsToNode});
}
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'config.dart';

class AutoWallDetector {
  final img.Image image;
  final int cols;
  final int rows;

  AutoWallDetector._(this.image, this.cols, this.rows);

  static AutoWallDetector? init(Uint8List bytes, int cols, int rows) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      return AutoWallDetector._(decoded, cols, rows);
    } catch (e) {
      return null;
    }
  }

  Set<String> detectWalls(double sensitivity) {
    Set<String> walls = {};
    if (image.width == 0 || image.height == 0) return walls;

    final double cellW = image.width / cols;
    final double cellH = image.height / rows;

    Map<String, double> wallScores = {};

    for (int y = 0; y < rows; y++) {
      for (int x = 1; x < cols; x++) {
        int px = (x * cellW).round();
        int pyStart = (y * cellH).round();
        int pyEnd = ((y + 1) * cellH).round();
        int borderPx = (cellW * 0.4).round().clamp(1, 10); 
        double score = _getDarkestColumnScore(px - borderPx, pyStart, px + borderPx, pyEnd);
        if (score >= sensitivity) {
          String k = '${x - 1}_${y}_v';
          walls.add(k);
          wallScores[k] = score;
        }
      }
    }

    for (int y = 1; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        int py = (y * cellH).round();
        int pxStart = (x * cellW).round();
        int pxEnd = ((x + 1) * cellW).round();
        int borderPy = (cellH * 0.4).round().clamp(1, 10);
        double score = _getDarkestRowScore(pxStart, py - borderPy, pxEnd, py + borderPy);
        if (score >= sensitivity) {
          String k = '${x}_${y - 1}_h';
          walls.add(k);
          wallScores[k] = score;
        }
      }
    }

    // NMS Parallel Double-Wall Removal (threshold: 3 cells parallel length)
    Map<int, List<int>> colToYAll = {};
    for (String w in walls) {
      if (w.endsWith('_v')) {
        var p = w.split('_');
        colToYAll.putIfAbsent(int.parse(p[0]), () => []).add(int.parse(p[1]));
      }
    }
    
    List<int> xCols = colToYAll.keys.toList()..sort();
    Set<String> wallsToRemove = {};
    for (int x in xCols) {
      if (colToYAll.containsKey(x + 1)) {
        List<int> y1 = colToYAll[x]!;
        List<int> y2 = colToYAll[x + 1]!;
        Set<int> overlap = y1.toSet().intersection(y2.toSet());
        List<int> overlapList = overlap.toList()..sort();
        List<int> currentSegment = [];
        for (int i = 0; i < overlapList.length; i++) {
          if (currentSegment.isEmpty || currentSegment.last == overlapList[i] - 1) {
            currentSegment.add(overlapList[i]);
          } else {
            if (currentSegment.length >= 3) {
              for (int sy in currentSegment) {
                double s1 = wallScores['${x}_${sy}_v'] ?? 0;
                double s2 = wallScores['${x + 1}_${sy}_v'] ?? 0;
                wallsToRemove.add(s1 >= s2 ? '${x + 1}_${sy}_v' : '${x}_${sy}_v');
              }
            }
            currentSegment = [overlapList[i]];
          }
        }
        if (currentSegment.length >= 3) {
          for (int sy in currentSegment) {
            double s1 = wallScores['${x}_${sy}_v'] ?? 0;
            double s2 = wallScores['${x + 1}_${sy}_v'] ?? 0;
            wallsToRemove.add(s1 >= s2 ? '${x + 1}_${sy}_v' : '${x}_${sy}_v');
          }
        }
      }
    }
    
    Map<int, List<int>> rowToXAll = {};
    for (String w in walls) {
      if (w.endsWith('_h')) {
        var p = w.split('_');
        rowToXAll.putIfAbsent(int.parse(p[1]), () => []).add(int.parse(p[0]));
      }
    }
    
    List<int> yRows = rowToXAll.keys.toList()..sort();
    for (int y in yRows) {
      if (rowToXAll.containsKey(y + 1)) {
        List<int> x1 = rowToXAll[y]!;
        List<int> x2 = rowToXAll[y + 1]!;
        Set<int> overlap = x1.toSet().intersection(x2.toSet());
        List<int> overlapList = overlap.toList()..sort();
        List<int> currentSegment = [];
        for (int i = 0; i < overlapList.length; i++) {
          if (currentSegment.isEmpty || currentSegment.last == overlapList[i] - 1) {
            currentSegment.add(overlapList[i]);
          } else {
            if (currentSegment.length >= 3) {
              for (int sx in currentSegment) {
                double s1 = wallScores['${sx}_${y}_h'] ?? 0;
                double s2 = wallScores['${sx}_${y + 1}_h'] ?? 0;
                wallsToRemove.add(s1 >= s2 ? '${sx}_${y + 1}_h' : '${sx}_${y}_h');
              }
            }
            currentSegment = [overlapList[i]];
          }
        }
        if (currentSegment.length >= 3) {
          for (int sx in currentSegment) {
            double s1 = wallScores['${sx}_${y}_h'] ?? 0;
            double s2 = wallScores['${sx}_${y + 1}_h'] ?? 0;
            wallsToRemove.add(s1 >= s2 ? '${sx}_${y + 1}_h' : '${sx}_${y}_h');
          }
        }
      }
    }

    walls.removeAll(wallsToRemove);

    Set<String> filteredWalls = {};
    int minLength = AppConfig.autoWallMinLength;

    Map<int, List<int>> rowToX = {};
    Map<int, List<int>> colToY = {};

    for (String w in walls) {
      var p = w.split('_');
      int wx = int.parse(p[0]);
      int wy = int.parse(p[1]);
      String dir = p[2];
      if (dir == 'h') {
        rowToX.putIfAbsent(wy, () => []).add(wx);
      } else {
        colToY.putIfAbsent(wx, () => []).add(wy);
      }
    }

    for (int y in rowToX.keys) {
      List<int> xList = rowToX[y]!;
      xList.sort();
      List<int> currentSegment = [];
      for (int i = 0; i < xList.length; i++) {
        if (currentSegment.isEmpty || currentSegment.last == xList[i] - 1) {
          currentSegment.add(xList[i]);
        } else {
          if (currentSegment.length >= minLength) {
            for (int sx in currentSegment) filteredWalls.add('${sx}_${y}_h');
          }
          currentSegment = [xList[i]];
        }
      }
      if (currentSegment.length >= minLength) {
        for (int sx in currentSegment) filteredWalls.add('${sx}_${y}_h');
      }
    }

    for (int x in colToY.keys) {
      List<int> yList = colToY[x]!;
      yList.sort();
      List<int> currentSegment = [];
      for (int i = 0; i < yList.length; i++) {
        if (currentSegment.isEmpty || currentSegment.last == yList[i] - 1) {
          currentSegment.add(yList[i]);
        } else {
          if (currentSegment.length >= minLength) {
            for (int sy in currentSegment) filteredWalls.add('${x}_${sy}_v');
          }
          currentSegment = [yList[i]];
        }
      }
      if (currentSegment.length >= minLength) {
        for (int sy in currentSegment) filteredWalls.add('${x}_${sy}_v');
      }
    }

    return filteredWalls;
  }

  double _getDarkestColumnScore(int x1, int y1, int x2, int y2) {
    x1 = x1.clamp(0, image.width - 1);
    x2 = x2.clamp(0, image.width - 1);
    y1 = y1.clamp(0, image.height - 1);
    y2 = y2.clamp(0, image.height - 1);

    int startX = x1 < x2 ? x1 : x2;
    int endX = x1 > x2 ? x1 : x2;
    int startY = y1 < y2 ? y1 : y2;
    int endY = y1 > y2 ? y1 : y2;

    if (startX == endX || startY == endY) return 0.0;

    double maxDarkness = 0.0;
    for (int x = startX; x <= endX; x++) {
      int totalLum = 0;
      int count = 0;
      for (int y = startY; y <= endY; y++) {
        final p = image.getPixelSafe(x, y);
        int lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
        totalLum += lum;
        count++;
      }
      if (count > 0) {
        double avgLum = totalLum / count;
        double darkness = 1.0 - (avgLum / 255.0);
        if (darkness > maxDarkness) maxDarkness = darkness;
      }
    }
    return maxDarkness;
  }

  double _getDarkestRowScore(int x1, int y1, int x2, int y2) {
    x1 = x1.clamp(0, image.width - 1);
    x2 = x2.clamp(0, image.width - 1);
    y1 = y1.clamp(0, image.height - 1);
    y2 = y2.clamp(0, image.height - 1);

    int startX = x1 < x2 ? x1 : x2;
    int endX = x1 > x2 ? x1 : x2;
    int startY = y1 < y2 ? y1 : y2;
    int endY = y1 > y2 ? y1 : y2;

    if (startX == endX || startY == endY) return 0.0;

    double maxDarkness = 0.0;
    for (int y = startY; y <= endY; y++) {
      int totalLum = 0;
      int count = 0;
      for (int x = startX; x <= endX; x++) {
        final p = image.getPixelSafe(x, y);
        int lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
        totalLum += lum;
        count++;
      }
      if (count > 0) {
        double avgLum = totalLum / count;
        double darkness = 1.0 - (avgLum / 255.0);
        if (darkness > maxDarkness) maxDarkness = darkness;
      }
    }
    return maxDarkness;
  }
}

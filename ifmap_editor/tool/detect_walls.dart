// tool/detect_walls.dart
//
// エディタの「壁の自動生成」(AutoWallDetector) を、画面を開かずにまとめて回す。
// 見取り図を何十枚も処理するとき用。
//
// 使い方（ifmap_editor/ で実行）:
//   dart run tool/detect_walls.dart jobs.json
//
// jobs.json:
//   [{"image": "a.png", "cols": 200, "rows": 80, "sensitivity": 0.5, "out": "a_walls.json"}]
//
// out には検出した壁のキー（エディタの applyWalls と同じ形）を配列で書き出す。
//   "{x}_{y}_v" … マス(x,y) の右の壁
//   "{x}_{y}_h" … マス(x,y) の下の壁
import 'dart:convert';
import 'dart:io';

import 'package:ifmap_editor/auto_wall_detector.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('使い方: dart run tool/detect_walls.dart jobs.json');
    exitCode = 64;
    return;
  }
  final jobs = jsonDecode(File(args.first).readAsStringSync()) as List;
  for (final j in jobs.cast<Map<String, dynamic>>()) {
    final cols = j['cols'] as int, rows = j['rows'] as int;
    final detector =
        AutoWallDetector.init(File(j['image'] as String).readAsBytesSync(), cols, rows);
    if (detector == null) {
      stderr.writeln('画像を読めません: ${j['image']}');
      exitCode = 1;
      continue;
    }
    // エディタ画面と同じく、感度スライダーの値を 1 - 値 にして渡す。
    final walls = detector.detectWalls(1.0 - (j['sensitivity'] as num).toDouble());
    File(j['out'] as String).writeAsStringSync(jsonEncode(walls.toList()));
    stdout.writeln('${j['image']}: 壁 ${walls.length} 本');
  }
}

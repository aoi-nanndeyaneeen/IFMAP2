// tool/strip_bg_image.dart
//
// マップJSONの _editorData.bgImageBase64 を取り除く。
//
// なぜ:
//   bgImageBase64 はエディタが見取り図を再表示するためだけのもので、
//   ナビゲーションアプリ(ifmap)は一度も読まない。それでも assets に
//   入っているぶんは Web 版で毎回ダウンロードされ、JSON として
//   パースもされる。現状これがアセット全体の3割近くを占めている。
//
// 使い方:
//   dart run tool/strip_bg_image.dart            # 何MB減るか出すだけ
//   dart run tool/strip_bg_image.dart --apply    # 実際に書き換える
//
// 注意:
//   書き換えたJSONは ifmap_editor で読み直しても背景の見取り図が出ない
//   （マス目・壁・部屋名は残る）。編集を続ける予定があるなら、
//   エディタが書き出した元のファイルを map_sources/ などに残しておくこと。
//   git に入っていれば履歴からも戻せる。
import 'dart:convert';
import 'dart:io';

const _assetDirs = ['assets/NITTC', 'assets/home'];

void main(List<String> args) {
  final apply = args.contains('--apply');

  var totalBefore = 0;
  var totalAfter = 0;
  var changed = 0;

  for (final dirPath in _assetDirs) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      stderr.writeln('見つかりません: $dirPath');
      continue;
    }

    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;

      final before = entity.lengthSync();
      final decoded = jsonDecode(entity.readAsStringSync());
      if (decoded is! Map<String, dynamic>) continue;

      final editorData = decoded['_editorData'];
      if (editorData is! Map || editorData['bgImageBase64'] == null) {
        totalBefore += before;
        totalAfter += before;
        continue;
      }

      editorData['bgImageBase64'] = null;
      final output = jsonEncode(decoded);
      final after = output.length;

      totalBefore += before;
      totalAfter += after;
      changed++;

      stdout.writeln('${entity.path}: '
          '${_mb(before)} -> ${_mb(after)} '
          '(-${_mb(before - after)})');

      if (apply) entity.writeAsStringSync(output);
    }
  }

  stdout.writeln('');
  stdout.writeln('合計: ${_mb(totalBefore)} -> ${_mb(totalAfter)} '
      '(-${_mb(totalBefore - totalAfter)}, $changed ファイル)');
  if (!apply && changed > 0) {
    stdout.writeln('実際に書き換えるには --apply を付けて実行する。');
  }
}

String _mb(int bytes) => '${(bytes / 1e6).toStringAsFixed(2)} MB';

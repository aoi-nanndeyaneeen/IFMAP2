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
// --apply は GitHub Actions の deploy.yml がビルド直前に、CI のチェックアウト
// 上でだけ実行している。リポジトリの JSON は書き換えないので、エディタで
// 読み直せば見取り図もそのまま出る。
//
// 注意:
//   手元で --apply すると ifmap_editor で読み直しても背景の見取り図が
//   出なくなる（マス目・壁・部屋名は残る）。手元では実行しないこと。
//   やってしまったら git restore で戻せる。
import 'dart:convert';
import 'dart:io';

// assets/ 以下を再帰的に見る。建物フォルダを足してもここは触らなくてよい。
const _assetsRoot = 'assets';

void main(List<String> args) {
  final apply = args.contains('--apply');

  var totalBefore = 0;
  var totalAfter = 0;
  var changed = 0;

  final root = Directory(_assetsRoot);
  if (!root.existsSync()) {
    stderr.writeln('見つかりません: $_assetsRoot（ifmap/ で実行すること）');
    exitCode = 1;
    return;
  }

  for (final entity in root.listSync(recursive: true)) {
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
    // 部屋名に日本語があるので文字数ではなく UTF-8 のバイト数で比べる
    final after = utf8.encode(output).length;

    totalBefore += before;
    totalAfter += after;
    changed++;

    stdout.writeln('${entity.path}: '
        '${_mb(before)} -> ${_mb(after)} '
        '(-${_mb(before - after)})');

    if (apply) entity.writeAsStringSync(output);
  }

  stdout.writeln('');
  stdout.writeln('合計: ${_mb(totalBefore)} -> ${_mb(totalAfter)} '
      '(-${_mb(totalBefore - totalAfter)}, $changed ファイル)');
  if (!apply && changed > 0) {
    stdout.writeln('実際に書き換えるには --apply を付けて実行する。');
  }
}

String _mb(int bytes) => '${(bytes / 1e6).toStringAsFixed(2)} MB';

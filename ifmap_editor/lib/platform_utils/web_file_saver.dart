// Web版でのファイル保存。Blob を作って <a download> を踏ませる。
//
// 以前は dart:html を使っていたが非推奨になったため
// package:web + dart:js_interop へ移した。
// （ifmap 側の lib/sensors/heading_source_web.dart と同じ流儀）
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'stub_file_saver.dart';

class WebFileSaver implements FileSaver {
  @override
  Future<void> saveFile(String fileName, String content, Uint8List? _) async {
    final blob = web.Blob(
      [content.toJS].toJS,
      web.BlobPropertyBag(type: 'application/json'),
    );
    final url = web.URL.createObjectURL(blob);
    try {
      // クリックさせるだけなので DOM に入れる必要はない。
      (web.document.createElement('a') as web.HTMLAnchorElement)
        ..href = url
        ..download = fileName
        ..click();
    } finally {
      web.URL.revokeObjectURL(url);
    }
  }
}

FileSaver getFileSaver() => WebFileSaver();

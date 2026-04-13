import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'stub_file_saver.dart';

class WebFileSaver implements FileSaver {
  @override
  Future<void> saveFile(String fileName, String content, Uint8List? _) async {
    final blob = html.Blob([content], 'application/json');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.document.body?.children.add(anchor);
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }
}

FileSaver getFileSaver() => WebFileSaver();

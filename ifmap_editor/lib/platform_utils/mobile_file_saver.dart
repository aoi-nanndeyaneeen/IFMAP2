import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'stub_file_saver.dart';

class MobileFileSaver implements FileSaver {
  @override
  Future<void> saveFile(String fileName, String content, Uint8List? bytes) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsString(content);
    await Share.shareXFiles([XFile(file.path)], text: 'Exported Map Data');
  }
}

FileSaver getFileSaver() => MobileFileSaver();

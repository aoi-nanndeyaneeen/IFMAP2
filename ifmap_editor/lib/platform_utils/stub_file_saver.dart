import 'dart:typed_data';

abstract class FileSaver {
  Future<void> saveFile(String fileName, String content, Uint8List? bytes);
}

FileSaver getFileSaver() => throw UnsupportedError('Cannot create a FileSaver');

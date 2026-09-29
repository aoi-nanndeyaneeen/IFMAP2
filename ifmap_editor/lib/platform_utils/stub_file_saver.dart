import 'dart:typed_data';

abstract class FileSaver {
  Future<void> saveFile(String fileName, String content, Uint8List? bytes);

  /// 画像などのバイナリを保存する。QRコードの印刷用PNGで使う。
  Future<void> saveBytes(String fileName, Uint8List bytes, String mimeType);
}

FileSaver getFileSaver() => throw UnsupportedError('Cannot create a FileSaver');

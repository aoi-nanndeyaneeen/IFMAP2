// プラットフォームごとにファイル保存の実装を差し替える。
//   Web        → web_file_saver.dart   (Blob + <a download>)
//   モバイル/PC → mobile_file_saver.dart (一時ファイル + 共有シート)
export 'stub_file_saver.dart'
    if (dart.library.js_interop) 'web_file_saver.dart'
    if (dart.library.io) 'mobile_file_saver.dart';

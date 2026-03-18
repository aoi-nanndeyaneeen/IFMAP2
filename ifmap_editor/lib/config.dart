// lib/config.dart
class AppConfig {
  // マス目の数（ここで自由に変更できます）
  static const int rows = 165;
  static const int cols = 234;
  
  // 文字を何文字で改行するか
  static const int maxCharsPerLine = 8;
  
  // 【ifmapアプリ出力設定】
  // 出力されたJSONをifmapで読み込んだ時、1マスを何ピクセルの距離として配置するか
  static const int pxPerCell = 10;
  // 1マスが現実世界の何メートルか（ifmapで距離や時間を計算するために使用）
  static const double metersPerCell = 1.0;

  // 【エディタ上のフォントサイズ・ラベル表示設定】
  // まとまった部屋の縦・横の短い方に対して、文字サイズが占める割合 (デフォルト: 0.4)
  static const double labelSizeRatio = 0.2;
  // どんなに縮尺を小さくしても守られる最小文字サイズ (デフォルト: 12.0)
  static const double labelMinSize = 12.0;
  // どんなに拡大してもそれ以上大きくならない最大文字サイズ (デフォルト: 40.0)
  static const double labelMaxSize = 40.0;
}
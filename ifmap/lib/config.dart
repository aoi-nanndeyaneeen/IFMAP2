// lib/config.dart

class AppConfig {
  static const String map1FPath = 'assets/map_1f.json';
  static const String map2FPath = 'assets/map_2f.json';
  static const double mapCanvasSize = 600.0;

  // ── 歩数推定 ───────────────────────────────────────────────────
  // 縮尺: 11px = 3.2m → 1px ≈ 0.29m → 歩幅0.7m ÷ 0.29 ≈ 2.4px/歩
  // キャリブレーション手順:
  //   ① 既知の廊下（例:10m）を歩いて歩数を数える（例:15歩）
  //   ② 同区間のJSON上のピクセル数を確認（例:34px）
  //   ③ stepLengthPx = 34 ÷ 15 ≈ 2.3
  static const double stepLengthPx = 2.75*4; //その計算だと2.75だが、実用に沿うようにするとこれにする。

  // 加速度センサーの歩数検出しきい値 (m/s², 重力除去後)
  // 感度が高すぎる(誤検出多い)→大きく、低すぎる(進まない)→小さく
  static const double stepAccelThreshold = 1;

  // ── コンパス ───────────────────────────────────────────────────
  // マップの「上方向」が指す磁北方位角（度）
  // 例: マップ上方向が真北なら 0、東向きなら 90
  // キャリブレーション手順:
  //   ① マップの「上」方向を向いてコンパス表示の値を読む
  //   ② その値をここに設定する
  static const double mapNorthDegrees = -90.0;
}
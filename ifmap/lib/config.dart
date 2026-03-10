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
  static const double stepLengthPx = 2.75*4; //4は係数

  // 加速度センサーの歩数検出しきい値 (m/s², 重力除去後)
  // 感度が高すぎる(誤検出多い)→大きく、低すぎる(進まない)→小さく
  static const double stepAccelThreshold = 1.0;

  // ── コンパス ───────────────────────────────────────────────────
  // マップの「上方向」が指す磁北方位角（度）
  // 例: マップ上方向が真北なら 0、東向きなら 90
  // キャリブレーション手順:
  //   ① マップの「上」方向を向いてコンパス表示の値を読む
  //   ② その値をここに設定する
  static const double mapNorthDegrees = -90.0;

   // ── マップ表示 ─────────────────────────────────────────────────
  // ズーム倍率
  static const double focusScale = 1.8;

  // 現在地を「マップ領域の上から何割の位置」に表示するか
  // 0.5 = ちょうど中央, 0.35 = やや上寄り, 0.65 = やや下寄り
  // UIパネルの増減でずれる場合はここを微調整してください
  static const double focusVerticalRatio = 0.5;

  // ── 通過点・ゲート ─────────────────────────────────────────────
  // 部屋とみなす半径（px）。5マス ≒ 18px（11px=3.2m換算）
  static const double waypointRadiusPx = 18.0;
}
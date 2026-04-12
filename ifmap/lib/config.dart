// lib/config.dart

/// マップ1件分の定義
class MapSection {
  final String path;  // pubspec.yaml の assets に登録したパス
  final String label; // UI表示名 & JSON の connectsToMap と完全一致させること
  
  // GPS/階層連携用
  final double? anchorLat;
  final double? anchorLng;
  final double? anchorX;
  final double? anchorY;
  final double? rotationAngle; // 磁北に対するマップの回転(度)
  final int floorLevel;        // 1, 2, 3... (地下は -1, -2...)

  const MapSection({
    required this.path,
    required this.label,
    this.anchorLat,
    this.anchorLng,
    this.anchorX,
    this.anchorY,
    this.rotationAngle,
    this.floorLevel = 1,
  });
}

class AppConfig {
  // ── マップ一覧 ─────────────────────────────────────────────────
  // 建物・フロアを追加するときはここにエントリを足すだけ。
  // あわせて pubspec.yaml の assets: にも同じパスを追加すること。
  static const List<MapSection> mapSections = [
    // --- HOME ---
    MapSection(
      path: 'assets/home/home_1F.json',
      label: 'HOME_1F',
      floorLevel: 1,
      // anchorLat: 35.xxxx, // 自宅の座標がわかったらここに入れる
      // anchorLng: 136.xxxx,
    ),
    MapSection(
      path: 'assets/home/home_2F.json',
      label: 'HOME_2F',
      floorLevel: 2,
    ),

    /*
    // --- NITTC 本棟 ---
    MapSection(
      path: 'assets/NITTC/NITTC_1F.json',
      label: 'NITTC_1F',
      floorLevel: 1,
      anchorLat: 35.151, // 例: 正門付近
      anchorLng: 136.924,
      anchorX: 1440,
      anchorY: 1870,
    ),
    MapSection(path: 'assets/NITTC/NITTC_2F.json', label: 'NITTC_2F', floorLevel: 2),
    MapSection(path: 'assets/NITTC/NITTC_3F.json', label: 'NITTC_3F', floorLevel: 3),
    */
  ];

  // ── 縮尺（ifmap_editor の config.dart と必ず揃えること） ────────
  // editor側:  1マス = metersPerCell(0.5m), JSON座標 = マス番号 × pxPerCell(10)
  // navigator: 1 JSON-px = metersPerCell ÷ pxPerCell = 0.5 ÷ 10 = 0.05 m
  static const double pxPerCell    = 10.0;  // 1マスの描画ピクセル数
  static const double metersPerPx  = 0.05;  // 1 JSON-px が表す実距離(m)
  static const double strideMeters = 0.7;   // 平均歩幅(m) ※実測でキャリブレーション

  /// 歩数センサー: 1歩あたりのJSON-px数（自動計算）
  static double get stepLengthPx => strideMeters / metersPerPx; // = 14.0 px

  // 加速度しきい値
  static const double stepAccelThreshold = 1.0;

  // ── 高度・気圧 ───────────────────────────────────────────────
  static bool enableBarometer = true; // センサー無効化用トグル
  static const double altitudeThreshold = 2.5; // 階移動を検知する高度差(m)
  static const double pressureFilterAlpha = 0.1; // 気圧フィルタの係数

  // ── コンパス＆GPS ──────────────────────────────────────────────
  static bool enableGps = true;       // GPS無効化用トグル
  // マップの「上」方向が指す磁北方位角(度)
  static const double mapNorthDegrees = -90.0;

  // ── マップ描画 ─────────────────────────────────────────────────
  static const double mapCanvasSize     = 2000.0;
  static const double focusScale        = 1.8;
  static const double focusVerticalRatio = 0.5;

  // ── ゲート(通過点)検出 ─────────────────────────────────────────
  static const double waypointRadiusPx = 50.0;
}

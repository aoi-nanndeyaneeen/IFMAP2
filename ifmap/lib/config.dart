// lib/config.dart

/// マップ1件分の定義
class MapSection {
  final String path;  // pubspec.yaml の assets に登録したパス
  final String label; // UI表示名 & JSON の connectsToMap と完全一致させること
  const MapSection({required this.path, required this.label});
}

class AppConfig {
  // ── マップ一覧 ─────────────────────────────────────────────────
  // 建物・フロアを追加するときはここにエントリを足すだけ。
  // あわせて pubspec.yaml の assets: にも同じパスを追加すること。
  static const List<MapSection> mapSections = [
    // --- 自宅 (現在はNITTC用として使っているため非表示) ---
    // MapSection(path: 'assets/home/map_1f.json', label: 'Home_1F'),
    // MapSection(path: 'assets/home/map_2f.json', label: 'Home_2F'),
    
    // --- NITTC 本棟 ---
    MapSection(path: 'assets/NITTC/NITTC_1F.json', label: 'NITTC_1F'),
    MapSection(path: 'assets/NITTC/NITTC_2F.json', label: 'NITTC_2F'),
    MapSection(path: 'assets/NITTC/NITTC_3F.json', label: 'NITTC_3F'),
  ];

  // ── 縮尺（ifmap_editor の config.dart と必ず揃えること） ────────
  // editor側:  1マス = metersPerCell(0.5m), JSON座標 = マス番号 × pxPerCell(10)
  // navigator: 1 JSON-px = metersPerCell ÷ pxPerCell = 0.5 ÷ 10 = 0.05 m
  static const double pxPerCell    = 10.0;  // 1マスの描画ピクセル数
  static const double metersPerPx  = 0.05;  // 1 JSON-px が表す実距離(m)
  static const double strideMeters = 0.7;   // 平均歩幅(m) ※実測でキャリブレーション

  /// 歩数センサー: 1歩あたりのJSON-px数（自動計算）
  static double get stepLengthPx => strideMeters / metersPerPx; // = 14.0 px

  // 加速度しきい値: 高い→鈍感(誤検出減) / 低い→敏感(進みやすい)
  static const double stepAccelThreshold = 1.0;

  // ── コンパス ───────────────────────────────────────────────────
  // マップの「上」方向が指す磁北方位角(度)
  // キャリブレーション: マップ上方向を実際に向いたときのコンパス値を入れる
  static const double mapNorthDegrees = -90.0;

  // ── マップ描画 ─────────────────────────────────────────────────
  static const double mapCanvasSize     = 2000.0; // CustomPaintのサイズ(px) // マップ全体をカバーできるよう拡張
  static const double focusScale        = 1.8;   // QR後・追従時のズーム倍率
  static const double focusVerticalRatio = 0.5;  // 現在地の縦位置(0=上端, 0.5=中央)

  // ── ゲート(通過点)検出 ─────────────────────────────────────────
  // 部屋とみなす半径: 5マス × 10px/マス = 50px
  // editor の metersPerCell/pxPerCell を変えたらここも更新すること
  static const double waypointRadiusPx = 50.0;
}
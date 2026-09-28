// lib/config.dart
//
// アプリ全体の定数と、どのマップを読み込むかの一覧。
// 数値の意味づけ（座標系・単位）はここに集約する。
import 'package:flutter/foundation.dart';

/// マップ1件（＝建物の1フロア）の定義。
class MapSection {
  /// pubspec.yaml の assets: で配信されるパス。
  final String path;

  /// UI表示名。JSON の connectsToMap / connectsToNode と完全一致させること。
  final String label;

  /// 1, 2, 3... （地下は -1, -2...）。気圧センサによる階移動検知に使う。
  final int floorLevel;

  /// 建物入口付近の緯度経度。GPSで「この建物に近づいた」を判定するためだけに使う。
  /// 屋内測位には使わない（屋内でGPSは当てにならない）。
  final double? anchorLat;
  final double? anchorLng;

  const MapSection({
    required this.path,
    required this.label,
    this.floorLevel = 1,
    this.anchorLat,
    this.anchorLng,
  });

  bool get hasAnchor => anchorLat != null && anchorLng != null;
}

class AppConfig {
  // ── マップ一覧 ─────────────────────────────────────────────────
  // 建物・フロアを追加するときはここにエントリを足すだけでよい。
  // pubspec.yaml はディレクトリ単位で assets を登録しているので、
  // assets/<建物>/ に JSON を置けば自動的にバンドルされる。
  //
  // 並び順が階移動の探索順になる。同じ建物のフロアは連続させ、
  // 下の階から上の階へ並べること。
  static const List<MapSection> mapSections = [
    // --- NITTC 本棟 ---
    MapSection(
      path: 'assets/NITTC/NITTC_ground_1F.json',
      label: 'NITTC_ground_1F',
      floorLevel: 1,
      anchorLat: 35.151, // 正門付近
      anchorLng: 136.924,
    ),
    MapSection(
      path: 'assets/NITTC/NITTC_1F.json',
      label: 'NITTC_1F',
      floorLevel: 1,
      anchorLat: 35.151,
      anchorLng: 136.924,
    ),
    MapSection(path: 'assets/NITTC/NITTC_2F.json', label: 'NITTC_2F', floorLevel: 2),
    MapSection(path: 'assets/NITTC/NITTC_3F.json', label: 'NITTC_3F', floorLevel: 3),

    // --- HOME ---
    // anchorLat/Lng は未設定。設定するとGPSで建物接近を検知できる。
    MapSection(path: 'assets/home/home_1F.json', label: 'HOME_1F', floorLevel: 1),
    MapSection(path: 'assets/home/home_2F.json', label: 'HOME_2F', floorLevel: 2),
  ];

  // ── 座標系と縮尺 ───────────────────────────────────────────────
  // エディタは「マス目」で編集し、JSON には マス番号 × pxPerCell を書き出す。
  // つまり JSON の x/y の単位は「JSON-px」で、1マス = pxPerCell JSON-px。
  // ノードIDは node_{行}-{列}（＝ node_{y/pxPerCell}-{x/pxPerCell}）。
  // ノード座標はマスの左上なので、中心を出すには +pxPerCell/2 する。
  static const double pxPerCell = 10.0;

  /// 1マスが表す実距離(m)。ifmap_editor 側の同名定数と必ず揃えること。
  static const double metersPerCell = 0.5;

  /// 1 JSON-px が表す実距離(m)。= 0.5 / 10 = 0.05 m
  static const double metersPerPx = metersPerCell / pxPerCell;

  /// マスの中心へのオフセット(JSON-px)。
  static const double cellCenter = pxPerCell / 2;

  // ── 歩数による推測航法 ─────────────────────────────────────────
  /// 平均歩幅(m)。実測でキャリブレーションする。
  static const double strideMeters = 0.7;

  /// 1歩あたりの JSON-px 数。= 0.7 / 0.05 = 14.0 px
  static const double stepLengthPx = strideMeters / metersPerPx;

  /// これを超える加速度(m/s^2)を1歩とみなす。
  static const double stepAccelThreshold = 1.0;

  /// 1歩を数えたあと次の歩を受け付けないクールダウン。
  static const Duration stepCooldown = Duration(milliseconds: 400);

  // ── 高度・気圧 ───────────────────────────────────────────────
  /// 階移動を検知する高度差(m)。
  static const double altitudeThreshold = 2.5;

  /// 気圧の一次ローパスフィルタ係数。
  static const double pressureFilterAlpha = 0.1;

  // ── コンパス ──────────────────────────────────────────────────
  /// マップの「上」方向が指す磁北方位角(度)。
  static const double mapNorthDegrees = -90.0;

  // ── マップ描画 ─────────────────────────────────────────────────
  static const double mapCanvasSize = 6000.0;
  static const double focusScale = 1.8;
  static const double focusVerticalRatio = 0.5;

  /// 背景（セル・壁・部屋名）の描画キャッシュを何フロア分保持するか。
  static const int backgroundCacheSize = 3;

  // ── 通知の出し方 ───────────────────────────────────────────────
  // 実地で歩いている最中に割り込むものなので、頻度はここで一括管理する。

  /// 同じ提案を出し直すまでの最短間隔。連打・ちらつき防止。
  static const Duration suggestionCooldown = Duration(seconds: 20);

  /// 「無視」された提案を再び出すまでの間隔。
  static const Duration suggestionSnooze = Duration(minutes: 5);

  /// GPSで「この建物に来た」と判定する距離(m)。
  static const double buildingEnterRadius = 20.0;

  /// いったん離れたと判定して提案を再武装する距離(m)。
  /// enter より大きくしてヒステリシスを持たせ、境界での往復を防ぐ。
  static const double buildingExitRadius = 40.0;

  /// 到着とみなす残距離(JSON-px)。
  static const double arrivalTolerancePx = 5.0;
}

/// 端末依存で切りたいセンサーのON/OFF。
/// Drawer から変更され、StepTracker が購読する。
class AppSettings {
  AppSettings._();

  /// 気圧センサ（フロア移動検知）。未対応機種では自動的に何も起きない。
  static final ValueNotifier<bool> barometerEnabled = ValueNotifier(true);

  /// GPS（建物接近検知）。屋内で誤作動するならオフにする。
  static final ValueNotifier<bool> gpsEnabled = ValueNotifier(true);
}

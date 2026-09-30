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

  /// 画面に出す建物名（例: 豊田高専）。同じ建物のフロアは同じ値にする。
  /// フロア切替はこの単位でまとめて出す。省略時は label の「_」より前。
  final String? building;

  /// 画面に出す階の名前（例: 1F、屋外）。省略時は label の最後の「_」より後。
  final String? floorName;

  /// 屋外の案内図（構内図）か。建物の中の図と塗り分けを変える
  /// （芝生の地、建物に影をつける など）。
  final bool outdoor;

  const MapSection({
    required this.path,
    required this.label,
    this.floorLevel = 1,
    this.anchorLat,
    this.anchorLng,
    this.building,
    this.floorName,
    this.outdoor = false,
  });

  bool get hasAnchor => anchorLat != null && anchorLng != null;

  String get buildingName {
    if (building != null) return building!;
    final i = label.indexOf('_');
    return i <= 0 ? label : label.substring(0, i);
  }

  String get floorDisplayName {
    if (floorName != null) return floorName!;
    final i = label.lastIndexOf('_');
    return i < 0 ? label : label.substring(i + 1);
  }

  /// 「豊田高専 2F」のような、利用者向けの呼び名。
  String get displayName => '$buildingName $floorDisplayName';
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
      building: '豊田高専',
      floorName: '屋外',
      outdoor: true,
      anchorLat: 35.151, // 正門付近
      anchorLng: 136.924,
    ),
    MapSection(
      path: 'assets/NITTC/NITTC_1F.json',
      label: 'NITTC_1F',
      floorLevel: 1,
      building: '豊田高専',
      floorName: '1F',
      anchorLat: 35.151,
      anchorLng: 136.924,
    ),
    MapSection(
        path: 'assets/NITTC/NITTC_2F.json',
        label: 'NITTC_2F',
        floorLevel: 2,
        building: '豊田高専',
        floorName: '2F'),
    MapSection(
        path: 'assets/NITTC/NITTC_3F.json',
        label: 'NITTC_3F',
        floorLevel: 3,
        building: '豊田高専',
        floorName: '3F'),

    // --- 学寮（tool/pdf_maps で見取り図PDFから自動生成） ---
    MapSection(
        path: 'assets/dorm/YUSHI_1F.json',
        label: 'YUSHI_1F',
        floorLevel: 1,
        building: '友志寮',
        floorName: '1F'),
    MapSection(
        path: 'assets/dorm/YUSHI_2F.json',
        label: 'YUSHI_2F',
        floorLevel: 2,
        building: '友志寮',
        floorName: '2F'),
    MapSection(
        path: 'assets/dorm/YUSHI_3F.json',
        label: 'YUSHI_3F',
        floorLevel: 3,
        building: '友志寮',
        floorName: '3F'),
    MapSection(
        path: 'assets/dorm/KISHI_1F.json',
        label: 'KISHI_1F',
        floorLevel: 1,
        building: '輝志寮',
        floorName: '1F'),
    MapSection(
        path: 'assets/dorm/KISHI_2F.json',
        label: 'KISHI_2F',
        floorLevel: 2,
        building: '輝志寮',
        floorName: '2F'),
    MapSection(
        path: 'assets/dorm/KISHI_3F.json',
        label: 'KISHI_3F',
        floorLevel: 3,
        building: '輝志寮',
        floorName: '3F'),
    MapSection(
        path: 'assets/dorm/EISHI_1F.json',
        label: 'EISHI_1F',
        floorLevel: 1,
        building: '栄志寮',
        floorName: '1F'),
    MapSection(
        path: 'assets/dorm/EISHI_2F.json',
        label: 'EISHI_2F',
        floorLevel: 2,
        building: '栄志寮',
        floorName: '2F'),
    MapSection(
        path: 'assets/dorm/EISHI_3F.json',
        label: 'EISHI_3F',
        floorLevel: 3,
        building: '栄志寮',
        floorName: '3F'),
    MapSection(
        path: 'assets/dorm/KOSHI_1F.json',
        label: 'KOSHI_1F',
        floorLevel: 1,
        building: '高志寮',
        floorName: '1F'),
    MapSection(
        path: 'assets/dorm/KOSHI_2F.json',
        label: 'KOSHI_2F',
        floorLevel: 2,
        building: '高志寮',
        floorName: '2F'),
    MapSection(
        path: 'assets/dorm/KOSHI_3F.json',
        label: 'KOSHI_3F',
        floorLevel: 3,
        building: '高志寮',
        floorName: '3F'),
    MapSection(
        path: 'assets/dorm/KOSHI_4F.json',
        label: 'KOSHI_4F',
        floorLevel: 4,
        building: '高志寮',
        floorName: '4F'),
    MapSection(
        path: 'assets/dorm/MEISHI_1F.json',
        label: 'MEISHI_1F',
        floorLevel: 1,
        building: '明志寮',
        floorName: '1F'),
    MapSection(
        path: 'assets/dorm/MEISHI_2F.json',
        label: 'MEISHI_2F',
        floorLevel: 2,
        building: '明志寮',
        floorName: '2F'),
    MapSection(
        path: 'assets/dorm/MEISHI_3F.json',
        label: 'MEISHI_3F',
        floorLevel: 3,
        building: '明志寮',
        floorName: '3F'),
    MapSection(
        path: 'assets/dorm/MEISHI_4F.json',
        label: 'MEISHI_4F',
        floorLevel: 4,
        building: '明志寮',
        floorName: '4F'),
    MapSection(
        path: 'assets/dorm/SOSHI_1F.json',
        label: 'SOSHI_1F',
        floorLevel: 1,
        building: '創志寮',
        floorName: '1F'),
    MapSection(
        path: 'assets/dorm/SOSHI_2F.json',
        label: 'SOSHI_2F',
        floorLevel: 2,
        building: '創志寮',
        floorName: '2F'),
    MapSection(
        path: 'assets/dorm/SOSHI_3F.json',
        label: 'SOSHI_3F',
        floorLevel: 3,
        building: '創志寮',
        floorName: '3F'),
    MapSection(
        path: 'assets/dorm/SOSHI_4F.json',
        label: 'SOSHI_4F',
        floorLevel: 4,
        building: '創志寮',
        floorName: '4F'),
    MapSection(
        path: 'assets/dorm/TAISHI_1F.json',
        label: 'TAISHI_1F',
        floorLevel: 1,
        building: '大志寮',
        floorName: '1F'),
    MapSection(
        path: 'assets/dorm/TAISHI_2F.json',
        label: 'TAISHI_2F',
        floorLevel: 2,
        building: '大志寮',
        floorName: '2F'),
    MapSection(
        path: 'assets/dorm/TAISHI_3F.json',
        label: 'TAISHI_3F',
        floorLevel: 3,
        building: '大志寮',
        floorName: '3F'),
    MapSection(
        path: 'assets/dorm/TAISHI_4F.json',
        label: 'TAISHI_4F',
        floorLevel: 4,
        building: '大志寮',
        floorName: '4F'),

    // --- 福利厚生施設（tool/pdf_maps で見取り図PDFから自動生成） ---
    MapSection(
        path: 'assets/welfare/WELFARE_1F.json',
        label: 'WELFARE_1F',
        floorLevel: 1,
        building: '福利厚生会館・食堂',
        floorName: '1F'),
    MapSection(
        path: 'assets/welfare/WELFARE_2F.json',
        label: 'WELFARE_2F',
        floorLevel: 2,
        building: '福利厚生会館・食堂',
        floorName: '2F'),
    MapSection(
        path: 'assets/welfare/TRAINING_1F.json',
        label: 'TRAINING_1F',
        floorLevel: 1,
        building: '合宿研修施設',
        floorName: '1F'),
    MapSection(
        path: 'assets/welfare/TRAINING_2F.json',
        label: 'TRAINING_2F',
        floorLevel: 2,
        building: '合宿研修施設',
        floorName: '2F'),

    // --- 体育施設（tool/pdf_maps で見取り図PDFから自動生成） ---
    MapSection(
        path: 'assets/gym/GYM1_1F.json',
        label: 'GYM1_1F',
        floorLevel: 1,
        building: '第1体育館',
        floorName: '1F'),
    MapSection(
        path: 'assets/gym/GYM2_1F.json',
        label: 'GYM2_1F',
        floorLevel: 1,
        building: '第2体育館',
        floorName: '1F'),
    MapSection(
        path: 'assets/gym/BUDO_1F.json',
        label: 'BUDO_1F',
        floorLevel: 1,
        building: '武道場・卓球場',
        floorName: '1F'),
    MapSection(
        path: 'assets/gym/KYUDO_1F.json',
        label: 'KYUDO_1F',
        floorLevel: 1,
        building: '弓道場',
        floorName: '1F'),

    // --- HOME ---
    // anchorLat/Lng は未設定。設定するとGPSで建物接近を検知できる。
    MapSection(
        path: 'assets/home/home_1F.json',
        label: 'HOME_1F',
        floorLevel: 1,
        building: '自宅',
        floorName: '1F'),
    MapSection(
        path: 'assets/home/home_2F.json',
        label: 'HOME_2F',
        floorLevel: 2,
        building: '自宅',
        floorName: '2F'),
  ];

  /// ラベルからマップ定義を引く。見つからなければ null。
  static MapSection? sectionOf(String label) {
    for (final s in mapSections) {
      if (s.label == label) return s;
    }
    return null;
  }

  /// 利用者向けの呼び名。定義がなければラベルそのまま。
  static String displayNameOf(String label) =>
      sectionOf(label)?.displayName ?? label;

  /// 階だけの呼び名（1F など）。
  static String floorNameOf(String label) =>
      sectionOf(label)?.floorDisplayName ?? label;

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

  /// 所要時間の見積もりに使う歩く速さ(m/秒)。屋内で人を探しながら
  /// 歩くので、屋外の標準(1.3)より少し遅めにしてある。
  static const double walkingSpeed = 1.1;

  /// 階段1回ぶんを平地の何mとみなすか。所要時間の見積もり用。
  static const double stairsEquivalentMeters = 12.0;

  /// 1歩あたりの JSON-px 数。= 0.7 / 0.05 = 14.0 px
  static const double stepLengthPx = strideMeters / metersPerPx;

  /// 曲がり角の前後この距離(m)は、歩数の進みを [cornerStepBoost] 倍にする。
  /// 経路はマスの中心を直角に結ぶが、人は角を斜めに切って最短で歩くので、
  /// 同じ歩数でも経路に沿った距離は多く進んだことになる。
  static const double cornerZoneMeters = 2.5;
  static const double cornerStepBoost = 2.0;

  /// 位置を合わせるタップの間隔の上限(m)。扉・部屋の出入り・曲がり角の
  /// ほかに、これだけ空いたら「現在地を確認」を挟む。
  static const double maxCheckpointGapMeters = 30.0;

  // 1歩の検出は sensors/step_detector.dart（周期性とリズムで判定）。

  // ── 高度・気圧 ───────────────────────────────────────────────
  /// 階移動を検知する高度差(m)。
  static const double altitudeThreshold = 2.5;

  /// 気圧の一次ローパスフィルタ係数。
  static const double pressureFilterAlpha = 0.1;

  // ── コンパス ──────────────────────────────────────────────────
  /// マップの「上」方向が指す磁北方位角(度)。
  /// マップは北を上にして作っているので 0。
  static const double mapNorthDegrees = 0.0;

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

  /// QRコードを読んだとき、経路からこの距離(JSON-px)以内なら経路上の
  /// 最寄りの点に位置を合わせる。これより離れていれば経路を引き直す。
  /// 通路の脇や壁際に貼ることが多いので、通路の幅くらい(3m)は許す。
  static const double qrSnapTolerancePx = 3.0 / metersPerPx;
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

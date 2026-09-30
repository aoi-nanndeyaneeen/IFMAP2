// lib/ui/place_category.dart
//
// 部屋名から「何の部屋か」を推し量り、地図の色・アイコン・検索の分類に使う。
//
// マップデータに部屋の種類は入っていない（エディタは名前しか持たない）。
// 名前にはたいてい「講義室」「トイレ」「階段」のような語が含まれるので、
// それを手がかりにする。当てはまらなければ「その他」で、見た目が
// 地味になるだけで動作には影響しない。
import 'package:flutter/material.dart';

enum PlaceKind {
  restroom,
  stairs,
  elevator,
  classroom,
  lab,
  workshop,
  computer,
  office,
  medical,
  library,
  food,
  sports,
  water,
  parking,
  locker,
  storage,
  home,
  building,
  generic,
}

@immutable
class PlaceCategory {
  final PlaceKind kind;

  /// 検索の分類チップなどに出す名前。
  final String label;
  final IconData icon;

  /// 地図上の部屋の塗り。
  final Color fill;

  /// 地図上の部屋の輪郭。
  final Color stroke;

  /// アイコンの丸バッジと、一覧のアイコンの色。
  final Color accent;

  const PlaceCategory({
    required this.kind,
    required this.label,
    required this.icon,
    required this.fill,
    required this.stroke,
    required this.accent,
  });

  PlaceCategory withIcon(IconData icon) => PlaceCategory(
      kind: kind,
      label: label,
      icon: icon,
      fill: fill,
      stroke: stroke,
      accent: accent);

  /// 地図にアイコンだけでも出しておきたい、案内の目印になる種類。
  bool get isLandmark =>
      kind == PlaceKind.restroom ||
      kind == PlaceKind.stairs ||
      kind == PlaceKind.elevator ||
      kind == PlaceKind.medical ||
      kind == PlaceKind.food;
}

class PlaceCategories {
  PlaceCategories._();

  static const generic = PlaceCategory(
    kind: PlaceKind.generic,
    label: 'その他',
    icon: Icons.meeting_room,
    fill: Color(0xFFECEEF1),
    stroke: Color(0xFFD3D7DC),
    accent: Color(0xFF5F6368),
  );

  static const restroom = PlaceCategory(
    kind: PlaceKind.restroom,
    label: 'トイレ',
    icon: Icons.wc,
    fill: Color(0xFFE3EDF8),
    stroke: Color(0xFFC6D8EE),
    accent: Color(0xFF1967D2),
  );

  static const stairs = PlaceCategory(
    kind: PlaceKind.stairs,
    label: '階段',
    icon: Icons.stairs,
    fill: Color(0xFFE9E4DD),
    stroke: Color(0xFFCFC5B8),
    accent: Color(0xFF795548),
  );

  static const elevator = PlaceCategory(
    kind: PlaceKind.elevator,
    label: 'エレベーター',
    icon: Icons.elevator,
    fill: Color(0xFFE9E4DD),
    stroke: Color(0xFFCFC5B8),
    accent: Color(0xFF795548),
  );

  static const classroom = PlaceCategory(
    kind: PlaceKind.classroom,
    label: '講義室・教室',
    icon: Icons.school,
    fill: Color(0xFFFCF0DC),
    stroke: Color(0xFFEBD4AE),
    accent: Color(0xFFE37400),
  );

  static const lab = PlaceCategory(
    kind: PlaceKind.lab,
    label: '研究室',
    icon: Icons.biotech,
    fill: Color(0xFFF0EBF8),
    stroke: Color(0xFFDACFEE),
    accent: Color(0xFF7B4FC9),
  );

  static const workshop = PlaceCategory(
    kind: PlaceKind.workshop,
    label: '実験・実習室',
    icon: Icons.science,
    fill: Color(0xFFE6F3EC),
    stroke: Color(0xFFC6E1D2),
    accent: Color(0xFF137333),
  );

  static const computer = PlaceCategory(
    kind: PlaceKind.computer,
    label: 'PC・サーバー',
    icon: Icons.computer,
    fill: Color(0xFFE2F1F2),
    stroke: Color(0xFFC2DFE1),
    accent: Color(0xFF0B7A83),
  );

  static const office = PlaceCategory(
    kind: PlaceKind.office,
    label: '事務・職員室',
    icon: Icons.business_center,
    fill: Color(0xFFFBE9E6),
    stroke: Color(0xFFF0CDC7),
    accent: Color(0xFFC5221F),
  );

  static const medical = PlaceCategory(
    kind: PlaceKind.medical,
    label: '保健室',
    icon: Icons.local_hospital,
    fill: Color(0xFFFDE7EA),
    stroke: Color(0xFFF4C7CE),
    accent: Color(0xFFD93025),
  );

  static const library = PlaceCategory(
    kind: PlaceKind.library,
    label: '図書・共用スペース',
    icon: Icons.local_library,
    fill: Color(0xFFFCF5D9),
    stroke: Color(0xFFEBDDA5),
    accent: Color(0xFFB06000),
  );

  static const food = PlaceCategory(
    kind: PlaceKind.food,
    label: '食堂・売店',
    icon: Icons.restaurant,
    fill: Color(0xFFFDE9D6),
    stroke: Color(0xFFF2CFAE),
    accent: Color(0xFFE8710A),
  );

  static const sports = PlaceCategory(
    kind: PlaceKind.sports,
    label: '運動施設',
    icon: Icons.sports,
    fill: Color(0xFFD5EBCF),
    stroke: Color(0xFFB2D8A8),
    accent: Color(0xFF188038),
  );

  static const water = PlaceCategory(
    kind: PlaceKind.water,
    label: 'プール',
    icon: Icons.pool,
    fill: Color(0xFFCDE4F9),
    stroke: Color(0xFFA7CDF0),
    accent: Color(0xFF1A73E8),
  );

  static const parking = PlaceCategory(
    kind: PlaceKind.parking,
    label: '駐車・駐輪場',
    icon: Icons.local_parking,
    fill: Color(0xFFE3E6EA),
    stroke: Color(0xFFC9CED4),
    accent: Color(0xFF3C4043),
  );

  static const locker = PlaceCategory(
    kind: PlaceKind.locker,
    label: 'ロッカー・更衣室',
    icon: Icons.checkroom,
    fill: Color(0xFFEEECE9),
    stroke: Color(0xFFD8D4CE),
    accent: Color(0xFF80868B),
  );

  static const storage = PlaceCategory(
    kind: PlaceKind.storage,
    label: '準備室・倉庫',
    icon: Icons.inventory_2,
    fill: Color(0xFFEEECE9),
    stroke: Color(0xFFD8D4CE),
    accent: Color(0xFF80868B),
  );

  static const home = PlaceCategory(
    kind: PlaceKind.home,
    label: '部屋',
    icon: Icons.chair,
    fill: Color(0xFFFCF0DC),
    stroke: Color(0xFFEBD4AE),
    accent: Color(0xFFE37400),
  );

  /// 屋外マップ上の建物（装飾セル）。
  static const building = PlaceCategory(
    kind: PlaceKind.building,
    label: '建物',
    icon: Icons.apartment,
    fill: Color(0xFFE4E1DC),
    stroke: Color(0xFFBDB6AC),
    accent: Color(0xFF5F6368),
  );

  /// 上から順に見て、最初に名前に含まれていた語で決める。
  /// 「機械工学科棟階段」のように学科名を含む名前が多いので、
  /// 部屋の用途を表す語（末尾に来やすい）を先に並べる。
  static final List<(List<String>, PlaceCategory)> _rules = [
    (['トイレ', '便所', 'wc', 'ＷＣ', '化粧室'], restroom),
    (['エレベーター', 'エレベータ'], elevator),
    (['階段'], stairs),
    (['保健'], medical),
    (['食堂', '売店', 'カフェ', '購買', 'ダイニング', 'キッチン'], food),
    (['プール'], water.withIcon(Icons.pool)),
    (['テニス'], sports.withIcon(Icons.sports_tennis)),
    (['野球'], sports.withIcon(Icons.sports_baseball)),
    (['ハンドボール'], sports.withIcon(Icons.sports_handball)),
    (['陸上', 'グラウンド', 'グランド'], sports.withIcon(Icons.directions_run)),
    (['体育館', '武道', '運動', 'コート', '競技'], sports.withIcon(Icons.sports_basketball)),
    (['駐輪'], parking.withIcon(Icons.pedal_bike)),
    (['駐車', 'ガレージ'], parking),
    (['更衣', 'ロッカー'], locker),
    (['研究室', 'ゼミ室'], lab),
    (['実験', '実習', '工場', '製図'], workshop),
    (['サーバ', 'ネットワーク', '電算', 'cad', 'ＣＡＤ', 'パソコン', '情報処理', '演習室'], computer),
    (['事務', '職員', '校長', '管理', '学生課', '教務', '会議', '応接'], office),
    (['図書', 'ラーニング', 'コモンズ', 'コラボレーション', 'ラウンジ', 'ホール', 'スペース', '交流'], library),
    (['講義室', '教室', 'ゼミナール', 'セミナー', 'プレゼンテーション', 'ワーキング'], classroom),
    (['準備室', '倉庫', '物置', '資料', '書庫'], storage),
    (['リビング', '和室', '寝室', '洋室', '子供部屋', '書斎'], home),
    (['風呂', '浴室', '洗面'], home.withIcon(Icons.bathtub)),
    (['玄関'], home.withIcon(Icons.door_front_door)),
  ];

  static final Map<String, PlaceCategory> _cache = {};

  static PlaceCategory of(String name) => _cache.putIfAbsent(name, () {
        final lower = name.toLowerCase();
        for (final (words, category) in _rules) {
          for (final w in words) {
            if (lower.contains(w.toLowerCase())) return category;
          }
        }
        return generic;
      });

  /// 検索画面の分類チップに並べる順。
  static const List<PlaceCategory> browsable = [
    restroom,
    stairs,
    classroom,
    lab,
    workshop,
    computer,
    office,
    library,
    food,
    medical,
    sports,
    parking,
    locker,
    storage,
  ];
}

/// エディタでは区切りに「_」を使っている名前がある（例: 伊藤_研究室）。
/// 画面ではスペースに置き換えて読みやすくする。
String displayPlaceName(String name) => name.replaceAll('_', ' ');

/// 地図の上に書く部屋名。名前が「建物_階_部屋」の階層になっているときは、
/// いま見ている建物と階の部分を省く（地図の上では分かりきっているため）。
/// 例: 大志寮_2F_食室 → 食室、大志寮_階段A → 階段A、伊藤_研究室 → 伊藤 研究室
String mapLabelName(String name, {required String building, required String floor}) {
  var rest = name;
  if (rest.startsWith('${building}_')) {
    rest = rest.substring(building.length + 1);
    if (rest.startsWith('${floor}_')) rest = rest.substring(floor.length + 1);
  }
  return displayPlaceName(rest);
}

/// 検索用に表記ゆれをならす。全角英数を半角に、ひらがなをカタカナに、
/// 大文字を小文字にし、空白と区切り記号を落とす。
String normalizeForSearch(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    var c = r;
    if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0; // 全角ASCII → 半角
    if (c >= 0x3041 && c <= 0x3096) c += 0x60; // ひらがな → カタカナ
    if (c == 0x20 || c == 0x3000 || c == 0x5F || c == 0x30FB || c == 0x2D) {
      continue; // 空白・_・中黒・-
    }
    b.writeCharCode(c);
  }
  return b.toString().toLowerCase();
}

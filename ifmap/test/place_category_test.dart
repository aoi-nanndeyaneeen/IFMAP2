// 部屋名からの分類、検索の表記ゆれ、距離と時間の表記。
import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/ui/format.dart';
import 'package:ifmap/ui/place_category.dart';

void main() {
  group('部屋名から種類を推し量る', () {
    PlaceKind kind(String name) => PlaceCategories.of(name).kind;

    test('用途を表す語で決める', () {
      expect(kind('機械工学科棟男子トイレ'), PlaceKind.restroom);
      expect(kind('新講義棟階段'), PlaceKind.stairs);
      expect(kind('211講義室'), PlaceKind.classroom);
      expect(kind('伊藤_研究室'), PlaceKind.lab);
      expect(kind('化学実験室(2)'), PlaceKind.workshop);
      expect(kind('サーバー室'), PlaceKind.computer);
      expect(kind('総務課(財務事務室)'), PlaceKind.office);
      expect(kind('第2駐車場'), PlaceKind.parking);
      expect(kind('テニスコート'), PlaceKind.sports);
      expect(kind('プール'), PlaceKind.water);
    });

    test('当てはまらなければその他', () {
      expect(kind('電気室'), PlaceKind.generic);
    });
  });

  group('検索の表記ゆれ', () {
    test('全角と半角、ひらがなとカタカナを同じに扱う', () {
      expect(normalizeForSearch('２１１講義室'), normalizeForSearch('211講義室'));
      expect(normalizeForSearch('といれ'), normalizeForSearch('トイレ'));
      expect(normalizeForSearch('ＣＡＤ室'), normalizeForSearch('cad室'));
    });

    test('区切りの記号と空白は無視する', () {
      expect(normalizeForSearch('伊藤_研究室'), normalizeForSearch('伊藤 研究室'));
      expect(normalizeForSearch('伊藤_研究室'), normalizeForSearch('伊藤研究室'));
    });

    test('画面では区切りをスペースにする', () {
      expect(displayPlaceName('伊藤_研究室'), '伊藤 研究室');
    });

    test('地図の上では、見ている建物と階の部分を省く', () {
      String label(String n) => mapLabelName(n, building: '大志寮', floor: '2F');
      expect(label('大志寮_2F_食室'), '食室');
      expect(label('大志寮_階段A'), '階段A');
      expect(label('大志寮_3F_食室'), '3F 食室'); // 別の階の名前はそのまま
      expect(label('伊藤_研究室'), '伊藤 研究室');
    });
  });

  group('表記', () {
    test('距離は遠いほど丸める', () {
      expect(formatMeters(7.4), '7 m');
      expect(formatMeters(47), '45 m');
      expect(formatMeters(123), '120 m');
      expect(formatMeters(1500), '1.5 km');
    });

    test('時間は切り上げ、最低1分', () {
      expect(formatMinutes(10), '1 分');
      expect(formatMinutes(125), '3 分');
    });

    test('到着予定の時刻', () {
      expect(formatArrival(90, now: DateTime(2026, 9, 30, 10, 40)), '10:42 着');
    });

    test('すぐ近くは「まもなく」', () {
      expect(formatStepDistance(2), 'まもなく');
      expect(formatStepDistance(12), '12 m 先');
    });
  });
}

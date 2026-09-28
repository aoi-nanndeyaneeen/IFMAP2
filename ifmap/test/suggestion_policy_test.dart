import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/config.dart';
import 'package:ifmap/navigation/suggestion_policy.dart';

const _sections = [
  MapSection(
      path: 'a', label: 'A_1F', floorLevel: 1, anchorLat: 35.0, anchorLng: 136.0),
  MapSection(
      path: 'b', label: 'A_2F', floorLevel: 2, anchorLat: 35.0, anchorLng: 136.0),
  MapSection(
      path: 'c', label: 'B_1F', floorLevel: 1, anchorLat: 36.0, anchorLng: 137.0),
];

/// 緯度経度の差をそのまま「メートル」とみなす簡易版。
/// 本物の距離計算はGeolocatorの仕事なので、ここでは距離の大小だけ見る。
double _fakeDistance(double lat1, double lng1, double lat2, double lng2) {
  final dLat = (lat1 - lat2).abs();
  final dLng = (lng1 - lng2).abs();
  return (dLat + dLng) * 1000;
}

void main() {
  late DateTime clock;
  late SuggestionPolicy policy;

  setUp(() {
    clock = DateTime(2026, 1, 1, 12);
    policy = SuggestionPolicy(
      distanceBetween: _fakeDistance,
      sections: _sections,
      now: () => clock,
    );
  });

  void advance(Duration d) => clock = clock.add(d);

  group('高度による階移動の提案', () {
    test('しきい値を超えたら上の階を提案する', () {
      final s = policy.onAltitude(3.0, 'A_1F');
      expect(s, isNotNull);
      expect(s!.targetLabel, 'A_2F');
      expect(s.kind, SuggestionKind.floorChange);
    });

    test('しきい値以下では何も出さない', () {
      expect(policy.onAltitude(1.0, 'A_1F'), isNull);
    });

    test('降りたら下の階を提案する', () {
      final s = policy.onAltitude(-3.0, 'A_2F');
      expect(s!.targetLabel, 'A_1F');
    });

    test('行き先の階が存在しなければ何も出さない', () {
      expect(policy.onAltitude(3.0, 'A_2F'), isNull); // 3F はない
    });

    // 階段の途中では高度が揺れ続けるので、これがないと出しっぱなしになる。
    test('表示中は次を出さない', () {
      expect(policy.onAltitude(3.0, 'A_1F'), isNotNull);
      expect(policy.onAltitude(3.5, 'A_1F'), isNull);
      expect(policy.onAltitude(4.0, 'A_1F'), isNull);
    });

    test('閉じてもクールダウンのあいだは出さない', () {
      final s = policy.onAltitude(3.0, 'A_1F')!;
      policy.accept(s);
      advance(AppConfig.suggestionCooldown - const Duration(seconds: 1));
      expect(policy.onAltitude(3.0, 'A_1F'), isNull);

      advance(const Duration(seconds: 2));
      expect(policy.onAltitude(3.0, 'A_1F'), isNotNull);
    });

    test('「あとで」を押されたらスヌーズ時間は出さない', () {
      final s = policy.onAltitude(3.0, 'A_1F')!;
      policy.snooze(s);

      advance(AppConfig.suggestionSnooze - const Duration(seconds: 1));
      expect(policy.onAltitude(3.0, 'A_1F'), isNull);

      advance(const Duration(seconds: 2));
      expect(policy.onAltitude(3.0, 'A_1F'), isNotNull);
    });
  });

  group('GPSによる建物の提案', () {
    test('入場半径に入ったら提案する', () {
      final s = policy.onPosition(36.0, 137.0, 'A_1F');
      expect(s, isNotNull);
      expect(s!.targetLabel, 'B_1F');
      expect(s.kind, SuggestionKind.buildingSwitch);
    });

    test('遠ければ何も出さない', () {
      expect(policy.onPosition(35.0, 136.0, 'A_1F'), isNull);
    });

    test('同じ建物の別フロアには出さない（そこは気圧の役目）', () {
      // A_1F にいて A_2F のアンカーは同一座標。
      final s = policy.onPosition(35.0, 136.0, 'A_1F');
      expect(s?.targetLabel, isNot('A_2F'));
    });

    // 境界上を行ったり来たりしても出し続けないこと。
    test('いったん近づいたら、離れるまで出し直さない', () {
      final s = policy.onPosition(36.0, 137.0, 'A_1F')!;
      policy.accept(s);
      advance(AppConfig.suggestionCooldown * 2);

      // まだ入場半径の中。再武装していないので出ない。
      expect(policy.onPosition(36.0, 137.0, 'A_1F'), isNull);
    });

    test('退出半径より外へ出れば再武装する', () {
      final s = policy.onPosition(36.0, 137.0, 'A_1F')!;
      policy.accept(s);
      advance(AppConfig.suggestionCooldown * 2);

      // いったん十分離れる。
      expect(policy.onPosition(35.0, 136.0, 'A_1F'), isNull);
      // 戻ってきたらまた出る。
      expect(policy.onPosition(36.0, 137.0, 'A_1F'), isNotNull);
    });

    test('アンカー未設定のマップは対象外', () {
      final p = SuggestionPolicy(
        distanceBetween: _fakeDistance,
        sections: const [
          MapSection(path: 'a', label: 'A_1F', anchorLat: 35.0, anchorLng: 136.0),
          MapSection(path: 'x', label: 'NO_ANCHOR'),
        ],
        now: () => clock,
      );
      expect(p.onPosition(99.0, 99.0, 'A_1F'), isNull);
    });
  });

  group('reset', () {
    test('抑制状態をすべて戻す', () {
      final s = policy.onAltitude(3.0, 'A_1F')!;
      policy.snooze(s);
      policy.reset();
      expect(policy.onAltitude(3.0, 'A_1F'), isNotNull);
    });
  });
}

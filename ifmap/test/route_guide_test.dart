// 経路から組み立てる案内（次にすること）の順番と、いまの手順の決め方。
import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/navigation/route_guide.dart';
import 'package:ifmap/sensors/step_tracker.dart';
import 'package:ifmap/sensors/turn_matching.dart';

const _end = GuideStep(maneuver: Maneuver.arrive, at: 400, title: '目的地に到着');

List<GuideStep> _steps() => RouteGuide.build(
      corners: const [
        RouteCorner(5, 90), // 出発直後（1m以内）は案内しない
        RouteCorner(100, 90),
        RouteCorner(300, -90),
        RouteCorner(395, 90), // 着く直前も案内しない
      ],
      gates: const [
        GateInfo('211講義室', isEnter: false, px: 50),
        GateInfo('扉', isDoor: true, px: 300),
      ],
      totalPx: 400,
      end: _end,
    );

void main() {
  group('組み立て', () {
    test('距離の順に並び、同じ距離ならチェックポイントが先', () {
      final steps = _steps();
      expect(steps.map((s) => s.maneuver), [
        Maneuver.exitRoom,
        Maneuver.right,
        Maneuver.door,
        Maneuver.left,
        Maneuver.arrive,
      ]);
      expect(steps.first.subtitle, '211講義室');
      expect(steps.first.isCheckpoint, isTrue);
      expect(steps[1].isCheckpoint, isFalse);
    });

    test('曲がる角度で言い方を変える', () {
      Maneuver of(double turn) => RouteGuide.build(
            corners: [RouteCorner(100, turn)],
            gates: const [],
            totalPx: 400,
            end: _end,
          ).first.maneuver;

      expect(of(45), Maneuver.slightRight);
      expect(of(-100), Maneuver.left);
      expect(of(150), Maneuver.sharpRight);
      expect(of(-178), Maneuver.uTurn);
      // 小さな曲がりは案内しない（到着だけが残る）
      expect(of(20), Maneuver.arrive);
    });
  });

  group('いまの手順', () {
    test('チェックポイントは確認されるまで進まない', () {
      final steps = _steps();
      final gate = steps[0].gateKey!;

      expect(RouteGuide.currentIndex(steps, 0, {}), 0);
      // 歩数はゲートで止まるので、距離がゲートを超えていても確認が要る
      expect(RouteGuide.currentIndex(steps, 80, {}), 0);
      expect(RouteGuide.currentIndex(steps, 50, {gate}), 1);
    });

    test('曲がり角は少し過ぎたら次へ', () {
      final steps = _steps();
      final passed = {steps[0].gateKey!};

      expect(RouteGuide.currentIndex(steps, 105, passed), 1);
      expect(RouteGuide.currentIndex(steps, 120, passed), 2);
    });

    test('最後は到着（またはフロアの移動）が残る', () {
      final steps = _steps();
      final passed = {steps[0].gateKey!, steps[2].gateKey!};

      expect(RouteGuide.currentIndex(steps, 400, passed), steps.length - 1);
      expect(steps.last.isFinal, isTrue);
    });
  });
}

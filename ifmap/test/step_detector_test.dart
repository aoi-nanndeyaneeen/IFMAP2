// 合成した加速度で歩行検出を確かめる。
//
// 手持ちのスマホでは、重力込みの加速度の大きさ |a| はおおよそ
//   9.81 + (上下の揺れ) + ノイズ
// になる（重力が支配的なので、揺れの向きの成分がそのまま足される）。
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/sensors/step_detector.dart';

const _g = 9.81;

/// [signal] を [seconds] 秒ぶん、約 [hz]Hz（ばらつき [jitter]）で流し、
/// 数えた歩数を返す。
int _run(
  StepDetector d,
  double Function(double t) signal, {
  required double seconds,
  double start = 0,
  double hz = 60,
  double jitter = 0.1,
  int seed = 1,
}) {
  final rnd = math.Random(seed);
  var t = start;
  var steps = 0;
  while (t < start + seconds) {
    steps += d.addSample(t, signal(t));
    t += (1 / hz) * (1 + jitter * (rnd.nextDouble() * 2 - 1));
  }
  return steps;
}

double Function(double) _walk(double stepHz, double amp,
    {double noise = 0.2, double harmonic = 0.3, double asym = 0, int seed = 7}) {
  final rnd = math.Random(seed);
  return (t) {
    // 左右で振幅が違う歩き方: 2歩周期で振幅を上下させる
    final side = asym == 0 ? 1.0 : 1 + asym * math.cos(math.pi * stepHz * t);
    return _g +
        side * amp * math.sin(2 * math.pi * stepHz * t) +
        harmonic * amp * math.sin(4 * math.pi * stepHz * t + 0.8) +
        noise * (rnd.nextDouble() * 2 - 1);
  };
}

void main() {
  group('歩行を数える', () {
    test('ふつうの歩き（1.8歩/秒）を10秒でほぼ18歩', () {
      final d = StepDetector();
      final steps = _run(d, _walk(1.8, 2.0), seconds: 10);
      expect(steps, inInclusiveRange(16, 19));
      expect(d.isWalking, isTrue);
    });

    test('ゆっくり歩き（1.2歩/秒・揺れ小さめ）も数える', () {
      final d = StepDetector();
      final steps = _run(d, _walk(1.2, 1.0, noise: 0.1), seconds: 10);
      expect(steps, inInclusiveRange(10, 13));
    });

    test('左右で揺れ方が違っても1歩ずつ数える', () {
      final d = StepDetector();
      final steps = _run(d, _walk(1.8, 2.0, asym: 0.4), seconds: 10);
      expect(steps, inInclusiveRange(15, 19));
    });

    test('Web のようにサンプル間隔が大きくばらついても数える', () {
      final d = StepDetector();
      final steps =
          _run(d, _walk(1.8, 2.0), seconds: 10, hz: 40, jitter: 0.4);
      expect(steps, inInclusiveRange(16, 19));
    });

    test('歩き出しの数歩は、歩行と確定した時点でまとめて数える', () {
      final d = StepDetector();
      final counts = <int>[];
      final rnd = math.Random(3);
      final sig = _walk(1.8, 2.0);
      for (var t = 0.0; t < 6; t += 1 / 60) {
        final n = d.addSample(t, sig(t) + 0 * rnd.nextDouble());
        if (n > 0) counts.add(n);
      }
      expect(counts.first, greaterThanOrEqualTo(3));
      expect(counts.skip(1).every((n) => n == 1), isTrue);
    });
  });

  group('歩行でないものは数えない', () {
    test('手に持って静止（小さな震えだけ）', () {
      final rnd = math.Random(5);
      final d = StepDetector();
      final steps = _run(d, (t) => _g + 0.08 * (rnd.nextDouble() * 2 - 1),
          seconds: 10);
      expect(steps, 0);
    });

    for (final hz in [4.0, 6.0, 8.0]) {
      test('速く振る（${hz}Hz）', () {
        // 8Hz は周期(0.125秒)が判定範囲の外にあり、以前は4倍の 0.5 秒を
        // 歩行の周期と誤認して数えていた。
        final d = StepDetector();
        final steps = _run(d, (t) => _g + 8 * math.sin(2 * math.pi * hz * t),
            seconds: 20);
        expect(steps, 0);
      });
    }

    test('ランダムな衝撃（机に置く・ぶつける）', () {
      final rnd = math.Random(11);
      // 0.3〜1.5秒おきに不規則な衝撃
      final hits = <double>[];
      for (var t = 0.5; t < 12; t += 0.3 + rnd.nextDouble() * 1.2) {
        hits.add(t);
      }
      double sig(double t) {
        var v = _g + 0.05 * (rnd.nextDouble() * 2 - 1);
        for (final h in hits) {
          final dt = t - h;
          if (dt >= 0 && dt < 0.08) v += 6 * math.exp(-dt * 40);
        }
        return v;
      }

      final d = StepDetector();
      expect(_run(d, sig, seconds: 12), lessThanOrEqualTo(2));
    });

    test('歩いて止まったら、止まってからは数えない', () {
      final rnd = math.Random(9);
      final walk = _walk(1.8, 2.0);
      final d = StepDetector();
      final walking = _run(d, walk, seconds: 6);
      final after = _run(d, (t) => _g + 0.05 * (rnd.nextDouble() * 2 - 1),
          seconds: 5, start: 6);
      expect(walking, inInclusiveRange(9, 11));
      expect(after, 0);
      expect(d.isWalking, isFalse);
    });
  });

  test('サンプルが0.5秒以上途切れたら、続きとしては扱わない', () {
    final d = StepDetector();
    final sig = _walk(1.8, 2.0);
    _run(d, sig, seconds: 5);
    expect(d.isWalking, isTrue);
    d.addSample(6.0, _g); // 1秒の空白
    expect(d.isWalking, isFalse);
  });
}

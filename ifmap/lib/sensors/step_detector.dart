// lib/sensors/step_detector.dart
//
// 加速度から「歩いている」ことと「1歩」を検出する。センサーには触らない
// 純粋なロジックなので、合成した信号でテストできる。
//
// 以前は「重力を除いた加速度が 1.0 m/s² を超えたら1歩」としていたため、
// 端末を振る・机に置く衝撃でも進んでしまった。ここでは歩数計の研究で
// 定番になっている手法を組み合わせる。
//
//   1. 前処理
//      重力込みの加速度の大きさ |a| を使い、ゆっくり動く平均（≒重力）を
//      引いてから 5Hz の低域通過で細かい震えを落とす。
//      重力を除いた加速度の大きさを使わないのは、上下の揺れが絶対値で
//      折り返されて周波数が2倍に見えてしまうため。|a| は重力 9.8 が
//      乗っているので折り返さない（端末の向きにもよらない）。
//
//   2. ピーク検出（Brajdic & Harle, UbiComp 2013 の windowed peak detection）
//      直近の窓の標準偏差に比例する動的しきい値を超えた山を歩みの候補にする。
//      0.3 秒より短い間隔の山は同じ1歩の中の揺れとみなして捨てる。
//      さらに前の山との間に十分深い谷があることを求める（山と谷の対）。
//      歩行は山と同じくらい谷も深いなめらかな揺れだが、ぶつけた衝撃は
//      一瞬のトゲで、トゲの間は平らなまま谷ができない。
//
//   3. 周期性による歩行判定（Rai et al. "Zee", MobiCom 2012）
//      歩行は 0.3〜1.2 秒の周期で規則的に繰り返す。直近の窓の自己相関を
//      とり、基本周期がその範囲にあり相関が十分高いときだけ歩行とみなす。
//      手で振る（速すぎる）、ランダムにぶつかる（周期がない）を弾ける。
//
//   4. 規則的に数歩続くまで数えない（Zhao, Analog Dialogue 44-06, 2010）
//      候補が4歩続き、その間隔がそろっていて（変動係数が小さい）、かつ
//      周期性がある時点で歩行と確定し、それまでの候補もまとめて数える。
//      歩行中も間隔が大きく崩れたり、2秒以上途切れたら歩行を解除する。
//      自己相関だけだと、不規則な衝撃のあとの「平均がゆっくり戻る成分」で
//      相関が高く出てしまうことがあるので、間隔のそろい方でも確かめる。
//
// 限界: 2〜3Hz で規則的に振ると、加速度だけでは歩行と区別できない。
import 'dart:math' as math;

class StepDetector {
  /// 内部で等間隔に打ち直すサンプリング周波数。端末の送ってくる間隔は
  /// ばらつく（Web では特に）ので、自己相関の前にそろえる。
  static const double sampleRate = 50;
  static const double _dt = 1 / sampleRate;

  /// これより短い間隔の山は同じ1歩の中の揺れとみなす（3.3歩/秒）。
  final double minStepInterval;

  /// これより間が空いたら歩行は途切れたとみなす。
  final double maxStepInterval;

  /// 歩行とみなす基本周期の範囲（秒）。1歩ぶん〜2歩ぶん（左右の差が
  /// 大きいと2歩周期のほうが強く出る）を含める。
  final double minPeriod;
  final double maxPeriod;

  /// 自己相関がこれ以上なら周期的とみなす。Zee は 0.7。手持ちのスマホは
  /// 腰に付けたセンサーより揺れが汚いので少し下げている。
  final double minCorrelation;

  /// 窓の標準偏差がこれ未満なら静止（手の震え程度）とみなす(m/s²)。
  final double minStd;

  /// 山の高さが「窓の標準偏差 × これ」未満なら歩みの山とみなさない。
  final double peakFactor;

  /// 前の山からの間に「山の高さ × これ」以上の深さの谷がなければ
  /// 歩みの山とみなさない。
  final double valleyFactor;

  /// この歩数だけ候補が続いてから数え始める。
  final int stepsToConfirm;

  /// 候補の間隔の変動係数（標準偏差/平均）がこれ以下なら規則的とみなす。
  final double maxIntervalCv;

  /// 歩行中、直近の間隔の中央値に対してこの比の範囲を外れた間隔は
  /// 歩みとみなさない（ぶつけた・立ち止まりかけた）。
  final double minIntervalRatio;
  final double maxIntervalRatio;

  /// 歩行中の周期性の再確認に使う、ゆるめの相関しきい値。
  /// 曲がる・人を避けるなどで一瞬崩れても歩行を切らないため。
  final double walkingCorrelation;

  /// 統計と自己相関に使う窓の長さ（秒）。
  final double windowSeconds;

  StepDetector({
    this.minStepInterval = 0.3,
    this.maxStepInterval = 2.0,
    this.minPeriod = 0.3,
    this.maxPeriod = 1.2,
    this.minCorrelation = 0.6,
    this.minStd = 0.35,
    this.peakFactor = 0.5,
    this.valleyFactor = 0.3,
    this.stepsToConfirm = 4,
    this.maxIntervalCv = 0.25,
    this.minIntervalRatio = 0.6,
    this.maxIntervalRatio = 1.6,
    this.walkingCorrelation = 0.45,
    this.windowSeconds = 2.5,
  });

  // ── 状態 ──────────────────────────────────────────────────────
  double? _rawT;
  double? _rawM;
  double _gridT = 0;
  double _mean = 0;
  double _lp = 0;
  final List<double> _window = [];
  double _prev1 = 0;
  double _prev2 = 0;
  int _processed = 0;
  double? _lastPeakT;
  double _minSincePeak = double.infinity;
  final List<double> _pending = [];
  final List<double> _recentIntervals = [];
  bool _walking = false;

  /// 数えた歩数の合計。
  int totalSteps = 0;

  // ── 診断用 ────────────────────────────────────────────────────
  double lastStd = 0;
  double lastCorrelation = 0;
  double lastPeriod = 0;

  bool get isWalking => _walking;

  int get _windowSamples => (windowSeconds * sampleRate).round();

  /// 自己相関を判定できる最低限の長さ。いちばん長い周期ずらしても
  /// 40サンプル(0.8秒)は重なるようにする。
  int get _minCheckSamples => (maxPeriod * sampleRate).round() + 40;

  /// 歩き始めの候補は、判定できるだけのデータが溜まるまで捨てずに持つ。
  static const int _maxPending = 12;

  /// 平均（≒重力）を追う時定数。1秒くらいで追従させる。
  static const double _meanTau = 1.0;

  /// 5Hz の一次低域通過の係数。歩行の成分（〜3Hz）は残し、震えを落とす。
  static final double _lpAlpha = () {
    const rc = 1 / (2 * math.pi * 5);
    return _dt / (rc + _dt);
  }();

  /// サンプルを1つ入れる。[t] は秒、[magnitude] は重力込みの加速度の
  /// 大きさ(m/s²)。この呼び出しで確定した歩数を返す（歩行確定の瞬間は
  /// それまでの候補ぶんまとめて返すので2以上になることがある）。
  int addSample(double t, double magnitude) {
    final rawT = _rawT;
    if (rawT == null) {
      _start(t, magnitude);
      return 0;
    }
    if (t <= rawT) return 0; // 順番が前後したサンプルは捨てる
    if (t - rawT > 0.5) {
      // タブが裏に回ったなどで途切れた。続きとしては扱えない。
      _start(t, magnitude);
      return 0;
    }

    var steps = 0;
    final rawM = _rawM!;
    while (_gridT + _dt <= t) {
      _gridT += _dt;
      final f = (_gridT - rawT) / (t - rawT);
      steps += _process(_gridT, rawM + (magnitude - rawM) * f);
    }
    _rawT = t;
    _rawM = magnitude;
    return steps;
  }

  void _start(double t, double m) {
    _rawT = t;
    _rawM = m;
    _gridT = t;
    _mean = m;
    _lp = 0;
    _window.clear();
    _prev1 = 0;
    _prev2 = 0;
    _processed = 0;
    _lastPeakT = null;
    _minSincePeak = double.infinity;
    _pending.clear();
    _recentIntervals.clear();
    _walking = false;
  }

  int _process(double t, double x) {
    _mean += (x - _mean) * (_dt / _meanTau);
    _lp += ((x - _mean) - _lp) * _lpAlpha;
    final s = _lp;

    _window.add(s);
    if (_window.length > _windowSamples) _window.removeAt(0);
    if (s < _minSincePeak) _minSincePeak = s;

    final lastPeak = _lastPeakT;
    if (lastPeak != null && t - lastPeak > maxStepInterval) {
      _walking = false;
      _pending.clear();
      _recentIntervals.clear();
      _lastPeakT = null;
    }

    var steps = 0;
    // ひとつ前のサンプルが山だったか
    if (_processed >= 2 && _prev1 > _prev2 && _prev1 >= s) {
      steps = _onPeak(t - _dt, _prev1);
    }
    _prev2 = _prev1;
    _prev1 = s;
    _processed++;
    return steps;
  }

  int _onPeak(double t, double value) {
    final std = _std(_window);
    lastStd = std;
    if (std < minStd) return 0;
    if (value < peakFactor * std) return 0;
    final lastPeak = _lastPeakT;
    if (lastPeak != null && t - lastPeak < minStepInterval) return 0;
    if (lastPeak != null && _minSincePeak > -valleyFactor * value) return 0;
    _lastPeakT = t;
    _minSincePeak = value;

    if (_walking) {
      final interval = t - lastPeak!;
      if (_fitsRhythm(interval) && _isPeriodic(walkingCorrelation)) {
        _recentIntervals.add(interval);
        if (_recentIntervals.length > 6) _recentIntervals.removeAt(0);
        totalSteps++;
        return 1;
      }
      // リズムが崩れた。歩行をいったん解除し、この山から候補を積み直す。
      _walking = false;
      _recentIntervals.clear();
      _pending
        ..clear()
        ..add(t);
      return 0;
    }

    _pending.add(t);
    if (_pending.length > _maxPending) _pending.removeAt(0);
    if (_pending.length < stepsToConfirm) return 0;
    // 歩き始めはデータが足りない。候補は捨てずに次の山を待つ。
    if (_window.length < _minCheckSamples) return 0;

    final latest = _pending.sublist(_pending.length - stepsToConfirm);
    if (!_isRegular(latest) || !_isPeriodic(minCorrelation)) {
      // まだ歩行と言い切れない。直近の候補だけ残して次の山を待つ。
      _pending.removeRange(0, _pending.length - (stepsToConfirm - 1));
      return 0;
    }

    _walking = true;
    _recentIntervals
      ..clear()
      ..addAll([for (var i = 1; i < latest.length; i++) latest[i] - latest[i - 1]]);
    final n = _pending.length;
    _pending.clear();
    totalSteps += n;
    return n;
  }

  /// 候補の時刻の間隔がそろっているか。
  bool _isRegular(List<double> times) {
    final intervals = [for (var i = 1; i < times.length; i++) times[i] - times[i - 1]];
    final mean = intervals.reduce((a, b) => a + b) / intervals.length;
    if (mean < minStepInterval || mean > maxStepInterval) return false;
    return _std(intervals) / mean <= maxIntervalCv;
  }

  /// 歩行中の1歩の間隔が、直近のリズムから大きく外れていないか。
  bool _fitsRhythm(double interval) {
    if (_recentIntervals.isEmpty) return true;
    final sorted = [..._recentIntervals]..sort();
    final median = sorted[sorted.length ~/ 2];
    final ratio = interval / median;
    return ratio >= minIntervalRatio && ratio <= maxIntervalRatio;
  }

  /// 窓の自己相関から基本周期を求め、歩行らしい周期かを判定する。
  ///
  /// 基本周期は、音の高さ（ピッチ）検出と同じ要領で「自己相関が最初に
  /// 負になった後の、最大値の9割以上ある最初の極大」とする。
  /// 最大値そのものを使うと、速く振ったときの周期の数倍（8Hz なら 0.5 秒）を
  /// 拾って歩行と誤認する。
  bool _isPeriodic(double threshold) {
    final x = _detrended(_window);
    final n = x.length;
    final maxLag = math.min((maxPeriod * sampleRate).round() + 1, n - 1);

    final r = List<double>.filled(maxLag + 1, 0);
    for (var lag = 1; lag <= maxLag; lag++) {
      var num = 0.0, a = 0.0, b = 0.0;
      for (var i = 0; i + lag < n; i++) {
        num += x[i] * x[i + lag];
        a += x[i] * x[i];
        b += x[i + lag] * x[i + lag];
      }
      r[lag] = (a == 0 || b == 0) ? 0 : num / math.sqrt(a * b);
    }

    lastCorrelation = 0;
    lastPeriod = 0;

    // 最初に負になるところ。ならなければ周期的な揺れではない。
    var zero = 1;
    while (zero <= maxLag && r[zero] >= 0) {
      zero++;
    }
    if (zero > maxLag) return false;

    var best = 0.0;
    for (var lag = zero; lag < maxLag; lag++) {
      if (r[lag] > best) best = r[lag];
    }
    for (var lag = zero + 1; lag < maxLag; lag++) {
      final isLocalMax = r[lag] >= r[lag - 1] && r[lag] >= r[lag + 1];
      if (!isLocalMax || r[lag] < 0.9 * best) continue;
      lastCorrelation = r[lag];
      lastPeriod = lag / sampleRate;
      return lastCorrelation >= threshold &&
          lastPeriod >= minPeriod &&
          lastPeriod <= maxPeriod;
    }
    return false;
  }

  /// 直線のトレンドを引く。平均がゆっくり戻る成分が残っていると、
  /// どのずらし幅でも相関が高く出てしまう。
  static List<double> _detrended(List<double> v) {
    final n = v.length;
    final meanI = (n - 1) / 2;
    final meanV = v.reduce((a, b) => a + b) / n;
    var cov = 0.0, varI = 0.0;
    for (var i = 0; i < n; i++) {
      cov += (i - meanI) * (v[i] - meanV);
      varI += (i - meanI) * (i - meanI);
    }
    final slope = varI == 0 ? 0 : cov / varI;
    return [for (var i = 0; i < n; i++) v[i] - meanV - slope * (i - meanI)];
  }

  static double _std(List<double> v) {
    if (v.length < 2) return 0;
    final mean = v.reduce((a, b) => a + b) / v.length;
    var sum = 0.0;
    for (final x in v) {
      sum += (x - mean) * (x - mean);
    }
    return math.sqrt(sum / v.length);
  }
}

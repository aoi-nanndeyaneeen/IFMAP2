// lib/navigation/suggestion_policy.dart
//
// 「いつ提案を出すか」だけを決める純粋ロジック。UIもセンサーも知らない。
//
// これを切り出した理由:
//   センサーの生イベント（気圧・GPS）をそのまま提案に変換すると、
//   階段の途中や建物の境界で提案が連続して出続ける。実際に歩いている
//   人の画面に割り込むものなので、出す条件は1か所にまとめてテストする。
//
// 出しすぎを防ぐしくみは3つ。
//   1. クールダウン  … 直前の提案から一定時間は何も出さない。
//   2. スヌーズ      … 「無視」された提案は一定時間出し直さない。
//   3. ヒステリシス  … GPSは「近づいた」より遠い距離まで離れないと再武装しない。
import '../config.dart';

enum SuggestionKind {
  /// 気圧センサが階の移動を検知した。
  floorChange,

  /// GPSで別の建物の入口に近づいた。
  buildingSwitch,
}

class Suggestion {
  final SuggestionKind kind;

  /// 切り替え先のフロアラベル。
  final String targetLabel;

  final String title;
  final String message;

  const Suggestion({
    required this.kind,
    required this.targetLabel,
    required this.title,
    required this.message,
  });

  /// 同じ対象への提案かどうか。スヌーズの単位になる。
  String get key => '${kind.name}:$targetLabel';
}

/// 実距離(m)を返す関数。Geolocator への依存をテストから切るために注入する。
typedef DistanceFn = double Function(
    double lat1, double lng1, double lat2, double lng2);

class SuggestionPolicy {
  final List<MapSection> sections;
  final DistanceFn distanceBetween;

  /// テストから時刻を差し替えられるようにしておく。
  final DateTime Function() now;

  SuggestionPolicy({
    required this.distanceBetween,
    this.sections = AppConfig.mapSections,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  DateTime? _lastShown;
  final Map<String, DateTime> _snoozedUntil = {};

  /// 建物ごとに「いま近くにいる」と判定済みかどうか。
  /// enterRadius で true、exitRadius を超えて初めて false に戻す。
  final Set<String> _inRange = {};

  /// 提案を表示中は次を出さない。UI側が設定する。
  bool showing = false;

  /// 気圧から求めた相対高度(m)を渡す。出すべき提案があれば返す。
  Suggestion? onAltitude(double relativeAltitudeM, String trackerLabel) {
    if (relativeAltitudeM.abs() <= AppConfig.altitudeThreshold) return null;

    final current = _sectionOf(trackerLabel);
    if (current == null) return null;

    final targetLevel =
        current.floorLevel + (relativeAltitudeM > 0 ? 1 : -1);
    final target = _sectionWithLevel(targetLevel, nearTo: current);
    if (target == null) return null;

    return _emit(Suggestion(
      kind: SuggestionKind.floorChange,
      targetLabel: target.label,
      title: '階を移動しましたか？',
      message: '高度の変化を検知しました。${target.displayName} へ切り替えますか？',
    ));
  }

  /// GPSの現在地を渡す。出すべき提案があれば返す。
  Suggestion? onPosition(double lat, double lng, String trackerLabel) {
    final current = _sectionOf(trackerLabel);

    Suggestion? found;
    for (final section in sections) {
      if (!section.hasAnchor || section.label == trackerLabel) continue;

      // 同じ建物の別フロアには出さない。フロア切り替えは気圧の仕事。
      if (current != null &&
          current.anchorLat == section.anchorLat &&
          current.anchorLng == section.anchorLng) {
        continue;
      }

      final dist =
          distanceBetween(lat, lng, section.anchorLat!, section.anchorLng!);

      // 離れたら再武装する。境界上での往復で出続けるのを防ぐ。
      if (dist > AppConfig.buildingExitRadius) {
        _inRange.remove(section.label);
        continue;
      }
      if (dist > AppConfig.buildingEnterRadius) continue;

      // すでに「近くにいる」と判定済みなら、離れるまで何も出さない。
      if (!_inRange.add(section.label)) continue;

      found ??= Suggestion(
        kind: SuggestionKind.buildingSwitch,
        targetLabel: section.label,
        title: '${section.buildingName} に着きましたか？',
        message: '${section.buildingName} の入口付近にいるようです。マップを表示しますか？',
      );
    }

    return found == null ? null : _emit(found);
  }

  /// 「無視」されたとき。一定時間は同じ提案を出し直さない。
  void snooze(Suggestion suggestion) {
    showing = false;
    _snoozedUntil[suggestion.key] = now().add(AppConfig.suggestionSnooze);
  }

  /// 受け入れられたとき。
  void accept(Suggestion suggestion) {
    showing = false;
    _snoozedUntil.remove(suggestion.key);
  }

  /// 経路や現在地をリセットしたとき。抑制状態も全部戻す。
  void reset() {
    showing = false;
    _lastShown = null;
    _snoozedUntil.clear();
    _inRange.clear();
  }

  Suggestion? _emit(Suggestion suggestion) {
    if (showing) return null;

    final t = now();
    final last = _lastShown;
    if (last != null && t.difference(last) < AppConfig.suggestionCooldown) {
      return null;
    }
    final until = _snoozedUntil[suggestion.key];
    if (until != null && t.isBefore(until)) return null;

    _lastShown = t;
    showing = true;
    return suggestion;
  }

  MapSection? _sectionOf(String label) {
    for (final s in sections) {
      if (s.label == label) return s;
    }
    return null;
  }

  /// [level] のフロアを探す。同じ建物（アンカーが一致、または両方未設定で
  /// mapSections 上で隣接）を優先したいので、現在のフロアに近い順に見る。
  MapSection? _sectionWithLevel(int level, {required MapSection nearTo}) {
    final origin = sections.indexOf(nearTo);
    if (origin == -1) return null;

    for (var d = 1; d < sections.length; d++) {
      for (final i in [origin - d, origin + d]) {
        if (i < 0 || i >= sections.length) continue;
        if (sections[i].floorLevel == level) return sections[i];
      }
    }
    return null;
  }
}

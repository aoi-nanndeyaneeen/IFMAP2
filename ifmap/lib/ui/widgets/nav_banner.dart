// lib/ui/widgets/nav_banner.dart
//
// ナビ中に画面上端に出す「次にすること」の案内。
//
// 歩きながらちらっと見て分かるよう、アイコンと一言を大きく出す。
// チェックポイント（扉・部屋の出入り）では歩数がそこで止まるので、
// 通過を知らせるボタンをこの中に置く。いちばん目に入る場所だから。
import 'package:flutter/material.dart';

import '../../navigation/route_guide.dart';
import '../format.dart';
import '../theme.dart';
import 'map_overlays.dart';

class NavBanner extends StatelessWidget {
  final GuideStep step;

  /// [step] までの距離(m)。
  final double distanceM;

  /// その次の手順。
  final GuideStep? next;

  /// 近くの目印（扉・曲がり角など）。ここを通ったと知らせると現在地が合う。
  /// 歩数だけで進むので押さなくてもよい。ずれが溜まっていそうなときだけ渡す。
  final GuideStep? fixStep;
  final VoidCallback? onConfirmCheckpoint;

  /// 階の移り目に着いたことを知らせる（例: 2Fに着いた）。
  final String? advanceLabel;
  final VoidCallback? onAdvance;

  /// 反対を向いているなどの注意。
  final String? warning;

  const NavBanner({
    super.key,
    required this.step,
    required this.distanceM,
    this.next,
    this.fixStep,
    this.onConfirmCheckpoint,
    this.advanceLabel,
    this.onAdvance,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    final fix = fixStep != null && onConfirmCheckpoint != null ? fixStep : null;
    final distanceText = step.maneuver == Maneuver.arrive && distanceM < 3
        ? 'まもなく到着'
        : formatStepDistance(distanceM);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.guidance,
            borderRadius: BorderRadius.circular(20),
            boxShadow: floatingShadow,
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (c, a) =>
                      ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                  child: Icon(maneuverIcon(step.maneuver),
                      key: ValueKey(step.maneuver), color: Colors.white, size: 46),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        distanceText,
                        style: const TextStyle(
                          color: Color(0xDDFFFFFF),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        step.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            height: 1.2),
                      ),
                      if (step.subtitle != null)
                        Text(
                          step.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xE6FFFFFF),
                              fontSize: 15,
                              fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                ),
              ]),
              if (onAdvance != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton.icon(
                    key: const ValueKey('advance-step'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.guidance,
                    ),
                    onPressed: onAdvance,
                    icon: Icon(advanceLabel == '到着した' ? Icons.sports_score : Icons.stairs),
                    label: Text(advanceLabel ?? '次へ'),
                  ),
                ),
              ] else if (fix != null) ...[
                // 押さなくても進む。ずれていたら直せる、という控えめな出し方にする。
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlinedButton.icon(
                    key: const ValueKey('confirm-step'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0x99FFFFFF)),
                    ),
                    onPressed: onConfirmCheckpoint,
                    icon: Icon(maneuverIcon(fix.maneuver), size: 18),
                    label: Text('${_fixText(fix)} → 位置を合わせる',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (next != null || warning != null) const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (next != null)
            _Pill(
              color: AppColors.guidanceDark,
              children: [
                const Text('その後',
                    style: TextStyle(
                        color: Color(0xDDFFFFFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Icon(maneuverIcon(next!.maneuver), color: Colors.white, size: 18),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(next!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          if (warning != null)
            _Pill(
              color: AppColors.warning,
              children: [
                const Icon(Icons.u_turn_left, color: AppColors.text, size: 18),
                const SizedBox(width: 4),
                Text(warning!,
                    style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            ),
        ]),
      ],
    );
  }

  static String _fixText(GuideStep s) {
    final name = s.subtitle == null ? '' : '「${s.subtitle}」';
    return switch (s.maneuver) {
      Maneuver.enterRoom => '$nameに入った',
      Maneuver.exitRoom => '$nameから出た',
      Maneuver.checkpoint => '地図の印に着いた',
      _ => _pastTense(s),
    };
  }

  static String _pastTense(GuideStep s) => switch (s.maneuver) {
        Maneuver.door => '扉を通った',
        Maneuver.checkpoint => 'ここに来た',
        Maneuver.slightLeft ||
        Maneuver.left ||
        Maneuver.sharpLeft ||
        Maneuver.slightRight ||
        Maneuver.right ||
        Maneuver.sharpRight ||
        Maneuver.uTurn =>
          '曲がった',
        Maneuver.enterRoom => '入った',
        Maneuver.exitRoom => '出た',
        Maneuver.exitBuilding => '外に出た',
        Maneuver.enterBuilding => '建物に入った',
        Maneuver.connector => '着いた',
        _ => '通過した',
      };
}

class _Pill extends StatelessWidget {
  final Color color;
  final List<Widget> children;
  const _Pill({required this.color, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: floatingShadow,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );
}

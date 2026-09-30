// lib/ui/widgets/sheets.dart
//
// 画面下のシートの中身。状況ごとに1つずつ。
//
//   読み込み中 → 現在地を設定 → 現在地あり → 場所を選んだ
//                                           → 経路の確認 → 案内中 → 到着
//
// シートの外枠（角丸・影・つまみ）は MapScreen が持ち、ここは中身だけ。
import 'package:flutter/material.dart';

import '../../config.dart';
import '../../data/map_data.dart';
import '../../navigation/navigation_controller.dart';
import '../../navigation/route_guide.dart';
import '../format.dart';
import '../place_category.dart';
import '../theme.dart';
import 'map_overlays.dart';

const _title = TextStyle(
    fontSize: 21, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.25);
const _body = TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.45);
const _meta = TextStyle(fontSize: 13.5, color: AppColors.textSecondary);

class LoadingSheet extends StatelessWidget {
  final int loaded;
  final int total;
  const LoadingSheet({super.key, required this.loaded, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Text('マップを準備しています', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('$loaded / $total', style: _meta.copyWith(fontFeatures: tabularFigures)),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: total == 0 ? null : loaded / total,
              backgroundColor: AppColors.surfaceDim,
            ),
          ),
        ],
      ),
    );
  }
}

class SetLocationSheet extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback onPickFromList;
  const SetLocationSheet({super.key, required this.onScan, required this.onPickFromList});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
              child: const Icon(Icons.my_location, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            const Expanded(child: Text('まず現在地を教えてください', style: _title)),
          ]),
          const SizedBox(height: 10),
          const Text(
            '近くに貼ってある QR コードを読み取ると、いまいる場所がすぐに分かります。'
            '地図上の部屋をタップして選ぶこともできます。',
            style: _body,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('QR コードを読み取る'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: onPickFromList,
              icon: const Icon(Icons.list),
              label: const Text('一覧から選ぶ'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 現在地が分かっていて、目的地はまだないとき。
/// 近くのトイレ・階段などを徒歩距離つきで出す。
class LocatedSheet extends StatelessWidget {
  final String here;
  final String floorText;
  final List<NearbyPlace> nearby;
  final VoidCallback onChange;
  final VoidCallback onSearch;
  final void Function(PlaceRef) onNearby;

  const LocatedSheet({
    super.key,
    required this.here,
    required this.floorText,
    required this.nearby,
    required this.onChange,
    required this.onSearch,
    required this.onNearby,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const _PulseDot(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('現在地', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  Text(here,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(floorText, style: _meta),
                ],
              ),
            ),
            TextButton(onPressed: onChange, child: const Text('変更')),
          ]),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                key: const ValueKey('search-destination'),
                onPressed: onSearch,
                icon: const Icon(Icons.directions),
                label: const Text('目的地を探す'),
              ),
            ),
          ),
          if (nearby.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('近くにあるもの',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: nearby.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _NearbyCard(item: nearby[i], onTap: () => onNearby(nearby[i].place)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

@immutable
class NearbyPlace {
  final PlaceRef place;
  final PlaceCategory category;
  final String title;
  final double meters;
  const NearbyPlace(this.place, this.category, this.title, this.meters);
}

class _NearbyCard extends StatelessWidget {
  final NearbyPlace item;
  final VoidCallback onTap;
  const _NearbyCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceDim,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            CategoryAvatar(category: item.category, size: 36),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Text(
                  '徒歩 ${formatMinutes(item.meters / AppConfig.walkingSpeed)} · ${formatMeters(item.meters)}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontFeatures: tabularFigures),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.userDot.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.userDot,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3)],
            ),
          ),
        ),
      );
}

/// 地図や検索で選んだ場所の情報。
class PlaceSheet extends StatelessWidget {
  final PlaceRef place;
  final String title;
  final bool isCurrentLocation;
  final bool hasStart;
  final double? walkingMeters;
  final VoidCallback onClose;
  final VoidCallback onRoute;
  final VoidCallback onSetHere;

  const PlaceSheet({
    super.key,
    required this.place,
    required this.title,
    required this.isCurrentLocation,
    required this.hasStart,
    required this.walkingMeters,
    required this.onClose,
    required this.onRoute,
    required this.onSetHere,
  });

  @override
  Widget build(BuildContext context) {
    final cat = PlaceCategories.of(place.name);
    final section = AppConfig.sectionOf(place.label);
    final where = section == null ? place.label : '${section.floorDisplayName} · ${section.buildingName}';
    final meters = walkingMeters;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(title, style: _title.copyWith(fontSize: 22)),
              ),
            ),
            IconButton(
              tooltip: '閉じる',
              onPressed: onClose,
              style: IconButton.styleFrom(backgroundColor: AppColors.surfaceDim),
              icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Icon(cat.icon, size: 16, color: cat.accent),
            const SizedBox(width: 4),
            Flexible(
              child: Text('${cat.label} · $where',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _meta),
            ),
          ]),
          if (isCurrentLocation || meters != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              if (isCurrentLocation) ...[
                const Icon(Icons.my_location, size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                const Text('現在地', style: TextStyle(fontSize: 13.5, color: AppColors.primary, fontWeight: FontWeight.w600)),
              ] else ...[
                const Icon(Icons.directions_walk, size: 16, color: AppColors.success),
                const SizedBox(width: 2),
                Text(
                  '徒歩 ${formatMinutes(meters! / AppConfig.walkingSpeed)}',
                  style: const TextStyle(fontSize: 13.5, color: AppColors.success, fontWeight: FontWeight.w600),
                ),
                Text('  ·  ${formatMeters(meters)}', style: _meta.copyWith(fontFeatures: tabularFigures)),
              ],
            ]),
          ],
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(children: [
              if (hasStart && !isCurrentLocation) ...[
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('route-here'),
                    onPressed: onRoute,
                    icon: const Icon(Icons.directions),
                    label: const Text('経路'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (!isCurrentLocation)
                Expanded(
                  child: hasStart
                      ? OutlinedButton.icon(
                          onPressed: onSetHere,
                          icon: const Icon(Icons.my_location, size: 18),
                          label: const Text('ここにいる'),
                        )
                      : FilledButton.icon(
                          key: const ValueKey('set-here'),
                          onPressed: onSetHere,
                          icon: const Icon(Icons.my_location, size: 18),
                          label: const Text('ここにいる'),
                        ),
                ),
            ]),
          ),
          if (!hasStart)
            const Padding(
              padding: EdgeInsets.only(top: 10, right: 12),
              child: Text('現在地を決めると、ここまでの道順を案内できます。', style: _meta),
            ),
        ],
      ),
    );
  }
}

/// 目的地を選んだ直後。経路の全体と所要時間を見せ、案内を始める。
class RoutePreviewSheet extends StatelessWidget {
  final NavigationController controller;
  final bool expanded;
  final VoidCallback onToggleSteps;
  final VoidCallback onStart;
  final VoidCallback onClose;

  const RoutePreviewSheet({
    super.key,
    required this.controller,
    required this.expanded,
    required this.onToggleSteps,
    required this.onStart,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final goal = c.goal!;
    final total = c.totalRouteMeters;
    final ready = total != null && c.floorPaths.isNotEmpty;
    final labels = c.routeLabels;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${c.placeTitle(goal)} へ',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: _title),
                    const SizedBox(height: 2),
                    Text('出発: ${c.start == null ? '—' : c.placeTitle(c.start!)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: _meta),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: '経路をやめる',
              onPressed: onClose,
              style: IconButton.styleFrom(backgroundColor: AppColors.surfaceDim),
              icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
            ),
          ]),
          const SizedBox(height: 12),
          if (c.routeNotFound)
            Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.wrong_location_outlined, color: Color(0xFFB06000)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'この2か所をつなぐ通路がマップ上に見つかりませんでした。'
                      '別の棟へは屋外や別の階を通る必要があるかもしれません。',
                      style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.text),
                    ),
                  ),
                ]),
              ),
            )
          else if (!ready)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
                SizedBox(width: 12),
                Text('経路を探しています…', style: _body),
              ]),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatMinutes(total / AppConfig.walkingSpeed),
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.success, height: 1.1)),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('(${formatMeters(total)})',
                      style: const TextStyle(fontSize: 16, color: AppColors.textSecondary, fontFeatures: tabularFigures)),
                ),
                const Spacer(),
                FilledButton.icon(
                  key: const ValueKey('start-navigation'),
                  onPressed: onStart,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  icon: const Icon(Icons.navigation),
                  label: const Text('案内を開始'),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (labels.length > 1)
                _InfoChip(
                  icon: Icons.stairs,
                  text: labels.map(AppConfig.floorNameOf).join(' → '),
                ),
              _InfoChip(
                icon: Icons.fact_check_outlined,
                text: '位置合わせ ${c.checkpoints.length} 回',
              ),
              _InfoChip(
                icon: Icons.turn_right,
                text: '曲がる ${c.checkpoints.where((g) => g.turn != null).length} 回',
              ),
            ]),
            const SizedBox(height: 4),
            _StepsToggle(expanded: expanded, onTap: onToggleSteps),
            if (expanded)
              StepsList(controller: controller),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceDim,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 13, color: AppColors.text, fontWeight: FontWeight.w500)),
        ]),
      );
}

class _StepsToggle extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;
  const _StepsToggle({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
          onPressed: onTap,
          icon: Icon(expanded ? Icons.expand_less : Icons.format_list_bulleted, size: 20),
          label: Text(expanded ? '手順をたたむ' : '手順を見る'),
        ),
      );
}

/// 案内の一覧（このフロアの手順）。済んだものは薄く、いまの手順は太く。
class StepsList extends StatelessWidget {
  final NavigationController controller;
  const StepsList({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final steps = c.guideSteps;
    final current = c.currentStepIndex;
    final traveled = c.traveledPx.value;
    final maxH = MediaQuery.sizeOf(context).height * 0.36;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.only(right: 12, bottom: 4),
        itemCount: steps.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return _StepRow(
              icon: Icons.trip_origin,
              iconColor: AppColors.primary,
              title: '出発',
              subtitle: c.start == null ? null : c.placeTitle(c.start!),
              trailing: AppConfig.floorNameOf(c.trackerLabel),
              done: true,
            );
          }
          final s = steps[i - 1];
          final done = i - 1 < current;
          final isNow = i - 1 == current;
          final meters = (s.at - traveled) * AppConfig.metersPerPx;
          return _StepRow(
            icon: maneuverIcon(s.maneuver),
            iconColor: s.isCheckpoint
                ? checkpointColor(s.maneuver)
                : (s.maneuver == Maneuver.arrive ? AppColors.destination : AppColors.text),
            title: s.title,
            subtitle: s.subtitle,
            trailing: done ? null : (meters > 1 ? formatMeters(meters) : null),
            done: done,
            highlighted: isNow,
            badge: s.isCheckpoint ? '確認' : null,
          );
        },
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? trailing;
  final bool done;
  final bool highlighted;
  final String? badge;

  const _StepRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.done = false,
    this.highlighted = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final fade = done && !highlighted;
    return Opacity(
      opacity: fade ? 0.45 : 1,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: highlighted ? AppColors.primarySoft : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500)),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.outline),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(badge!, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ),
                  ],
                ]),
                if (subtitle != null)
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: _meta),
              ],
            ),
          ),
          if (trailing != null)
            Text(trailing!,
                style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, fontFeatures: tabularFigures)),
        ]),
      ),
    );
  }
}

/// 案内中の下のシート。残りの時間・距離・到着時刻と「終了」。
class NavigatingSheet extends StatelessWidget {
  final NavigationController controller;
  final bool expanded;
  final VoidCallback onToggleSteps;
  final VoidCallback onEnd;

  const NavigatingSheet({
    super.key,
    required this.controller,
    required this.expanded,
    required this.onToggleSteps,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final seconds = c.remainingSeconds;
    final meters = c.remainingTotalMeters;
    final floorsLeft = c.routeLabels.length - 1 - c.routeLabels.indexOf(c.trackerLabel);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: onToggleSteps,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        seconds == null ? '—' : formatMinutes(seconds),
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success,
                            height: 1.15,
                            fontFeatures: tabularFigures),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (meters != null) formatMeters(meters),
                          if (seconds != null) formatArrival(seconds),
                          if (floorsLeft > 0) 'あと $floorsLeft 階',
                        ].join('  ·  '),
                        style: _meta.copyWith(fontFeatures: tabularFigures),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: expanded ? '手順をたたむ' : '手順を見る',
              onPressed: onToggleSteps,
              style: IconButton.styleFrom(backgroundColor: AppColors.surfaceDim),
              icon: Icon(expanded ? Icons.expand_more : Icons.format_list_bulleted,
                  color: AppColors.textSecondary),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('end-navigation'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                minimumSize: const Size(72, 44),
              ),
              onPressed: onEnd,
              child: const Text('終了'),
            ),
          ]),
          if (expanded) ...[
            const Divider(height: 16),
            StepsList(controller: controller),
          ],
        ],
      ),
    );
  }
}

class ArrivedSheet extends StatelessWidget {
  final String placeName;
  final VoidCallback onDone;
  const ArrivedSheet({super.key, required this.placeName, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sports_score, color: AppColors.success, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('到着しました',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.success)),
                  Text(placeName, maxLines: 2, overflow: TextOverflow.ellipsis, style: _title),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              key: const ValueKey('finish-navigation'),
              onPressed: onDone,
              child: const Text('完了'),
            ),
          ),
        ],
      ),
    );
  }
}

// lib/ui/widgets/map_overlays.dart
//
// 地図の上に浮かべる小さな部品たち。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../config.dart';
import '../../navigation/suggestion_policy.dart';
import '../place_category.dart';
import '../theme.dart';

/// 浮いて見える白いカードの影。地図の上に置く部品はすべてこれを使う。
const List<BoxShadow> floatingShadow = [
  BoxShadow(color: Color(0x29000000), blurRadius: 6, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 6)),
];

/// 上端の検索欄。タップで検索画面を開く。
class MapSearchBar extends StatelessWidget {
  final VoidCallback onMenu;
  final VoidCallback onSearch;
  final VoidCallback onScan;

  /// 欄に薄く出す文。
  final String hint;

  const MapSearchBar({
    super.key,
    required this.onMenu,
    required this.onSearch,
    required this.onScan,
    this.hint = '場所・部屋を検索',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: floatingShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onSearch,
          child: Row(children: [
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'メニュー',
              icon: const Icon(Icons.menu, color: AppColors.textSecondary),
              onPressed: onMenu,
            ),
            Expanded(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 16, color: AppColors.textSecondary, height: 1.2),
              ),
            ),
            Container(width: 1, height: 24, color: AppColors.divider),
            IconButton(
              key: const ValueKey('scan-qr'),
              tooltip: 'QRコードで現在地を設定',
              icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary),
              onPressed: onScan,
            ),
            const SizedBox(width: 4),
          ]),
        ),
      ),
    );
  }
}

/// 検索欄の下に並ぶ分類のチップ（トイレ・階段…）。
class CategoryChipsRow extends StatelessWidget {
  final List<PlaceCategory> categories;
  final void Function(PlaceCategory) onTap;

  const CategoryChipsRow(
      {super.key, required this.categories, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = categories[i];
          return Center(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 3,
                      offset: Offset(0, 1)),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(17),
                  onTap: () => onTap(cat),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(cat.icon, size: 18, color: cat.accent),
                      const SizedBox(width: 6),
                      Text(cat.label,
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.text)),
                    ]),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 右端の階の切り替え。上の階ほど上に並ぶ。
///
/// 自分のいる階には青い点、目的地のある階には赤い点をつける。
/// 経路が通る階は文字を青くする。
class FloorPicker extends StatelessWidget {
  final List<MapSection> floors;
  final String current;
  final String? userLabel;
  final String? goalLabel;
  final Set<String> routeLabels;
  final void Function(String label) onSelect;

  /// 建物が複数あるときの建物名。タップで建物を選び直す。
  final String? buildingName;
  final VoidCallback? onBuildingTap;

  const FloorPicker({
    super.key,
    required this.floors,
    required this.current,
    required this.onSelect,
    this.userLabel,
    this.goalLabel,
    this.routeLabels = const {},
    this.buildingName,
    this.onBuildingTap,
  });

  @override
  Widget build(BuildContext context) {
    final ordered = floors.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (buildingName != null) ...[
          _BuildingChip(name: buildingName!, onTap: onBuildingTap),
          const SizedBox(height: 8),
        ],
        Container(
          width: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: floatingShadow,
          ),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in ordered)
                _FloorButton(
                  key: ValueKey('floor-${f.label}'),
                  text: f.floorDisplayName,
                  selected: f.label == current,
                  onRoute: routeLabels.contains(f.label),
                  hasUser: f.label == userLabel,
                  hasGoal: f.label == goalLabel,
                  onTap: () => onSelect(f.label),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FloorButton extends StatelessWidget {
  final String text;
  final bool selected;
  final bool onRoute;
  final bool hasUser;
  final bool hasGoal;
  final VoidCallback onTap;

  const _FloorButton({
    super.key,
    required this.text,
    required this.selected,
    required this.onRoute,
    required this.hasUser,
    required this.hasGoal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Colors.white
        : (onRoute ? AppColors.primary : AppColors.textSecondary);
    return Semantics(
      button: true,
      selected: selected,
      label: '$text を表示',
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: 48,
          height: 44,
          child: Stack(alignment: Alignment.center, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
            Text(
              text,
              style: TextStyle(
                fontSize: text.length > 2 ? 11.5 : 14,
                fontWeight: selected || onRoute ? FontWeight.w700 : FontWeight.w500,
                color: color,
                fontFeatures: tabularFigures,
              ),
            ),
            if (hasUser)
              const Positioned(
                  left: 6, top: 8, child: _Dot(color: AppColors.userDot)),
            if (hasGoal)
              const Positioned(
                  right: 6, top: 8, child: _Dot(color: AppColors.destination)),
          ]),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
      );
}

class _BuildingChip extends StatelessWidget {
  final String name;
  final VoidCallback? onTap;
  const _BuildingChip({required this.name, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const StadiumBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          decoration: const ShapeDecoration(
              shape: StadiumBorder(), shadows: floatingShadow, color: Colors.white),
          padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.apartment, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(name,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text)),
            const Icon(Icons.arrow_drop_down,
                size: 18, color: AppColors.textSecondary),
          ]),
        ),
      ),
    );
  }
}

/// 地図の右下に置く丸いボタン。
class RoundMapButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final Color background;

  const RoundMapButton({
    super.key,
    required this.child,
    required this.onPressed,
    required this.tooltip,
    this.size = 52,
    this.background = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          boxShadow: floatingShadow,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// 地図が回っているときだけ出る方位磁針。タップで北を上に戻す。
class CompassButton extends StatelessWidget {
  final double bearing;
  final VoidCallback onPressed;
  const CompassButton({super.key, required this.bearing, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return RoundMapButton(
      tooltip: '北を上にする',
      size: 44,
      onPressed: onPressed,
      child: Transform.rotate(
        angle: -bearing,
        child: const CustomPaint(size: Size(22, 22), painter: _NeedlePainter()),
      ),
    );
  }
}

class _NeedlePainter extends CustomPainter {
  const _NeedlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final w = size.width * 0.26, h = size.height / 2;
    final north = Path()
      ..moveTo(c.dx, c.dy - h)
      ..lineTo(c.dx + w, c.dy)
      ..lineTo(c.dx - w, c.dy)
      ..close();
    final south = Path()
      ..moveTo(c.dx, c.dy + h)
      ..lineTo(c.dx + w, c.dy)
      ..lineTo(c.dx - w, c.dy)
      ..close();
    canvas.drawPath(north, Paint()..color = AppColors.destination);
    canvas.drawPath(south, Paint()..color = const Color(0xFFBDC1C6));
  }

  @override
  bool shouldRepaint(_NeedlePainter old) => false;
}

/// 提案（階を移動した？ 建物に着いた？）のカード。
/// 歩きながら見るので、画面を塞がずに上に浮かべる。
class SuggestionCard extends StatelessWidget {
  final Suggestion suggestion;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const SuggestionCard({
    super.key,
    required this.suggestion,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final icon = suggestion.kind == SuggestionKind.floorChange
        ? Icons.stairs
        : Icons.apartment;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: floatingShadow,
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                  color: AppColors.warningSoft, shape: BoxShape.circle),
              child: Icon(icon, color: const Color(0xFFB06000), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(suggestion.title,
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(suggestion.message,
                      style: const TextStyle(
                          fontSize: 13.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: onDismiss, child: const Text('あとで')),
            TextButton(onPressed: onAccept, child: const Text('切り替える')),
          ]),
        ],
      ),
    );
  }
}

/// 画面下に一瞬出る知らせ。
class ToastView extends StatelessWidget {
  final String text;
  final bool error;
  const ToastView({super.key, required this.text, this.error = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFB3261E) : const Color(0xF0303134),
        borderRadius: BorderRadius.circular(12),
        boxShadow: floatingShadow,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Flexible(
          child: Text(text,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, height: 1.35)),
        ),
      ]),
    );
  }
}

/// 子の大きさが変わったら知らせる。地図の余白（シートの高さなど）を
/// 実際の見た目に合わせるのに使う。
class MeasureSize extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onChange;
  const MeasureSize({super.key, required this.onChange, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMeasureSize).onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  ValueChanged<Size> onChange;
  Size? _last;
  _RenderMeasureSize(this.onChange);

  @override
  void performLayout() {
    super.performLayout();
    final s = size;
    if (s == _last) return;
    _last = s;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(s));
  }
}

/// シート上端のつまみ。
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFDADCE0),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// 色つきの丸にアイコン。一覧の先頭などに使う。
class CategoryAvatar extends StatelessWidget {
  final PlaceCategory category;
  final double size;
  const CategoryAvatar({super.key, required this.category, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: category.accent.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(category.icon,
            color: category.accent, size: math.max(16, size * 0.5)),
      );
}

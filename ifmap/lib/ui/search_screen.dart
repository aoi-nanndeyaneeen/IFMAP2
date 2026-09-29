// lib/ui/search_screen.dart
//
// 場所の検索。全フロアの部屋から探し、選んだ場所（PlaceRef）を返す。
//
// 並び順は「近い順」。出発地と同じフロアは徒歩距離で、ほかのフロアは
// その後ろにフロア順で並べる。同じ名前の部屋がフロアごとにあるので、
// 必ずフロアを添えて出す（名前だけで返すと別の階へ案内してしまう）。
import 'package:flutter/material.dart';

import '../config.dart';
import '../data/map_data.dart';
import '../navigation/navigation_controller.dart';
import 'format.dart';
import 'place_category.dart';
import 'theme.dart';
import 'widgets/map_overlays.dart';

class PlaceSearchScreen extends StatefulWidget {
  final NavigationController controller;
  final PlaceCategory? initialCategory;

  /// 現在地を選ぶための検索か（見出しと案内が変わる）。
  final bool pickingStart;

  const PlaceSearchScreen({
    super.key,
    required this.controller,
    this.initialCategory,
    this.pickingStart = false,
  });

  @override
  State<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _Entry {
  final PlaceRef place;
  final String title;
  final String normalized;
  final PlaceCategory category;
  final double? meters;
  final int floorOrder;
  _Entry(this.place, this.title, this.normalized, this.category, this.meters,
      this.floorOrder);
}

class _PlaceSearchScreenState extends State<PlaceSearchScreen> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  PlaceCategory? _category;
  late final List<_Entry> _all;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    final c = widget.controller;
    final labels = AppConfig.mapSections.map((s) => s.label).toList();
    _all = [
      for (final p in c.repo.destinations())
        _Entry(
          p,
          displayPlaceName(p.name),
          normalizeForSearch(p.name),
          PlaceCategories.of(p.name),
          c.walkingMetersTo(p),
          labels.indexOf(p.label),
        ),
      // 階段は目的地一覧には入っていないが、探したいことが多い。
      for (final label in c.repo.labels)
        for (final name in _stairsNames(label))
          _Entry(
            PlaceRef(name, label),
            displayPlaceName(name),
            normalizeForSearch(name),
            PlaceCategories.stairs,
            c.walkingMetersTo(PlaceRef(name, label)),
            labels.indexOf(label),
          ),
    ];
    if (_category == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  Iterable<String> _stairsNames(String label) {
    final floor = widget.controller.repo.floor(label);
    if (floor == null) return const [];
    return floor.entryIdByName.keys.where((n) {
      if (floor.destinationNames.contains(n)) return false;
      final node = floor.nodes[floor.entryIdByName[n]];
      return node is Map && node['isStairs'] == true;
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<_Entry> _results() {
    final q = normalizeForSearch(_query.text.trim());
    final start = widget.controller.start;
    final out = _all.where((e) {
      if (e.place == start && !widget.pickingStart) return false;
      if (_category != null && e.category.kind != _category!.kind) return false;
      return q.isEmpty || e.normalized.contains(q);
    }).toList();
    out.sort((a, b) {
      // 出発地のフロアで距離が分かるものを先に、近い順。
      final am = a.meters, bm = b.meters;
      if (am != null && bm != null) return am.compareTo(bm);
      if (am != null) return -1;
      if (bm != null) return 1;
      // 検索語で始まるものを先に。
      if (q.isNotEmpty) {
        final as = a.normalized.startsWith(q), bs = b.normalized.startsWith(q);
        if (as != bs) return as ? -1 : 1;
      }
      final f = a.floorOrder.compareTo(b.floorOrder);
      return f != 0 ? f : a.title.compareTo(b.title);
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final results = _results();
    final showCategories = _query.text.isEmpty && _category == null;
    final multipleBuildings =
        AppConfig.mapSections.map((s) => s.buildingName).toSet().length > 1;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
            child: Row(children: [
              IconButton(
                tooltip: '戻る',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDim,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('search-field'),
                        controller: _query,
                        focusNode: _focus,
                        textInputAction: TextInputAction.search,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 16),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: widget.pickingStart
                              ? 'いまいる場所を検索'
                              : '部屋名・番号で検索（例: 211）',
                          hintStyle: const TextStyle(color: AppColors.textTertiary),
                        ),
                      ),
                    ),
                    if (_query.text.isNotEmpty)
                      IconButton(
                        tooltip: '消す',
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => setState(_query.clear),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
          if (widget.pickingStart)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Row(children: [
                Icon(Icons.my_location, size: 18, color: AppColors.primary),
                SizedBox(width: 8),
                Text('現在地にする場所を選んでください',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
              ]),
            ),
          if (_category != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: Icon(_category!.icon, size: 18, color: _category!.accent),
                  label: Text(_category!.label),
                  onDeleted: () => setState(() => _category = null),
                  deleteIcon: const Icon(Icons.close, size: 18),
                ),
              ),
            ),
          if (showCategories)
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _presentCategories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final cat = _presentCategories[i];
                  return ActionChip(
                    avatar: Icon(cat.icon, size: 18, color: cat.accent),
                    label: Text(cat.label),
                    onPressed: () => setState(() => _category = cat),
                  );
                },
              ),
            ),
          const Divider(),
          Expanded(
            child: results.isEmpty
                ? _Empty(query: _query.text)
                : ListView.builder(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: results.length,
                    itemBuilder: (_, i) => _ResultTile(
                      entry: results[i],
                      query: _query.text.trim(),
                      showBuilding: multipleBuildings,
                      onTap: () => Navigator.pop(context, results[i].place),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }

  List<PlaceCategory> get _presentCategories {
    final kinds = _all.map((e) => e.category.kind).toSet();
    return [for (final c in PlaceCategories.browsable) if (kinds.contains(c.kind)) c];
  }
}

class _ResultTile extends StatelessWidget {
  final _Entry entry;
  final String query;
  final bool showBuilding;
  final VoidCallback onTap;

  const _ResultTile({
    required this.entry,
    required this.query,
    required this.showBuilding,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final section = AppConfig.sectionOf(entry.place.label);
    final floor = section?.floorDisplayName ?? entry.place.label;
    final where = showBuilding && section != null ? '$floor · ${section.buildingName}' : floor;
    final meters = entry.meters;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(children: [
          CategoryAvatar(category: entry.category),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Highlighted(text: entry.title, query: query),
                const SizedBox(height: 2),
                Text('${entry.category.label} · $where',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (meters != null)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatMeters(meters),
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600, fontFeatures: tabularFigures)),
              Text(formatMinutes(meters / AppConfig.walkingSpeed),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ])
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(floor,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ),
        ]),
      ),
    );
  }
}

/// 検索語に一致した部分を太字にする。表記ゆれ（全角・ひらがな）も考える。
class _Highlighted extends StatelessWidget {
  final String text;
  final String query;
  const _Highlighted({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(fontSize: 15.5, color: AppColors.text, fontWeight: FontWeight.w500);
    final q = normalizeForSearch(query);
    if (q.isEmpty) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: base);
    }
    // 1文字ずつ正規化して位置を対応づける。
    final chars = text.characters.toList();
    final norm = chars.map(normalizeForSearch).toList();
    final joined = norm.join();
    final hit = joined.indexOf(q);
    if (hit < 0) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: base);
    }
    var pos = 0;
    final spans = <TextSpan>[];
    for (var i = 0; i < chars.length; i++) {
      final inHit = pos < hit + q.length && pos + norm[i].length > hit;
      spans.add(TextSpan(
        text: chars[i],
        style: inHit ? const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryDark) : null,
      ));
      pos += norm[i].length;
    }
    return Text.rich(TextSpan(style: base, children: spans),
        maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

class _Empty extends StatelessWidget {
  final String query;
  const _Empty({required this.query});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.search_off, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(query.isEmpty ? '場所がありません' : '「$query」は見つかりませんでした',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          ]),
        ),
      );
}

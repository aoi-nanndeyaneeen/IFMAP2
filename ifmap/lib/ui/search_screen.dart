// lib/ui/search_screen.dart
//
// 場所の検索。全フロアの部屋から探し、選んだ場所（PlaceRef）を返す。
//
// 探し方は3通り。
//   建物から … 区域（校舎・学寮…）→ 建物 → 階ごとの部屋、と絞っていく。
//              初めての場所で「どの建物か」から分かる人向け。
//   名前から … 文字を入れると全部の部屋から探す（建物名にも一致する）。
//   種類から … トイレ・階段などの分類。
//
// 並び順は「近い順」。出発地と同じフロアは徒歩距離で、ほかのフロアは
// その後ろにフロア順で並べる。同じ名前の部屋が建物ごとにあるので、
// 必ず建物と階を添えて出す（名前だけで返すと別の場所へ案内してしまう）。
import 'package:flutter/material.dart';

import '../config.dart';
import '../data/campus_index.dart';
import '../data/map_data.dart';
import '../navigation/navigation_controller.dart';
import 'format.dart';
import 'place_category.dart';
import 'theme.dart';
import 'widgets/map_overlays.dart';

class PlaceSearchScreen extends StatefulWidget {
  final NavigationController controller;
  final PlaceCategory? initialCategory;

  /// 最初から開いておく建物。
  final String? initialBuilding;

  /// 現在地を選ぶための検索か（見出しと案内が変わる）。
  final bool pickingStart;

  const PlaceSearchScreen({
    super.key,
    required this.controller,
    this.initialCategory,
    this.initialBuilding,
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
  final IndexedBuilding? building;
  final String floor;
  final double? meters;
  final int floorOrder;
  _Entry(this.place, this.title, this.normalized, this.category, this.building,
      this.floor, this.meters, this.floorOrder);
}

class _PlaceSearchScreenState extends State<PlaceSearchScreen> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  PlaceCategory? _category;
  IndexedBuilding? _building;
  late final List<_Entry> _all;

  NavigationController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    final campus = _c.campus;
    if (widget.initialBuilding != null) {
      for (final a in campus.visibleAreas) {
        for (final b in a.buildings) {
          if (b.name == widget.initialBuilding) _building = b;
        }
      }
    }
    final labels = AppConfig.mapSections.map((s) => s.label).toList();
    final seen = <PlaceRef>{};
    final all = <_Entry>[];

    void add(PlaceRef p, {String? shortName, PlaceCategory? category}) {
      if (!seen.add(p)) return;
      final b = campus.buildingOf(p);
      final title = displayPlaceName(shortName ?? campus.roomNameOf(p) ?? p.name);
      final floor = AppConfig.floorNameOf(p.label);
      all.add(_Entry(
        p,
        title,
        // 部屋の名前に加えて、建物名・元の名前でも探せるようにする。
        normalizeForSearch('$title ${p.name} ${b?.name ?? ''}'),
        category ?? PlaceCategories.of(shortName ?? campus.roomNameOf(p) ?? p.name),
        b,
        floor,
        _c.walkingMetersTo(p),
        labels.indexOf(p.label),
      ));
    }

    for (final p in _c.repo.destinations()) {
      add(p);
    }
    // 階段は目的地一覧には入っていないが、探したいことが多い。
    for (final label in _c.repo.labels) {
      for (final name in _stairsNames(label)) {
        add(PlaceRef(name, label), category: PlaceCategories.stairs);
      }
    }
    // 索引にあって上に出てこなかった部屋（念のため）。
    for (final a in campus.visibleAreas) {
      for (final b in a.buildings) {
        for (final r in b.rooms) {
          add(r.place, shortName: r.name);
        }
      }
    }
    _all = all;
  }

  Iterable<String> _stairsNames(String label) {
    final floor = _c.repo.floor(label);
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
    final start = _c.start;
    final out = _all.where((e) {
      if (e.place == start && !widget.pickingStart) return false;
      if (_building != null && e.building != _building) return false;
      if (_category != null && e.category.kind != _category!.kind) return false;
      return q.isEmpty || e.normalized.contains(q);
    }).toList();
    out.sort((a, b) {
      // 建物の中では階の順に並べる（階ごとの見出しを付けるため）。
      if (_building != null) {
        final f = a.floorOrder.compareTo(b.floorOrder);
        if (f != 0) return f;
      }
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

  /// 戻る操作。建物を開いていればまず建物の一覧へ戻る。
  void _back() {
    if (_building != null && widget.initialBuilding == null) {
      setState(() {
        _building = null;
        _query.clear();
      });
    } else {
      Navigator.pop(context);
    }
  }

  void _openBuilding(IndexedBuilding b) {
    final self = b.self;
    if (self != null && b.roomCount == 0) {
      Navigator.pop(context, self);
      return;
    }
    setState(() {
      _building = b;
      _category = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final browsing =
        _query.text.isEmpty && _category == null && _building == null;
    return PopScope(
      canPop: _building == null || widget.initialBuilding != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(children: [
            _buildSearchField(),
            if (widget.pickingStart) _buildPickingHint(),
            if (_building != null || _category != null) _buildFilterChips(),
            if (browsing) _buildCategoryRow(),
            const Divider(),
            Expanded(child: browsing ? _buildBuildingList() : _buildResults()),
          ]),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
      child: Row(children: [
        IconButton(
          tooltip: '戻る',
          icon: const Icon(Icons.arrow_back),
          onPressed: _back,
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
                    hintText: _building != null
                        ? '${_building!.name}の中で探す'
                        : (widget.pickingStart
                            ? 'いまいる場所を検索'
                            : '部屋名・建物名で検索（例: 211）'),
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
    );
  }

  Widget _buildPickingHint() => const Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
        child: Row(children: [
          Icon(Icons.my_location, size: 18, color: AppColors.primary),
          SizedBox(width: 8),
          Text('現在地にする場所を選んでください',
              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(spacing: 8, runSpacing: 4, children: [
          if (_building != null)
            InputChip(
              key: const ValueKey('building-chip'),
              avatar: const Icon(Icons.apartment, size: 18, color: AppColors.textSecondary),
              label: Text(_building!.name),
              onDeleted: () => setState(() => _building = null),
              deleteIcon: const Icon(Icons.close, size: 18),
            ),
          if (_category != null)
            InputChip(
              avatar: Icon(_category!.icon, size: 18, color: _category!.accent),
              label: Text(_category!.label),
              onDeleted: () => setState(() => _category = null),
              deleteIcon: const Icon(Icons.close, size: 18),
            ),
        ]),
      ),
    );
  }

  List<PlaceCategory> get _presentCategories {
    final kinds = _all.map((e) => e.category.kind).toSet();
    return [for (final c in PlaceCategories.browsable) if (kinds.contains(c.kind)) c];
  }

  Widget _buildCategoryRow() {
    return SizedBox(
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
    );
  }

  // ─── 建物の一覧 ──────────────────────────────────────────────

  Widget _buildBuildingList() {
    final areas = _c.campus.visibleAreas;
    if (areas.isEmpty) return _buildResults();
    final here = _c.start == null ? null : _c.campus.buildingOf(_c.start!);

    return ListView(
      key: const ValueKey('building-list'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text('建物から探す',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        ),
        for (final area in areas) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
            child: Text(area.name,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          ),
          for (final b in area.buildings)
            _BuildingTile(
              building: b,
              isHere: b == here,
              onTap: () => _openBuilding(b),
            ),
        ],
      ],
    );
  }

  // ─── 結果 ───────────────────────────────────────────────────

  Widget _buildResults() {
    final results = _results();
    if (results.isEmpty) return _Empty(query: _query.text);
    final multipleBuildings = _c.campus.visibleAreas.length > 1 ||
        AppConfig.mapSections.map((s) => s.buildingName).toSet().length > 1;

    // 建物の中では階ごとに見出しを付ける。
    final items = <Object>[];
    String? lastFloor;
    for (final e in results) {
      if (_building != null && e.floor != lastFloor) {
        items.add(e.floor);
        lastFloor = e.floor;
      }
      items.add(e);
    }

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        if (item is String) return _FloorHeader(item);
        final e = item as _Entry;
        return _ResultTile(
          entry: e,
          query: _query.text.trim(),
          showBuilding: multipleBuildings && _building == null,
          onTap: () => Navigator.pop(context, e.place),
        );
      },
    );
  }
}

class _BuildingTile extends StatelessWidget {
  final IndexedBuilding building;
  final bool isHere;
  final VoidCallback onTap;
  const _BuildingTile({required this.building, required this.isHere, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final floors = building.roomsByFloor.keys.toList();
    final detail = building.roomCount == 0
        ? '地図上の場所'
        : '${floors.join(' · ')}  ·  ${building.roomCount} か所';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceDim,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.apartment, color: AppColors.textSecondary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(building.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500)),
                ),
                if (isHere) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('現在地',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ),
                ],
              ]),
              const SizedBox(height: 1),
              Text(detail,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ]),
          ),
          Icon(building.roomCount == 0 ? Icons.place_outlined : Icons.chevron_right,
              color: AppColors.textTertiary),
        ]),
      ),
    );
  }
}

class _FloorHeader extends StatelessWidget {
  final String floor;
  const _FloorHeader(this.floor);

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: AppColors.surfaceDim,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Text(floor,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
      );
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
    final floor = entry.floor;
    final buildingName = entry.building?.name ?? section?.buildingName;
    final where = showBuilding && buildingName != null ? '$buildingName · $floor' : floor;
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

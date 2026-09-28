import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/routing/route_planner.dart';

Map<String, dynamic> _node(int x, int y, List<String> edges,
        [Map<String, dynamic> extra = const {}]) =>
    {'x': x * 10, 'y': y * 10, 'edges': edges, ...extra};

/// 1F: start -- stair1F
/// 2F: stair2F -- goal
/// 階段は両フロアで同じ name ('階段A') を持たせて対応づける。
Map<String, Map<String, dynamic>> _twoFloorsWithStairs() => {
      'F1': {
        'start': _node(0, 0, ['s1']),
        's1': _node(1, 0, ['start'], {'isStairs': true, 'name': '階段A'}),
      },
      'F2': {
        's2': _node(1, 0, ['goal'], {'isStairs': true, 'name': '階段A'}),
        'goal': _node(2, 0, ['s2']),
      },
    };

void main() {
  const labels = ['F1', 'F2', 'F3'];

  group('同一フロア', () {
    test('そのフロアの経路だけを返す', () {
      final result = RoutePlanner.plan(RoutePlanRequest(
        nodesByLabel: {
          'F1': {
            'a': _node(0, 0, ['b']),
            'b': _node(1, 0, ['a']),
          }
        },
        sectionLabels: labels,
        startId: 'a',
        goalId: 'b',
        startLabel: 'F1',
        goalLabel: 'F1',
      ));
      expect(result.keys, ['F1']);
      expect(result['F1'], ['a', 'b']);
    });
  });

  group('階をまたぐ', () {
    test('名前の一致する階段を経由して両フロアの経路を返す', () {
      final result = RoutePlanner.plan(RoutePlanRequest(
        nodesByLabel: _twoFloorsWithStairs(),
        sectionLabels: labels,
        startId: 'start',
        goalId: 'goal',
        startLabel: 'F1',
        goalLabel: 'F2',
      ));
      expect(result['F1'], ['start', 's1']);
      expect(result['F2'], ['s2', 'goal']);
    });

    test('下りも同じように扱える', () {
      final result = RoutePlanner.plan(RoutePlanRequest(
        nodesByLabel: _twoFloorsWithStairs(),
        sectionLabels: labels,
        startId: 'goal',
        goalId: 'start',
        startLabel: 'F2',
        goalLabel: 'F1',
      ));
      expect(result['F2'], ['goal', 's2']);
      expect(result['F1'], ['s1', 'start']);
    });

    test('接続点があれば階段より優先する', () {
      final nodes = {
        'F1': {
          'start': _node(0, 0, ['c1', 's1']),
          'c1': _node(1, 0, ['start'],
              {'isConnector': true, 'name': '渡り廊下', 'connectsToMap': 'F2'}),
          's1': _node(0, 1, ['start'], {'isStairs': true, 'name': '階段A'}),
        },
        'F2': {
          'c2': _node(1, 0, ['goal'],
              {'isConnector': true, 'name': '渡り廊下', 'connectsToMap': 'F1'}),
          's2': _node(0, 1, <String>[], {'isStairs': true, 'name': '階段A'}),
          'goal': _node(2, 0, ['c2']),
        },
      };
      final result = RoutePlanner.plan(RoutePlanRequest(
        nodesByLabel: nodes,
        sectionLabels: labels,
        startId: 'start',
        goalId: 'goal',
        startLabel: 'F1',
        goalLabel: 'F2',
      ));
      expect(result['F1']!.last, 'c1');
      expect(result['F2']!.first, 'c2');
    });

    test('3フロア分を通しで組み立てる', () {
      final nodes = {
        'F1': {
          'start': _node(0, 0, ['a1']),
          'a1': _node(1, 0, ['start'], {'isStairs': true, 'name': '階段A'}),
        },
        'F2': {
          'a2': _node(1, 0, ['b2'], {'isStairs': true, 'name': '階段A'}),
          'b2': _node(2, 0, ['a2'], {'isStairs': true, 'name': '階段B'}),
        },
        'F3': {
          'b3': _node(2, 0, ['goal'], {'isStairs': true, 'name': '階段B'}),
          'goal': _node(3, 0, ['b3']),
        },
      };
      final result = RoutePlanner.plan(RoutePlanRequest(
        nodesByLabel: nodes,
        sectionLabels: labels,
        startId: 'start',
        goalId: 'goal',
        startLabel: 'F1',
        goalLabel: 'F3',
      ));
      expect(result.keys.toSet(), {'F1', 'F2', 'F3'});
      expect(result['F2'], ['a2', 'b2']);
      expect(result['F3']!.last, 'goal');
    });

    test('階段も接続点もなければ途中で打ち切る', () {
      final result = RoutePlanner.plan(RoutePlanRequest(
        nodesByLabel: {
          'F1': {'start': _node(0, 0, <String>[])},
          'F2': {'goal': _node(0, 0, <String>[])},
        },
        sectionLabels: labels,
        startId: 'start',
        goalId: 'goal',
        startLabel: 'F1',
        goalLabel: 'F2',
      ));
      expect(result, isEmpty);
    });
  });

  group('trimmed', () {
    test('出発フロアと目的フロアの間だけを残す', () {
      final request = RoutePlanRequest(
        nodesByLabel: {
          'F1': {'a': _node(0, 0, <String>[])},
          'F2': {'b': _node(0, 0, <String>[])},
          'F3': {'c': _node(0, 0, <String>[])},
        },
        sectionLabels: labels,
        startId: 'a',
        goalId: 'b',
        startLabel: 'F1',
        goalLabel: 'F2',
      );
      final trimmed = request.trimmed();
      expect(trimmed.nodesByLabel.keys.toSet(), {'F1', 'F2'});
      expect(trimmed.sectionLabels, ['F1', 'F2']);
    });

    test('往復してもメッセージ経由で同じ結果になる', () {
      final request = RoutePlanRequest(
        nodesByLabel: _twoFloorsWithStairs(),
        sectionLabels: labels,
        startId: 'start',
        goalId: 'goal',
        startLabel: 'F1',
        goalLabel: 'F2',
      );
      final direct = RoutePlanner.plan(request);
      final viaMessage =
          RoutePlanner.planFromMessage(request.trimmed().toMessage());
      expect(viaMessage, direct);
    });
  });

  group('connectorsTo / matchingStairs', () {
    test('行き先の一致する接続点だけを拾う', () {
      final nodes = {
        'ok': _node(0, 0, <String>[], {'isConnector': true, 'connectsToMap': 'F2'}),
        'other': _node(1, 0, <String>[], {'isConnector': true, 'connectsToMap': 'F9'}),
        'plain': _node(2, 0, <String>[]),
      };
      expect(RoutePlanner.connectorsTo(nodes, 'F2'), {'ok'});
    });

    test('両フロアに同じ名前がある階段だけを候補にする', () {
      final from = {
        'sA': _node(0, 0, <String>[], {'isStairs': true, 'name': 'A'}),
        'sB': _node(1, 0, <String>[], {'isStairs': true, 'name': 'B'}),
      };
      final to = {
        'tA': _node(0, 0, <String>[], {'isStairs': true, 'name': 'A'}),
      };
      expect(RoutePlanner.matchingStairs(from, to), {'sA'});
    });

    test('名前が一致しなければ自フロアの階段を全部候補にする', () {
      final from = {
        'sA': _node(0, 0, <String>[], {'isStairs': true, 'name': 'A'}),
        'sB': _node(1, 0, <String>[], {'isStairs': true, 'name': 'B'}),
      };
      expect(RoutePlanner.matchingStairs(from, const {}), {'sA', 'sB'});
    });
  });
}

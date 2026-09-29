import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap_editor/map_editor_controller.dart';
import 'package:ifmap_editor/qr_tools.dart';

void main() {
  group('QrTools', () {
    test('IDは6文字で、読み間違えやすい文字を含まない', () {
      for (var i = 0; i < 200; i++) {
        final id = QrTools.newId(const []);
        expect(id, hasLength(6));
        expect(id, isNot(contains(RegExp('[lo01]'))));
      }
    });

    test('既存のIDとは重ならない', () {
      final used = <String>{};
      for (var i = 0; i < 500; i++) {
        final id = QrTools.newId(used);
        expect(used.add(id), isTrue);
      }
    });

    test('URLは ?qr=<ID> の形', () {
      expect(QrTools.urlOf('ab2cde'), endsWith('?qr=ab2cde'));
    });
  });

  group('読み込み', () {
    test('_editorData の qrId / qrMemo がマスに戻る', () {
      final ctrl = MapEditorController();
      ctrl.loadFromEditorData({
        'rows': 3,
        'cols': 3,
        'cells': [
          {'x': 1, 'y': 1, 'type': 1, 'qrId': 'ab2cde', 'qrMemo': '1F中央階段前'},
          {'x': 2, 'y': 1, 'type': 1},
        ],
      }, 'map.json');

      expect(ctrl.qrCells, hasLength(1));
      final c = ctrl.qrCells.single;
      expect((c.x, c.y), (1, 1));
      expect(c.qrId, 'ab2cde');
      expect(c.qrMemo, '1F中央階段前');
    });

    test('元に戻すの履歴にも QR が残る', () {
      final ctrl = MapEditorController();
      ctrl.grid[0][0]
        ..type = 1
        ..qrId = 'ab2cde';
      final clone = ctrl.cloneGrid(ctrl.grid);
      expect(clone[0][0].qrId, 'ab2cde');
    });
  });
}

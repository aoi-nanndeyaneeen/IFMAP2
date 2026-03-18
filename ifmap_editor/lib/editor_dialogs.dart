import 'package:flutter/material.dart';
import 'input_handler.dart';
import 'map_editor_controller.dart';

class EditorDialogs {
  EditorDialogs._();

  /// 部屋名 / 階段名ダイアログ。確定した名前、キャンセル時は null を返す。
  static Future<String?> showName(
    BuildContext context,
    MapEditorController ctrl,
    int type, {
    String? initialName,
  }) async {
    final tc = TextEditingController(text: initialName ?? '');
    final label = type == 3 ? '部屋' : '階段';
    String? result;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$label名を入力'),
        content: TextField(
          controller: tc, autofocus: true,
          decoration: InputDecoration(hintText: type == 3 ? '例: 会議室101' : '例: 南階段'),
          onSubmitted: (v) => _submitName(context, v, ctrl, type, initialName, () => result = v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => _submitName(context, tc.text, ctrl, type, initialName, () => result = tc.text),
            child: const Text('決定'),
          ),
        ],
      ),
    );
    return result;
  }

  static void _submitName(BuildContext ctx, String v, MapEditorController ctrl,
      int type, String? oldName, VoidCallback onOk) {
    if (v.isEmpty) return;
    if (v != oldName && ctrl.isNameDuplicate(v, type)) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('エラー: 「$v」は既に存在します')));
      return;
    }
    onOk();
    Navigator.pop(ctx);
  }

  /// 接続点ダイアログ。確定時は ConnectorDialogResult、キャンセル時は null。
  static Future<ConnectorDialogResult?> showConnector(
    BuildContext context,
    MapEditorController ctrl, {
    String? initialName,
    String? initialMap,
    String? initialNode,
  }) async {
    final nc = TextEditingController(text: initialName ?? '');
    final mc = TextEditingController(text: initialMap  ?? '');
    final oc = TextEditingController(text: initialNode ?? '');
    ConnectorDialogResult? result;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('⇄ 接続点の設定'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nc, autofocus: true,
            decoration: const InputDecoration(labelText: 'このノードの名前')),
          const SizedBox(height: 8),
          TextField(controller: mc,
            decoration: const InputDecoration(labelText: '接続先マップのラベル', hintText: '例: 2F')),
          const SizedBox(height: 8),
          TextField(controller: oc,
            decoration: const InputDecoration(labelText: '接続先ノードID', hintText: '例: connector_from_1f')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () {
              if (nc.text.isEmpty) return;
              if (nc.text != initialName && ctrl.isNameDuplicate(nc.text, 5)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('エラー: 同じ名前が既に存在します')));
                return;
              }
              result = ConnectorDialogResult(
                name: nc.text,
                connectsToMap:  mc.text.isNotEmpty ? mc.text : null,
                connectsToNode: oc.text.isNotEmpty ? oc.text : null,
              );
              Navigator.pop(context);
            },
            child: const Text('決定'),
          ),
        ],
      ),
    );
    return result;
  }

  /// 別名保存ダイアログ。確定したファイル名、キャンセル時は null。
  static Future<String?> showSaveAs(
      BuildContext context, String currentFileName) async {
    final base = currentFileName.replaceAll('.json', '');
    final nc = TextEditingController(
      text: base.contains('_') ? base.substring(0, base.lastIndexOf('_')) : base);
    final fc = TextEditingController(
      text: base.contains('_') ? base.substring(base.lastIndexOf('_') + 1) : '');
    String? result;

    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('名前を設定して保存'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nc,
            decoration: const InputDecoration(labelText: '建物・キャンパス名 (例: 本館)')),
          TextField(controller: fc,
            decoration: const InputDecoration(labelText: '階数 (必須) (例: 1F, 2階)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('キャンセル')),
          ElevatedButton(onPressed: () {
            if (fc.text.isEmpty) {
              ScaffoldMessenger.of(c).showSnackBar(
                const SnackBar(content: Text('エラー: 階数を入力してください')));
              return;
            }
            result = '${nc.text}_${fc.text}.json';
            Navigator.pop(c);
          }, child: const Text('保存')),
        ],
      ),
    );
    return result;
  }
}
// ifmap_editor/lib/qr_tools.dart
//
// QRコード設置位置まわり。
//   ・IDの採番と、QRに埋め込むURLの組み立て
//   ・印刷用カード(PNG)の生成と保存
//   ・設置/編集ダイアログと一覧ダイアログ
//
// QRはマスの type とは独立した付加情報で、歩けるマスならどこにでも置ける。
// アプリ(ifmap)は URL の ?qr=<ID> からマスを引き、現在地を確定させる。
// 部屋の入口だけでなく、曲がり角・分岐・階段前など、歩数の誤差が
// 溜まりやすい場所に置くと効く。
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'config.dart';
import 'map_cell.dart';
import 'map_editor_controller.dart';
import 'platform_utils/file_saver.dart';

class QrTools {
  QrTools._();

  // 読み間違えやすい l / o / 0 / 1 は使わない。
  static const _idChars = 'abcdefghijkmnpqrstuvwxyz23456789';
  static final _random = Random.secure();

  /// 6文字のID。本当はフロアをまたいで一意にしたいが、エディタは
  /// 1フロアずつしか開かないので、確認できるのは同じフロア内だけ。
  /// 32^6 ≒ 10億通りあるので、フロア間で衝突する心配は実質ない。
  static String newId(Iterable<String> existing) {
    final used = existing.toSet();
    while (true) {
      final id = List.generate(
          6, (_) => _idChars[_random.nextInt(_idChars.length)]).join();
      if (!used.contains(id)) return id;
    }
  }

  static String urlOf(String id) => '${AppConfig.appBaseUrl}?qr=$id';

  static String _memoOrPlaceholder(String? memo) =>
      (memo == null || memo.isEmpty) ? '（メモなし）' : memo;

  /// 印刷用カード。白地にQRと設置場所のメモを載せる。
  static Future<Uint8List> renderCard(String id, String? memo) async {
    const qrSize = 600.0, pad = 40.0, textArea = 150.0;
    const w = qrSize + pad * 2, h = qrSize + pad * 2 + textArea;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
        const Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);

    canvas.save();
    canvas.translate(pad, pad);
    QrPainter(
      data: urlOf(id),
      version: QrVersions.auto,
      // 印刷して貼るので汚れや反射に少し強い M にする
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: true,
      eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square, color: Colors.black),
      dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square, color: Colors.black),
    ).paint(canvas, const Size(qrSize, qrSize));
    canvas.restore();

    final text = TextPainter(
      text: TextSpan(children: [
        TextSpan(
          text: '${_memoOrPlaceholder(memo)}\n',
          style: const TextStyle(
              fontSize: 40, fontWeight: FontWeight.bold, color: Colors.black),
        ),
        TextSpan(
          text: 'スキャンすると現在地が確定します  [$id]',
          style: const TextStyle(fontSize: 24, color: Colors.black54),
        ),
      ]),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w - pad * 2);
    text.paint(canvas, Offset((w - text.width) / 2, pad + qrSize + 24));
    text.dispose();

    final image =
        await recorder.endRecording().toImage(w.toInt(), h.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  static Future<void> saveCard(BuildContext context, MapCell cell) async {
    final id = cell.qrId;
    if (id == null) return;
    final png = await renderCard(id, cell.qrMemo);
    await getFileSaver().saveBytes('qr_$id.png', png, 'image/png');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('qr_$id.png を保存しました')));
    }
  }

  // ─── クリック時 ─────────────────────────────────────────────

  /// QRツールでマスをクリックした。置かれていなければ設置、
  /// 置かれていれば編集ダイアログを出す。
  static Future<void> handleClick(
    BuildContext context,
    MapEditorController ctrl,
    int y,
    int x,
  ) async {
    final cell = ctrl.grid[y][x];
    if (!cell.isWalkable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('QRコードは歩けるマス（通路・部屋・階段など）に置いてください')));
      return;
    }

    if (cell.qrId == null) {
      final memo = await _askMemo(context, title: 'QRコードを設置',
          initial: cell.name ?? '', confirmLabel: '設置');
      if (memo == null) return;
      ctrl.saveHistory();
      cell.qrId = newId(ctrl.qrCells.map((c) => c.qrId!));
      cell.qrMemo = memo.isEmpty ? null : memo;
      ctrl.notify();
      if (context.mounted) await _showEditor(context, ctrl, cell);
      return;
    }

    await _showEditor(context, ctrl, cell);
  }

  static Future<String?> _askMemo(
    BuildContext context, {
    required String title,
    required String initial,
    required String confirmLabel,
  }) {
    final tc = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: tc,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '設置場所のメモ',
            hintText: '例: 1F中央階段前',
            helperText: '印刷カードに載ります。空でも可',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, tc.text.trim()),
              child: Text(confirmLabel)),
        ],
      ),
    );
  }

  static Future<void> _showEditor(
      BuildContext context, MapEditorController ctrl, MapCell cell) {
    final id = cell.qrId!;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('QRコード [$id]'),
        content: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            QrImageView(
                data: urlOf(id),
                size: 200,
                errorCorrectionLevel: QrErrorCorrectLevel.M),
            const SizedBox(height: 8),
            Text(_memoOrPlaceholder(cell.qrMemo),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SelectableText(urlOf(id),
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
            Text('マス (${cell.x}, ${cell.y})',
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text('撤去', style: TextStyle(color: Colors.red)),
            onPressed: () {
              ctrl.saveHistory();
              cell.qrId = null;
              cell.qrMemo = null;
              ctrl.notify();
              Navigator.pop(ctx);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.edit_note),
            label: const Text('メモを変更'),
            onPressed: () async {
              final memo = await _askMemo(ctx, title: 'メモを変更',
                  initial: cell.qrMemo ?? '', confirmLabel: '変更');
              if (memo == null) return;
              ctrl.saveHistory();
              cell.qrMemo = memo.isEmpty ? null : memo;
              ctrl.notify();
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('URLをコピー'),
            onPressed: () => Clipboard.setData(ClipboardData(text: urlOf(id))),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('印刷用PNG'),
            onPressed: () => saveCard(ctx, cell),
          ),
        ],
      ),
    );
  }

  // ─── 一覧 ───────────────────────────────────────────────────

  static Future<void> showList(
      BuildContext context, MapEditorController ctrl) {
    final cells = ctrl.qrCells;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('QRコード一覧（${cells.length}件）'),
        content: SizedBox(
          width: 520,
          height: 480,
          child: cells.isEmpty
              ? const Center(
                  child: Text('まだありません。\n左のパレットの「QRコード設置」で'
                      '歩けるマスをクリックすると置けます。',
                      textAlign: TextAlign.center))
              : ListView.separated(
                  itemCount: cells.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = cells[i];
                    return ListTile(
                      leading: QrImageView(data: urlOf(c.qrId!), size: 56),
                      title: Text(_memoOrPlaceholder(c.qrMemo)),
                      subtitle: Text('[${c.qrId}]  マス (${c.x}, ${c.y})'
                          '${c.name != null ? '  ${c.name}' : ''}'),
                      trailing: IconButton(
                        tooltip: '印刷用PNG',
                        icon: const Icon(Icons.download),
                        onPressed: () => saveCard(ctx, c),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('閉じる')),
          if (cells.isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('すべて印刷用PNGで保存'),
              onPressed: () async {
                for (final c in cells) {
                  await saveCard(ctx, c);
                }
              },
            ),
        ],
      ),
    );
  }
}

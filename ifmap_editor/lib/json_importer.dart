import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'map_editor_controller.dart';

class JsonImporter {
  JsonImporter._();

  static Future<void> importJson(
    BuildContext context,
    MapEditorController ctrl,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.bytes == null) return;

    try {
      final jsonStr    = utf8.decode(result.files.single.bytes!);
      final decoded    = jsonDecode(jsonStr) as Map<String, dynamic>;
      final editorData = decoded['_editorData'];

      if (editorData == null) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('エディタ用データ(_editorData)が見つかりません')));
        return;
      }

      ctrl.loadFromEditorData(
        editorData as Map<String, dynamic>,
        result.files.single.name,
      );

      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('プロジェクトを復元しました')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('読出エラー: $e')));
    }
  }
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'editor_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BrowserContextMenu.disableContextMenu();
  runApp(const MapEditorApp());
}

class MapEditorApp extends StatelessWidget {
  const MapEditorApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'infacilityMAP Editor',
    theme: ThemeData(primarySwatch: Colors.blue),
    home: const EditorScreen(),
  );
}
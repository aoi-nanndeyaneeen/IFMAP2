// lib/ui/sensor_debug_sheet.dart
//
// 実機で困ったときの確認画面。
//   ・方位が取れないのは許可の問題か、イベントが来ていないのか
//   ・気圧/GPSがない端末でも、値を手で入れて提案の動きを確かめたい
// 開発用なので体裁は最小限にしてある。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../config.dart';
import '../navigation/navigation_controller.dart';
import '../sensors/heading_source.dart';
import '../sensors/motion_source.dart';

Future<void> showSensorDebugSheet(
  BuildContext context,
  NavigationController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SensorDebugSheet(controller: controller),
  );
}

class _SensorDebugSheet extends StatefulWidget {
  final NavigationController controller;
  const _SensorDebugSheet({required this.controller});

  @override
  State<_SensorDebugSheet> createState() => _SensorDebugSheetState();
}

class _SensorDebugSheetState extends State<_SensorDebugSheet> {
  final _altitude = TextEditingController();
  final _lat = TextEditingController(text: '35.151');
  final _lng = TextEditingController(text: '136.924');

  @override
  void dispose() {
    _altitude.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('センサー診断',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              ValueListenableBuilder<double>(
                valueListenable: c.altitude,
                builder: (_, v, __) =>
                    Text('相対高度: ${v.toStringAsFixed(2)} m'),
              ),
              ValueListenableBuilder<Position?>(
                valueListenable: c.gps,
                builder: (_, p, __) => Text(p == null
                    ? 'GPS: 取得できていません'
                    : 'GPS: ${p.latitude.toStringAsFixed(5)}, '
                        '${p.longitude.toStringAsFixed(5)}'),
              ),
              const Divider(height: 24),

              const Text('値を手で流し込む',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              // 「押しても何も起きない」と誤解されやすいので用途を書いておく
              Text(
                '開発用。気圧計やGPSがない場所で、階・建物の切替提案の動きを'
                '確かめるためのもの。センサーを有効にするボタンではない。'
                '高度は値を入れてから押すこと。',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
              TextField(
                controller: _altitude,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                decoration: const InputDecoration(labelText: '相対高度 (m)'),
              ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _lat,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '緯度'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _lng,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '経度'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                OutlinedButton(
                  onPressed: _injectAltitude,
                  child: const Text('高度を流す'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _injectGps,
                  child: const Text('GPSを流す'),
                ),
              ]),
              const Divider(height: 24),

              _StepDiagnostics(controller: c),
              const Divider(height: 24),

              const _CompassDiagnostics(),
            ],
          ),
        ),
      ),
    );
  }

  void _injectAltitude() {
    final v = double.tryParse(_altitude.text);
    if (v != null) widget.controller.debugInjectAltitude(v);
  }

  void _injectGps() {
    final lat = double.tryParse(_lat.text);
    final lng = double.tryParse(_lng.text);
    if (lat == null || lng == null) return;
    widget.controller.debugInjectGps(Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    ));
  }
}

/// コンパスの生の状態を0.5秒ごとに出す。
/// 「許可は通ったのか」「イベントは来ているのか」を実機で切り分けるためのもの。
class _CompassDiagnostics extends StatefulWidget {
  const _CompassDiagnostics();

  @override
  State<_CompassDiagnostics> createState() => _CompassDiagnosticsState();
}

class _CompassDiagnosticsState extends State<_CompassDiagnostics> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 許可ダイアログを出す。ルートを出さなくても診断画面から直接試せるように
  /// ここにも置いている。iOS はユーザー操作起点でないと拒否するのでボタンから呼ぶ。
  Future<void> _request() async {
    await requestSensorPermission();
    if (mounted) setState(() {});
  }

  /// 診断結果を丸ごとクリップボードへ。スマホで1行ずつ読み上げるのは辛いので。
  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('診断結果をコピーしました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines =
        sensorDiagnostics().entries.map((e) => '${e.key}: ${e.value}').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('コンパス', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton.icon(
            onPressed: _request,
            icon: const Icon(Icons.explore, size: 18),
            label: const Text('方位の許可を求める'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _copy(lines.join('\n')),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('コピー'),
          ),
        ]),
        const SizedBox(height: 8),
        for (final line in lines)
          SelectableText(line,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
      ],
    );
  }
}

/// 歩数による現在地推定の状態を0.5秒ごとに出す。
/// 「加速度が来ていない」のか「チェックポイントで止まっている」のかを見分ける。
class _StepDiagnostics extends StatefulWidget {
  final NavigationController controller;
  const _StepDiagnostics({required this.controller});

  @override
  State<_StepDiagnostics> createState() => _StepDiagnosticsState();
}

class _StepDiagnosticsState extends State<_StepDiagnostics> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final traveledM = c.traveledPx.value * AppConfig.metersPerPx;
    final lines = <String>[
      for (final e in motionDiagnostics().entries) '${e.key}: ${e.value}',
      for (final e in c.stepDiagnostics.entries) '${e.key}: ${e.value}',
      for (final e in c.turnDiagnostics.entries) '${e.key}: ${e.value}',
      '経路: ${c.currentPath.isEmpty ? 'なし（経路がないと歩数は数えない）' : '${c.currentPath.length} ノード'}',
      '進んだ距離: ${traveledM.toStringAsFixed(1)} m',
      '学んだ歩幅: ${(c.strideScale * AppConfig.strideMeters).toStringAsFixed(2)} m'
          '（標準の ${(c.strideScale * 100).toStringAsFixed(0)}%）',
      '最後に位置を合わせてから: ${c.walkedSinceFixMeters.toStringAsFixed(1)} m',
      '次のチェックポイント: ${c.nextGate?.label ?? 'なし'}'
          '${c.nextGate != null ? '（通り過ぎれば自動で進む）' : ''}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('歩数（現在地の推定）',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        for (final line in lines)
          SelectableText(line,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
      ],
    );
  }
}

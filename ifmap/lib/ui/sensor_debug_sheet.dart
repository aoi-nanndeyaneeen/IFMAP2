// lib/ui/sensor_debug_sheet.dart
//
// 実機で困ったときの確認画面。
//   ・方位が取れないのは許可の問題か、イベントが来ていないのか
//   ・気圧/GPSがない端末でも、値を手で入れて提案の動きを確かめたい
// 開発用なので体裁は最小限にしてある。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../navigation/navigation_controller.dart';
import '../sensors/heading_source.dart';

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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('コンパス', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        for (final e in sensorDiagnostics().entries)
          SelectableText('${e.key}: ${e.value}',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
      ],
    );
  }
}

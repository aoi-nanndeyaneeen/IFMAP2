// 画面が最後まで組み立てられるかだけを見る。
//
// 単体テストは通っているのに実機で真っ白、という事故がいちばん痛いので、
// 実際のマップを読み込んで MapScreen を一度描いてみる。
// センサーのプラグインはテスト環境に無いため、チャンネルを黙らせておく。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/ui/map_screen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // sensors_plus / flutter_compass / geolocator の EventChannel は
    // テストでは未登録。何も流さないストリームとして応答させる。
    const channels = [
      'dev.fluttercommunity.plus/sensors/user_accel',
      'dev.fluttercommunity.plus/sensors/barometer',
      'hemanthraj/flutter_compass',
      'flutter.baseflow.com/geolocator_updates',
    ];
    for (final name in channels) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (call) async => null,
      );
    }
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => false, // 位置情報サービスは無効という扱い
    );
  });

  testWidgets('マップを読み込んで画面が描ける', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapScreen()));

    // 実アセットの読み込みはファイルI/Oと Isolate を使うので、
    // pump() だけでは進まない。runAsync で実時間を与えながら待つ。
    final progress = find.byType(LinearProgressIndicator);
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      // pump に duration を渡さないと、loadAll がフロアの合間に挟む
      // Future.delayed(Duration.zero) のタイマーが進まない。
      await tester.pump(const Duration(milliseconds: 200));
      if (progress.evaluate().isEmpty) break; // 全フロア読み終わった
    }

    expect(tester.takeException(), isNull);
    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);

    // フロア切り替えのチップは2枚以上読めたときだけ出る。
    // ここが出ていれば、実アセットの読み込みが最後まで通っている。
    expect(find.byType(ChoiceChip), findsWidgets);

    // 全フロア読み終わっているので進捗バーは消えている。
    expect(progress, findsNothing);
  });
}

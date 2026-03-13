// ifmap_editor/lib/config.dart
class AppConfig {
  // ── マス目サイズ ────────────────────────────────────────────────
  // 推奨: 建物1棟(~100m×60m)を 0.5m/マスで表現 → 200×120 マス
  // ※ 400×600 は GridView では Chrome がクラッシュする。
  //   CustomPainter なら 400×600 も動くが、作業しやすい 200×120 を推奨。
  static const int rows = 20;
  static const int cols = 30;

  // ── 縮尺 (editorとnavigatorで共通の基準) ───────────────────────
  // 1マスが表す実寸(m)
  static const double metersPerCell = 0.5;
  // JSONに出力する座標スケール: JSON座標 = マスindex × pxPerCell
  static const int pxPerCell = 10;

  // ── UI ─────────────────────────────────────────────────────────
  static const int maxCharsPerLine = 10;
  // CustomPainterでセル枠線を描画する最小セルサイズ(px) ─ 小さすぎると重い
  static const double gridLineMinCellPx = 3.0;
}
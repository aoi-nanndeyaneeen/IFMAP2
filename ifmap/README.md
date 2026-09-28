# ifmap — ナビゲーションアプリ

利用者が実際に使う側。スマホのブラウザ、Android、iOS で動く。

設計の全体像は [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) にある。
ここは動かし方と、よく触る場所の案内だけ。

## 動かす

```bash
flutter pub get
flutter run -d chrome        # Web版
flutter run                  # 接続中の実機
```

解析とテスト:

```bash
flutter analyze
flutter test
```

## よく触る場所

| やりたいこと | 触る場所 |
|---|---|
| 建物・フロアを増やす | `assets/<建物>/` に JSON を置き、`lib/config.dart` の `mapSections` に追加 |
| 縮尺・歩幅を変える | `lib/config.dart` の `metersPerCell` / `strideMeters` |
| 通知の頻度を変える | `lib/config.dart` の `suggestionCooldown` / `suggestionSnooze` / `buildingEnterRadius` |
| 提案を出す条件を変える | `lib/navigation/suggestion_policy.dart` |
| 経路の探し方を変える | `lib/routing/` |
| 見た目を変える | `lib/ui/` |

`pubspec.yaml` の `assets:` はディレクトリ単位で登録してあるので、
JSONを足すときに編集する必要はない。

## マップJSONを軽くする

エディタが書き出す JSON には見取り図が base64 で埋まっているが、
このアプリは読まない。消すと合計 15 MB → 9.3 MB になる。

```bash
dart run tool/strip_bg_image.dart          # どれだけ減るか見るだけ
dart run tool/strip_bg_image.dart --apply  # 実際に消す
```

消したファイルを `ifmap_editor` で読み直すと見取り図が出ない
（マス目・壁・部屋名は残る）。編集を続けるなら元ファイルを別に残しておくこと。

## QRコード

`https://aoi-nanndeyaneeen.github.io/IFMAP2/?start=<ノード名>` を
QRコード化して各部屋に貼る。カメラで読むだけで現在地が設定された状態で開く。

アプリ内の「QRスキャン」ボタンからは、ノード名そのものが入ったQRも読める。

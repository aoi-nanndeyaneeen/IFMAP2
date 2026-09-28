# 📍 infacilityMAP (IFMAP2)

**infacilityMAP** は、見取り図をベースにした完全オリジナルの「屋内ナビゲーションシステム」です。
GPSが届かない屋内空間でも、QRコードをスキャンするだけで現在地を特定し、目的地までの最短ルートを自動計算して案内します。階層（フロア）をまたいだナビゲーションにも対応しています。

## ✨ 主な機能 (Features)

* **QRコードによる自己位置特定**: 施設内に貼られたQRコードを読み取る（またはURLパラメータを踏む）ことで、一瞬で現在地を特定しマップ上に表示します。
* **最短ルート自動計算**: ダイクストラ法（Dijkstra's algorithm）を用いて、現在地から目的地までの最短経路を瞬時に計算し、赤い矢印でナビゲーションします。
* **階層またぎナビゲーション**: 1階から2階へなど、異なるフロアが目的地の場合、自動的に「一番近い階段」を経由するルートを案内します。
* **専用マップエディタ同梱**: プログラミング知識がなくても、建物の見取り図（画像）を読み込んで、マウス操作だけで独自のナビゲーションマップ（JSON）を作成できる専用エディタが付属しています。
* **Webアプリ完全対応**: Cloudflare Pages等を利用してWebアプリとしてデプロイ可能。ユーザーはアプリをインストールすることなく、スマホのブラウザからQRを読み込むだけで即座にナビゲーションを開始できます。

---

## 📁 プロジェクト構成 (Architecture)

このリポジトリは、以下の2つの独立したFlutterプロジェクトで構成されています。

### 1. `ifmap_editor` (マップ作成ツール / PC向け)
施設の見取り図からナビゲーション用のマップデータ（JSON）を作成するためのツールです。
* **機能**: 背景画像の読み込み、歩行可能エリア（道）の描画、目的地・階段の配置と命名、JSONデータのエクスポート。

### 2. `ifmap` (ナビゲーションアプリ / スマホ・Web向け)
利用者が実際に使用するナビゲーションアプリです。
* **機能**: マップの描画、QRスキャナー（カメラ起動）、目的地検索、フロア切り替え、最短ルートの描画、現在地への自動ズーム。

### 設計メモ
なぜこの作りなのか、どこを触れば何が変わるかは
**[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** にまとめてあります。
座標系・JSONの形・通知の出し分け・既知の弱点もここです。

---

## 🚀 使い方 (How to Use)

### Step 1: マップデータの作成 (`ifmap_editor`)
1. エディタをPCで起動します。
2. 「見取り図を読込」ボタンから、建物の平面図（画像）を読み込みます。
3. ペンツールを使って、歩ける場所（青）、目的地・部屋（黄）、階段（緑）を塗っていきます。
4. 「JSON出力」ボタンを押し、JSONファイルを保存します。
5. `ifmap/assets/<建物名>/` フォルダに置きます（例: `ifmap/assets/NITTC/NITTC_1F.json`）。
6. `ifmap/lib/config.dart` の `mapSections` にエントリを1行足します。
   `pubspec.yaml` はディレクトリ単位で登録しているので編集不要です。

> 階段でフロアをつなぐときは、**両方のフロアで階段に同じ名前を付けてください**。
> 名前が一致する階段どうしが自動で対応づけられます。

### Step 2: ナビゲーションの利用 (`ifmap`)
1. アプリを起動するか、デプロイされたWeb版のURLにアクセスします。
2. スマホのカメラで、各部屋に設置されたQRコードをスキャンします。
   *(※ Web版の場合は `https://[あなたのURL]/?start=room_name` のようなURLをQRコード化しておくと、スキャンと同時にアプリが起動し現在地が設定されます)*
3. マップをタップするか、右上の一覧ボタンから目的地を選ぶとルートが描画されます。
4. 部屋の出入口や扉に来たら、画面下のチェックポイントをタップします。
   歩数だけだと位置がずれていくので、ここで現在地を確定させています。

---

## 💻 開発環境のセットアップ (Getting Started)

このプロジェクトをローカルで動かすための手順です。

### 必須要件
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (>=3.10.0)
* Dart SDK

### インストールと起動
リポジトリをクローン後、各プロジェクトフォルダでパッケージをインストールしてください。

```bash
# クローン
git clone [https://github.com/aoi-nanndeyaneeen/IFMAP2.git](https://github.com/aoi-nanndeyaneeen/IFMAP2.git)
cd IFMAP2

# アプリ側のセットアップと起動
cd ifmap
flutter pub get
flutter run

# エディタ側のセットアップと起動
cd ../ifmap_editor
flutter pub get
flutter run -d windows # または -d chrome, -d macos
```

### 解析とテスト
`main` への push / PR で自動的に走ります（[.github/workflows/ci.yml](.github/workflows/ci.yml)）。
手元でも同じものが回せます。

```bash
cd ifmap
flutter analyze
flutter test

---

## 📱 iPhoneで使う (GitHub Pages への自動デプロイ)

`main` に push するだけで GitHub Actions が Flutter Web をビルドし、GitHub Pages に公開します。
Mac も Apple Developer 登録も不要です。

* 公開URL: `https://aoi-nanndeyaneeen.github.io/IFMAP2/`
* ワークフロー: [.github/workflows/deploy.yml](.github/workflows/deploy.yml)
* `ifmap/` 配下を変更して push → 解析とテストが通れば 2〜4分で公開版が更新される
  （手動実行は Actions タブの "Run workflow" から）

### iPhone側の初回セットアップ
1. **Safari** で上記URLを開く（Chrome ではホーム画面追加ができない）
2. 共有ボタン → **「ホーム画面に追加」**
3. 以降はホーム画面のアイコンから、ネイティブアプリと同じ全画面で起動する

コードを更新すると、次回起動時にネットワークから新版が読み込まれます。

> **オフラインでは動きません。** Flutter 3.41 でオフラインキャッシュ用の
> Service Worker は廃止され、`flutter build web` が出力する
> `flutter_service_worker.js` は自分を登録解除するだけのスタブになっています。
> 起動には毎回ネットワークが必要です（ブラウザのHTTPキャッシュは効きます）。
> 電波の弱い建物内で開けないことがある点に注意。

### QRコードの作り方
`https://aoi-nanndeyaneeen.github.io/IFMAP2/?start=<ノード名>` をQRコード化して各部屋に貼ります。
iPhone標準のカメラアプリで読むだけで、現在地が設定された状態で開きます。

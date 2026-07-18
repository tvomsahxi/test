# マインドマップアプリ

起きた問題やテーマを「起点」にして、思考を四角(ノード)でつなげて整理するマインドマップアプリです。

2つのバージョンがあります:

| バージョン | 場所 | 動かし方 |
| --- | --- | --- |
| Flutter アプリ(Android / iOS / Web) | `mindmap_app/` | 下記参照 |
| 単一HTML版(プロトタイプ) | `index.html` | ブラウザで開くだけ |

## 使い方(共通)

1. **起点を入力して「作成」** — 新しいキャンバスができ、タイトルの文字が中央の四角に入った状態でスタートします
2. **四角をタップ** — つながる新しい四角が作られ、文字の入力が求められます
3. できた四角・元の四角のどれをタップしても、そこに連なる四角を追加できます

### その他の操作

| 操作 | 動作 |
| --- | --- |
| 四角をドラッグ | 四角を移動 |
| 四角を長押し | テキスト編集・削除(枝ごと)メニュー |
| 背景をドラッグ | キャンバスを移動 |
| ピンチ | ズーム |
| 🎯 / 中心ボタン | 中心に戻る |

作成したマップは端末に自動保存されます(Flutter版は `shared_preferences`、HTML版は `localStorage`)。

## Flutter アプリの実行

[Flutter SDK](https://docs.flutter.dev/get-started/install) をインストールした上で:

```bash
cd mindmap_app
flutter pub get

# 接続した実機やエミュレータで実行
flutter run

# Android APK を作る
flutter build apk

# テスト
flutter test
```

### 構成

```
mindmap_app/lib/
├── main.dart           # アプリ本体・ホーム画面(マップ一覧と新規作成)
├── editor_screen.dart  # キャンバス画面(ノード表示・タップ追加・ドラッグ・ズーム)
├── models.dart         # MindMap / MindNode モデルと子ノードの自動配置ロジック
└── storage.dart        # shared_preferences への保存・読込
```

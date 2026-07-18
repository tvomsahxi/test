# マインドマップアプリ 内部仕様書

アプリを「作る人・直す人」の視点から、実装の構造を説明する文書です。
Flutter / Dart を学んだことがない読者でも読み進められるよう、
前半(§2)に必要な予備知識をまとめ、後半で実装の詳細とリファレンスを載せています。
(ユーザーから見た仕様は [外部仕様書](external_spec.md) を参照)

- 対象コード: `mindmap_app/`(Flutter 3.32 / Dart 3 系)
- 依存パッケージ: `shared_preferences`(端末保存)、`share_plus`(OS共有シート)

---

## 1. 全体構造

### 1.1 ファイル構成と責務

```
lib/
├── main.dart           … アプリの入口・テーマ設定・ホーム画面(一覧/新規作成/削除/エクスポートメニュー/復元の適用)
├── editor_screen.dart  … キャンバス画面(四角の描画・タップ/長押し/ドラッグ・パン/ズーム・接続線の描画)
├── outline_screen.dart … リスト(振り返り)画面(アウトライン表示・テキストコピー)
├── export.dart         … 純粋ロジック:JSONバックアップ生成・AI分析用Markdown生成・バックアップ解析
├── export_screen.dart  … エクスポート画面(プレビュー・コピー・共有)
├── import_screen.dart  … 復元画面(貼り付け・検査・取り込み方の選択)
├── models.dart         … データモデル(MindMap / MindNode)と木構造の操作・自動配置ロジック
└── storage.dart        … 端末への保存・読込(shared_preferences のラッパー)
test/
└── widget_test.dart    … 単体テスト(モデル・エクスポート)と画面操作テスト(全18件)
```

### 1.2 依存関係(誰が誰を使うか)

```
main.dart(ホーム)
 ├─▶ editor_screen.dart ─▶ outline_screen.dart
 ├─▶ outline_screen.dart
 ├─▶ export_screen.dart
 ├─▶ import_screen.dart
 ├─▶ export.dart
 └─▶ storage.dart
        │
models.dart ◀── ほぼ全ファイルが参照(データの中心)
```

設計方針:

- **データとロジックを UI から分離する。** マップの木構造操作(追加・削除・アウトライン化)は
  `models.dart`、書き出し/読み込みの文字列変換は `export.dart` にあり、どちらも
  Flutter に依存しない純粋な Dart コード。そのため画面を起動せずにテストできる。
- **保存はホーム画面が一元管理する。** マップ一覧(`List<MindMap>`)の実体はホーム画面が持ち、
  キャンバス画面には「変更があったら呼ぶ保存関数」だけを渡す(§4.2)。

---

## 2. Flutter / Dart 未学者のための予備知識

この節だけで Flutter アプリの読み方が一通り分かるように書いています。
既に知っている場合は §3 へ。

### 2.1 Flutter とは

1つのコードベースから Android / iOS / Web などのアプリを作れるフレームワーク。
言語は **Dart**。画面は「**ウィジェット**」という部品を入れ子に組み合わせて作る。

```dart
// 「中央に文字を置く」画面の例。ウィジェットの入れ子がそのまま画面構造になる
Center(              // 中央寄せするウィジェット
  child: Text('こんにちは'),  // 文字を表示するウィジェット
)
```

HTML に例えると、ウィジェットのツリーが DOM ツリーに相当する。
レイアウト(`Row`=横並び、`Column`=縦並び、`Padding`=余白)も、
ボタンも、画面全体も、すべてウィジェット。

### 2.2 StatelessWidget と StatefulWidget

ウィジェットには2種類ある。

| 種類 | 意味 | このアプリでの例 |
| --- | --- | --- |
| `StatelessWidget` | 状態(変化するデータ)を持たない。渡された値を表示するだけ | `OutlineScreen`、`ExportScreen`、`_NodeBox` |
| `StatefulWidget` | 状態を持ち、状態が変わると画面を描き直す | `HomeScreen`、`EditorScreen`、`ImportScreen` |

`StatefulWidget` は本体と `State` オブジェクトのペアで書く。**状態変数は `State` クラスに置き**、
変更するときは必ず `setState(() { ... })` で包む。`setState` を呼ぶと Flutter が
`build()` メソッドを再実行し、画面が新しい状態で描き直される。

```dart
class HomeScreen extends StatefulWidget {           // 本体(設定値の入れ物)
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {  // 状態と画面の作り方
  List<MindMap> _maps = [];                         // ← 状態

  void _addMap(MindMap m) {
    setState(() => _maps.add(m));                   // ← 状態変更は setState で包む
  }

  @override
  Widget build(BuildContext context) { ... }        // ← 状態から画面を組み立てる
}
```

**重要な考え方:「画面を直接書き換える」のではなく「状態を変えて、画面は状態から作り直す」。**
このアプリでも、四角の追加・移動・削除はすべて `MindMap` のデータを変えて `setState` するだけで、
画面側は毎回データから描き直している。

### 2.3 build() と BuildContext

- `build()` … 「今の状態ならこういう画面」というウィジェットツリーを返す関数。何度でも呼ばれる。
- `BuildContext` … ツリー上の「現在地」を表すオブジェクト。画面遷移(`Navigator.of(context)`)や
  テーマ取得、スナックバー表示(`ScaffoldMessenger.of(context)`)の起点として使う。

### 2.4 画面遷移(Navigator)

画面はスタック(積み重ね)で管理される。

```dart
// 進む(上に積む)。push は Future を返し、戻ってきたときに完了する
await Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => EditorScreen(...)),
);

// 戻る(1枚おろす)。第2引数で呼び出し元に値を返せる
Navigator.pop(context, ImportRequest(mode, maps));
```

このアプリでは復元画面がこの「戻り値」を使っており、
`ImportScreen` は選択結果(`ImportRequest`)を `pop` で返し、ホーム画面が受け取って適用する。

### 2.5 非同期処理(Future / async / await)

端末への保存やダイアログ表示など「すぐには終わらない処理」は `Future`(将来値が入る箱)を返す。
`await` でその完了を待つ。`await` を使う関数には `async` を付ける。

```dart
Future<void> _createMap() async {
  ...
  await _persist();          // 保存が終わるまで待つ
  if (!mounted) return;      // 待っている間に画面が破棄されていたら何もしない
  _openMap(map);
}
```

`mounted` は「この State がまだ画面に生きているか」を表すフラグで、
`await` の後に画面操作をするときの安全確認として使う。

### 2.6 このアプリを読むのに必要な Dart 文法

| 文法 | 例 | 意味 |
| --- | --- | --- |
| `final` / `const` | `final id;` / `const SizedBox(...)` | 再代入不可の変数 / コンパイル時定数(ウィジェットに付けると再生成が省ける) |
| null 安全 | `String? parentId` | `?` 付きの型だけが `null` を入れられる。`parentId == null` でルート判定に使用 |
| `!` | `copied!` | 「null ではない」と表明して `?` を外す(null なら実行時エラー) |
| `??` | `id ?? _uid()` | 左が null なら右を使う |
| アロー関数 | `bool get isRoot => parentId == null;` | 本体が式1つの関数の省略形 |
| 名前付き引数 | `MindNode({required this.text, this.x = 0})` | 呼び出し側が `text: '...'` のように名前で渡す。`required` は必須 |
| `factory` | `factory MindMap.fromTitle(...)` | 名前付きの生成用コンストラクタ |
| コレクション操作 | `nodes.where((n) => n.parentId == id)` | `where`=絞り込み、`map`=変換、`toList()`=リスト化 |
| カスケード `..` | `buf..writeln('a')..writeln('b')` | 同じオブジェクトへ連続でメソッドを呼ぶ |
| レコード | `List<(MindNode, int)>` | 複数の値の組。`e.$1`(ノード)、`e.$2`(深さ)で取り出す |
| パターン分解 | `for (final (node, depth) in entries)` | レコードをその場で2変数に分解 |
| enum | `enum ImportMode { merge, replace }` | 決まった選択肢だけを取る型 |
| スプレッド | `[..._maps]` | リストの中身を展開して新しいリストを作る(元を壊さずソートするため) |
| `is` / `as` | `if (decoded is! Map)` | 型判定 / 型変換(JSON解析で使用) |

---

## 3. データモデル(`models.dart`)

### 3.1 構造

マインドマップは「ノードの平らなリスト+親ID参照」で木構造を表す。

```
MindMap
├── id        : String   … 一意なID(時刻+乱数から生成)
├── title     : String   … マップ名(=ルートノードのテキストと同期)
├── createdAt : DateTime
├── updatedAt : DateTime … 変更のたびに更新。一覧の並び順に使用
└── nodes     : List<MindNode>
      MindNode
      ├── id       : String
      ├── text     : String
      ├── parentId : String?  … null ならルート(起点)。それ以外は親ノードのid
      ├── x, y     : double   … キャンバス中心を原点(0,0)とした論理座標
```

子リストを持たせず親IDで表現しているのは、JSON化が単純になり、
「子の一覧が欲しい」ときは `childrenOf(id)` で都度絞り込めば足りるため
(このアプリの規模ではノード数が少なく、線形探索で十分)。

### 3.2 座標系

- ノード座標はキャンバス中心が原点 `(0,0)`。右が +x、下が +y
- 描画時はキャンバス(4000×4000 の論理領域)の中心 `(2000,2000)` を足してピクセル位置に変換する(§4.2)

### 3.3 子ノードの自動配置(`addChild`)

新しい四角を親の周りの「空いていそうな方向」に置く。

- **親がルートの場合**: 基準角 = 真上(-90°)。既にいる子の数 × 45° だけ時計回りにずらす
  (1個目は上、2個目は右上、…と放射状に並ぶ)
- **親がルート以外の場合**: 基準角 = 祖父母→親 の方向(枝が伸びてきた向きの延長)。
  既にいる子の数に応じて `±48°、±96°…` と左右交互に振る
- 距離は一律 `nodeDistance = 170`

厳密な重なり回避はせず「だいたい散らばる」ことを狙った軽い実装。重なったらユーザーがドラッグで直せる。

### 3.4 JSON 変換

`toJson()` / `fromJson()` で `Map<String, dynamic>`(JSONオブジェクト相当)と相互変換する。
日時はミリ秒のエポック整数で保存。この形式がそのまま端末保存(§6)とバックアップ(§5.1)に使われる。

---

## 4. 画面の実装

### 4.1 ホーム画面(`main.dart` — `HomeScreen`)

状態:

| 変数 | 型 | 意味 |
| --- | --- | --- |
| `_maps` | `List<MindMap>` | 全マップの実体。**アプリ内で唯一の正本** |
| `_loaded` | `bool` | 起動時の読込が終わったか(終わるまでくるくるを表示) |
| `_titleController` | `TextEditingController` | タイトル入力欄の中身を読むためのオブジェクト |

処理の流れ:

- 起動時 `initState()` → `_load()` で `MapStorage.load()` を await → `_maps` に格納
- 作成: `_createMap()` — 入力を trim → 空なら無視 → `MindMap.fromTitle()` で生成 → 保存 → キャンバスへ push
- 一覧は表示のたびに `updatedAt` 降順へソート(`[..._maps]..sort(...)` で元リストは壊さない)
- 削除・復元適用も全部ここで行い、必ず `_persist()`(=`MapStorage.save(_maps)`)を呼ぶ

### 4.2 キャンバス画面(`editor_screen.dart` — `EditorScreen`)

**データの受け渡し:** コンストラクタで `map`(編集対象。参照渡しなのでここでの変更は
ホームの `_maps` 内の同じオブジェクトに反映される)と `onChanged`(ホームの `_persist`)を受け取る。
変更のたびに `_markChanged()` → `updatedAt` 更新+`onChanged()` で自動保存になる。

**キャンバスの仕組み:**

```
InteractiveViewer(パン/ズーム担当。0.35〜2.5倍)
└── SizedBox(4000×4000 の論理キャンバス)
    └── Stack(重ね置き)
        ├── CustomPaint(_EdgePainter) … 親子をつなぐ曲線を全部描く
        └── Positioned × ノード数        … 各四角を座標に配置
            └── FractionalTranslation(-0.5,-0.5) … 四角の中心を座標に合わせる
                └── _NodeBox(四角の見た目+ジェスチャー)
```

- `Positioned(left: 2000 + node.x, top: 2000 + node.y)` で置き、
  `FractionalTranslation` で自身のサイズの半分だけ戻すことで「**四角の中心が座標**」になる
  (四角のサイズは文字量で変わるため、この方法だとサイズを知らずに中心合わせできる)
- 接続線は `_EdgePainter`(`CustomPainter` 継承)が全ノードを走査し、
  親の中心→子の中心を3次ベジェ曲線(中間点で水平に膨らむ形)で描く
- 初期表示は `LayoutBuilder` で画面サイズを知り、`TransformationController` に
  「キャンバス中心が画面中央に来る平行移動」をセットする(🎯ボタンも同じ処理)

**ジェスチャーの分担:**

| 操作 | 担当 | 実装 |
| --- | --- | --- |
| 背景ドラッグ/ピンチ | `InteractiveViewer` | 標準機能 |
| 四角タップ | `_NodeBox` の `GestureDetector.onTap` | 入力ダイアログ→`map.addChild()` |
| 四角長押し | 同 `onLongPress` | ボトムシート(編集/枝ごと削除) |
| 四角ドラッグ | 同 `onPanUpdate` | `node.x += delta.dx / scale` |

四角の上で始まったドラッグは `_NodeBox` の `GestureDetector` が勝ち、
背景で始まったドラッグは `InteractiveViewer` が勝つ(Flutter のジェスチャー調停に任せている)。
ドラッグの `delta` は**画面ピクセル**なので、現在のズーム倍率
(`_viewController.value.getMaxScaleOnAxis()`)で割ってキャンバス座標に直す。

### 4.3 リスト画面(`outline_screen.dart` — `OutlineScreen`)

- `map.outline()`(深さ優先走査で `(ノード, 深さ)` のリストを返す)をそのまま
  `ListView` の行にする。インデントは `深さ × 20px` の左パディング
- コピーは `map.toOutlineText()` を `Clipboard.setData` へ渡すだけ
- 状態を持たないので `StatelessWidget`

### 4.4 エクスポート画面(`export_screen.dart` — `ExportScreen`)

- 表示する `title` / `subject`(共有時の件名=ファイル名形式)/ `text`(本文)を受け取るだけの `StatelessWidget`
- 「コピー」→ `Clipboard.setData`、「共有」→ `SharePlus.instance.share(ShareParams(...))`
- **何をエクスポートするかはこの画面は知らない**(本文の生成は呼び出し元が `export.dart` で行う)。
  そのため JSON/AI 用のどちらでも同じ画面を使い回せる

### 4.5 復元画面(`import_screen.dart` — `ImportScreen`)

状態: `_controller`(貼り付け内容)、`_parsed`(解析済みマップ、未解析なら null)、`_error`(エラー文言)。

```
貼り付け → [読み込む] → parseJsonBackup()
   │            ├─ 成功 → _parsed にセット → 件数表示+「追加/置き換え」ボタンに切り替え
   │            └─ FormatException → _error に日本語メッセージ → 赤字表示
   └─ テキストを編集すると _parsed/_error をリセット(古い解析結果で取り込まない)
```

取り込みボタンは `Navigator.pop(context, ImportRequest(mode, maps))` で結果を返すだけで、
**実際の適用(マージ/置換/確認ダイアログ/保存)はホーム画面の `_openImport()` が行う**。
理由: マップの正本と保存責務をホームに集中させるため(§1.2)。

- マージ: 既存の id 集合を作り、重複はスキップ・新規のみ追加(件数を集計してスナックバー表示)
- 置換: 既存が1つでもあれば確認ダイアログを挟み、`_maps` を丸ごと差し替え

---

## 5. 純粋ロジック(`export.dart`)

UI に依存しない文字列変換だけを置くファイル。全関数がトップレベル関数。

| 関数 | 入力 → 出力 | 内容 |
| --- | --- | --- |
| `buildJsonBackup(maps, {now})` | マップ一覧 → JSON文字列 | §5.1 の形式。`JsonEncoder.withIndent` で人が読める整形付き |
| `parseJsonBackup(text)` | JSON文字列 → マップ一覧 | 形式検査をしながら復元。失敗は日本語メッセージの `FormatException` |
| `buildAiExport(maps, {now})` | マップ一覧 → Markdown文字列 | 冒頭に説明+分析観点、以降はマップを作成日順に日時付きアウトラインで並べる |
| `exportTimestamp(now)` | 日時 → `2026-07-18_1530` | 共有件名(ファイル名形式)用 |

`now` を引数で渡せるようにしてあるのはテストのため(現在時刻を固定できる)。

### 5.1 バックアップ形式(version 1)

```json
{
  "app": "mindmap_app",
  "format": "mindmap-backup",   ← parseJsonBackup はこの値で形式判定する
  "version": 1,                 ← 将来形式を変えるときの互換判定用
  "exportedAt": "ISO8601文字列",
  "mapCount": 2,
  "maps": [ MindMap.toJson() の配列 ]
}
```

`maps` の中身は端末保存(§6)と同一形式なので、モデルの `fromJson` がそのまま使える。

---

## 6. 端末保存(`storage.dart`)

- `MapStorage.load()` / `save(maps)` の2メソッドだけの薄いクラス
- 保存先: `shared_preferences`(端末のキーバリュー保存。Android は SharedPreferences、
  iOS は UserDefaults、Web は localStorage に対応する)
- キー: **`mindmaps-v1`**。値は全マップを `jsonEncode` した1つの文字列
- `load()` は壊れたデータを読んだ場合、例外を握りつぶして空リストを返す
  (起動不能になるより「一覧が空」の方がまし、という判断。バックアップ機能がその保険)

---

## 7. 使用した自作クラス・関数リファレンス

### models.dart

| 名前 | 種別 | 説明 |
| --- | --- | --- |
| `MindNode` | クラス | 四角1つ。`id` / `text` / `parentId` / `x` / `y`。`isRoot` は `parentId == null` |
| `MindMap` | クラス | マップ1つ。ノードのリストと題名・日時を持つ |
| `MindMap.fromTitle(title)` | factory | ルートノード1つ入りの新規マップを作る |
| `root` | getter | ルートノードを返す |
| `childrenOf(id)` | メソッド | 指定ノードの子一覧 |
| `nodeById(id)` | メソッド | ID からノードを引く(無ければ null) |
| `addChild(parent, text)` | メソッド | 自動配置(§3.3)で子を追加し、その子を返す |
| `removeSubtree(node)` | メソッド | ノードとその子孫を再帰収集して削除。削除数を返す |
| `subtreeSize(node)` | メソッド | 枝のノード数(削除確認の文言用) |
| `outline()` | メソッド | 深さ優先で `(ノード, 深さ)` のリストを返す |
| `toOutlineText()` | メソッド | `outline()` をインデント付き `- テキスト` 形式の文字列へ |
| `toJson()` / `fromJson()` | 変換 | JSON(Map)との相互変換。`MindNode` にも同名あり |
| `_uid()` | 関数 | 時刻+乱数による簡易一意ID(ファイル内私用) |

### storage.dart / export.dart

§5・§6 の表を参照。

### 画面クラス(lib/*_screen.dart, main.dart)

| 名前 | 種別 | 説明 |
| --- | --- | --- |
| `MindMapApp` | StatelessWidget | ルートウィジェット。`MaterialApp` でテーマ(シード色 `#5B7CFA`)と初期画面を設定 |
| `HomeScreen` / `_HomeScreenState` | StatefulWidget | §4.1。主要メソッド: `_load` `_persist` `_createMap` `_openMap` `_deleteMap` `_openExport` `_openImport` `_showExportMenu` |
| `EditorScreen` / `_EditorScreenState` | StatefulWidget | §4.2。主要メソッド: `_centerView` `_markChanged` `_askText` `_addChild` `_showNodeMenu` `_editNode` `_deleteNode` `_moveNode` |
| `_NodeBox` | StatelessWidget | 四角1つの見た目とジェスチャー。タップ/長押し/ドラッグをコールバックで親へ通知 |
| `_EdgePainter` | CustomPainter | 全接続線をベジェ曲線で描画 |
| `OutlineScreen` | StatelessWidget | §4.3 |
| `ExportScreen` | StatelessWidget | §4.4 |
| `ImportScreen` / `_ImportScreenState` | StatefulWidget | §4.5 |
| `ImportMode` | enum | `merge`(追加)/ `replace`(置換) |
| `ImportRequest` | クラス | 復元画面の戻り値(モード+マップ一覧) |

(`_` で始まる名前は Dart の慣習で「そのファイル内だけで使う私用」を意味する)

---

## 8. 使用した Flutter 標準ウィジェット・クラスリファレンス

### 画面の骨組み

| 名前 | 役割 | 使用箇所 |
| --- | --- | --- |
| `MaterialApp` | アプリ全体の設定(テーマ・タイトル・初期画面) | `MindMapApp` |
| `Scaffold` | 1画面の骨組み(アプリバー+本文) | 全画面 |
| `AppBar` | 画面上部のバー(タイトル・アクションボタン) | 全画面 |
| `SafeArea` | ノッチ等の端末の非表示領域を避ける | ホーム、復元ほか |

### レイアウト

| 名前 | 役割 |
| --- | --- |
| `Column` / `Row` | 縦並び / 横並び |
| `Expanded` | `Column`/`Row` 内で余った空間いっぱいに広がる |
| `Stack` / `Positioned` | 重ね置き / 重ね置きの中の絶対座標配置(キャンバスの心臓部) |
| `Padding` / `SizedBox` / `Container` | 余白 / 固定サイズの箱・すき間 / 装飾(色・角丸・枠線)付きの箱 |
| `Center` | 中央寄せ |
| `FractionalTranslation` | 自身のサイズ比で平行移動(四角の中心合わせに使用) |
| `LayoutBuilder` | 親から与えられたサイズを知ってから中身を組む(初期表示の中央合わせ) |

### 表示・入力

| 名前 | 役割 |
| --- | --- |
| `Text` / `SelectableText` | 文字表示 /(選択・コピー可能な)文字表示 |
| `TextField` + `TextEditingController` | 文字入力欄と、その内容へアクセスするための操作ハンドル |
| `ListView` / `ListView.separated` | スクロールする一覧(ホームの一覧・リスト画面) |
| `Card` / `ListTile` | 一覧の1行を作る定番部品 |
| `Icon` / `IconButton` | アイコン / アイコンのボタン |
| `FilledButton` / `OutlinedButton` / `TextButton` | 塗り/枠線/文字だけのボタン(重要度順に使い分け) |
| `CircularProgressIndicator` | 読込中のくるくる |
| `AnimatedOpacity` | 透明度をなめらかに変える(操作ヒントのフェードアウト) |
| `IgnorePointer` | タッチを素通しにする(ヒントが操作を邪魔しないように) |

### 操作・遷移・通知

| 名前 | 役割 |
| --- | --- |
| `GestureDetector` | タップ・長押し・ドラッグの検出(`onTap` / `onLongPress` / `onPanUpdate` / `onPanEnd`) |
| `InteractiveViewer` + `TransformationController` | パン/ピンチズームできる入れ物と、その表示位置・倍率の読み書き |
| `Navigator` / `MaterialPageRoute` | 画面スタックの進む/戻る(§2.4) |
| `showDialog` / `AlertDialog` | ダイアログ表示(入力・確認) |
| `showModalBottomSheet` | 画面下から出るメニュー(長押しメニュー・保存メニュー) |
| `ScaffoldMessenger` + `SnackBar` | 画面下部の一時通知(「コピーしました」等) |

### 描画・サービス

| 名前 | 役割 |
| --- | --- |
| `CustomPaint` + `CustomPainter` | 自由描画。`paint(canvas, size)` に線や図形を描く(接続線) |
| `Canvas` / `Path` / `Paint` | 描画先 / 図形の経路(`cubicTo`=ベジェ曲線)/ 線の色・太さ |
| `Clipboard`(`flutter/services`) | クリップボードの読み書き |
| `Matrix4` | 平行移動・拡大の行列(`TransformationController` の中身) |

### 外部パッケージ

| 名前 | 役割 | 使用箇所 |
| --- | --- | --- |
| `shared_preferences` | 端末のキーバリュー保存 | `storage.dart` |
| `share_plus` | OSの共有シートを開く(`SharePlus.instance.share(ShareParams(...))`) | `export_screen.dart` |

### Dart 標準(`dart:convert` ほか)

| 名前 | 役割 |
| --- | --- |
| `jsonEncode` / `jsonDecode` | オブジェクト⇄JSON文字列 |
| `JsonEncoder.withIndent` | 整形(インデント)付きJSON出力 |
| `StringBuffer` | 文字列の連結を効率よく行う(AI用Markdown生成) |
| `DateTime` / `Duration` | 日時 / 時間の長さ |
| `Future` / `Timer` | 非同期の値 / 一定時間後に実行(ヒントの自動非表示) |

---

## 9. 定数一覧

| 定数 | 値 | 場所 | 意味 |
| --- | --- | --- | --- |
| `accentColor` | `#5B7CFA` | main.dart | テーマ色(HTML版と同じ青) |
| `MindMap.nodeDistance` | 170 | models.dart | 親子ノード間の距離 |
| `_canvasSize` | 4000 | editor_screen.dart | 論理キャンバスの一辺 |
| `minScale` / `maxScale` | 0.35 / 2.5 | editor_screen.dart | ズーム倍率の下限/上限 |
| ヒント表示時間 | 5秒 | editor_screen.dart | 操作ヒントのフェードまで |
| 保存キー | `mindmaps-v1` | storage.dart | shared_preferences のキー |
| バックアップ形式 | `mindmap-backup` / version 1 | export.dart | 復元時の形式判定 |
| タイトル最大長 | 60文字 | main.dart | 入力欄の `maxLength` |

---

## 10. テスト(`test/widget_test.dart`)

`flutter test` で実行。全18件。各テスト前に `SharedPreferences.setMockInitialValues({})`
で保存領域を空にリセットする。

| グループ | 件数 | 検証内容 |
| --- | --- | --- |
| MindMap モデル | 6 | 生成・自動配置・枝ごと削除・アウトライン順序・テキスト変換・JSON往復 |
| エクスポート | 5 | バックアップJSONの生成と読み戻し・AI用Markdownの内容・タイムスタンプ・壊れた入力のエラー3種 |
| アプリ操作フロー | 7 | 作成→キャンバス表示 / タップ追加 / 長押し編集・削除 / リスト表示とコピー / バックアップとAIエクスポート / 復元(追加・重複スキップ・確認付き置換)/ 壊れたJSONのエラー表示 |

画面テストの要点:

- クリップボードは `setMockMethodCallHandler` でOS呼び出しを横取りし、コピー内容を検証する
- スナックバー表示中は下部ボタンへのタップが遮られるため、次の操作前に
  `tester.pump(Duration(seconds: 5))` で消えるのを待つ(実挙動と同じ)
- キャンバス上の四角は AppBar のタイトルと同文字のことがあるため、
  `find.descendant(of: find.byType(InteractiveViewer), ...)` でキャンバス内に限定して探す

## 11. 今後の拡張のための注意

- **保存形式を変えるとき**: `mindmaps-v1` キーと `version: 1` を上げ、旧形式からの移行処理を
  `MapStorage.load()` / `parseJsonBackup()` に足すこと(既存ユーザーのデータを壊さない)
- **ノードの親付け替えやアンドゥ**を足す場合も、変更はすべて `MindMap` のメソッドとして実装し、
  画面側は `setState` + `_markChanged()` を呼ぶだけ、という現在の分担を保つとテストしやすい
- 大量ノード(数百個〜)になると `childrenOf` の線形探索と全再描画が効いてくるため、
  その際は親→子の索引(Map)化と `shouldRepaint` の最適化を検討する

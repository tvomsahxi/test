import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';

import 'package:mindmap_app/export.dart';
import 'package:mindmap_app/main.dart';
import 'package:mindmap_app/models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MindMap モデル', () {
    test('タイトルからルートノード付きで作成される', () {
      final map = MindMap.fromTitle('大事な予定に遅れた');
      expect(map.nodes.length, 1);
      expect(map.root.text, '大事な予定に遅れた');
      expect(map.root.x, 0);
      expect(map.root.y, 0);
    });

    test('addChild で親から離れた位置に子ができる', () {
      final map = MindMap.fromTitle('起点');
      final child = map.addChild(map.root, '子1');
      expect(map.nodes.length, 2);
      expect(child.parentId, map.root.id);
      final dist = (Offset(child.x, child.y) - Offset.zero).distance;
      expect(dist, closeTo(MindMap.nodeDistance, 0.01));

      // 兄弟は別の位置に置かれる
      final child2 = map.addChild(map.root, '子2');
      expect(
        (Offset(child.x, child.y) - Offset(child2.x, child2.y)).distance,
        greaterThan(10),
      );
    });

    test('removeSubtree は枝ごと削除する', () {
      final map = MindMap.fromTitle('起点');
      final a = map.addChild(map.root, 'a');
      final b = map.addChild(a, 'b');
      map.addChild(b, 'c');
      map.addChild(map.root, '残る');
      expect(map.subtreeSize(a), 3);
      final removed = map.removeSubtree(a);
      expect(removed, 3);
      expect(map.nodes.length, 2);
      expect(map.nodes.any((n) => n.text == '残る'), isTrue);
    });

    test('outline はルートから深さ優先で並び、深さを持つ', () {
      final map = MindMap.fromTitle('起点');
      final a = map.addChild(map.root, 'a');
      map.addChild(a, 'a-1');
      map.addChild(map.root, 'b');
      final entries = map.outline();
      expect(entries.map((e) => e.$1.text).toList(), ['起点', 'a', 'a-1', 'b']);
      expect(entries.map((e) => e.$2).toList(), [0, 1, 2, 1]);
    });

    test('toOutlineText はインデント付きテキストを作る(改行は空白に置換)', () {
      final map = MindMap.fromTitle('起点');
      final a = map.addChild(map.root, 'a');
      map.addChild(a, '改行\nあり');
      expect(
        map.toOutlineText(),
        '- 起点\n  - a\n    - 改行 あり',
      );
    });

    test('JSON へ往復変換できる', () {
      final map = MindMap.fromTitle('起点');
      map.addChild(map.root, '子');
      final restored = MindMap.fromJson(map.toJson());
      expect(restored.id, map.id);
      expect(restored.title, map.title);
      expect(restored.nodes.length, 2);
      expect(restored.nodes[1].parentId, restored.root.id);
    });
  });

  group('エクスポート', () {
    test('buildJsonBackup は復元可能なJSONを作る', () {
      final map1 = MindMap.fromTitle('起点1');
      map1.addChild(map1.root, '子');
      final map2 = MindMap.fromTitle('起点2');

      final json = buildJsonBackup([map1, map2],
          now: DateTime(2026, 7, 18, 15, 30));
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['format'], 'mindmap-backup');
      expect(decoded['version'], 1);
      expect(decoded['mapCount'], 2);

      // maps はそのまま MindMap.fromJson で読み戻せる
      final restored = (decoded['maps'] as List)
          .map((e) => MindMap.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(restored.length, 2);
      expect(restored[0].title, '起点1');
      expect(restored[0].nodes.length, 2);
      expect(restored[1].title, '起点2');
    });

    test('buildAiExport は説明文と各マップのアウトラインを含む', () {
      final map1 = MindMap.fromTitle('遅刻した');
      map1.addChild(map1.root, '自己判断が原因');
      final map2 = MindMap.fromTitle('別のテーマ');

      final text = buildAiExport([map1, map2],
          now: DateTime(2026, 7, 18, 15, 30));
      expect(text, contains('# マインドマップ 思考分析用エクスポート'));
      expect(text, contains('分析してください'));
      expect(text, contains('マップ数: 2'));
      expect(text, contains('## マップ1: 遅刻した'));
      expect(text, contains('  - 自己判断が原因'));
      expect(text, contains('## マップ2: 別のテーマ'));
    });

    test('exportTimestamp はファイル名に使える形式', () {
      expect(exportTimestamp(DateTime(2026, 7, 8, 9, 5)), '2026-07-08_0905');
    });

    test('parseJsonBackup はバックアップを読み戻せる', () {
      final map = MindMap.fromTitle('起点');
      map.addChild(map.root, '子');
      final restored = parseJsonBackup(buildJsonBackup([map]));
      expect(restored.length, 1);
      expect(restored[0].title, '起点');
      expect(restored[0].nodes.length, 2);
    });

    test('parseJsonBackup は壊れた入力に日本語エラーを返す', () {
      expect(
        () => parseJsonBackup('これはJSONではない'),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', 'JSONとして読み取れませんでした')),
      );
      expect(
        () => parseJsonBackup('{"foo": 1}'),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', 'このアプリのバックアップ形式ではありません')),
      );
      expect(
        () => parseJsonBackup('{"format": "mindmap-backup", "maps": [{"bad": 1}]}'),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', 'マップデータの読み取りに失敗しました')),
      );
    });
  });

  group('アプリ操作フロー', () {
    testWidgets('タイトル入力→作成でキャンバスが開き中央に四角が置かれる',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MindMapApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '大事な予定に遅れた');
      await tester.tap(find.text('作成'));
      await tester.pumpAndSettle();

      // AppBar のタイトルとルートノードの2箇所に表示される
      expect(find.text('大事な予定に遅れた'), findsNWidgets(2));
    });

    testWidgets('四角をタップ→入力→追加でつながる四角が増える',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MindMapApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '起点');
      await tester.tap(find.text('作成'));
      await tester.pumpAndSettle();

      // ルートの四角をタップ(AppBar のタイトルではなくキャンバス内のノードを選ぶ)
      await tester.tap(
        find.descendant(
            of: find.byType(InteractiveViewer), matching: find.text('起点')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('つながる内容を入力'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '遅れてもいいと自己判断した');
      await tester.tap(find.text('追加'));
      await tester.pumpAndSettle();

      expect(find.text('遅れてもいいと自己判断した'), findsOneWidget);

      // できた四角をタップするとさらに子を追加できる
      await tester.tap(find.text('遅れてもいいと自己判断した'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'アラームを2段階セット');
      await tester.tap(find.text('追加'));
      await tester.pumpAndSettle();

      expect(find.text('アラームを2段階セット'), findsOneWidget);
    });

    testWidgets('長押しメニューから編集・削除ができる', (WidgetTester tester) async {
      await tester.pumpWidget(const MindMapApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '起点');
      await tester.tap(find.text('作成'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
            of: find.byType(InteractiveViewer), matching: find.text('起点')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '消す予定の四角');
      await tester.tap(find.text('追加'));
      await tester.pumpAndSettle();

      // 長押し → 編集
      await tester.longPress(find.text('消す予定の四角'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('テキストを編集'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '編集後のテキスト');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('編集後のテキスト'), findsOneWidget);
      expect(find.text('消す予定の四角'), findsNothing);

      // 長押し → 削除
      await tester.longPress(find.text('編集後のテキスト'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('この四角を削除(枝ごと)'));
      await tester.pumpAndSettle();
      expect(find.text('編集後のテキスト'), findsNothing);
    });

    testWidgets('リスト表示で振り返り、コピーできる', (WidgetTester tester) async {
      // Clipboard 呼び出しを捕捉する
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );

      await tester.pumpWidget(const MindMapApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '起点');
      await tester.tap(find.text('作成'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
            of: find.byType(InteractiveViewer), matching: find.text('起点')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '振り返りたい内容');
      await tester.tap(find.text('追加'));
      await tester.pumpAndSettle();

      // エディタからリスト表示を開く
      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pumpAndSettle();
      expect(find.text('リストで振り返る'), findsOneWidget);
      expect(find.text('起点'), findsOneWidget);
      expect(find.text('振り返りたい内容'), findsOneWidget);

      // テキストとしてコピー
      await tester.tap(find.byIcon(Icons.copy_outlined));
      await tester.pumpAndSettle();
      expect(copied, '- 起点\n  - 振り返りたい内容');
      expect(find.text('リストをコピーしました'), findsOneWidget);

      // ホーム一覧のリストボタンからも開ける
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pumpAndSettle();
      expect(find.text('リストで振り返る'), findsOneWidget);
      expect(find.text('振り返りたい内容'), findsOneWidget);
    });

    testWidgets('保存ボタンからJSONバックアップとAI分析用エクスポートができる',
        (WidgetTester tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );

      await tester.pumpWidget(const MindMapApp());
      await tester.pumpAndSettle();

      // マップがないときに書き出しを選ぶとスナックバーで知らせる
      await tester.tap(find.byIcon(Icons.save_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JSONでバックアップ'));
      await tester.pumpAndSettle();
      expect(find.text('まだマインドマップがありません'), findsOneWidget);
      // スナックバーが消えるのを待つ(残っていると下部のボタンへのタップを遮る)
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // マップを1つ作ってホームに戻る
      await tester.enterText(find.byType(TextField), '起点');
      await tester.tap(find.text('作成'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
            of: find.byType(InteractiveViewer), matching: find.text('起点')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '考えたこと');
      await tester.tap(find.text('追加'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // JSONバックアップ
      await tester.tap(find.byIcon(Icons.save_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JSONでバックアップ'));
      await tester.pumpAndSettle();
      expect(find.text('JSONバックアップ'), findsOneWidget);
      await tester.tap(find.text('コピー'));
      await tester.pumpAndSettle();
      final decoded = jsonDecode(copied!) as Map<String, dynamic>;
      expect(decoded['format'], 'mindmap-backup');
      expect((decoded['maps'] as List).length, 1);

      // 「コピーしました」スナックバーが消えるのを待ってから次へ
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // AI分析用エクスポート
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.save_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI分析用にエクスポート'));
      await tester.pumpAndSettle();
      expect(find.text('AI分析用エクスポート'), findsOneWidget);
      await tester.tap(find.text('コピー'));
      await tester.pumpAndSettle();
      expect(copied, contains('思考分析用エクスポート'));
      expect(copied, contains('## マップ1: 起点'));
      expect(copied, contains('  - 考えたこと'));
    });

    testWidgets('バックアップから復元できる(追加と置き換え)', (WidgetTester tester) async {
      final backup = buildJsonBackup([MindMap.fromTitle('復元マップ')]);

      await tester.pumpWidget(const MindMapApp());
      await tester.pumpAndSettle();

      // 既存マップを1つ作ってホームに戻る
      await tester.enterText(find.byType(TextField), '起点');
      await tester.tap(find.text('作成'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // 復元(追加): 既存の「起点」に「復元マップ」が加わる
      await tester.tap(find.byIcon(Icons.save_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text('バックアップから復元'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), backup);
      await tester.tap(find.text('読み込む'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1個のマップ'), findsOneWidget);
      await tester.tap(find.text('追加して取り込む(今あるマップは残す)'));
      await tester.pumpAndSettle();
      expect(find.text('1個のマップを追加しました'), findsOneWidget);
      expect(find.text('起点'), findsOneWidget);
      expect(find.text('復元マップ'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // 同じバックアップをもう一度「追加」すると重複はスキップされる
      await tester.tap(find.byIcon(Icons.save_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text('バックアップから復元'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), backup);
      await tester.tap(find.text('読み込む'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('追加して取り込む(今あるマップは残す)'));
      await tester.pumpAndSettle();
      expect(find.text('0個のマップを追加しました(1個は既にあるためスキップ)'),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // 復元(置き換え): 確認ダイアログを経て「復元マップ」だけになる
      await tester.tap(find.byIcon(Icons.save_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text('バックアップから復元'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), backup);
      await tester.tap(find.text('読み込む'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全て置き換える(今あるマップは削除)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('置き換えます。よろしいですか?'), findsOneWidget);
      await tester.tap(find.text('置き換える'));
      await tester.pumpAndSettle();
      expect(find.text('1個のマップに置き換えました'), findsOneWidget);
      expect(find.text('復元マップ'), findsOneWidget);
      expect(find.text('起点'), findsNothing);
    });

    testWidgets('壊れたJSONを読み込むとエラーメッセージが出る',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MindMapApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.save_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text('バックアップから復元'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'こわれたデータ');
      await tester.tap(find.text('読み込む'));
      await tester.pumpAndSettle();
      expect(find.text('JSONとして読み取れませんでした'), findsOneWidget);
    });
  });
}

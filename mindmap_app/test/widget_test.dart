import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });
}

import 'package:flutter/material.dart';

import 'editor_screen.dart';
import 'export.dart';
import 'export_screen.dart';
import 'import_screen.dart';
import 'models.dart';
import 'outline_screen.dart';
import 'storage.dart';

void main() {
  runApp(const MindMapApp());
}

const accentColor = Color(0xFF5B7CFA);

class MindMapApp extends StatelessWidget {
  const MindMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'マインドマップ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: accentColor),
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storage = MapStorage();
  final _titleController = TextEditingController();
  List<MindMap> _maps = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final maps = await _storage.load();
    setState(() {
      _maps = maps;
      _loaded = true;
    });
  }

  Future<void> _persist() => _storage.save(_maps);

  Future<void> _createMap() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final map = MindMap.fromTitle(title);
    setState(() {
      _maps.add(map);
      _titleController.clear();
    });
    await _persist();
    if (!mounted) return;
    _openMap(map);
  }

  Future<void> _openMap(MindMap map) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => EditorScreen(map: map, onChanged: _persist)),
    );
    // 編集から戻ったら一覧の表示(ノード数・更新日時)を更新
    setState(() {});
  }

  Future<void> _deleteMap(MindMap map) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('「${map.title}」を削除しますか?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _maps.remove(map));
    await _persist();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}/${d.month}/${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  /// エクスポート系メニューの共通処理:マップが無ければ知らせて何もしない。
  void _openExport({required String title, required String subject, required String Function(DateTime) build}) {
    if (_maps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('まだマインドマップがありません')),
      );
      return;
    }
    final now = DateTime.now();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExportScreen(
          title: title,
          subject: subject.replaceAll('{ts}', exportTimestamp(now)),
          text: build(now),
        ),
      ),
    );
  }

  /// バックアップJSONからの復元。
  Future<void> _openImport() async {
    final request = await Navigator.of(context).push<ImportRequest>(
      MaterialPageRoute(builder: (_) => const ImportScreen()),
    );
    if (request == null || !mounted) return;

    if (request.mode == ImportMode.replace && _maps.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            '今ある${_maps.length}個のマップを削除して、バックアップの${request.maps.length}個に置き換えます。よろしいですか?',
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('置き換える', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    var message = '';
    setState(() {
      if (request.mode == ImportMode.replace) {
        _maps = List.of(request.maps);
        message = '${request.maps.length}個のマップに置き換えました';
      } else {
        final existing = _maps.map((m) => m.id).toSet();
        var added = 0;
        var skipped = 0;
        for (final m in request.maps) {
          if (existing.contains(m.id)) {
            skipped++;
          } else {
            _maps.add(m);
            added++;
          }
        }
        message = skipped == 0
            ? '$added個のマップを追加しました'
            : '$added個のマップを追加しました($skipped個は既にあるためスキップ)';
      }
    });
    await _persist();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 保存ボタン → バックアップ/エクスポート/復元の選択シート
  Future<void> _showExportMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('保存・エクスポート',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('JSONでバックアップ'),
              subtitle: const Text('全マップを復元できる形式で書き出す'),
              onTap: () {
                Navigator.pop(context);
                _openExport(
                  title: 'JSONバックアップ',
                  subject: 'mindmap-backup_{ts}.json',
                  build: (now) => buildJsonBackup(_maps, now: now),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.psychology_outlined),
              title: const Text('AI分析用にエクスポート'),
              subtitle: const Text('生成AIに考え方を分析してもらうためのテキスト'),
              onTap: () {
                Navigator.pop(context);
                _openExport(
                  title: 'AI分析用エクスポート',
                  subject: 'mindmap-analysis_{ts}.md',
                  build: (now) => buildAiExport(_maps, now: now),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('バックアップから復元'),
              subtitle: const Text('書き出したJSONを読み込んで戻す'),
              onTap: () {
                Navigator.pop(context);
                _openImport();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [..._maps]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Scaffold(
      appBar: AppBar(
        title: const Text('マインドマップ',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: '保存・エクスポート',
            icon: const Icon(Icons.save_alt),
            onPressed: _showExportMenu,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                '起点(問題やテーマ)をタイトルにして新しいキャンバスを作成。四角をタップすると、つながる四角が増えていきます。',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade600, height: 1.6),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _titleController,
                      maxLength: 60,
                      decoration: const InputDecoration(
                        hintText: '起点を入力(例:大事な予定に遅れた)',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                        ),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                      onSubmitted: (_) => _createMap(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _createMap,
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 16),
                    ),
                    child: const Text('作成',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: !_loaded
                    ? const Center(child: CircularProgressIndicator())
                    : sorted.isEmpty
                        ? Center(
                            child: Text(
                              'まだマインドマップがありません。\n上の欄に起点を入力して作成してください。',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey.shade600,
                                  height: 1.8,
                                  fontSize: 14),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: sorted.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final map = sorted[i];
                              return Card(
                                elevation: 1,
                                margin: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  title: Text(
                                    map.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    '${map.nodes.length}個の四角 ・ ${_fmtDate(map.updatedAt)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'リストで振り返る',
                                        icon: const Icon(
                                            Icons.format_list_bulleted),
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    OutlineScreen(map: map)),
                                          );
                                        },
                                      ),
                                      IconButton(
                                        tooltip: '削除',
                                        icon:
                                            const Icon(Icons.delete_outline),
                                        onPressed: () => _deleteMap(map),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _openMap(map),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

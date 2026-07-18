import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'export.dart';
import 'main.dart' show accentColor;
import 'models.dart';

enum ImportMode { merge, replace }

/// インポート画面の結果。取り込むマップと取り込み方を返す。
class ImportRequest {
  const ImportRequest(this.mode, this.maps);

  final ImportMode mode;
  final List<MindMap> maps;
}

/// バックアップJSONを貼り付けて復元する画面。
/// 結果は Navigator.pop の戻り値([ImportRequest])で返す。
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _controller = TextEditingController();
  List<MindMap>? _parsed;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    setState(() {
      _controller.text = text;
      _parsed = null;
      _error = null;
    });
  }

  void _parse() {
    try {
      final maps = parseJsonBackup(_controller.text.trim());
      setState(() {
        _parsed = maps;
        _error = maps.isEmpty ? 'バックアップにマップがありません' : null;
        if (maps.isEmpty) _parsed = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _parsed = null;
        _error = e.message;
      });
    }
  }

  void _apply(ImportMode mode) {
    final maps = _parsed;
    if (maps == null) return;
    Navigator.pop(context, ImportRequest(mode, maps));
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    final nodeCount =
        parsed?.fold<int>(0, (sum, m) => sum + m.nodes.length) ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('バックアップから復元',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  expands: true,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: '「JSONでバックアップ」で書き出したテキストをここに貼り付け',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  onChanged: (_) => setState(() {
                    _parsed = null;
                    _error = null;
                  }),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              if (parsed == null) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.content_paste),
                        label: const Text('クリップボードから貼り付け'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _parse,
                        icon: const Icon(Icons.search),
                        label: const Text('読み込む'),
                        style: FilledButton.styleFrom(
                          backgroundColor: accentColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDF0F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${parsed.length}個のマップ(四角$nodeCount個)が見つかりました。取り込み方を選んでください。',
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _apply(ImportMode.merge),
                  icon: const Icon(Icons.library_add_outlined),
                  label: const Text('追加して取り込む(今あるマップは残す)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _apply(ImportMode.replace),
                  icon: const Icon(Icons.restore),
                  label: const Text('全て置き換える(今あるマップは削除)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

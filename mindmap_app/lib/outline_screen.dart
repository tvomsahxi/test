import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart' show accentColor;
import 'models.dart';

/// マインドマップをインデント付きリストで振り返る画面。
class OutlineScreen extends StatelessWidget {
  const OutlineScreen({super.key, required this.map});

  final MindMap map;

  String _fmtDate(DateTime d) =>
      '${d.year}/${d.month}/${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _copyToClipboard(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: map.toOutlineText()));
    messenger.showSnackBar(
      const SnackBar(content: Text('リストをコピーしました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = map.outline();
    return Scaffold(
      appBar: AppBar(
        title: const Text('リストで振り返る',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'テキストとしてコピー',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => _copyToClipboard(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '作成 ${_fmtDate(map.createdAt)} ・ 更新 ${_fmtDate(map.updatedAt)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          for (final (node, depth) in entries)
            Padding(
              padding: EdgeInsets.only(left: depth * 20.0, bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Icon(
                      depth == 0 ? Icons.flag : Icons.circle,
                      size: depth == 0 ? 16 : 8,
                      color: depth == 0 ? accentColor : Colors.grey.shade400,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      node.text,
                      style: TextStyle(
                        fontSize: depth == 0 ? 16 : 14,
                        fontWeight:
                            depth == 0 ? FontWeight.w700 : FontWeight.w400,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

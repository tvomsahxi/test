import 'dart:async';

import 'package:flutter/material.dart';

import 'main.dart' show accentColor;
import 'models.dart';
import 'outline_screen.dart';

/// キャンバスの論理サイズ。中央がノード座標の原点。
const double _canvasSize = 4000;
const double _canvasCenter = _canvasSize / 2;

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.map, required this.onChanged});

  final MindMap map;
  final Future<void> Function() onChanged;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _viewController = TransformationController();
  Size _viewport = Size.zero;
  bool _hintVisible = true;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _hintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _hintVisible = false);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _viewController.dispose();
    super.dispose();
  }

  void _centerView() {
    _viewController.value = Matrix4.translationValues(
      _viewport.width / 2 - _canvasCenter,
      _viewport.height / 2 - _canvasCenter,
      0,
    );
  }

  Future<void> _markChanged() {
    widget.map.updatedAt = DateTime.now();
    return widget.onChanged();
  }

  /// テキスト入力ダイアログ。空欄・キャンセルなら null。
  Future<String?> _askText({
    required String heading,
    required String okLabel,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(heading, style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
            hintText: '思いついたことを入力…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accentColor),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(okLabel),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return null;
    return result;
  }

  /// 四角をタップ → つながる四角を追加
  Future<void> _addChild(MindNode parent) async {
    final text = await _askText(heading: 'つながる内容を入力', okLabel: '追加');
    if (text == null) return;
    setState(() => widget.map.addChild(parent, text));
    await _markChanged();
  }

  /// 四角を長押し → 編集・削除メニュー
  Future<void> _showNodeMenu(MindNode node) async {
    final label =
        node.text.length > 20 ? '${node.text.substring(0, 20)}…' : node.text;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('「$label」',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('テキストを編集'),
              onTap: () {
                Navigator.pop(context);
                _editNode(node);
              },
            ),
            if (!node.isRoot)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('この四角を削除(枝ごと)',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteNode(node);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _editNode(MindNode node) async {
    final text = await _askText(
        heading: 'テキストを編集', okLabel: '保存', initial: node.text);
    if (text == null) return;
    setState(() {
      node.text = text;
      if (node.isRoot) widget.map.title = text;
    });
    await _markChanged();
  }

  Future<void> _deleteNode(MindNode node) async {
    final size = widget.map.subtreeSize(node);
    if (size > 1) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('この四角と、つながる${size - 1}個の四角も削除されます。よろしいですか?',
              style: const TextStyle(fontSize: 16)),
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
    }
    setState(() => widget.map.removeSubtree(node));
    await _markChanged();
  }

  void _moveNode(MindNode node, Offset delta) {
    // GestureDetector の delta は画面座標なので、ズーム倍率で割って
    // キャンバス座標に変換する。
    final scale = _viewController.value.getMaxScaleOnAxis();
    setState(() {
      node.x += delta.dx / scale;
      node.y += delta.dy / scale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.map.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'リストで振り返る',
            icon: const Icon(Icons.format_list_bulleted),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => OutlineScreen(map: widget.map)),
              );
            },
          ),
          IconButton(
            tooltip: '中心に戻る',
            icon: const Icon(Icons.filter_center_focus),
            onPressed: _centerView,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (size != _viewport) {
            _viewport = size;
            _centerView();
          }
          return Stack(
            children: [
              InteractiveViewer(
                transformationController: _viewController,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                minScale: 0.35,
                maxScale: 2.5,
                child: SizedBox(
                  width: _canvasSize,
                  height: _canvasSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(painter: _EdgePainter(widget.map)),
                      ),
                      for (final node in widget.map.nodes)
                        Positioned(
                          left: _canvasCenter + node.x,
                          top: _canvasCenter + node.y,
                          child: FractionalTranslation(
                            translation: const Offset(-0.5, -0.5),
                            child: _NodeBox(
                              key: ValueKey(node.id),
                              node: node,
                              onTap: () => _addChild(node),
                              onLongPress: () => _showNodeMenu(node),
                              onDrag: (delta) => _moveNode(node, delta),
                              onDragEnd: _markChanged,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _hintVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 500),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xC71F2430),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          '四角をタップ → つながる四角を追加 / 長押し → 編集・削除',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// マインドマップの四角(ノード)ウィジェット。
class _NodeBox extends StatelessWidget {
  const _NodeBox({
    super.key,
    required this.node,
    required this.onTap,
    required this.onLongPress,
    required this.onDrag,
    required this.onDragEnd,
  });

  final MindNode node;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<Offset> onDrag;
  final Future<void> Function() onDragEnd;

  @override
  Widget build(BuildContext context) {
    final isRoot = node.isRoot;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onPanUpdate: (details) => onDrag(details.delta),
      onPanEnd: (_) => onDragEnd(),
      child: Container(
        constraints: const BoxConstraints(minWidth: 60, maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isRoot ? accentColor : Colors.white,
          border: Border.all(
            color: isRoot ? accentColor : const Color(0xFFC9D2EA),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F1E2850),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          node.text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isRoot ? Colors.white : const Color(0xFF1F2430),
            fontSize: isRoot ? 15 : 14,
            fontWeight: isRoot ? FontWeight.w700 : FontWeight.w400,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

/// 親子ノードをつなぐ曲線を描く。
class _EdgePainter extends CustomPainter {
  _EdgePainter(this.map);

  final MindMap map;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFAAB6D8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (final node in map.nodes) {
      final parent = map.nodeById(node.parentId);
      if (parent == null) continue;
      final p1 = Offset(_canvasCenter + parent.x, _canvasCenter + parent.y);
      final p2 = Offset(_canvasCenter + node.x, _canvasCenter + node.y);
      final mx = (p1.dx + p2.dx) / 2;
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(mx, p1.dy, mx, p2.dy, p2.dx, p2.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_EdgePainter oldDelegate) => true;
}

import 'dart:math';

String _uid() {
  final r = Random();
  return DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      r.nextInt(1 << 32).toRadixString(36);
}

/// マインドマップ上の1つの四角(ノード)。
/// 座標はキャンバス中心を原点とした論理座標。
class MindNode {
  MindNode({
    String? id,
    required this.text,
    this.parentId,
    this.x = 0,
    this.y = 0,
  }) : id = id ?? _uid();

  final String id;
  String text;
  final String? parentId;
  double x;
  double y;

  bool get isRoot => parentId == null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'parentId': parentId,
        'x': x,
        'y': y,
      };

  factory MindNode.fromJson(Map<String, dynamic> json) => MindNode(
        id: json['id'] as String,
        text: json['text'] as String,
        parentId: json['parentId'] as String?,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
      );
}

class MindMap {
  MindMap({
    String? id,
    required this.title,
    required this.nodes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uid(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 起点タイトルから、中央にルートノードを持つ新しいマップを作る。
  factory MindMap.fromTitle(String title) => MindMap(
        title: title,
        nodes: [MindNode(text: title)],
      );

  final String id;
  String title;
  final List<MindNode> nodes;
  final DateTime createdAt;
  DateTime updatedAt;

  MindNode get root => nodes.firstWhere((n) => n.isRoot);

  List<MindNode> childrenOf(String id) =>
      nodes.where((n) => n.parentId == id).toList();

  MindNode? nodeById(String? id) {
    if (id == null) return null;
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// 親から見て空いている方向に子を置く座標を返す。
  static const double nodeDistance = 170;

  MindNode addChild(MindNode parent, String text) {
    final grand = nodeById(parent.parentId);
    final siblings = childrenOf(parent.id);
    final n = siblings.length;

    double baseAngle;
    double offset;
    if (grand != null) {
      baseAngle = atan2(parent.y - grand.y, parent.x - grand.x);
      const spread = pi / 3 * 0.8;
      offset = (n.isEven ? 1 : -1) * ((n + 1) ~/ 2) * spread;
    } else {
      baseAngle = -pi / 2; // ルートの子は上から時計回りに配置
      offset = n * (2 * pi / 8);
    }
    final angle = baseAngle + offset;
    final child = MindNode(
      text: text,
      parentId: parent.id,
      x: parent.x + cos(angle) * nodeDistance,
      y: parent.y + sin(angle) * nodeDistance,
    );
    nodes.add(child);
    return child;
  }

  /// ノードをその枝(子孫)ごと削除する。削除した個数を返す。
  int removeSubtree(MindNode node) {
    final doomed = <String>{};
    void collect(String id) {
      doomed.add(id);
      for (final c in childrenOf(id)) {
        collect(c.id);
      }
    }

    collect(node.id);
    nodes.removeWhere((n) => doomed.contains(n.id));
    return doomed.length;
  }

  /// 削除確認用:この枝に含まれるノード数(自分含む)。
  int subtreeSize(MindNode node) {
    var count = 1;
    for (final c in childrenOf(node.id)) {
      count += subtreeSize(c);
    }
    return count;
  }

  /// ルートから深さ優先でたどった (ノード, 深さ) のリスト。
  /// 振り返り用のアウトライン表示に使う。追加した順に並ぶ。
  List<(MindNode, int)> outline() {
    final result = <(MindNode, int)>[];
    void walk(MindNode node, int depth) {
      result.add((node, depth));
      for (final c in childrenOf(node.id)) {
        walk(c, depth + 1);
      }
    }

    walk(root, 0);
    return result;
  }

  /// アウトラインをインデント付きテキストにする(コピー・共有用)。
  String toOutlineText() => outline()
      .map((e) => '${'  ' * e.$2}- ${e.$1.text.replaceAll('\n', ' ')}')
      .join('\n');

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory MindMap.fromJson(Map<String, dynamic> json) => MindMap(
        id: json['id'] as String,
        title: json['title'] as String,
        nodes: (json['nodes'] as List)
            .map((n) => MindNode.fromJson(n as Map<String, dynamic>))
            .toList(),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
      );
}

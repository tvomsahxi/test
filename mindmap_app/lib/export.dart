import 'dart:convert';

import 'models.dart';

/// エクスポートのファイル名などに使うタイムスタンプ(例: 2026-07-18_1530)。
String exportTimestamp(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}${two(now.minute)}';
}

String _fmtDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}/${d.month}/${d.day} ${d.hour}:${two(d.minute)}';
}

/// 全マップを復元可能なJSON形式でバックアップする。
/// 保存形式(MindMap.toJson)をそのまま含むので、後から読み戻せる。
String buildJsonBackup(List<MindMap> maps, {DateTime? now}) {
  final data = {
    'app': 'mindmap_app',
    'format': 'mindmap-backup',
    'version': 1,
    'exportedAt': (now ?? DateTime.now()).toIso8601String(),
    'mapCount': maps.length,
    'maps': maps.map((m) => m.toJson()).toList(),
  };
  return const JsonEncoder.withIndent('  ').convert(data);
}

/// バックアップJSONを解析してマップ一覧を返す。
/// 読み取れない場合は日本語メッセージ付きの FormatException を投げる。
List<MindMap> parseJsonBackup(String text) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    throw const FormatException('JSONとして読み取れませんでした');
  }
  if (decoded is! Map<String, dynamic> ||
      decoded['format'] != 'mindmap-backup') {
    throw const FormatException('このアプリのバックアップ形式ではありません');
  }
  final maps = decoded['maps'];
  if (maps is! List) {
    throw const FormatException('バックアップにマップが含まれていません');
  }
  try {
    return maps
        .map((e) => MindMap.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    throw const FormatException('マップデータの読み取りに失敗しました');
  }
}

/// 生成AIに読ませて思考の傾向を分析してもらうためのMarkdownを作る。
/// 各マップを日付付きのアウトラインとして並べ、冒頭に分析を促す説明を置く。
String buildAiExport(List<MindMap> maps, {DateTime? now}) {
  final sorted = [...maps]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final buf = StringBuffer()
    ..writeln('# マインドマップ 思考分析用エクスポート')
    ..writeln()
    ..writeln('出力日時: ${_fmtDate(now ?? DateTime.now())} / マップ数: ${maps.length}')
    ..writeln()
    ..writeln('以下は、私が「起きた問題やテーマ」を起点に作成したマインドマップの記録です。')
    ..writeln('起点から枝分かれした各行は、そのとき私が考えたこと・原因・対策です。')
    ..writeln('インデントの深さが枝の深さ(思考の連なり)を表します。')
    ..writeln()
    ..writeln('このデータをもとに、次の観点で私の考え方を分析してください:')
    ..writeln('- 繰り返し現れるテーマや思考のパターン(癖)')
    ..writeln('- 問題が起きたときの判断の傾向(例: 自己解釈で楽観的に判断していないか)')
    ..writeln('- 対策の立て方の傾向と、抜けやすい視点')
    ..writeln('- 今後に向けた具体的なアドバイス')
    ..writeln();

  for (final (i, map) in sorted.indexed) {
    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## マップ${i + 1}: ${map.title.replaceAll('\n', ' ')}')
      ..writeln()
      ..writeln(
          '作成: ${_fmtDate(map.createdAt)} / 更新: ${_fmtDate(map.updatedAt)} / 四角の数: ${map.nodes.length}')
      ..writeln()
      ..writeln(map.toOutlineText())
      ..writeln();
  }
  return buf.toString();
}

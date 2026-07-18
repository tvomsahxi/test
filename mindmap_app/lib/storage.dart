import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// マップ一覧を端末に保存・読込する。
class MapStorage {
  static const _key = 'mindmaps-v1';

  Future<List<MindMap>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => MindMap.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<MindMap> maps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(maps.map((m) => m.toJson()).toList()));
  }
}

// lib/providers/tag_provider.dart
// Manages tags (load, add, update, delete) with usage count tracking.

import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../models/models.dart';

class TagProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;

  List<TagModel> _tags = [];
  List<TagModel> get tags => List.unmodifiable(_tags);

  Map<int, int> _usageCounts = {};
  int usageCount(int tagId) => _usageCounts[tagId] ?? 0;

  bool _loading = false;
  bool get loading => _loading;

  TagModel? getById(int id) {
    try {
      return _tags.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _tags = await _db.getAllTags();
    _usageCounts = await _db.getTagUsageCounts();
    _loading = false;
    notifyListeners();
  }

  Future<void> addTag(TagModel tag) async {
    final saved = await _db.insertTag(tag);
    _tags = [..._tags, saved];
    notifyListeners();
  }

  Future<void> updateTag(TagModel tag) async {
    await _db.updateTag(tag);
    final idx = _tags.indexWhere((t) => t.id == tag.id);
    if (idx != -1) {
      _tags = List.from(_tags)..[idx] = tag;
      notifyListeners();
    }
  }

  Future<void> deleteTag(int id) async {
    await _db.deleteTag(id);
    _tags = _tags.where((t) => t.id != id).toList();
    _usageCounts.remove(id);
    notifyListeners();
  }
}

import 'package:flutter/foundation.dart';
import '../models/tag.dart';
import '../services/tag_service.dart';

class TagManager extends ChangeNotifier {
  final TagService _service = TagService();
  List<Tag> _tags = [];
  bool _isLoading = false;

  List<Tag> get tags => _tags;
  bool get isLoading => _isLoading;

  Future<void> loadTags() async {
    _isLoading = true;
    notifyListeners();

    _tags = await _service.getAll();

    _isLoading = false;
    notifyListeners();
  }

  Future<Tag?> getTagById(int id) async {
    return await _service.getById(id);
  }

  Future<int> addTag(Tag tag) async {
    final id = await _service.insert(tag);
    await loadTags();
    return id;
  }

  Future<void> updateTag(Tag tag) async {
    await _service.update(tag);
    await loadTags();
  }

  Future<void> deleteTag(int id) async {
    await _service.delete(id);
    await loadTags();
  }

  Future<List<Tag>> getTagsForAlbum(int albumId) async {
    return await _service.getTagsForAlbum(albumId);
  }

  Future<void> setTagsForAlbum(int albumId, List<int> tagIds) async {
    await _service.setTagsForAlbum(albumId, tagIds);
  }

  /// Filter local list by name
  List<Tag> filterTags({String? query}) {
    if (query == null || query.isEmpty) return _tags;
    final lower = query.toLowerCase();
    return _tags.where((t) => t.name.toLowerCase().contains(lower)).toList();
  }
}

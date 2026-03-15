// lib/providers/selection_provider.dart
// Manages the global selected-images pool (persisted in SQLite).

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../db/database_helper.dart';

class SelectionProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;

  /// Ordered list of selected asset IDs (persisted).
  List<String> _assetIds = [];
  List<String> get assetIds => List.unmodifiable(_assetIds);

  /// Resolved AssetEntity objects (populated lazily/on demand).
  List<AssetEntity> _entities = [];
  List<AssetEntity> get entities => List.unmodifiable(_entities);

  bool get isEmpty => _assetIds.isEmpty;
  int get count => _assetIds.length;

  bool isSelected(String assetId) => _assetIds.contains(assetId);

  Future<void> load() async {
    _assetIds = await _db.getSelectedAssetIds();
    await _resolveEntities();
    notifyListeners();
  }

  Future<void> toggle(String assetId) async {
    if (_assetIds.contains(assetId)) {
      await _db.removeFromSelected(assetId);
      _assetIds = List.from(_assetIds)..remove(assetId);
    } else {
      await _db.addToSelected(assetId);
      _assetIds = List.from(_assetIds)..add(assetId);
    }
    await _resolveEntities();
    notifyListeners();
  }

  /// Selects [assetId] if not already selected.
  /// Skips entity resolution for speed — used by drag-to-select where
  /// resolution on every frame would cause jank.
  Future<void> select(String assetId) async {
    if (_assetIds.contains(assetId)) return;
    await _db.addToSelected(assetId);
    _assetIds = List.from(_assetIds)..add(assetId);
    notifyListeners();
  }

  /// Deselects [assetId] if currently selected.
  /// Same performance trade-off as [select].
  Future<void> deselect(String assetId) async {
    if (!_assetIds.contains(assetId)) return;
    await _db.removeFromSelected(assetId);
    _assetIds = List.from(_assetIds)..remove(assetId);
    notifyListeners();
  }

  Future<void> removeOne(String assetId) async {
    await _db.removeFromSelected(assetId);
    _assetIds = List.from(_assetIds)..remove(assetId);
    _entities = _entities.where((e) => e.id != assetId).toList();
    notifyListeners();
  }

  /// Selects all [assetIds] not already selected. Batched single DB write.
  Future<void> addMultiple(Set<String> assetIds) async {
    final toAdd = assetIds.where((id) => !_assetIds.contains(id)).toList();
    if (toAdd.isEmpty) return;
    await _db.addMultipleToSelected(toAdd);
    _assetIds = List.from(_assetIds)..addAll(toAdd);
    notifyListeners();
  }

  /// Deselects all [assetIds] that are currently selected. Batched single DB write.
  Future<void> removeMultiple(Set<String> assetIds) async {
    final toRemove = assetIds.where((id) => _assetIds.contains(id)).toList();
    if (toRemove.isEmpty) return;
    await _db.removeMultipleFromSelected(toRemove);
    final removeSet = toRemove.toSet();
    _assetIds = _assetIds.where((id) => !removeSet.contains(id)).toList();
    notifyListeners();
  }

  /// Atomically sets selection to exactly [desired]. Computes the diff and
  /// issues a single batch add and a single batch remove. Used by drag-select
  /// to keep the DB consistent during a sweep without per-item writes.
  Future<void> setSelection(Set<String> desired) async {
    final current = _assetIds.toSet();
    final toAdd = desired.difference(current).toList();
    final toRemove = current.difference(desired).toList();
    if (toAdd.isEmpty && toRemove.isEmpty) return;
    if (toAdd.isNotEmpty) await _db.addMultipleToSelected(toAdd);
    if (toRemove.isNotEmpty) await _db.removeMultipleFromSelected(toRemove);
    // Preserve order of previously-selected items; append newly added ones.
    final newIds = _assetIds
        .where((id) => !toRemove.contains(id))
        .toList()
      ..addAll(toAdd);
    _assetIds = newIds;
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _db.clearSelected();
    _assetIds = [];
    _entities = [];
    notifyListeners();
  }

  /// Reorder in-memory only; call [persistOrder] to save.
  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final idsCopy = List<String>.from(_assetIds);
    final entCopy = List<AssetEntity>.from(_entities);
    final id = idsCopy.removeAt(oldIndex);
    idsCopy.insert(newIndex, id);
    if (oldIndex < entCopy.length) {
      final ent = entCopy.removeAt(oldIndex);
      entCopy.insert(newIndex, ent);
    }
    _assetIds = idsCopy;
    _entities = entCopy;
    notifyListeners();
  }

  Future<void> persistOrder() async {
    await _db.setSelectedOrder(_assetIds);
  }

  Future<void> _resolveEntities() async {
    final resolved = <AssetEntity>[];
    for (final id in _assetIds) {
      final entity = await AssetEntity.fromId(id);
      if (entity != null) resolved.add(entity);
    }
    _entities = resolved;
  }
}

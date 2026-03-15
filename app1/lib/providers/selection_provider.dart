// lib/providers/selection_provider.dart
// Manages the global selected-images pool (persisted in SQLite).
//
// Design:
// - _assetIds (List) preserves insertion order for ImagesSelectedView reordering.
// - _selectedSet (Set) mirrors _assetIds for O(1) isSelected() lookups.
// - Entities are resolved lazily — call resolveEntities() only when needed
//   (i.e. when ImagesSelectedView is opened), not on every toggle.

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../db/database_helper.dart';

class SelectionProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;

  List<String> _assetIds = [];
  List<String> get assetIds => List.unmodifiable(_assetIds);

  final Set<String> _selectedSet = {};

  List<AssetEntity> _entities = [];
  List<AssetEntity> get entities => List.unmodifiable(_entities);

  bool _entitiesDirty = false;

  bool get isEmpty => _assetIds.isEmpty;
  int get count => _assetIds.length;

  bool isSelected(String assetId) => _selectedSet.contains(assetId);

  Future<void> load() async {
    _assetIds = await _db.getSelectedAssetIds();
    _selectedSet..clear()..addAll(_assetIds);
    _entitiesDirty = true;
    notifyListeners();
  }

  /// Resolves AssetEntity objects for the current selection.
  /// Call this when ImagesSelectedView is about to display the list.
  Future<void> resolveEntities() async {
    if (!_entitiesDirty) return;
    final resolved = <AssetEntity>[];
    for (final id in _assetIds) {
      final entity = await AssetEntity.fromId(id);
      if (entity != null) resolved.add(entity);
    }
    _entities = resolved;
    _entitiesDirty = false;
    notifyListeners();
  }

  Future<void> toggle(String assetId) async {
    if (_selectedSet.contains(assetId)) {
      await _db.removeFromSelected(assetId);
      _assetIds = List.from(_assetIds)..remove(assetId);
      _selectedSet.remove(assetId);
    } else {
      await _db.addToSelected(assetId);
      _assetIds = List.from(_assetIds)..add(assetId);
      _selectedSet.add(assetId);
    }
    _entitiesDirty = true;
    notifyListeners();
  }

  Future<void> select(String assetId) async {
    if (_selectedSet.contains(assetId)) return;
    await _db.addToSelected(assetId);
    _assetIds = List.from(_assetIds)..add(assetId);
    _selectedSet.add(assetId);
    _entitiesDirty = true;
    notifyListeners();
  }

  Future<void> deselect(String assetId) async {
    if (!_selectedSet.contains(assetId)) return;
    await _db.removeFromSelected(assetId);
    _assetIds = List.from(_assetIds)..remove(assetId);
    _selectedSet.remove(assetId);
    _entitiesDirty = true;
    notifyListeners();
  }

  Future<void> addMultiple(Set<String> assetIds) async {
    final toAdd = assetIds.where((id) => !_selectedSet.contains(id)).toList();
    if (toAdd.isEmpty) return;
    await _db.addMultipleToSelected(toAdd);
    _assetIds = List.from(_assetIds)..addAll(toAdd);
    _selectedSet.addAll(toAdd);
    _entitiesDirty = true;
    notifyListeners();
  }

  Future<void> removeMultiple(Set<String> assetIds) async {
    final toRemove = assetIds.where((id) => _selectedSet.contains(id)).toList();
    if (toRemove.isEmpty) return;
    await _db.removeMultipleFromSelected(toRemove);
    final removeSet = toRemove.toSet();
    _assetIds = _assetIds.where((id) => !removeSet.contains(id)).toList();
    _selectedSet.removeAll(removeSet);
    _entitiesDirty = true;
    notifyListeners();
  }

  Future<void> setSelection(Set<String> desired) async {
    final toAdd = desired.difference(_selectedSet).toList();
    final toRemove = _selectedSet.difference(desired).toList();
    if (toAdd.isEmpty && toRemove.isEmpty) return;
    if (toAdd.isNotEmpty) await _db.addMultipleToSelected(toAdd);
    if (toRemove.isNotEmpty) await _db.removeMultipleFromSelected(toRemove);
    final removeSet = toRemove.toSet();
    final newIds = _assetIds
        .where((id) => !removeSet.contains(id))
        .toList()
      ..addAll(toAdd);
    _assetIds = newIds;
    _selectedSet..removeAll(removeSet)..addAll(toAdd);
    _entitiesDirty = true;
    notifyListeners();
  }

  Future<void> removeOne(String assetId) async {
    await _db.removeFromSelected(assetId);
    _assetIds = List.from(_assetIds)..remove(assetId);
    _selectedSet.remove(assetId);
    _entities = _entities.where((e) => e.id != assetId).toList();
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _db.clearSelected();
    _assetIds = [];
    _selectedSet.clear();
    _entities = [];
    _entitiesDirty = false;
    notifyListeners();
  }

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
}

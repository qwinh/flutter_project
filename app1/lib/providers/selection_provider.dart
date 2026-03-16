// lib/providers/selection_provider.dart
// Manages the global selected-images pool (persisted in SQLite).
//
// _assetIds  — ordered list, drives UI and DB persistence
// _selectedSet — mirrors _assetIds for O(1) isSelected() lookups
// _entities  — resolved AssetEntity objects, lazy (call resolveEntities())
// _maxSortIdx — tracked in memory to avoid a MAX() query on every insert
//
// All async mutations update _selectedSet BEFORE awaiting DB so that
// concurrent calls (e.g. rapid drag events) see a consistent in-memory
// state and don't double-add or double-remove.

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

  // Tracks the highest sort_idx currently in the DB to avoid a MAX() query
  // on every single-item insert.
  int _maxSortIdx = -1;

  bool get isEmpty => _assetIds.isEmpty;
  int get count => _assetIds.length;

  bool isSelected(String id) => _selectedSet.contains(id);

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> load() async {
    _assetIds = await _db.getSelectedAssetIds();
    _selectedSet..clear()..addAll(_assetIds);
    _maxSortIdx = _assetIds.isEmpty ? -1 : _assetIds.length - 1;
    _entitiesDirty = true;
    notifyListeners();
  }

  // ── Entity resolution (lazy, parallel) ───────────────────────────────────

  Future<void> resolveEntities() async {
    if (!_entitiesDirty) return;
    final snapshot = List.of(_assetIds);
    final resolved = await Future.wait(
      snapshot.map((id) => AssetEntity.fromId(id)),
    );
    _entities = resolved.whereType<AssetEntity>().toList();
    _entitiesDirty = false;
    notifyListeners();
  }

  // ── Single-item mutations ─────────────────────────────────────────────────

  Future<void> toggle(String id) async {
    if (_selectedSet.contains(id)) {
      _assetIds = List.from(_assetIds)..remove(id);
      _selectedSet.remove(id);
      _entitiesDirty = true;
      notifyListeners();
      await _db.removeFromSelected(id);
    } else {
      _maxSortIdx++;
      _assetIds = List.from(_assetIds)..add(id);
      _selectedSet.add(id);
      _entitiesDirty = true;
      notifyListeners();
      await _db.addToSelected(id, _maxSortIdx);
    }
  }

  Future<void> select(String id) async {
    if (_selectedSet.contains(id)) return;
    _maxSortIdx++;
    _assetIds = List.from(_assetIds)..add(id);
    _selectedSet.add(id);
    _entitiesDirty = true;
    notifyListeners();
    await _db.addToSelected(id, _maxSortIdx);
  }

  Future<void> deselect(String id) async {
    if (!_selectedSet.contains(id)) return;
    _assetIds = List.from(_assetIds)..remove(id);
    _selectedSet.remove(id);
    _entitiesDirty = true;
    notifyListeners();
    await _db.removeFromSelected(id);
  }

  /// Removes one item and keeps _entities in sync immediately (no re-resolve needed).
  Future<void> removeOne(String id) async {
    if (!_selectedSet.contains(id)) return;
    _assetIds = List.from(_assetIds)..remove(id);
    _selectedSet.remove(id);
    _entities = _entities.where((e) => e.id != id).toList();
    // _entitiesDirty stays false — entities list is already correct
    notifyListeners();
    await _db.removeFromSelected(id);
  }

  // ── Batch mutations ───────────────────────────────────────────────────────

  Future<void> addMultiple(Set<String> ids) async {
    final toAdd = ids.where((id) => !_selectedSet.contains(id)).toList();
    if (toAdd.isEmpty) return;
    final startIdx = _maxSortIdx + 1;
    _maxSortIdx += toAdd.length;
    _assetIds = List.from(_assetIds)..addAll(toAdd);
    _selectedSet.addAll(toAdd);
    _entitiesDirty = true;
    notifyListeners();
    await _db.addMultipleToSelected(toAdd, startIdx);
  }

  Future<void> removeMultiple(Set<String> ids) async {
    final toRemove = ids.where((id) => _selectedSet.contains(id)).toList();
    if (toRemove.isEmpty) return;
    final removeSet = toRemove.toSet();
    _assetIds = _assetIds.where((id) => !removeSet.contains(id)).toList();
    _selectedSet.removeAll(removeSet);
    _entitiesDirty = true;
    notifyListeners();
    await _db.removeMultipleFromSelected(toRemove);
  }

  /// Atomically sets selection to exactly [desired].
  Future<void> setSelection(Set<String> desired) async {
    final toAdd = desired.difference(_selectedSet).toList();
    final toRemove = _selectedSet.difference(desired).toList();
    if (toAdd.isEmpty && toRemove.isEmpty) return;

    final startIdx = _maxSortIdx + 1;
    _maxSortIdx += toAdd.length;

    final removeSet = toRemove.toSet();
    _assetIds = [
      ..._assetIds.where((id) => !removeSet.contains(id)),
      ...toAdd,
    ];
    _selectedSet..removeAll(removeSet)..addAll(toAdd);
    _entitiesDirty = true;
    notifyListeners();

    if (toAdd.isNotEmpty) await _db.addMultipleToSelected(toAdd, startIdx);
    if (toRemove.isNotEmpty) await _db.removeMultipleFromSelected(toRemove);
  }

  Future<void> clearAll() async {
    _assetIds = [];
    _selectedSet.clear();
    _entities = [];
    _maxSortIdx = -1;
    _entitiesDirty = false;
    notifyListeners();
    await _db.clearSelected();
  }

  // ── Reorder (in-memory; call persistOrder to save) ────────────────────────

  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final ids = List<String>.from(_assetIds);
    final ents = List<AssetEntity>.from(_entities);
    final id = ids.removeAt(oldIndex);
    ids.insert(newIndex, id);
    if (oldIndex < ents.length) {
      final e = ents.removeAt(oldIndex);
      ents.insert(newIndex, e);
    }
    _assetIds = ids;
    _entities = ents;
    notifyListeners();
  }

  Future<void> persistOrder() async => _db.setSelectedOrder(_assetIds);
}

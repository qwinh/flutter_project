// lib/providers/selection_provider.dart
// Manages the globally selected image pool (persisted across sessions).

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../db/database_helper.dart';

class SelectionProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;

  // Ordered list of asset IDs
  List<String> _assetIds = [];
  List<String> get assetIds => List.unmodifiable(_assetIds);

  // Resolved AssetEntity objects (may be null if device removed the image)
  final Map<String, AssetEntity> _entities = {};
  List<AssetEntity> get entities =>
      _assetIds.map((id) => _entities[id]).whereType<AssetEntity>().toList();

  int get count => _assetIds.length;

  bool isSelected(String assetId) => _assetIds.contains(assetId);

  Future<void> load() async {
    _assetIds = await _db.getSelectedAssetIds();
    await _resolveEntities();
    notifyListeners();
  }

  Future<void> _resolveEntities() async {
    for (final id in _assetIds) {
      if (!_entities.containsKey(id)) {
        final e = await AssetEntity.fromId(id);
        if (e != null) _entities[id] = e;
      }
    }
  }

  Future<void> select(String assetId) async {
    if (_assetIds.contains(assetId)) return;
    await _db.addToSelected(assetId);
    _assetIds = [..._assetIds, assetId];
    final e = await AssetEntity.fromId(assetId);
    if (e != null) _entities[assetId] = e;
    notifyListeners();
  }

  Future<void> deselect(String assetId) async {
    if (!_assetIds.contains(assetId)) return;
    await _db.removeFromSelected(assetId);
    _assetIds = _assetIds.where((id) => id != assetId).toList();
    _entities.remove(assetId);
    notifyListeners();
  }

  Future<void> toggle(String assetId) async {
    if (isSelected(assetId)) {
      await deselect(assetId);
    } else {
      await select(assetId);
    }
  }

  Future<void> clearAll() async {
    await _db.clearSelected();
    _assetIds = [];
    _entities.clear();
    notifyListeners();
  }

  Future<void> reorder(List<String> orderedIds) async {
    _assetIds = orderedIds;
    await _db.setSelectedOrder(orderedIds);
    notifyListeners();
  }
}

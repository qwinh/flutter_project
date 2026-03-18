// lib/providers/album_provider.dart
// Manages albums list and per-album operations.

import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../models/models.dart';
import 'image_provider.dart';

class AlbumProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;

  List<AlbumModel> _albums = [];
  List<AlbumModel> get albums => List.unmodifiable(_albums);

  // Per-album tag IDs cache: albumId → List<tagId>
  final Map<int, List<int>> _albumTagIds = {};

  // Per-album asset IDs cache: albumId → List<assetId>
  final Map<int, List<String>> _albumAssetIds = {};

  bool _loading = false;
  bool get loading => _loading;

  DeviceImageProvider? _imageProv;
  void attachImageProvider(DeviceImageProvider p) => _imageProv = p;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _albums = await _db.getAllAlbums();
    final bulk = await _db.getAllAlbumTagIds();
    _albumTagIds
      ..clear()
      ..addAll(bulk);
    _loading = false;
    notifyListeners();
  }

  Future<AlbumModel> addAlbum(AlbumModel album,
      {List<int> tagIds = const [],
      List<String> assetIds = const []}) async {
    final saved = await _db.insertAlbum(album);
    if (tagIds.isNotEmpty) await _db.setTagsForAlbum(saved.id!, tagIds);
    if (assetIds.isNotEmpty) await _db.addImagesToAlbum(saved.id!, assetIds);
    _albums = [..._albums, saved]..sort((a, b) => a.name.compareTo(b.name));
    _albumTagIds[saved.id!] = tagIds;
    _albumAssetIds[saved.id!] = List.of(assetIds);
    notifyListeners();
    return saved;
  }

  Future<void> updateAlbum(AlbumModel album, {List<int>? tagIds}) async {
    await _db.updateAlbum(album);
    if (tagIds != null) {
      await _db.setTagsForAlbum(album.id!, tagIds);
      _albumTagIds[album.id!] = tagIds;
    }
    final idx = _albums.indexWhere((a) => a.id == album.id);
    if (idx != -1) {
      _albums = List.from(_albums)..[idx] = album;
      _albums.sort((a, b) => a.name.compareTo(b.name));
    }
    notifyListeners();
  }

  Future<void> deleteAlbum(int id) async {
    await _db.deleteAlbum(id);
    _albums = _albums.where((a) => a.id != id).toList();
    _albumTagIds.remove(id);
    _albumAssetIds.remove(id);
    notifyListeners();
  }

  /// Deletes multiple albums in a single DB statement, one [notifyListeners] at the end.
  Future<void> deleteAlbums(Set<int> ids) async {
    if (ids.isEmpty) return;
    await _db.deleteAlbumsBatch(ids.toList());
    for (final id in ids) {
      _albumTagIds.remove(id);
      _albumAssetIds.remove(id);
    }
    _albums = _albums.where((a) => !ids.contains(a.id)).toList();
    notifyListeners();
  }

  /// Toggles isFavorite for multiple albums — one [notifyListeners] at the end.
  Future<void> toggleFavoriteAlbums(Set<int> ids) async {
    if (ids.isEmpty) return;
    final updated = <AlbumModel>[];
    for (final id in ids) {
      final album = getById(id);
      if (album == null) continue;
      final toggled = album.copyWith(isFavorite: !album.isFavorite);
      await _db.updateAlbum(toggled);
      updated.add(toggled);
    }
    final updatedMap = {for (final a in updated) a.id!: a};
    _albums = [
      for (final a in _albums) updatedMap[a.id] ?? a,
    ]..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  Future<List<int>> getTagIds(int albumId) async {
    if (!_albumTagIds.containsKey(albumId)) {
      _albumTagIds[albumId] = await _db.getTagIdsForAlbum(albumId);
    }
    return _albumTagIds[albumId]!;
  }

  List<int> getTagIdsSync(int albumId) => _albumTagIds[albumId] ?? [];

  Future<List<String>> getAssetIds(int albumId) async {
    if (!_albumAssetIds.containsKey(albumId)) {
      _albumAssetIds[albumId] = await _db.getAssetIdsForAlbum(albumId);
    }
    return _albumAssetIds[albumId]!;
  }

  Future<void> addImagesToAlbum(int albumId, List<String> assetIds) async {
    await _db.addImagesToAlbum(albumId, assetIds);
    _albumAssetIds[albumId] = await _db.getAssetIdsForAlbum(albumId);
    _imageProv?.invalidateFilterCache();
    notifyListeners();
  }

  Future<void> removeImageFromAlbum(int albumId, String assetId) async {
    await _db.removeImageFromAlbum(albumId, assetId);
    _albumAssetIds[albumId]?.remove(assetId);
    _imageProv?.invalidateFilterCache();
    notifyListeners();
  }

  Future<void> removeImagesFromAlbum(
      int albumId, List<String> assetIds) async {
    if (assetIds.isEmpty) return;
    await _db.removeImagesFromAlbum(albumId, assetIds);
    final cached = _albumAssetIds[albumId];
    if (cached != null) {
      final removeSet = assetIds.toSet();
      _albumAssetIds[albumId] =
          cached.where((id) => !removeSet.contains(id)).toList();
    }
    _imageProv?.invalidateFilterCache();
    notifyListeners();
  }

  AlbumModel? getById(int id) {
    try {
      return _albums.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }
}
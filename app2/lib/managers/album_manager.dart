import 'package:flutter/foundation.dart';
import '../models/album.dart';
import '../services/album_service.dart';

class AlbumManager extends ChangeNotifier {
  final AlbumService _service = AlbumService();
  List<Album> _albums = [];
  bool _isLoading = false;

  List<Album> get albums => _albums;
  bool get isLoading => _isLoading;

  // Cached image counts per album
  final Map<int, int> _imageCounts = {};
  int getImageCount(int albumId) => _imageCounts[albumId] ?? 0;

  Future<void> loadAlbums() async {
    _isLoading = true;
    notifyListeners();

    _albums = await _service.getAll();

    // Load image counts
    _imageCounts.clear();
    for (final album in _albums) {
      if (album.id != null) {
        _imageCounts[album.id!] = await _service.getImageCount(album.id!);
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<Album?> getAlbumById(int id) async {
    return await _service.getById(id);
  }

  Future<int> addAlbum(Album album) async {
    final id = await _service.insert(album);
    await loadAlbums();
    return id;
  }

  Future<void> updateAlbum(Album album) async {
    await _service.update(album);
    await loadAlbums();
  }

  Future<void> deleteAlbum(int id) async {
    await _service.delete(id);
    await loadAlbums();
  }

  Future<void> toggleFavorite(int id, bool favorite) async {
    await _service.toggleFavorite(id, favorite);
    await loadAlbums();
  }

  Future<void> addImagesToAlbum(int albumId, List<String> imageUris) async {
    await _service.addImages(albumId, imageUris);
    // Update the album's modify date
    final album = await _service.getById(albumId);
    if (album != null) {
      await _service.update(album.copyWith(dateLatestModify: DateTime.now()));
    }
    await loadAlbums();
  }

  Future<void> removeImageFromAlbum(int albumId, String imageUri) async {
    await _service.removeImage(albumId, imageUri);
    final album = await _service.getById(albumId);
    if (album != null) {
      await _service.update(album.copyWith(dateLatestModify: DateTime.now()));
    }
    await loadAlbums();
  }

  Future<List<String>> getAlbumImageUris(int albumId) async {
    return await _service.getAlbumImageUris(albumId);
  }

  Future<String?> getAlbumCoverUri(int albumId) async {
    return await _service.getAlbumCoverUri(albumId);
  }

  Future<List<Album>> getAlbumsByTag(int tagId) async {
    return await _service.getAlbumsByTag(tagId);
  }

  /// Filter local list by name and/or favorite status
  List<Album> filterAlbums({String? query, bool? onlyFavorites}) {
    var result = List<Album>.from(_albums);
    if (query != null && query.isNotEmpty) {
      final lower = query.toLowerCase();
      result = result.where((a) => a.name.toLowerCase().contains(lower)).toList();
    }
    if (onlyFavorites == true) {
      result = result.where((a) => a.favorite).toList();
    }
    return result;
  }
}

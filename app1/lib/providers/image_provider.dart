// lib/providers/image_provider.dart

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import '../db/database_helper.dart';

enum SortOrder { dateDesc, dateAsc, nameAsc, nameDesc }

class ImageFilterState {
  final Set<int> includeAlbumIds;
  final Set<int> excludeAlbumIds;
  // Applies to the combined include+exclude set:
  // true  (ALL) = in(A) AND not_in(B) AND ...
  // false (ANY) = in(A) OR  not_in(B) OR  ...
  final bool albumFilterAnd;
  final bool onlyFavoriteAlbums;
  final int? minWidth;
  final int? minHeight;
  final SortOrder sortOrder;

  const ImageFilterState({
    this.includeAlbumIds = const {},
    this.excludeAlbumIds = const {},
    this.albumFilterAnd = false,
    this.onlyFavoriteAlbums = false,
    this.minWidth,
    this.minHeight,
    this.sortOrder = SortOrder.dateDesc,
  });

  bool get hasAlbumFilter =>
      includeAlbumIds.isNotEmpty || excludeAlbumIds.isNotEmpty || onlyFavoriteAlbums;

  bool get hasAnyFilter => hasAlbumFilter || minWidth != null || minHeight != null;

  ImageFilterState copyWith({
    Set<int>? includeAlbumIds,
    Set<int>? excludeAlbumIds,
    bool? albumFilterAnd,
    bool? onlyFavoriteAlbums,
    Object? minWidth = _sentinel,
    Object? minHeight = _sentinel,
    SortOrder? sortOrder,
  }) => ImageFilterState(
    includeAlbumIds: includeAlbumIds ?? this.includeAlbumIds,
    excludeAlbumIds: excludeAlbumIds ?? this.excludeAlbumIds,
    albumFilterAnd: albumFilterAnd ?? this.albumFilterAnd,
    onlyFavoriteAlbums: onlyFavoriteAlbums ?? this.onlyFavoriteAlbums,
    minWidth: minWidth == _sentinel ? this.minWidth : minWidth as int?,
    minHeight: minHeight == _sentinel ? this.minHeight : minHeight as int?,
    sortOrder: sortOrder ?? this.sortOrder,
  );
}

const _sentinel = Object();

class DeviceImageProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;

  List<AssetEntity> _all = [];
  List<AssetEntity> _filtered = [];
  List<AssetEntity> get filtered => List.unmodifiable(_filtered);
  List<AssetEntity> get all => List.unmodifiable(_all);

  ImageFilterState _filterState = const ImageFilterState();
  ImageFilterState get filterState => _filterState;

  bool _loading = false;
  bool get loading => _loading;

  bool _permissionGranted = false;
  bool get permissionGranted => _permissionGranted;

  final Map<int, Set<String>> _albumCache = {};
  Set<String> _favoriteAssetIds = {};

  Future<void> requestPermissionAndLoad() async {
    final result = await PhotoManager.requestPermissionExtend();
    _permissionGranted = result.hasAccess;
    if (_permissionGranted) {
      await loadAll();
    } else {
      await PhotoManager.openSetting();
      notifyListeners();
    }
  }

  Future<void> loadAll() async {
    _loading = true;
    notifyListeners();
    final albums = await PhotoManager.getAssetPathList(type: RequestType.image, onlyAll: true);
    _all = albums.isNotEmpty
        ? await albums.first.getAssetListRange(start: 0, end: await albums.first.assetCountAsync)
        : [];
    _loading = false;
    await _applyFilters();
  }

  Future<void> setFilter(ImageFilterState state) async {
    _filterState = state;
    await _applyFilters();
  }

  Future<Set<String>> _cacheAlbum(int id) async =>
      _albumCache[id] ??= await _db.getAssetIdsForAlbums({id});

  Future<void> _applyFilters() async {
    final f = _filterState;

    // Pre-fetch album asset sets.
    for (final id in {...f.includeAlbumIds, ...f.excludeAlbumIds}) {
      await _cacheAlbum(id);
    }
    if (f.onlyFavoriteAlbums) {
      _favoriteAssetIds = await _db.getFavoriteAlbumAssetIds();
    }

    List<AssetEntity> result = List.of(_all);

    // Combined album filter: each album produces a predicate.
    // in(A)  → asset IS in album A
    // not(B) → asset is NOT in album B
    // R combines all: AND = all must hold, OR = any must hold.
    final allIds = {...f.includeAlbumIds, ...f.excludeAlbumIds};
    if (allIds.isNotEmpty) {
      result = result.where((asset) {
        final preds = allIds.map((id) {
          final inAlbum = _albumCache[id]?.contains(asset.id) ?? false;
          return f.includeAlbumIds.contains(id) ? inAlbum : !inAlbum;
        });
        return f.albumFilterAnd ? preds.every((p) => p) : preds.any((p) => p);
      }).toList();
    }

    if (f.onlyFavoriteAlbums) {
      result = result.where((a) => _favoriteAssetIds.contains(a.id)).toList();
    }
    if (f.minWidth != null) result = result.where((a) => a.width >= f.minWidth!).toList();
    if (f.minHeight != null) result = result.where((a) => a.height >= f.minHeight!).toList();

    switch (f.sortOrder) {
      case SortOrder.dateDesc: result.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
      case SortOrder.dateAsc:  result.sort((a, b) => a.createDateTime.compareTo(b.createDateTime));
      case SortOrder.nameAsc:  result.sort((a, b) => (a.title ?? '').compareTo(b.title ?? ''));
      case SortOrder.nameDesc: result.sort((a, b) => (b.title ?? '').compareTo(a.title ?? ''));
    }

    _filtered = result;
    notifyListeners();
  }

  void invalidateFilterCache() {
    _albumCache.clear();
    _favoriteAssetIds = {};
  }
}
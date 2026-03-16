// lib/providers/image_provider.dart
// Loads all device images via photo_manager, applies in-memory filters/sort.

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../db/database_helper.dart';

enum SortOrder { dateDesc, dateAsc, nameAsc, nameDesc }

class ImageFilterState {
  final Set<int> includeAlbumIds;
  final Set<int> excludeAlbumIds;
  final bool onlyFavoriteAlbums;
  final int? minWidth;
  final int? minHeight;
  final SortOrder sortOrder;

  const ImageFilterState({
    this.includeAlbumIds = const {},
    this.excludeAlbumIds = const {},
    this.onlyFavoriteAlbums = false,
    this.minWidth,
    this.minHeight,
    this.sortOrder = SortOrder.dateDesc,
  });

  bool get hasAlbumFilter =>
      includeAlbumIds.isNotEmpty ||
      excludeAlbumIds.isNotEmpty ||
      onlyFavoriteAlbums;

  bool get hasAnyFilter =>
      hasAlbumFilter || minWidth != null || minHeight != null;

  ImageFilterState copyWith({
    Set<int>? includeAlbumIds,
    Set<int>? excludeAlbumIds,
    bool? onlyFavoriteAlbums,
    Object? minWidth = _sentinel,
    Object? minHeight = _sentinel,
    SortOrder? sortOrder,
  }) {
    return ImageFilterState(
      includeAlbumIds: includeAlbumIds ?? this.includeAlbumIds,
      excludeAlbumIds: excludeAlbumIds ?? this.excludeAlbumIds,
      onlyFavoriteAlbums: onlyFavoriteAlbums ?? this.onlyFavoriteAlbums,
      minWidth: minWidth == _sentinel ? this.minWidth : minWidth as int?,
      minHeight: minHeight == _sentinel ? this.minHeight : minHeight as int?,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
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

  Set<String> _includeAssetIds = {};
  Set<String> _excludeAssetIds = {};
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

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );

    if (albums.isNotEmpty) {
      _all = await albums.first.getAssetListRange(
        start: 0,
        end: await albums.first.assetCountAsync,
      );
    } else {
      _all = [];
    }

    _loading = false;
    await _applyFilters();
  }

  Future<void> setFilter(ImageFilterState state) async {
    _filterState = state;
    await _applyFilters();
  }

  Future<void> refreshForAlbumFilter(Set<int> albumIds) async {
    _includeAssetIds = await _db.getAssetIdsForAlbums(albumIds);
    await _applyFilters();
  }

  Future<void> refreshFavoriteFilter() async {
    _favoriteAssetIds = await _db.getFavoriteAlbumAssetIds();
    await _applyFilters();
  }

  Future<void> _applyFilters() async {
    final f = _filterState;

    if (f.includeAlbumIds.isNotEmpty) {
      _includeAssetIds = await _db.getAssetIdsForAlbums(f.includeAlbumIds);
    }
    if (f.excludeAlbumIds.isNotEmpty) {
      _excludeAssetIds = await _db.getAssetIdsForAlbums(f.excludeAlbumIds);
    }
    if (f.onlyFavoriteAlbums) {
      _favoriteAssetIds = await _db.getFavoriteAlbumAssetIds();
    }

    List<AssetEntity> result = List.of(_all);

    if (f.includeAlbumIds.isNotEmpty) {
      result = result.where((a) => _includeAssetIds.contains(a.id)).toList();
    }
    if (f.excludeAlbumIds.isNotEmpty) {
      result = result.where((a) => !_excludeAssetIds.contains(a.id)).toList();
    }
    if (f.onlyFavoriteAlbums) {
      result = result.where((a) => _favoriteAssetIds.contains(a.id)).toList();
    }
    if (f.minWidth != null) {
      result = result.where((a) => a.width >= f.minWidth!).toList();
    }
    if (f.minHeight != null) {
      result = result.where((a) => a.height >= f.minHeight!).toList();
    }

    switch (f.sortOrder) {
      case SortOrder.dateDesc:
        result.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
        break;
      case SortOrder.dateAsc:
        result.sort((a, b) => a.createDateTime.compareTo(b.createDateTime));
        break;
      case SortOrder.nameAsc:
        result.sort((a, b) => (a.title ?? '').compareTo(b.title ?? ''));
        break;
      case SortOrder.nameDesc:
        result.sort((a, b) => (b.title ?? '').compareTo(a.title ?? ''));
        break;
    }

    _filtered = result;
    notifyListeners();
  }

  void invalidateFilterCache() {
    _includeAssetIds = {};
    _excludeAssetIds = {};
    _favoriteAssetIds = {};
  }
}
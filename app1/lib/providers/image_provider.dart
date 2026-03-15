// lib/providers/image_provider.dart
// Loads device images via photo_manager, applies in-memory filters/sort.
// Supports multi-album include/exclude filter, native album filter,
// dimension filter, and 4 sort modes.

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../db/database_helper.dart';

enum SortOrder { dateDesc, dateAsc, nameAsc, nameDesc }

/// How the album-ID filter is applied.
enum AlbumFilterMode {
  /// Show images that belong to any of the selected albums (OR).
  includeAny,
  /// Hide images that belong to any of the selected albums.
  excludeAll,
}

class ImageFilterState {
  /// Custom-album filter (our DB albums). Empty = no filter.
  final Set<int> albumIds;
  final AlbumFilterMode albumFilterMode;

  /// Show only images in any favorite album.
  final bool onlyFavoriteAlbums;

  /// Native photo_manager album (OS album). null = All Photos.
  final AssetPathEntity? nativeAlbum;

  final int? minWidth;
  final int? minHeight;
  final SortOrder sortOrder;

  const ImageFilterState({
    this.albumIds = const {},
    this.albumFilterMode = AlbumFilterMode.includeAny,
    this.onlyFavoriteAlbums = false,
    this.nativeAlbum,
    this.minWidth,
    this.minHeight,
    this.sortOrder = SortOrder.dateDesc,
  });

  ImageFilterState copyWith({
    Set<int>? albumIds,
    AlbumFilterMode? albumFilterMode,
    bool? onlyFavoriteAlbums,
    Object? nativeAlbum = _sentinel,
    Object? minWidth = _sentinel,
    Object? minHeight = _sentinel,
    SortOrder? sortOrder,
  }) {
    return ImageFilterState(
      albumIds: albumIds ?? this.albumIds,
      albumFilterMode: albumFilterMode ?? this.albumFilterMode,
      onlyFavoriteAlbums: onlyFavoriteAlbums ?? this.onlyFavoriteAlbums,
      nativeAlbum: nativeAlbum == _sentinel
          ? this.nativeAlbum
          : nativeAlbum as AssetPathEntity?,
      minWidth: minWidth == _sentinel ? this.minWidth : minWidth as int?,
      minHeight: minHeight == _sentinel ? this.minHeight : minHeight as int?,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  bool get hasCustomAlbumFilter => albumIds.isNotEmpty;
}

const _sentinel = Object();

class DeviceImageProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;

  // All loaded assets for the current native album source.
  List<AssetEntity> _all = [];
  List<AssetEntity> _filtered = [];
  List<AssetEntity> get filtered => List.unmodifiable(_filtered);
  List<AssetEntity> get all => List.unmodifiable(_all);

  // Pagination
  List<AssetPathEntity> _nativeAlbums = [];
  List<AssetPathEntity> get nativeAlbums => List.unmodifiable(_nativeAlbums);

  int _currentPage = 0;
  bool _hasMore = true;
  bool get hasMore => _hasMore;
  static const int _pageSize = 80;

  ImageFilterState _filterState = const ImageFilterState();
  ImageFilterState get filterState => _filterState;

  bool _loading = false;
  bool get loading => _loading;

  bool _permissionGranted = false;
  bool get permissionGranted => _permissionGranted;

  // DB-backed filter sets (refreshed when needed)
  Set<String> _customAlbumAssetIds = {};
  Set<String> _favoriteAssetIds = {};

  Future<void> requestPermissionAndLoad() async {
    final result = await PhotoManager.requestPermissionExtend();
    _permissionGranted = result.hasAccess;
    if (_permissionGranted) {
      await _loadNativeAlbums();
      await loadAll();
    } else {
      await PhotoManager.openSetting();
      notifyListeners();
    }
  }

  Future<void> _loadNativeAlbums() async {
    _nativeAlbums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
    );
  }

  /// Returns the active AssetPathEntity: the one set in filter, or the "all"
  /// album (onlyAll: true), whichever is appropriate.
  AssetPathEntity? get _sourceAlbum {
    if (_filterState.nativeAlbum != null) return _filterState.nativeAlbum;
    // Find the "all" album
    return _nativeAlbums.isNotEmpty ? _nativeAlbums.first : null;
  }

  Future<void> loadAll() async {
    _loading = true;
    notifyListeners();

    _currentPage = 0;
    _hasMore = true;
    _all = [];

    final source = _sourceAlbum;
    if (source != null) {
      final assets = await source.getAssetListPaged(
        page: 0,
        size: _pageSize,
      );
      _all = assets;
      _currentPage = 1;
      _hasMore = assets.length >= _pageSize;
    }

    _loading = false;
    await _applyFilters();
  }

  /// Loads the next page of assets. Call when user scrolls near the bottom.
  Future<void> loadMore() async {
    if (!_hasMore || _loading) return;
    final source = _sourceAlbum;
    if (source == null) return;

    final assets = await source.getAssetListPaged(
      page: _currentPage,
      size: _pageSize,
    );
    _all = [..._all, ...assets];
    _currentPage++;
    _hasMore = assets.length >= _pageSize;
    await _applyFilters();
  }

  Future<void> setFilter(ImageFilterState state) async {
    final nativeChanged = state.nativeAlbum != _filterState.nativeAlbum;
    _filterState = state;
    if (nativeChanged) {
      // Reload assets from the new native album source
      await loadAll();
    } else {
      await _applyFilters();
    }
  }

  Future<void> _applyFilters() async {
    // Refresh DB-backed sets when needed
    if (_filterState.hasCustomAlbumFilter) {
      _customAlbumAssetIds =
          await _db.getAssetIdsForAlbums(_filterState.albumIds);
    }
    if (_filterState.onlyFavoriteAlbums) {
      _favoriteAssetIds = await _db.getFavoriteAlbumAssetIds();
    }

    List<AssetEntity> result = List.of(_all);

    // Custom album filter (include any / exclude all)
    if (_filterState.hasCustomAlbumFilter) {
      switch (_filterState.albumFilterMode) {
        case AlbumFilterMode.includeAny:
          result = result
              .where((a) => _customAlbumAssetIds.contains(a.id))
              .toList();
          break;
        case AlbumFilterMode.excludeAll:
          result = result
              .where((a) => !_customAlbumAssetIds.contains(a.id))
              .toList();
          break;
      }
    }

    // Favorite albums filter
    if (_filterState.onlyFavoriteAlbums) {
      result =
          result.where((a) => _favoriteAssetIds.contains(a.id)).toList();
    }

    // Dimension filters
    if (_filterState.minWidth != null) {
      result =
          result.where((a) => a.width >= _filterState.minWidth!).toList();
    }
    if (_filterState.minHeight != null) {
      result =
          result.where((a) => a.height >= _filterState.minHeight!).toList();
    }

    // Sort
    switch (_filterState.sortOrder) {
      case SortOrder.dateDesc:
        result.sort(
            (a, b) => b.createDateTime.compareTo(a.createDateTime));
        break;
      case SortOrder.dateAsc:
        result.sort(
            (a, b) => a.createDateTime.compareTo(b.createDateTime));
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
    _customAlbumAssetIds = {};
    _favoriteAssetIds = {};
  }
}

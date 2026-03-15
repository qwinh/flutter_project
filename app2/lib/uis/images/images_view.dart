import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../managers/image_selection_manager.dart';
import '../shared/app_drawer.dart';
import '../shared/drag_select_grid.dart';

class ImagesView extends StatefulWidget {
  const ImagesView({super.key});

  @override
  State<ImagesView> createState() => _ImagesViewState();
}

class _ImagesViewState extends State<ImagesView> {
  List<AssetEntity> _assets = [];
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _currentAlbum;
  bool _isLoading = true;
  int _currentPage = 0;
  bool _hasMore = true;
  static const int _pageSize = 80;

  /// How many rows to prefetch above and below the current viewport / drag edge.
  static const int _prefetchRows = 3;
  /// Estimated cell size used for scroll-position → index math (updated on layout).
  double _cellSize = 120;
  int _lastPrefetchCenter = -1;

  final ScrollController _scrollController = ScrollController();
  final Map<String, Uint8List?> _thumbnailCache = {};

  // ---------- Drag-select state ----------
  bool _isInSelectionMode = false;
  // Whether the current drag gesture is in "deselect" mode (started on a
  // currently-selected item).
  bool _dragDeselectMode = false;
  // Indices being *swept* (not yet committed) during the current drag gesture.
  Set<int> _dragSweepIndices = {};
  // Snapshot of selection-manager IDs taken at drag start so we can compute
  // a clean union/difference during the sweep without duplicating or losing
  // pre-existing selections.
  Set<String> _preDragSelection = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _requestPermissionAndLoad();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreAssets();
    }
    _prefetchFromScroll();
  }

  // ─── Prefetch helpers ────────────────────────────────────────────────────

  /// The number of columns currently displayed (kept in sync during layout).
  int _currentCrossAxisCount = 3;

  /// Called from scroll listener to warm thumbnails near the current viewport.
  void _prefetchFromScroll() {
    if (_cellSize <= 0 || _assets.isEmpty) return;
    final scrollOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final rowInView = (scrollOffset / _cellSize).round();
    final centerIndex = (rowInView * _currentCrossAxisCount)
        .clamp(0, _assets.length - 1);
    _prefetchAround(centerIndex, _currentCrossAxisCount);
  }

  /// Pre-warm thumbnails for items in [
  ///   centerIndex - prefetchRows*cols,
  ///   centerIndex + prefetchRows*cols
  /// ] that aren't already in the cache. Runs entirely in the background.
  void _prefetchAround(int centerIndex, int cols) {
    final halfWindow = _prefetchRows * cols;
    final start = (centerIndex - halfWindow).clamp(0, _assets.length - 1);
    final end = (centerIndex + halfWindow).clamp(0, _assets.length - 1);

    // Don't re-prefetch if the center hasn't moved meaningfully.
    if ((centerIndex - _lastPrefetchCenter).abs() < cols) return;
    _lastPrefetchCenter = centerIndex;

    for (int i = start; i <= end; i++) {
      final id = _assets[i].id;
      if (_thumbnailCache.containsKey(id)) continue; // already cached
      // Mark as in-flight immediately to prevent duplicate fetches.
      _thumbnailCache[id] = null;
      _assets[i]
          .thumbnailDataWithSize(const ThumbnailSize(200, 200))
          .then((bytes) {
        _thumbnailCache[id] = bytes;
        // No setState — the tile will read from the cache when it next builds.
      }).ignore();
    }
  }

  Future<void> _requestPermissionAndLoad() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Photo permission denied. Please grant access in Settings.',
            ),
          ),
        );
      }
      return;
    }
    await _loadAlbums();
    await _loadAssets();
  }

  Future<void> _loadAlbums() async {
    _albums = await PhotoManager.getAssetPathList(type: RequestType.image);
    if (_albums.isNotEmpty && _currentAlbum == null) {
      _currentAlbum = _albums.first;
    }
  }

  Future<void> _loadAssets() async {
    if (_currentAlbum == null) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);
    _currentPage = 0;
    _hasMore = true;

    final assets = await _currentAlbum!.getAssetListPaged(
      page: 0,
      size: _pageSize,
    );

    setState(() {
      _assets = assets;
      _currentPage = 1;
      _hasMore = assets.length >= _pageSize;
      _isLoading = false;
    });
    // Warm the first screenful immediately after load.
    _prefetchAround(0, _currentCrossAxisCount);
  }

  Future<void> _loadMoreAssets() async {
    if (!_hasMore || _isLoading || _currentAlbum == null) return;

    final assets = await _currentAlbum!.getAssetListPaged(
      page: _currentPage,
      size: _pageSize,
    );

    final prevCount = _assets.length;
    setState(() {
      _assets.addAll(assets);
      _currentPage++;
      _hasMore = assets.length >= _pageSize;
    });
    // Pre-warm thumbnails at the newly loaded boundary.
    _prefetchAround(prevCount, _currentCrossAxisCount);
  }

  // ---------- Drag-select callbacks ----------

  void _onDragSelectionStart(int startIndex) {
    final selectionManager = context.read<ImageSelectionManager>();
    final id = _assets[startIndex].id;

    setState(() {
      _isInSelectionMode = true;
      _dragDeselectMode = selectionManager.isSelected(id);
      _preDragSelection = Set<String>.from(selectionManager.selectedUris);
      _dragSweepIndices = {startIndex};
    });

    // If starting on an unselected item, begin by selecting it; otherwise
    // keep it selected (and allow the drag to clear it).
    if (!_dragDeselectMode) {
      selectionManager.add(id);
    }
  }

  void _onDragSelectionUpdate(int startIndex, int endIndex) {
    final selectionManager = context.read<ImageSelectionManager>();
    final newSweep = <int>{};
    for (int i = startIndex; i <= endIndex; i++) {
      newSweep.add(i);
    }

    // Only update if sweep changed.
    if (newSweep.length == _dragSweepIndices.length &&
        newSweep.containsAll(_dragSweepIndices)) {
      return;
    }

    setState(() => _dragSweepIndices = newSweep);

    // Pre-warm thumbnails ahead of the drag frontier so items are ready
    // before the finger sweeps into them.
    _prefetchAround(endIndex, _currentCrossAxisCount);

    final sweepIds = newSweep.map((i) => _assets[i].id).toSet();

    // If the drag started on a selected item, treat the drag as a *deselect*
    // operation. Otherwise, it's a select operation.
    final desired = _dragDeselectMode
        ? _preDragSelection.difference(sweepIds)
        : _preDragSelection.union(sweepIds);

    selectionManager.setSelection(desired);
  }

  void _onDragSelectionEnd() {
    setState(() {
      _dragSweepIndices = {};
      _preDragSelection = {};
      _dragDeselectMode = false;
    });
    // Selection already committed via setSelection during the sweep.
  }

  void _onItemTap(int index) {
    final selectionManager = context.read<ImageSelectionManager>();
    if (_isInSelectionMode) {
      // Toggle
      selectionManager.toggle(_assets[index].id);
      // Exit selection mode if nothing left.
      if (selectionManager.count == 0) {
        setState(() => _isInSelectionMode = false);
      }
    } else {
      // Navigate to full-screen viewer.
      context.push(
        '/images/view',
        extra: {'assets': _assets, 'initialIndex': index},
      );
    }
  }

  void _exitSelectionMode() {
    final selectionManager = context.read<ImageSelectionManager>();
    selectionManager.clear();
    setState(() => _isInSelectionMode = false);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectionManager = context.watch<ImageSelectionManager>();
    final theme = Theme.of(context);

    // Sync selection mode if manager gets cleared externally.
    if (selectionManager.count > 0 && !_isInSelectionMode) {
      // Entered from outside (e.g. image_view toggle) — respect it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isInSelectionMode = true);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: _isInSelectionMode
            ? Text('${selectionManager.count} selected')
            : const Text('Browse Images'),
        leading: _isInSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Exit selection',
                onPressed: _exitSelectionMode,
              )
            : null,
        actions: [
          if (_isInSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Select all',
              onPressed: () {
                final allIds = _assets.map((a) => a.id).toSet();
                selectionManager.addAll(allIds);
              },
            ),
          ],
          if (selectionManager.count > 0)
            TextButton.icon(
              onPressed: () => context.push('/images/selected'),
              icon: Badge(
                label: Text('${selectionManager.count}'),
                child: const Icon(Icons.checklist),
              ),
              label: const Text('Selected'),
            ),
        ],
        bottom: _albums.length > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: DropdownButtonFormField<AssetPathEntity>(
                    initialValue: _currentAlbum,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: _albums.map((album) {
                      return DropdownMenuItem(
                        value: album,
                        child: Text(
                          album.name.isEmpty ? 'All Photos' : album.name,
                        ),
                      );
                    }).toList(),
                    onChanged: (album) {
                      setState(() {
                        _currentAlbum = album;
                      });
                      _loadAssets();
                    },
                  ),
                ),
              )
            : null,
      ),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _assets.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.image_not_supported,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No images found.',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                int crossAxisCount = 3;
                if (constraints.maxWidth > 600) crossAxisCount = 4;
                if (constraints.maxWidth > 900) crossAxisCount = 5;

                // Keep prefetch math in sync with the actual layout.
                if (_currentCrossAxisCount != crossAxisCount) {
                  _currentCrossAxisCount = crossAxisCount;
                }
                // Cell size = (available width − padding − gaps) / cols.
                final spacing = 4.0;
                final pad = 4.0;
                final cellW =
                    (constraints.maxWidth - pad * 2 - spacing * (crossAxisCount - 1)) /
                    crossAxisCount;
                if (cellW > 0) _cellSize = cellW;

                return DragSelectGrid(
                  scrollController: _scrollController,
                  crossAxisCount: crossAxisCount,
                  itemCount: _assets.length,
                  spacing: 4,
                  padding: const EdgeInsets.all(4),
                  isInSelectionMode: _isInSelectionMode,
                  onSelectionStart: _onDragSelectionStart,
                  onSelectionUpdate: _onDragSelectionUpdate,
                  onSelectionEnd: _onDragSelectionEnd,
                  onItemTap: _onItemTap,
                  child: GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(4),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: _assets.length,
                    itemBuilder: (context, index) {
                      final asset = _assets[index];
                      final isSelected = selectionManager.isSelected(asset.id);

                      return _ImageTile(
                        asset: asset,
                        isSelected: isSelected,
                        isInSelectionMode: _isInSelectionMode,
                        thumbnailCache: _thumbnailCache,
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Simplified image tile — no per-tile GestureDetector for selection
// (the DragSelectGrid wrapper handles all gestures).
// ---------------------------------------------------------------------------

class _ImageTile extends StatefulWidget {
  final AssetEntity asset;
  final bool isSelected;
  final bool isInSelectionMode;
  final Map<String, Uint8List?> thumbnailCache;

  const _ImageTile({
    required this.asset,
    required this.isSelected,
    required this.isInSelectionMode,
    required this.thumbnailCache,
  });

  @override
  State<_ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<_ImageTile>
    with SingleTickerProviderStateMixin {
  Uint8List? _thumbnailBytes;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    final cacheKey = widget.asset.id;
    if (widget.thumbnailCache.containsKey(cacheKey)) {
      setState(() {
        _thumbnailBytes = widget.thumbnailCache[cacheKey];
      });
    } else {
      final bytes = await widget.asset.thumbnailDataWithSize(
        const ThumbnailSize(200, 200),
      );
      widget.thumbnailCache[cacheKey] = bytes;
      if (mounted) {
        setState(() {
          _thumbnailBytes = bytes;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      transformAlignment: Alignment.center,
      transform: widget.isSelected
          ? Matrix4.diagonal3Values(0.90, 0.90, 1.0)
          : Matrix4.identity(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _thumbnailBytes != null
                ? Image.memory(_thumbnailBytes!, fit: BoxFit.cover)
                : Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.image, color: Colors.grey),
                  ),
          ),
          // Selection overlay — blue tint
          if (widget.isSelected)
            AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.blue.withValues(alpha: 0.3),
                  border: Border.all(color: Colors.blue, width: 3),
                ),
              ),
            ),
          // Selection indicator (checkmark circle)
          if (widget.isInSelectionMode || widget.isSelected)
            Positioned(
              top: 4,
              right: 4,
              child: AnimatedScale(
                scale: widget.isSelected ? 1.0 : 0.8,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isSelected ? Colors.blue : Colors.black38,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: widget.isSelected
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

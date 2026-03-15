// lib/views/images_view.dart
// Displays device images in a paginated grid.
// Long-press → drag-to-select with auto-scroll (DragSelectGrid).
// Filter sheet: multi-album include/exclude, favorites, native album, dimensions, sort.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../providers/album_provider.dart';
import '../providers/image_provider.dart' as ip;
import '../providers/selection_provider.dart';
import '../router/app_router.dart';
import '../widgets/drag_select_grid.dart';
import '../widgets/widgets.dart';

class ImagesView extends StatefulWidget {
  const ImagesView({super.key});

  @override
  State<ImagesView> createState() => _ImagesViewState();
}

class _ImagesViewState extends State<ImagesView> {
  bool _selectionMode = false;
  late final AppLifecycleListener _lifecycleListener;

  final ScrollController _scrollController = ScrollController();
  final Map<String, Uint8List?> _thumbnailCache = {};

  // Drag-select state
  bool _dragDeselectMode = false;
  Set<int> _dragSweepIndices = {};
  Set<String> _preDragSelection = {};

  // Prefetch state
  int _currentCrossAxisCount = 3;
  double _cellSize = 120;
  int _lastPrefetchCenter = -1;
  static const int _prefetchRows = 3;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ip.DeviceImageProvider>().requestPermissionAndLoad();
      context.read<SelectionProvider>().load();
    });
    _lifecycleListener = AppLifecycleListener(onResume: _onAppResumed);
  }

  void _onAppResumed() {
    final imgProv = context.read<ip.DeviceImageProvider>();
    if (!imgProv.permissionGranted) {
      imgProv.requestPermissionAndLoad();
    } else if (imgProv.all.isEmpty) {
      imgProv.loadAll();
    }
  }

  void _onScroll() {
    final imgProv = context.read<ip.DeviceImageProvider>();
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      imgProv.loadMore();
    }
    _prefetchFromScroll(imgProv.filtered);
  }

  void _prefetchFromScroll(List<AssetEntity> assets) {
    if (_cellSize <= 0 || assets.isEmpty) return;
    final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final row = (offset / _cellSize).round();
    final center = (row * _currentCrossAxisCount).clamp(0, assets.length - 1);
    _prefetchAround(center, _currentCrossAxisCount, assets);
  }

  void _prefetchAround(int center, int cols, List<AssetEntity> assets) {
    if (assets.isEmpty) return;
    final half = _prefetchRows * cols;
    final start = (center - half).clamp(0, assets.length - 1);
    final end = (center + half).clamp(0, assets.length - 1);

    if ((center - _lastPrefetchCenter).abs() < cols) return;
    _lastPrefetchCenter = center;

    for (int i = start; i <= end; i++) {
      final id = assets[i].id;
      if (_thumbnailCache.containsKey(id)) continue;
      _thumbnailCache[id] = null; // mark in-flight
      assets[i]
          .thumbnailDataWithSize(const ThumbnailSize(200, 200))
          .then((bytes) {
        _thumbnailCache[id] = bytes;
      }).ignore();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _lifecycleListener.dispose();
    super.dispose();
  }

  // ── Drag-select callbacks ──────────────────────────────────────────────────

  void _onSelectionStart(int index) {
    final selProv = context.read<SelectionProvider>();
    final imgProv = context.read<ip.DeviceImageProvider>();
    final id = imgProv.filtered[index].id;

    setState(() {
      _selectionMode = true;
      _dragDeselectMode = selProv.isSelected(id);
      _preDragSelection = Set<String>.from(selProv.assetIds);
      _dragSweepIndices = {index};
    });

    if (!_dragDeselectMode) {
      selProv.select(id);
    }
  }

  void _onSelectionUpdate(int start, int end) {
    final selProv = context.read<SelectionProvider>();
    final imgProv = context.read<ip.DeviceImageProvider>();
    final assets = imgProv.filtered;

    final newSweep = <int>{for (int i = start; i <= end; i++) i};
    if (newSweep.length == _dragSweepIndices.length &&
        newSweep.containsAll(_dragSweepIndices)) {
      return;
    }

    setState(() => _dragSweepIndices = newSweep);
    _prefetchAround(end, _currentCrossAxisCount, assets);

    final sweepIds = newSweep.map((i) => assets[i].id).toSet();

    // Build the desired selection based on drag mode
    final desired = _dragDeselectMode
        ? _preDragSelection.difference(sweepIds)
        : _preDragSelection.union(sweepIds);

    // Apply: add new, remove stale
    final toAdd = desired.difference(selProv.assetIds.toSet());
    final toRemove = selProv.assetIds.toSet().difference(desired);
    for (final id in toAdd) {
      selProv.select(id);
    }
    for (final id in toRemove) {
      selProv.deselect(id);
    }
  }

  void _onSelectionEnd() {
    setState(() {
      _dragSweepIndices = {};
      _preDragSelection = {};
      _dragDeselectMode = false;
    });
  }

  void _onItemTap(int index) {
    final imgProv = context.read<ip.DeviceImageProvider>();
    final selProv = context.read<SelectionProvider>();

    if (_selectionMode) {
      selProv.toggle(imgProv.filtered[index].id);
      if (selProv.count == 0) setState(() => _selectionMode = false);
    } else {
      context.read<FilteredListNotifier>().setList(imgProv.filtered);
      context.push('/images/view/$index');
    }
  }

  void _exitSelectionMode() {
    setState(() => _selectionMode = false);
  }

  @override
  Widget build(BuildContext context) {
    final imgProv = context.watch<ip.DeviceImageProvider>();
    final selProv = context.watch<SelectionProvider>();
    final selCount = selProv.count;

    context.read<SelectionCountNotifier>().update(selCount);

    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('$selCount selected')
            : const Text('Photos'),
        actions: [
          if (_selectionMode) ...[
            // Select-all
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Select all',
              onPressed: () {
                for (final a in imgProv.filtered) {
                  selProv.select(a.id);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _exitSelectionMode,
            ),
          ] else ...[
            if (selCount > 0)
              TextButton.icon(
                onPressed: () => context.push('/selected'),
                icon: Badge(
                  label: Text('$selCount'),
                  child: const Icon(Icons.checklist),
                ),
                label: const Text('Selected'),
              ),
            IconButton(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filters & Sort',
              onPressed: () => _showFilterSheet(context, imgProv),
            ),
          ],
        ],
        // Native album dropdown
        bottom: imgProv.nativeAlbums.length > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  child: DropdownButtonFormField<AssetPathEntity?>(
                    value: imgProv.filterState.nativeAlbum,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem<AssetPathEntity?>(
                        value: null,
                        child: Text('All Photos'),
                      ),
                      ...imgProv.nativeAlbums.map((a) =>
                          DropdownMenuItem<AssetPathEntity?>(
                            value: a,
                            child: Text(
                                a.name.isEmpty ? 'All Photos' : a.name),
                          )),
                    ],
                    onChanged: (album) {
                      imgProv.setFilter(imgProv.filterState
                          .copyWith(nativeAlbum: album));
                    },
                  ),
                ),
              )
            : null,
      ),
      body: imgProv.loading
          ? const Center(child: CircularProgressIndicator())
          : !imgProv.permissionGranted
              ? _PermissionPrompt(
                  onRequest: imgProv.requestPermissionAndLoad)
              : imgProv.filtered.isEmpty
                  ? const Center(child: Text('No photos found.'))
                  : LayoutBuilder(
                      builder: (ctx, constraints) {
                        int cols = 3;
                        if (constraints.maxWidth > 600) cols = 4;
                        if (constraints.maxWidth > 900) cols = 5;

                        if (_currentCrossAxisCount != cols) {
                          _currentCrossAxisCount = cols;
                        }
                        const spacing = 4.0;
                        const pad = 4.0;
                        final cellW =
                            (constraints.maxWidth - pad * 2 - spacing * (cols - 1)) /
                                cols;
                        if (cellW > 0) _cellSize = cellW;

                        final assets = imgProv.filtered;

                        return DragSelectGrid(
                          scrollController: _scrollController,
                          crossAxisCount: cols,
                          itemCount: assets.length,
                          spacing: spacing,
                          padding: const EdgeInsets.all(pad),
                          isInSelectionMode: _selectionMode,
                          onSelectionStart: _onSelectionStart,
                          onSelectionUpdate: _onSelectionUpdate,
                          onSelectionEnd: _onSelectionEnd,
                          onItemTap: _onItemTap,
                          child: GridView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(pad),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              crossAxisSpacing: spacing,
                              mainAxisSpacing: spacing,
                            ),
                            itemCount: assets.length,
                            itemBuilder: (ctx, i) {
                              final asset = assets[i];
                              return AssetThumb(
                                key: ValueKey(asset.id),
                                asset: asset,
                                selected: selProv.isSelected(asset.id),
                                cachedBytes: _thumbnailCache[asset.id],
                              );
                            },
                          ),
                        );
                      },
                    ),
    );
  }

  void _showFilterSheet(
      BuildContext context, ip.DeviceImageProvider imgProv) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        current: imgProv.filterState,
        onApply: (state) {
          imgProv.setFilter(state);
          Navigator.pop(context);
        },
      ),
    );
  }
}

// ── Filter / sort bottom sheet ────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  final ip.ImageFilterState current;
  final ValueChanged<ip.ImageFilterState> onApply;

  const _FilterSheet({required this.current, required this.onApply});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ip.ImageFilterState _state;
  final _minWCtrl = TextEditingController();
  final _minHCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _state = widget.current;
    _minWCtrl.text = _state.minWidth?.toString() ?? '';
    _minHCtrl.text = _state.minHeight?.toString() ?? '';
  }

  @override
  void dispose() {
    _minWCtrl.dispose();
    _minHCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ap = context.read<AlbumProvider>();
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Filter & Sort',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),

            // ── Custom album filter ──────────────────────────────────────
            Text('Custom Album Filter',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),

            // Mode selector
            if (_state.albumIds.isNotEmpty) ...[
              Row(
                children: [
                  const Text('Mode: '),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('In these albums'),
                    selected: _state.albumFilterMode ==
                        ip.AlbumFilterMode.includeAny,
                    onSelected: (_) => setState(() => _state = _state.copyWith(
                        albumFilterMode: ip.AlbumFilterMode.includeAny)),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Not in these albums'),
                    selected: _state.albumFilterMode ==
                        ip.AlbumFilterMode.excludeAll,
                    onSelected: (_) => setState(() => _state = _state.copyWith(
                        albumFilterMode: ip.AlbumFilterMode.excludeAll)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],

            // Album multi-select chips
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: ap.albums.map((a) {
                final selected = _state.albumIds.contains(a.id);
                return FilterChip(
                  label: Text(a.name),
                  selected: selected,
                  onSelected: (v) {
                    final newIds = Set<int>.from(_state.albumIds);
                    v ? newIds.add(a.id!) : newIds.remove(a.id);
                    setState(
                        () => _state = _state.copyWith(albumIds: newIds));
                  },
                );
              }).toList(),
            ),
            if (ap.albums.isEmpty)
              Text('No custom albums yet.',
                  style: TextStyle(color: theme.colorScheme.outline)),

            const SizedBox(height: 12),

            // Favorite albums only
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('In favorite albums only'),
              value: _state.onlyFavoriteAlbums,
              onChanged: (v) => setState(
                  () => _state = _state.copyWith(onlyFavoriteAlbums: v)),
            ),

            // Min dimensions
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minWCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Min width (px)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _minHCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Min height (px)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Sort
            Text('Sort', style: theme.textTheme.titleSmall),
            Wrap(
              spacing: 8,
              children: ip.SortOrder.values.map((s) {
                return ChoiceChip(
                  label: Text(_sortLabel(s)),
                  selected: _state.sortOrder == s,
                  onSelected: (_) => setState(
                      () => _state = _state.copyWith(sortOrder: s)),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            FilledButton(
              onPressed: () {
                final w = int.tryParse(_minWCtrl.text);
                final h = int.tryParse(_minHCtrl.text);
                widget.onApply(
                    _state.copyWith(minWidth: w, minHeight: h));
              },
              child: const Text('Apply'),
            ),
            TextButton(
              onPressed: () =>
                  widget.onApply(const ip.ImageFilterState()),
              child: const Text('Reset filters'),
            ),
          ],
        ),
      ),
    );
  }

  String _sortLabel(ip.SortOrder s) => switch (s) {
        ip.SortOrder.dateDesc => 'Newest first',
        ip.SortOrder.dateAsc => 'Oldest first',
        ip.SortOrder.nameAsc => 'Name A–Z',
        ip.SortOrder.nameDesc => 'Name Z–A',
      };
}

// ── Permission prompt ──────────────────────────────────────────────────────────

class _PermissionPrompt extends StatelessWidget {
  final VoidCallback onRequest;
  const _PermissionPrompt({required this.onRequest});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined, size: 64),
            const SizedBox(height: 16),
            const Text(
              'PhotoVault needs access to your photos.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRequest,
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Provider to share the current filtered list with ImageView for swipe nav.
class FilteredListNotifier extends ChangeNotifier {
  List<dynamic> _list = [];
  List<dynamic> get list => _list;

  void setList(List<dynamic> list) {
    _list = list;
    notifyListeners();
  }
}

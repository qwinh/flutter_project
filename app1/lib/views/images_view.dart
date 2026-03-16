// lib/views/images_view.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart' as ip;
import 'package:provider/provider.dart';

import '../providers/album_provider.dart';
import '../providers/image_provider.dart' as ip;
import '../providers/selection_provider.dart';
import '../router/app_router.dart';
import '../widgets/widgets.dart';
import '../widgets/drag_select_grid.dart';

class ImagesView extends StatefulWidget {
  const ImagesView({super.key});

  @override
  State<ImagesView> createState() => _ImagesViewState();
}

class _ImagesViewState extends State<ImagesView> {
  bool _selectionMode = false;
  late final AppLifecycleListener _lifecycleListener;

  final _scrollController = ScrollController();

  bool _dragDeselectMode = false;
  Set<String> _preDragSelection = {};

  // ── Local hide-selected state ─────────────────────────────────────────────
  // Accumulated set of IDs hidden by pressing the hide button.
  // Tap: union current selection into this set.
  // Double-tap: clear this set (unhide all).
  // Lives only in this widget — nothing is stored or persisted.
  Set<String> _hiddenIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ip.DeviceImageProvider>().requestPermissionAndLoad();
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

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _enterSelectionMode() => setState(() => _selectionMode = true);
  void _exitSelectionMode() => setState(() => _selectionMode = false);

  // ── Hide button logic ─────────────────────────────────────────────────────

  /// Single tap: snapshot current selection into hidden set (additive).
  void _hideSelected(SelectionProvider selProv) {
    if (selProv.count == 0) return;
    setState(() {
      _hiddenIds = {..._hiddenIds, ...selProv.assetIds};
    });
  }

  /// Double-tap: clear all hidden IDs, everything reappears.
  void _unhideAll() {
    setState(() => _hiddenIds = {});
  }

  // ── Visible assets (provider filtered list minus locally hidden) ──────────

  List<ip.AssetEntity> _visibleAssets(ip.DeviceImageProvider imgProv) {
    if (_hiddenIds.isEmpty) return imgProv.filtered;
    return imgProv.filtered
        .where((a) => !_hiddenIds.contains(a.id))
        .toList();
  }

  // ── DragSelectGrid callbacks ───────────────────────────────────────────────

  void _onDragSelectionStart(int startIndex, List<ip.AssetEntity> visible) {
    final selProv = context.read<SelectionProvider>();
    final id = visible[startIndex].id;

    _dragDeselectMode = selProv.isSelected(id);
    _preDragSelection = selProv.assetIds.toSet();

    setState(() => _selectionMode = true);

    if (!_dragDeselectMode) selProv.select(id);
  }

  void _onDragSelectionUpdate(int startIndex, int endIndex, List<ip.AssetEntity> visible) {
    final selProv = context.read<SelectionProvider>();

    final sweepIds = <String>{};
    for (int i = startIndex; i <= endIndex; i++) {
      if (i < visible.length) sweepIds.add(visible[i].id);
    }

    final desired = _dragDeselectMode
        ? _preDragSelection.difference(sweepIds)
        : _preDragSelection.union(sweepIds);

    selProv.setSelection(desired);
  }

  void _onDragSelectionEnd() {
    _preDragSelection = {};
    _dragDeselectMode = false;
  }

  void _onItemTap(int index, List<ip.AssetEntity> visible) {
    final selProv = context.read<SelectionProvider>();
    if (_selectionMode) {
      selProv.toggle(visible[index].id).then((_) {
        if (selProv.count == 0) _exitSelectionMode();
      });
    } else {
      context.read<FilteredListNotifier>().setList(visible);
      context.push('/images/view/$index');
    }
  }

  void _showFilterSheet(BuildContext context, ip.DeviceImageProvider imgProv) {
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

  @override
  Widget build(BuildContext context) {
    final imgProv = context.watch<ip.DeviceImageProvider>();
    final selProv = context.watch<SelectionProvider>();
    final selCount = selProv.count;
    final filterState = imgProv.filterState;
    final visible = _visibleAssets(imgProv);
    final hidingAny = _hiddenIds.isNotEmpty;

    context.read<SelectionCountNotifier>().update(selCount);

    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('$selCount selected')
            : const Text('Photos'),
        actions: [
          if (_selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.deselect),
              tooltip: 'Deselect all',
              onPressed: selCount > 0
                  ? () {
                      selProv.clearAll();
                      _exitSelectionMode();
                    }
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Select all visible',
              onPressed: () {
                final allIds = visible.map((a) => a.id).toSet();
                selProv.addMultiple(allIds);
              },
            ),
            // Hide selected: single tap hides, double-tap unhides all.
            if (selCount > 0)
              GestureDetector(
                onDoubleTap: _unhideAll,
                child: IconButton(
                  icon: Icon(
                    hidingAny ? Icons.visibility_off : Icons.visibility_off_outlined,
                    color: hidingAny
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  tooltip: hidingAny
                      ? 'Tap to hide more · Double-tap to show all'
                      : 'Hide selected from view',
                  onPressed: () => _hideSelected(selProv),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Exit selection',
              onPressed: _exitSelectionMode,
            ),
          ] else ...[
            // Hide button: visible whenever there's a selection or items are hidden.
            // Tap hides current selection, double-tap unhides all.
            if (selCount > 0 || hidingAny)
              GestureDetector(
                onDoubleTap: hidingAny ? _unhideAll : null,
                child: IconButton(
                  icon: Icon(
                    hidingAny ? Icons.visibility_off : Icons.visibility_off_outlined,
                    color: hidingAny
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  tooltip: hidingAny
                      ? 'Tap to hide more · Double-tap to show all'
                      : 'Hide selected from view',
                  onPressed: selCount > 0 ? () => _hideSelected(selProv) : null,
                ),
              ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  tooltip: 'Filters & Sort',
                  onPressed: () => _showFilterSheet(context, imgProv),
                ),
                if (filterState.hasAnyFilter)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
      body: imgProv.loading
          ? const Center(child: CircularProgressIndicator())
          : !imgProv.permissionGranted
              ? _PermissionPrompt(onRequest: imgProv.requestPermissionAndLoad)
              : RefreshIndicator(
                  onRefresh: () =>
                      context.read<ip.DeviceImageProvider>().loadAll(),
                  child: visible.isEmpty
                      ? SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SizedBox(
                            height: 300,
                            child: Center(
                              child: Text(hidingAny
                                  ? 'All photos are hidden.'
                                  : 'No photos found.'),
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (ctx, constraints) {
                            final gridWidth = constraints.maxWidth;
                            final cols =
                                (gridWidth / 120).floor().clamp(3, 6);
                            final itemCount = visible.length;
                            return DragSelectGrid(
                              scrollController: _scrollController,
                              crossAxisCount: cols,
                              itemCount: itemCount,
                              spacing: 2,
                              padding: const EdgeInsets.all(2),
                              isInSelectionMode: _selectionMode,
                              onSelectionStart: (i) =>
                                  _onDragSelectionStart(i, visible),
                              onSelectionUpdate: (s, e) =>
                                  _onDragSelectionUpdate(s, e, visible),
                              onSelectionEnd: _onDragSelectionEnd,
                              onItemTap: (i) => _onItemTap(i, visible),
                              child: GridView.builder(
                                controller: _scrollController,
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(2),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: cols,
                                  crossAxisSpacing: 2,
                                  mainAxisSpacing: 2,
                                ),
                                itemCount: itemCount,
                                itemBuilder: (ctx, i) {
                                  final asset = visible[i];
                                  return AssetThumb(
                                    asset: asset,
                                    selected: selProv.isSelected(asset.id),
                                  );
                                },
                              ),
                            );
                          },
                        ),
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

  void _toggleInclude(int albumId) {
    final next = Set<int>.from(_state.includeAlbumIds);
    if (next.contains(albumId)) {
      next.remove(albumId);
    } else {
      next.add(albumId);
      final excl = Set<int>.from(_state.excludeAlbumIds)..remove(albumId);
      setState(() =>
          _state = _state.copyWith(includeAlbumIds: next, excludeAlbumIds: excl));
      return;
    }
    setState(() => _state = _state.copyWith(includeAlbumIds: next));
  }

  void _toggleExclude(int albumId) {
    final next = Set<int>.from(_state.excludeAlbumIds);
    if (next.contains(albumId)) {
      next.remove(albumId);
    } else {
      next.add(albumId);
      final incl = Set<int>.from(_state.includeAlbumIds)..remove(albumId);
      setState(() =>
          _state = _state.copyWith(excludeAlbumIds: next, includeAlbumIds: incl));
      return;
    }
    setState(() => _state = _state.copyWith(excludeAlbumIds: next));
  }

  @override
  Widget build(BuildContext context) {
    final albums = context.watch<AlbumProvider>().albums;
    final theme = Theme.of(context);

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Filter & Sort', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),

            // ── In these albums (include) ──────────────────────────────────
            Text('Show only — in these albums',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            if (albums.isEmpty)
              const Text('No albums yet.',
                  style: TextStyle(color: Colors.grey))
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: albums.map((a) {
                  final included = _state.includeAlbumIds.contains(a.id);
                  return FilterChip(
                    label: Text(a.name),
                    selected: included,
                    onSelected: (_) => _toggleInclude(a.id!),
                    selectedColor: theme.colorScheme.primaryContainer,
                    checkmarkColor: theme.colorScheme.onPrimaryContainer,
                  );
                }).toList(),
              ),
            const SizedBox(height: 14),

            // ── Not in these albums (exclude) ──────────────────────────────
            Text('Hide — in these albums',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            if (albums.isEmpty)
              const Text('No albums yet.',
                  style: TextStyle(color: Colors.grey))
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: albums.map((a) {
                  final excluded = _state.excludeAlbumIds.contains(a.id);
                  return FilterChip(
                    label: Text(a.name),
                    selected: excluded,
                    onSelected: (_) => _toggleExclude(a.id!),
                    selectedColor: theme.colorScheme.errorContainer,
                    checkmarkColor: theme.colorScheme.onErrorContainer,
                  );
                }).toList(),
              ),
            const SizedBox(height: 8),

            // ── Favorite albums only ───────────────────────────────────────
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('In favorite albums only'),
              value: _state.onlyFavoriteAlbums,
              onChanged: (v) => setState(
                  () => _state = _state.copyWith(onlyFavoriteAlbums: v)),
            ),

            // ── Min dimensions ─────────────────────────────────────────────
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
            const SizedBox(height: 14),

            // ── Sort ───────────────────────────────────────────────────────
            Text('Sort', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: ip.SortOrder.values.map((s) {
                return ChoiceChip(
                  label: Text(_sortLabel(s)),
                  selected: _state.sortOrder == s,
                  onSelected: (_) =>
                      setState(() => _state = _state.copyWith(sortOrder: s)),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            FilledButton(
              onPressed: () {
                final w = int.tryParse(_minWCtrl.text);
                final h = int.tryParse(_minHCtrl.text);
                widget.onApply(_state.copyWith(minWidth: w, minHeight: h));
              },
              child: const Text('Apply'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => widget.onApply(const ip.ImageFilterState()),
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

// ── Permission prompt ─────────────────────────────────────────────────────────

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
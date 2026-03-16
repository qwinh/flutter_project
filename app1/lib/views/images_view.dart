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

  // Tap → include. Tap again on included → clear. Double-tap → exclude.
  // Double-tap on excluded → clear.
  void _onAlbumTap(int albumId) {
    final included = _state.includeAlbumIds.contains(albumId);
    final excluded = _state.excludeAlbumIds.contains(albumId);
    if (included) {
      // clear
      setState(() => _state = _state.copyWith(
            includeAlbumIds: Set.from(_state.includeAlbumIds)..remove(albumId),
          ));
    } else if (excluded) {
      // clear exclude too (in case tap after double-tap)
      setState(() => _state = _state.copyWith(
            excludeAlbumIds: Set.from(_state.excludeAlbumIds)..remove(albumId),
          ));
    } else {
      // include
      setState(() => _state = _state.copyWith(
            includeAlbumIds: {..._state.includeAlbumIds, albumId},
            excludeAlbumIds: Set.from(_state.excludeAlbumIds)..remove(albumId),
          ));
    }
  }

  void _onAlbumDoubleTap(int albumId) {
    setState(() => _state = _state.copyWith(
          excludeAlbumIds: {..._state.excludeAlbumIds, albumId},
          includeAlbumIds: Set.from(_state.includeAlbumIds)..remove(albumId),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final albums = context.watch<AlbumProvider>().albums;
    final sortedAlbums = [...albums]..sort((a, b) => a.name.compareTo(b.name));
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Handle bar ──────────────────────────────────────────────────
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [

                // ── Albums ────────────────────────────────────────────────
                if (albums.isNotEmpty) ...[
                  Row(
                    children: [
                      Text('Albums', style: theme.textTheme.labelMedium
                          ?.copyWith(color: cs.onSurfaceVariant)),
                      const Spacer(),
                      Text('tap include · hold exclude',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant.withOpacity(0.6))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Material(
                        color: cs.surfaceContainerHighest.withOpacity(0.45),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          shrinkWrap: true,
                          itemCount: sortedAlbums.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: cs.outlineVariant.withOpacity(0.3),
                          ),
                          itemBuilder: (_, i) {
                            final a = sortedAlbums[i];
                            final included = _state.includeAlbumIds.contains(a.id);
                            final excluded = _state.excludeAlbumIds.contains(a.id);
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _onAlbumTap(a.id!),
                              onLongPress: () => _onAlbumDoubleTap(a.id!),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        a.name,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: included
                                              ? cs.primary
                                              : excluded
                                                  ? cs.error
                                                  : null,
                                          fontWeight: (included || excluded)
                                              ? FontWeight.w500
                                              : null,
                                        ),
                                      ),
                                    ),
                                    if (included)
                                      Icon(Icons.check_circle_rounded,
                                          size: 16, color: cs.primary)
                                    else if (excluded)
                                      Icon(Icons.remove_circle_rounded,
                                          size: 16, color: cs.error)
                                    else
                                      const SizedBox(width: 16),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Favorite albums only ────────────────────────────────
                _SubtleSwitch(
                  label: 'Favorite albums only',
                  value: _state.onlyFavoriteAlbums,
                  onChanged: (v) => setState(
                      () => _state = _state.copyWith(onlyFavoriteAlbums: v)),
                ),
                const SizedBox(height: 8),

                // ── Min dimensions ──────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _SubtleTextField(
                        controller: _minWCtrl,
                        label: 'Min W (px)',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SubtleTextField(
                        controller: _minHCtrl,
                        label: 'Min H (px)',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Sort ────────────────────────────────────────────────
                Text('Sort', style: theme.textTheme.labelMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: 6,
                    children: ip.SortOrder.values.map((s) {
                      final active = _state.sortOrder == s;
                      return GestureDetector(
                        onTap: () => setState(
                            () => _state = _state.copyWith(sortOrder: s)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: active
                                ? cs.primaryContainer
                                : cs.surfaceContainerHighest.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _sortLabel(s),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: active
                                  ? cs.onPrimaryContainer
                                  : cs.onSurfaceVariant,
                              fontWeight: active ? FontWeight.w600 : null,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Actions ─────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          final w = int.tryParse(_minWCtrl.text);
                          final h = int.tryParse(_minHCtrl.text);
                          widget.onApply(
                              _state.copyWith(minWidth: w, minHeight: h));
                        },
                        child: const Text('Apply'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () =>
                          widget.onApply(const ip.ImageFilterState()),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _sortLabel(ip.SortOrder s) => switch (s) {
        ip.SortOrder.dateDesc => 'Newest',
        ip.SortOrder.dateAsc => 'Oldest',
        ip.SortOrder.nameAsc => 'A→Z',
        ip.SortOrder.nameDesc => 'Z→A',
      };
}

// ── Subtle helper widgets ─────────────────────────────────────────────────────

class _SubtleSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SubtleSwitch(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: value ? cs.primary : cs.onSurfaceVariant,
                    )),
            const Spacer(),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

class _SubtleTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const _SubtleTextField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withOpacity(0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
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
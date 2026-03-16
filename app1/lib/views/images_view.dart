// lib/views/images_view.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart' as pm;
import 'package:provider/provider.dart';

import '../providers/album_provider.dart';
import '../providers/image_provider.dart' as ip;
import '../providers/notifiers.dart';
import '../providers/selection_provider.dart';
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
  Set<String> _hiddenIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        context.read<ip.DeviceImageProvider>().requestPermissionAndLoad());
    _lifecycleListener = AppLifecycleListener(onResume: _onAppResumed);
  }

  void _onAppResumed() {
    final p = context.read<ip.DeviceImageProvider>();
    if (!p.permissionGranted) {
      p.requestPermissionAndLoad();
    } else if (p.all.isEmpty) {
      p.loadAll();
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _exitSelectionMode() => setState(() => _selectionMode = false);

  List<pm.AssetEntity> _visible(ip.DeviceImageProvider p) => _hiddenIds.isEmpty
      ? p.filtered
      : p.filtered.where((a) => !_hiddenIds.contains(a.id)).toList();

  void _hideSelected(SelectionProvider sel) {
    if (sel.count == 0) return;
    setState(() => _hiddenIds = {..._hiddenIds, ...sel.assetIds});
  }

  void _unhideAll() => setState(() => _hiddenIds = {});

  void _onDragStart(int i, List<pm.AssetEntity> vis) {
    final sel = context.read<SelectionProvider>();
    _dragDeselectMode = sel.isSelected(vis[i].id);
    _preDragSelection = sel.assetIds.toSet();
    setState(() => _selectionMode = true);
    if (!_dragDeselectMode) sel.select(vis[i].id);
  }

  void _onDragUpdate(int s, int e, List<pm.AssetEntity> vis) {
    final sel = context.read<SelectionProvider>();
    final sweep = {for (int i = s; i <= e; i++) if (i < vis.length) vis[i].id};
    sel.setSelection(_dragDeselectMode
        ? _preDragSelection.difference(sweep)
        : _preDragSelection.union(sweep));
  }

  void _onDragEnd() {
    _preDragSelection = {};
    _dragDeselectMode = false;
  }

  void _onTap(int i, List<pm.AssetEntity> vis) {
    final sel = context.read<SelectionProvider>();
    if (_selectionMode) {
      sel.toggle(vis[i].id).then((_) { if (sel.count == 0) _exitSelectionMode(); });
    } else {
      context.read<FilteredListNotifier>().setList(vis);
      context.push('/images/view/$i');
    }
  }

  void _showFilterSheet(ip.DeviceImageProvider p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        current: p.filterState,
        onApply: (s) { p.setFilter(s); Navigator.pop(context); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imgProv = context.watch<ip.DeviceImageProvider>();
    final sel = context.watch<SelectionProvider>();
    final vis = _visible(imgProv);
    final hiding = _hiddenIds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: _selectionMode ? Text('${sel.count} selected') : const Text('Photos'),
        actions: [
          if (_selectionMode) ...[
            IconButton(icon: const Icon(Icons.deselect), tooltip: 'Deselect all',
              onPressed: sel.count > 0 ? () { sel.clearAll(); _exitSelectionMode(); } : null),
            IconButton(icon: const Icon(Icons.select_all), tooltip: 'Select all visible',
              onPressed: () => sel.addMultiple(vis.map((a) => a.id).toSet())),
            if (sel.count > 0)
              GestureDetector(
                onDoubleTap: hiding ? _unhideAll : null,
                child: IconButton(
                  icon: Icon(hiding ? Icons.visibility_off : Icons.visibility_off_outlined,
                      color: hiding ? Theme.of(context).colorScheme.primary : null),
                  tooltip: hiding ? 'Tap hide more · Double-tap show all' : 'Hide selected',
                  onPressed: () => _hideSelected(sel),
                ),
              ),
            IconButton(icon: const Icon(Icons.close), onPressed: _exitSelectionMode),
          ] else ...[
            if (sel.count > 0 || hiding)
              GestureDetector(
                onDoubleTap: hiding ? _unhideAll : null,
                child: IconButton(
                  icon: Icon(hiding ? Icons.visibility_off : Icons.visibility_off_outlined,
                      color: hiding ? Theme.of(context).colorScheme.primary : null),
                  tooltip: hiding ? 'Tap hide more · Double-tap show all' : 'Hide selected',
                  onPressed: sel.count > 0 ? () => _hideSelected(sel) : null,
                ),
              ),
            Stack(clipBehavior: Clip.none, children: [
              IconButton(icon: const Icon(Icons.filter_list), tooltip: 'Filters & Sort',
                  onPressed: () => _showFilterSheet(imgProv)),
              if (imgProv.filterState.hasAnyFilter)
                Positioned(right: 6, top: 6, child: Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
                )),
            ]),
          ],
        ],
      ),
      body: imgProv.loading
          ? const Center(child: CircularProgressIndicator())
          : !imgProv.permissionGranted
              ? _PermissionPrompt(onRequest: imgProv.requestPermissionAndLoad)
              : RefreshIndicator(
                  onRefresh: () => context.read<ip.DeviceImageProvider>().loadAll(),
                  child: vis.isEmpty
                      ? SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SizedBox(height: 300, child: Center(
                            child: Text(hiding ? 'All photos hidden.' : 'No photos found.'))))
                      : LayoutBuilder(builder: (ctx, constraints) {
                          final w = constraints.maxWidth;
                          final cols = (w / 120).floor().clamp(3, 6);
                          return DragSelectGrid(
                            scrollController: _scrollController,
                            crossAxisCount: cols, itemCount: vis.length,
                            spacing: 2, padding: const EdgeInsets.all(2),
                            isInSelectionMode: _selectionMode,
                            onSelectionStart: (i) => _onDragStart(i, vis),
                            onSelectionUpdate: (s, e) => _onDragUpdate(s, e, vis),
                            onSelectionEnd: _onDragEnd,
                            onItemTap: (i) => _onTap(i, vis),
                            child: GridView.builder(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(2),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: cols, crossAxisSpacing: 2, mainAxisSpacing: 2),
                              itemCount: vis.length,
                              itemBuilder: (ctx, i) {
                                final asset = vis[i];
                                final idx = sel.assetIds.indexOf(asset.id);
                                return AssetThumb(
                                  asset: asset,
                                  selected: idx >= 0,
                                  selectionIndex: idx >= 0 ? idx + 1 : null,
                                );
                              },
                            ),
                          );
                        }),
                ),
    );
  }
}

// ── Filter sheet ──────────────────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  final ip.ImageFilterState current;
  final ValueChanged<ip.ImageFilterState> onApply;
  const _FilterSheet({required this.current, required this.onApply});
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ip.ImageFilterState _s;
  final _minW = TextEditingController();
  final _minH = TextEditingController();
  bool _sortActive = false;

  @override
  void initState() {
    super.initState();
    _s = widget.current;
    _minW.text = _s.minWidth?.toString() ?? '';
    _minH.text = _s.minHeight?.toString() ?? '';
  }

  @override
  void dispose() { _minW.dispose(); _minH.dispose(); super.dispose(); }

  void _tapAlbum(int id) {
    if (_s.includeAlbumIds.contains(id)) {
      setState(() => _s = _s.copyWith(includeAlbumIds: {..._s.includeAlbumIds}..remove(id)));
    } else if (_s.excludeAlbumIds.contains(id)) {
      setState(() => _s = _s.copyWith(excludeAlbumIds: {..._s.excludeAlbumIds}..remove(id)));
    } else {
      setState(() => _s = _s.copyWith(
        includeAlbumIds: {..._s.includeAlbumIds, id},
        excludeAlbumIds: {..._s.excludeAlbumIds}..remove(id),
      ));
    }
  }

  void _holdAlbum(int id) => setState(() => _s = _s.copyWith(
    excludeAlbumIds: {..._s.excludeAlbumIds, id},
    includeAlbumIds: {..._s.includeAlbumIds}..remove(id),
  ));

  @override
  Widget build(BuildContext context) {
    final albums = context.watch<AlbumProvider>().albums;
    final base = [...albums]..sort((a, b) => a.name.compareTo(b.name));
    final sorted = _sortActive ? [
      ...base.where((a) => _s.includeAlbumIds.contains(a.id) || _s.excludeAlbumIds.contains(a.id)),
      ...base.where((a) => !_s.includeAlbumIds.contains(a.id) && !_s.excludeAlbumIds.contains(a.id)),
    ] : base;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
              children: [

                if (albums.isNotEmpty) ...[
                  Row(children: [
                    Text('Albums', style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(width: 6),
                    FilterPill(label: _s.albumFilterAnd ? 'ALL' : 'ANY', color: cs.secondaryContainer,
                        textColor: cs.onSecondaryContainer,
                        onTap: () => setState(() => _s = _s.copyWith(albumFilterAnd: !_s.albumFilterAnd))),
                    const SizedBox(width: 6),
                    FilterPill(label: _sortActive ? '● A-Z' : 'A-Z',
                        color: _sortActive ? cs.tertiaryContainer : cs.surfaceContainerHighest.withOpacity(0.5),
                        textColor: _sortActive ? cs.onTertiaryContainer : cs.onSurfaceVariant,
                        onTap: () => setState(() => _sortActive = !_sortActive)),
                    const Spacer(),
                    Text('tap · hold exclude', style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant.withOpacity(0.5))),
                  ]),
                  const SizedBox(height: 6),
                  FilterScrollList(
                    maxHeight: 220,
                    itemBuilder: (ctx, i) {
                      final a = sorted[i];
                      final inc = _s.includeAlbumIds.contains(a.id);
                      final exc = _s.excludeAlbumIds.contains(a.id);
                      return FilterListRow(
                        label: a.name, included: inc, excluded: exc,
                        onTap: () => _tapAlbum(a.id!),
                        onLongPress: () => _holdAlbum(a.id!),
                      );
                    },
                    itemCount: sorted.length,
                  ),
                  const SizedBox(height: 12),
                ],

                _SubtleSwitch(label: 'Favorite albums only', value: _s.onlyFavoriteAlbums,
                    onChanged: (v) => setState(() => _s = _s.copyWith(onlyFavoriteAlbums: v))),
                const SizedBox(height: 8),

                Row(children: [
                  Expanded(child: _SubtleTextField(controller: _minW, label: 'Min W (px)')),
                  const SizedBox(width: 10),
                  Expanded(child: _SubtleTextField(controller: _minH, label: 'Min H (px)')),
                ]),
                const SizedBox(height: 12),

                Text('Sort', style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(spacing: 6, children: ip.SortOrder.values.map((s) {
                    final active = _s.sortOrder == s;
                    return FilterPill(
                      label: _sortLabel(s),
                      color: active ? cs.primaryContainer : cs.surfaceContainerHighest.withOpacity(0.4),
                      textColor: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                      bold: active,
                      onTap: () => setState(() => _s = _s.copyWith(sortOrder: s)),
                    );
                  }).toList()),
                ),
                const SizedBox(height: 16),

                Row(children: [
                  Expanded(child: FilledButton(
                    onPressed: () => widget.onApply(_s.copyWith(
                        minWidth: int.tryParse(_minW.text),
                        minHeight: int.tryParse(_minH.text))),
                    child: const Text('Apply'),
                  )),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () => widget.onApply(const ip.ImageFilterState()),
                    child: const Text('Reset'),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _sortLabel(ip.SortOrder s) => switch (s) {
    ip.SortOrder.dateDesc => 'Newest',
    ip.SortOrder.dateAsc  => 'Oldest',
    ip.SortOrder.nameAsc  => 'A→Z',
    ip.SortOrder.nameDesc => 'Z→A',
  };
}

class _SubtleSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SubtleSwitch({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: value ? cs.primary : cs.onSurfaceVariant)),
          const Spacer(),
          Switch.adaptive(value: value, onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ]),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withOpacity(0.4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      ),
    );
  }
}

class _PermissionPrompt extends StatelessWidget {
  final VoidCallback onRequest;
  const _PermissionPrompt({required this.onRequest});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.photo_library_outlined, size: 64),
        const SizedBox(height: 16),
        const Text('PhotoVault needs access to your photos.', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRequest, child: const Text('Grant Permission')),
      ]),
    ),
  );
}

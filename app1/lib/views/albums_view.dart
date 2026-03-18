// lib/views/albums_view.dart
// Shows all albums as list tiles.
// Long press → multi-select mode.
// Swipe left-to-right → edit, right-to-left → delete.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/album_provider.dart';
import '../providers/tag_provider.dart';
import '../services/notification_service.dart';
import '../widgets/widgets.dart';

class AlbumsView extends StatefulWidget {
  const AlbumsView({super.key});

  @override
  State<AlbumsView> createState() => _AlbumsViewState();
}

class _AlbumsViewState extends State<AlbumsView> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<int> _selectedIds = {};
  bool _selectionMode = false;
  bool _favOnly = false;

  Set<int> _tagFilter = {};
  Set<int> _tagExclude = {};
  bool _tagFilterAnd = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AlbumModel> _applyFilters(List<AlbumModel> albums, AlbumProvider ap) {
    return albums.where((a) {
      if (_searchQuery.isNotEmpty &&
          !a.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      if (_favOnly && !a.isFavorite) return false;
      final allTagIds = {..._tagFilter, ..._tagExclude};
      if (allTagIds.isNotEmpty) {
        final albumTagIds = ap.getTagIdsSync(a.id!).toSet();
        final predicates = allTagIds.map((id) {
          final has = albumTagIds.contains(id);
          return _tagFilter.contains(id) ? has : !has;
        });
        final match = _tagFilterAnd
            ? predicates.every((p) => p)
            : predicates.any((p) => p);
        if (!match) return false;
      }
      return true;
    }).toList();
  }

  void _enterSelectionMode(int id) => setState(() {
        _selectionMode = true;
        _selectedIds.add(id);
      });

  void _exitSelectionMode() => setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });

  Future<void> _bulkDelete() async {
    final count = _selectedIds.length;
    final confirmed = await confirmDialog(
      context,
      title: 'Delete Albums',
      message: 'Delete $count album(s)?',
    );
    if (!confirmed || !mounted) return;
    // Single notifyListeners at the end via deleteAlbums.
    await context.read<AlbumProvider>().deleteAlbums(Set.of(_selectedIds));
    _exitSelectionMode();
    await NotificationService.instance.show(
        'Albums deleted', '$count album(s) removed.');
  }

  Future<void> _bulkToggleFavorite() async {
    // Single notifyListeners at the end via toggleFavoriteAlbums.
    await context
        .read<AlbumProvider>()
        .toggleFavoriteAlbums(Set.of(_selectedIds));
    _exitSelectionMode();
  }

  @override
  Widget build(BuildContext context) {
    final ap = context.watch<AlbumProvider>();
    final tp = context.watch<TagProvider>();
    final filtered = _applyFilters(ap.albums, ap);

    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('${_selectedIds.length} selected')
            : const Text('Albums'),
        actions: _selectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.favorite),
                  tooltip: 'Toggle favorite',
                  onPressed: _bulkToggleFavorite,
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'Delete',
                  onPressed: _bulkDelete,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _exitSelectionMode,
                ),
              ]
            : [
                IconButton(
                  icon: Icon(
                    _favOnly ? Icons.favorite : Icons.favorite_border,
                    color: _favOnly ? Colors.pink : null,
                  ),
                  tooltip: _favOnly ? 'Show all albums' : 'Favorites only',
                  onPressed: () => setState(() => _favOnly = !_favOnly),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'New album',
                  onPressed: () => context.push('/albums/add'),
                ),
              ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search albums…',
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          if (tp.tags.isNotEmpty)
            _TagFilterBar(
              tags: tp.tags,
              included: _tagFilter,
              excluded: _tagExclude,
              andMode: _tagFilterAnd,
              onIncludedChanged: (s) => setState(() => _tagFilter = s),
              onExcludedChanged: (s) => setState(() => _tagExclude = s),
              onModeChanged: (v) => setState(() => _tagFilterAnd = v),
            ),
          Expanded(
            child: ap.loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? const Center(child: Text('No albums yet.'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final album = filtered[i];
                          return _AlbumTile(
                            // Stable key prevents Flutter from tearing down
                            // _AlbumThumb state on selection changes.
                            key: ValueKey('tile_${album.id}'),
                            album: album,
                            selectionMode: _selectionMode,
                            isSelected: _selectedIds.contains(album.id),
                            onTap: () {
                              if (_selectionMode) {
                                setState(() {
                                  _selectedIds.contains(album.id)
                                      ? _selectedIds.remove(album.id)
                                      : _selectedIds.add(album.id!);
                                });
                              } else {
                                context.push('/albums/${album.id}');
                              }
                            },
                            onDoubleTap: () => context
                                .read<AlbumProvider>()
                                .updateAlbum(album.copyWith(
                                    isFavorite: !album.isFavorite)),
                            onLongPress: () =>
                                _enterSelectionMode(album.id!),
                            onEdit: () =>
                                context.push('/albums/${album.id}?edit=true'),
                            onDelete: () async {
                              final ok = await confirmDialog(
                                context,
                                title: 'Delete Album',
                                message: 'Delete "${album.name}"?',
                              );
                              if (ok && context.mounted) {
                                await context
                                    .read<AlbumProvider>()
                                    .deleteAlbum(album.id!);
                              }
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Album list tile with swipe actions ────────────────────────────────────────

class _AlbumTile extends StatelessWidget {
  final AlbumModel album;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onLongPress;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AlbumTile({
    super.key,
    required this.album,
    required this.selectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onLongPress,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('album_${album.id}'),
      background: Container(
        color: Colors.blue,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onEdit();
          return false;
        }
        return confirmDialog(
          context,
          title: 'Delete Album',
          message: 'Delete "${album.name}"?',
        );
      },
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onDoubleTap: onDoubleTap,
        child: Tooltip(
          message: 'Double-tap to toggle favorite',
          child: ListTile(
            selected: isSelected,
            // _AlbumThumb is keyed by albumId; its state lives as long as
            // the tile stays in the tree — selection changes no longer
            // destroy and recreate it.
            leading: _AlbumThumb(
              key: ValueKey('thumb_${album.id}'),
              albumId: album.id!,
            ),
            title: Text(album.name),
            subtitle: album.description.isNotEmpty
                ? Text(album.description,
                    maxLines: 1, overflow: TextOverflow.ellipsis)
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (album.isFavorite)
                  const Icon(Icons.favorite, color: Colors.pink, size: 18),
                if (selectionMode)
                  Icon(isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked),
              ],
            ),
            onTap: onTap,
            onLongPress: onLongPress,
          ),
        ),
      ),
    );
  }
}

// ── Album thumbnail ───────────────────────────────────────────────────────────

/// Shows the first image of the album as a square thumbnail.
/// Reads [AlbumProvider] directly so it doesn't need to be passed down.
/// State is preserved across parent rebuilds as long as the widget's [key]
/// stays stable (guaranteed by the ValueKey in _AlbumTile).
class _AlbumThumb extends StatefulWidget {
  final int albumId;
  const _AlbumThumb({super.key, required this.albumId});

  @override
  State<_AlbumThumb> createState() => _AlbumThumbState();
}

class _AlbumThumbState extends State<_AlbumThumb> {
  AssetEntity? _first;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-run whenever AlbumProvider notifies so the thumbnail stays fresh
    // after images are added to or removed from this album.
    _load();
  }

  Future<void> _load() async {
    final ids = await context.read<AlbumProvider>().getAssetIds(widget.albumId);
    if (!mounted) return;
    final entity = ids.isNotEmpty ? await AssetEntity.fromId(ids.first) : null;
    if (mounted) setState(() { _first = entity; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_first == null) {
      return Container(
        width: 48,
        height: 48,
        color: Theme.of(context).colorScheme.surfaceVariant,
        child: const Icon(Icons.photo),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 48,
        height: 48,
        child: AssetThumb(asset: _first!, size: 48),
      ),
    );
  }
}

// ── Tag filter bar ─────────────────────────────────────────────────────────────

class _TagFilterBar extends StatefulWidget {
  final List<TagModel> tags;
  final Set<int> included;
  final Set<int> excluded;
  final bool andMode;
  final ValueChanged<Set<int>> onIncludedChanged;
  final ValueChanged<Set<int>> onExcludedChanged;
  final ValueChanged<bool> onModeChanged;

  const _TagFilterBar({
    required this.tags,
    required this.included,
    required this.excluded,
    required this.andMode,
    required this.onIncludedChanged,
    required this.onExcludedChanged,
    required this.onModeChanged,
  });

  @override
  State<_TagFilterBar> createState() => _TagFilterBarState();
}

class _TagFilterBarState extends State<_TagFilterBar> {
  bool _sortActive = false;

  void _tap(int id) {
    if (widget.included.contains(id)) {
      widget.onIncludedChanged({...widget.included}..remove(id));
    } else if (widget.excluded.contains(id)) {
      widget.onExcludedChanged({...widget.excluded}..remove(id));
    } else {
      widget.onIncludedChanged({...widget.included, id});
      widget.onExcludedChanged({...widget.excluded}..remove(id));
    }
  }

  void _hold(int id) {
    widget.onExcludedChanged({...widget.excluded, id});
    widget.onIncludedChanged({...widget.included}..remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final hasFilter = widget.included.isNotEmpty || widget.excluded.isNotEmpty;

    final base = [...widget.tags]..sort((a, b) => a.name.compareTo(b.name));
    final sorted = _sortActive
        ? [
            ...base.where(
                (t) => widget.included.contains(t.id) || widget.excluded.contains(t.id)),
            ...base.where(
                (t) => !widget.included.contains(t.id) && !widget.excluded.contains(t.id)),
          ]
        : base;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('Tags',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(width: 6),
            FilterPill(
              label: widget.andMode ? 'ALL' : 'ANY',
              color: cs.secondaryContainer,
              textColor: cs.onSecondaryContainer,
              bold: true,
              onTap: () => widget.onModeChanged(!widget.andMode),
            ),
            const SizedBox(width: 6),
            FilterPill(
              label: _sortActive ? '● A-Z' : 'A-Z',
              color: _sortActive
                  ? cs.tertiaryContainer
                  : cs.surfaceContainerHighest.withOpacity(0.5),
              textColor: _sortActive ? cs.onTertiaryContainer : cs.onSurfaceVariant,
              onTap: () => setState(() => _sortActive = !_sortActive),
            ),
            const Spacer(),
            Text('tap · hold exclude',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant.withOpacity(0.5))),
            if (hasFilter) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  widget.onIncludedChanged({});
                  widget.onExcludedChanged({});
                },
                child: Icon(Icons.close,
                    size: 15, color: cs.onSurfaceVariant.withOpacity(0.7)),
              ),
            ],
          ]),
          const SizedBox(height: 5),
          FilterScrollList(
            maxHeight: 180,
            itemCount: sorted.length,
            itemBuilder: (_, i) {
              final t = sorted[i];
              return FilterListRow(
                label: t.name,
                included: widget.included.contains(t.id),
                excluded: widget.excluded.contains(t.id),
                onTap: () => _tap(t.id!),
                onLongPress: () => _hold(t.id!),
              );
            },
          ),
        ],
      ),
    );
  }
}
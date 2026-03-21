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
import '../widgets/description_subtitle.dart';
import '../widgets/filterable_list.dart';
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

  Set<TagModel> _tagFilter = {};
  Set<TagModel> _tagExclude = {};
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
      final allTags = {..._tagFilter, ..._tagExclude};
      if (allTags.isNotEmpty) {
        final albumTagIds = ap.getTagIdsSync(a.id!).toSet();
        final predicates = allTags.map((tag) {
          final has = albumTagIds.contains(tag.id);
          return _tagFilter.contains(tag) ? has : !has;
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
    await context.read<AlbumProvider>().deleteAlbums(Set.of(_selectedIds));
    _exitSelectionMode();
    await NotificationService.instance
        .show('Albums deleted', '$count album(s) removed.');
  }

  Future<void> _bulkToggleFavorite() async {
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
          // ── Tag filter — now uses shared FilterableListView ────────────
          if (tp.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
              child: FilterableListView<TagModel>(
                items: tp.tags,
                labelOf: (t) => t.name,
                included: _tagFilter,
                excluded: _tagExclude,
                andMode: _tagFilterAnd,
                header: 'Tags',
                onIncludedChanged: (s) => setState(() => _tagFilter = s),
                onExcludedChanged: (s) => setState(() => _tagExclude = s),
                onModeChanged: (v) => setState(() => _tagFilterAnd = v),
              ),
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
        // FIX: swipe-to-delete confirms here; onDismissed calls onDelete()
        // which must NOT show a second dialog (see _AlbumsViewState.onDelete).
        return confirmDialog(
          context,
          title: 'Delete Album',
          message: 'Delete "${album.name}"?',
        );
      },
      // onDismissed is only reached after confirmDismiss returned true,
      // so onDelete skips its own confirmation when called from here.
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onDoubleTap: onDoubleTap,
        child: Tooltip(
          message: 'Double-tap to toggle favorite',
          child: ListTile(
            selected: isSelected,
            leading: _AlbumThumb(
              key: ValueKey('thumb_${album.id}'),
              albumId: album.id!,
            ),
            title: Text(album.name),
            subtitle: descriptionSubtitle(album.description),
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
    _load();
  }

  Future<void> _load() async {
    final ids =
        await context.read<AlbumProvider>().getAssetIds(widget.albumId);
    if (!mounted) return;
    final entity =
        ids.isNotEmpty ? await AssetEntity.fromId(ids.first) : null;
    if (mounted) setState(() {
      _first = entity;
      _loaded = true;
    });
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

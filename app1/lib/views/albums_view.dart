// lib/views/albums_view.dart
// Displays all custom albums. Features: search, tag filter, favorites toggle,
// bulk select (delete/favorite) via long-press, swipe-to-delete, sort by date.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/album_provider.dart';
import '../providers/tag_provider.dart';
import '../widgets/widgets.dart';

class AlbumsView extends StatefulWidget {
  const AlbumsView({super.key});

  @override
  State<AlbumsView> createState() => _AlbumsViewState();
}

class _AlbumsViewState extends State<AlbumsView> {
  String _query = '';
  int? _filterTagId;
  bool _onlyFavorites = false;
  final _searchCtrl = TextEditingController();

  // Bulk-selection mode
  final Set<int> _bulkSelected = {};
  bool _bulkMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AlbumProvider>().load();
      context.read<TagProvider>().load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<AlbumModel> _filter(AlbumProvider ap, TagProvider tp) {
    var list = ap.albums;

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((a) => a.name.toLowerCase().contains(q)).toList();
    }
    if (_onlyFavorites) {
      list = list.where((a) => a.isFavorite).toList();
    }
    if (_filterTagId != null) {
      list = list
          .where((a) =>
              ap.getTagIdsSync(a.id!).contains(_filterTagId))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final ap = context.watch<AlbumProvider>();
    final tp = context.watch<TagProvider>();
    final filtered = _filter(ap, tp);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _bulkMode
            ? Text('${_bulkSelected.length} selected')
            : const Text('Albums'),
        actions: _bulkMode
            ? [
                IconButton(
                  icon: const Icon(Icons.favorite),
                  tooltip: 'Toggle favorite',
                  onPressed: () async {
                    for (final id in _bulkSelected) {
                      final a = ap.getById(id);
                      if (a != null) {
                        await ap.updateAlbum(
                            a.copyWith(isFavorite: !a.isFavorite));
                      }
                    }
                    setState(() {
                      _bulkMode = false;
                      _bulkSelected.clear();
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'Delete selected',
                  onPressed: () async {
                    final ok = await confirmDialog(context,
                        title: 'Delete Albums',
                        message:
                            'Delete ${_bulkSelected.length} album(s)?');
                    if (ok) {
                      for (final id in _bulkSelected.toList()) {
                        await ap.deleteAlbum(id);
                      }
                      setState(() {
                        _bulkMode = false;
                        _bulkSelected.clear();
                      });
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _bulkMode = false;
                    _bulkSelected.clear();
                  }),
                ),
              ]
            : [
                IconButton(
                  icon: Icon(
                    _onlyFavorites ? Icons.favorite : Icons.favorite_border,
                    color: _onlyFavorites ? Colors.red : null,
                  ),
                  onPressed: () =>
                      setState(() => _onlyFavorites = !_onlyFavorites),
                ),
                PopupMenuButton<int?>(
                  icon: Icon(Icons.filter_list,
                      color: _filterTagId != null
                          ? theme.colorScheme.primary
                          : null),
                  tooltip: 'Filter by Tag',
                  onSelected: (id) =>
                      setState(() => _filterTagId = id),
                  itemBuilder: (_) => [
                    const PopupMenuItem<int?>(
                        value: null, child: Text('All Tags')),
                    ...tp.tags.map((t) => PopupMenuItem<int?>(
                        value: t.id, child: Text(t.name))),
                  ],
                ),
              ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SearchBar(
              controller: _searchCtrl,
              hintText: 'Search albums…',
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => _query = v),
              trailing: [
                if (_query.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                    child: const Icon(Icons.clear),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: ap.loading
          ? const Center(child: CircularProgressIndicator())
          : filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_album_outlined,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        _query.isNotEmpty
                            ? 'No albums match your search.'
                            : 'No albums yet. Tap + to create one.',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final album = filtered[i];
                    final selected = _bulkSelected.contains(album.id!);
                    final tagNames = ap
                        .getTagIdsSync(album.id!)
                        .map((tid) => tp.getById(tid)?.name)
                        .whereType<String>()
                        .toList();

                    return _AlbumCard(
                      album: album,
                      tagNames: tagNames,
                      selected: selected,
                      bulkMode: _bulkMode,
                      onTap: () {
                        if (_bulkMode) {
                          setState(() {
                            selected
                                ? _bulkSelected.remove(album.id)
                                : _bulkSelected.add(album.id!);
                            if (_bulkSelected.isEmpty) _bulkMode = false;
                          });
                        } else {
                          context.push('/albums/${album.id}');
                        }
                      },
                      onLongPress: () {
                        setState(() {
                          _bulkMode = true;
                          _bulkSelected.add(album.id!);
                        });
                      },
                      onFavoriteToggle: () => ap.updateAlbum(
                        album.copyWith(isFavorite: !album.isFavorite),
                      ),
                      onDelete: () async {
                        final ok = await confirmDialog(context,
                            title: 'Delete Album',
                            message: 'Delete "${album.name}"?');
                        if (ok) ap.deleteAlbum(album.id!);
                      },
                      onEdit: () =>
                          context.push('/albums/${album.id}?edit=true'),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/albums/add'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final AlbumModel album;
  final List<String> tagNames;
  final bool selected;
  final bool bulkMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _AlbumCard({
    required this.album,
    required this.tagNames,
    required this.selected,
    required this.bulkMode,
    required this.onTap,
    required this.onLongPress,
    required this.onFavoriteToggle,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey(album.id),
      direction:
          bulkMode ? DismissDirection.none : DismissDirection.startToEnd,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: Colors.indigo.shade400,
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.colorScheme.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          onEdit();
          return false;
        }
        return showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete'),
            content: Text('Delete "${album.name}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          onTap: onTap,
          onLongPress: onLongPress,
          selected: selected,
          leading: CircleAvatar(
            backgroundColor: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.primaryContainer,
            child: Icon(
              selected ? Icons.check : Icons.photo_album,
              color: selected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onPrimaryContainer,
            ),
          ),
          title: Text(album.name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: tagNames.isEmpty
              ? null
              : Text(tagNames.join(' · '),
                  style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            icon: Icon(
              album.isFavorite
                  ? Icons.favorite
                  : Icons.favorite_border,
              color: album.isFavorite ? Colors.red : null,
            ),
            onPressed: onFavoriteToggle,
          ),
        ),
      ),
    );
  }
}

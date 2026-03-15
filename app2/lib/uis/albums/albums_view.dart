import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../managers/album_manager.dart';
import '../../managers/tag_manager.dart';
import '../../models/tag.dart';
import '../shared/app_drawer.dart';

class AlbumsView extends StatefulWidget {
  const AlbumsView({super.key});

  @override
  State<AlbumsView> createState() => _AlbumsViewState();
}

class _AlbumsViewState extends State<AlbumsView> {
  String _searchQuery = '';
  bool _onlyFavorites = false;
  int? _filterTagId;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AlbumManager>().loadAlbums();
      context.read<TagManager>().loadTags();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final albumManager = context.watch<AlbumManager>();
    final tagManager = context.watch<TagManager>();
    final theme = Theme.of(context);

    var filteredAlbums = albumManager.filterAlbums(
      query: _searchQuery,
      onlyFavorites: _onlyFavorites,
    );

    // Further filter by tag if selected
    // We'll do this asynchronously below, but for sync display we use a FutureBuilder approach later
    // For simplicity, tag filtering is done via a separate path

    return Scaffold(
      appBar: AppBar(
        title: const Text('Albums'),
        actions: [
          IconButton(
            icon: Icon(
              _onlyFavorites ? Icons.favorite : Icons.favorite_border,
              color: _onlyFavorites ? Colors.red : null,
            ),
            tooltip: 'Show Favorites Only',
            onPressed: () {
              setState(() {
                _onlyFavorites = !_onlyFavorites;
              });
            },
          ),
          PopupMenuButton<Tag?>(
            icon: Icon(
              Icons.filter_list,
              color: _filterTagId != null ? theme.colorScheme.primary : null,
            ),
            tooltip: 'Filter by Tag',
            onSelected: (tag) {
              setState(() {
                _filterTagId = tag?.id;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem<Tag?>(
                value: null,
                child: Text('All Tags'),
              ),
              ...tagManager.tags.map((tag) => PopupMenuItem<Tag?>(
                    value: tag,
                    child: Text(tag.name),
                  )),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search albums...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
        ),
      ),
      drawer: const AppDrawer(),
      body: _buildBody(albumManager, filteredAlbums, theme),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/albums/add'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(AlbumManager albumManager, List filteredAlbums, ThemeData theme) {
    if (albumManager.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // If tag filter active, use FutureBuilder
    if (_filterTagId != null) {
      return FutureBuilder(
        future: albumManager.getAlbumsByTag(_filterTagId!),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          var tagAlbums = snapshot.data!;
          // Apply search filter on top
          if (_searchQuery.isNotEmpty) {
            final lower = _searchQuery.toLowerCase();
            tagAlbums = tagAlbums
                .where((a) => a.name.toLowerCase().contains(lower))
                .toList();
          }
          if (_onlyFavorites) {
            tagAlbums = tagAlbums.where((a) => a.favorite).toList();
          }
          if (tagAlbums.isEmpty) {
            return const Center(child: Text('No albums found.'));
          }
          return _buildAlbumList(tagAlbums, albumManager, theme);
        },
      );
    }

    if (filteredAlbums.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_album_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty ? 'No albums match your search.' : 'No albums yet.',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            if (_searchQuery.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Tap + to create one!',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ],
          ],
        ),
      );
    }

    return _buildAlbumList(filteredAlbums, albumManager, theme);
  }

  Widget _buildAlbumList(List albums, AlbumManager albumManager, ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final imageCount = albumManager.getImageCount(album.id!);

        return Dismissible(
          key: ValueKey(album.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Album'),
                content: Text('Delete "${album.name}"? This cannot be undone.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
          },
          onDismissed: (_) => albumManager.deleteAlbum(album.id!),
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.photo_album,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(
                album.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '$imageCount images',
                style: TextStyle(color: Colors.grey[600]),
              ),
              trailing: IconButton(
                icon: Icon(
                  album.favorite ? Icons.favorite : Icons.favorite_border,
                  color: album.favorite ? Colors.red : Colors.grey,
                ),
                onPressed: () => albumManager.toggleFavorite(album.id!, !album.favorite),
              ),
              onTap: () => context.push('/albums/${album.id}'),
            ),
          ),
        );
      },
    );
  }
}

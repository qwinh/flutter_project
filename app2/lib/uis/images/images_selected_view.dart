import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../managers/image_selection_manager.dart';
import '../../managers/album_manager.dart';
import '../../models/album.dart';

class ImagesSelectedView extends StatefulWidget {
  const ImagesSelectedView({super.key});

  @override
  State<ImagesSelectedView> createState() => _ImagesSelectedViewState();
}

class _ImagesSelectedViewState extends State<ImagesSelectedView> {
  // Map assetId -> AssetEntity for resolving thumbnails
  final Map<String, AssetEntity> _assetCache = {};
  final Map<String, Uint8List?> _thumbnailCache = {};
  bool _isLoadingAssets = false;

  @override
  void initState() {
    super.initState();
    _resolveAssets();
  }

  Future<void> _resolveAssets() async {
    final selectionManager = context.read<ImageSelectionManager>();
    if (selectionManager.selectedUris.isEmpty) return;

    setState(() => _isLoadingAssets = true);

    // Load all assets and match by id
    for (final assetId in selectionManager.selectedUris) {
      if (!_assetCache.containsKey(assetId)) {
        final entity = await AssetEntity.fromId(assetId);
        if (entity != null) {
          _assetCache[assetId] = entity;
        }
      }
    }

    setState(() => _isLoadingAssets = false);
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All'),
        content: const Text('Remove all selected images?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<ImageSelectionManager>().clear();
      setState(() => _assetCache.clear());
    }
  }

  Future<void> _commitToAlbum() async {
    final selectionManager = context.read<ImageSelectionManager>();
    final albumManager = context.read<AlbumManager>();

    if (selectionManager.count == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No images selected.')));
      return;
    }

    // Show dialog: new album or existing album
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Commit to Album'),
        content: const Text('Create a new album or add to an existing one?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'existing'),
            child: const Text('Existing Album'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'new'),
            child: const Text('New Album'),
          ),
        ],
      ),
    );

    if (choice == 'new') {
      if (mounted) context.push('/albums/add');
    } else if (choice == 'existing') {
      // Load albums and let user pick
      await albumManager.loadAlbums();
      if (!mounted) return;
      final albums = albumManager.albums;

      if (albums.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No albums exist. Create one first.')),
          );
        }
        return;
      }

      final selectedAlbum = await showDialog<Album>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Choose Album'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: albums.length,
              itemBuilder: (context, index) {
                final album = albums[index];
                return ListTile(
                  leading: const Icon(Icons.photo_album),
                  title: Text(album.name),
                  onTap: () => Navigator.pop(context, album),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (selectedAlbum != null && mounted) {
        await albumManager.addImagesToAlbum(
          selectedAlbum.id!,
          selectionManager.selectedList,
        );
        await selectionManager.clear();
        setState(() => _assetCache.clear());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Images added to "${selectedAlbum.name}"!')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectionManager = context.watch<ImageSelectionManager>();
    final selectedIds = selectionManager.selectedUris.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Selected (${selectionManager.count})'),
        actions: [
          if (selectionManager.count > 0) ...[
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear All',
              onPressed: _clearAll,
            ),
          ],
        ],
      ),
      body: selectionManager.count == 0
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.checklist, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No images selected.',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/images'),
                    icon: const Icon(Icons.image_search),
                    label: const Text('Browse Images'),
                  ),
                ],
              ),
            )
          : _isLoadingAssets
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                int crossAxisCount = 3;
                if (constraints.maxWidth > 600) crossAxisCount = 4;
                if (constraints.maxWidth > 900) crossAxisCount = 5;

                return GridView.builder(
                  padding: const EdgeInsets.all(4),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: selectedIds.length,
                  itemBuilder: (context, index) {
                    final assetId = selectedIds[index];
                    final asset = _assetCache[assetId];

                    return _SelectedImageTile(
                      asset: asset,
                      onRemove: () => selectionManager.remove(assetId),
                      thumbnailCache: _thumbnailCache,
                    );
                  },
                );
              },
            ),
      bottomNavigationBar: selectionManager.count > 0
          ? Container(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: _commitToAlbum,
                icon: const Icon(Icons.save),
                label: const Text('Commit to Album'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _SelectedImageTile extends StatefulWidget {
  final AssetEntity? asset;
  final VoidCallback onRemove;
  final Map<String, Uint8List?> thumbnailCache;

  const _SelectedImageTile({
    required this.asset,
    required this.onRemove,
    required this.thumbnailCache,
  });

  @override
  State<_SelectedImageTile> createState() => _SelectedImageTileState();
}

class _SelectedImageTileState extends State<_SelectedImageTile> {
  Uint8List? _thumbnailBytes;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    if (widget.asset != null) {
      final cacheKey = widget.asset!.id;
      if (widget.thumbnailCache.containsKey(cacheKey)) {
        setState(() {
          _thumbnailBytes = widget.thumbnailCache[cacheKey];
        });
      } else {
        final bytes = await widget.asset!.thumbnailDataWithSize(
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
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _thumbnailBytes != null
              ? Image.memory(_thumbnailBytes!, fit: BoxFit.cover)
              : Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.image),
                ),
        ),
        // Remove button
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: widget.onRemove,
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red,
              ),
              child: const Icon(Icons.close, size: 18, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

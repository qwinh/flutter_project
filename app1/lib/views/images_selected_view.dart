// lib/views/images_selected_view.dart
// Shows the global selection pool. Allows reordering, removing individual
// images, clearing all, and committing to an album.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../providers/album_provider.dart';
import '../providers/selection_provider.dart';
import '../services/notification_service.dart';
import '../widgets/widgets.dart';

class ImagesSelectedView extends StatefulWidget {
  const ImagesSelectedView({super.key});

  @override
  State<ImagesSelectedView> createState() => _ImagesSelectedViewState();
}

class _ImagesSelectedViewState extends State<ImagesSelectedView> {
  final Map<String, AssetEntity?> _assetCache = {};
  final Map<String, Uint8List?> _thumbnailCache = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveAssets());
  }

  Future<void> _resolveAssets() async {
    final selProv = context.read<SelectionProvider>();
    if (selProv.assetIds.isEmpty) return;
    setState(() => _loading = true);
    for (final id in selProv.assetIds) {
      if (!_assetCache.containsKey(id)) {
        _assetCache[id] = await AssetEntity.fromId(id);
      }
    }
    setState(() => _loading = false);
  }

  Future<void> _commitToAlbum() async {
    final selProv = context.read<SelectionProvider>();
    final ap = context.read<AlbumProvider>();

    if (selProv.count == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nothing selected.')));
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Commit to Album'),
        content: const Text(
            'Create a new album or add to an existing one?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'existing'),
              child: const Text('Existing')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'new'),
              child: const Text('New Album')),
        ],
      ),
    );

    if (!mounted) return;

    if (choice == 'new') {
      context.push('/albums/add');
    } else if (choice == 'existing') {
      await ap.load();
      if (!mounted) return;

      if (ap.albums.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No albums. Create one first.')));
        return;
      }

      final picked = await showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Choose Album'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: ap.albums.length,
              itemBuilder: (_, i) {
                final a = ap.albums[i];
                return ListTile(
                  leading: const Icon(Icons.photo_album),
                  title: Text(a.name),
                  onTap: () => Navigator.pop(ctx, a.id),
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
          ],
        ),
      );

      if (picked != null && mounted) {
        await ap.addImagesToAlbum(picked, selProv.assetIds);
        await selProv.clearAll();
        setState(() => _assetCache.clear());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'Images added to "${ap.getById(picked)?.name}"!')));
        }
        await NotificationService.instance
            .show('Images added', 'Selection committed to album.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selProv = context.watch<SelectionProvider>();
    final ids = selProv.assetIds;

    return Scaffold(
      appBar: AppBar(
        title: Text('Selected (${selProv.count})'),
        actions: [
          if (selProv.count > 0)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear all',
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: 'Clear All',
                    message: 'Remove all ${selProv.count} selected images?',
                    confirmLabel: 'Clear');
                if (ok) {
                  await selProv.clearAll();
                  setState(() => _assetCache.clear());
                }
              },
            ),
        ],
      ),
      body: selProv.count == 0
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.checklist, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('No images selected.',
                      style: TextStyle(
                          fontSize: 16, color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => context.push('/images'),
                    icon: const Icon(Icons.image_search),
                    label: const Text('Browse Images'),
                  ),
                ],
              ),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : ReorderableListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: ids.length,
                  onReorder: (oldIdx, newIdx) {
                    final newIds = List<String>.from(ids);
                    if (oldIdx < newIdx) newIdx--;
                    final item = newIds.removeAt(oldIdx);
                    newIds.insert(newIdx, item);
                    selProv.reorder(newIds);
                  },
                  itemBuilder: (ctx, i) {
                    final id = ids[i];
                    final entity = _assetCache[id];
                    return _SelectedTile(
                      key: ValueKey(id),
                      entity: entity,
                      thumbnailCache: _thumbnailCache,
                      onRemove: () => selProv.deselect(id),
                    );
                  },
                ),
      bottomNavigationBar: selProv.count > 0
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _commitToAlbum,
                icon: const Icon(Icons.save),
                label: const Text('Commit to Album'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
            )
          : null,
    );
  }
}

class _SelectedTile extends StatefulWidget {
  final AssetEntity? entity;
  final Map<String, Uint8List?> thumbnailCache;
  final VoidCallback onRemove;

  const _SelectedTile({
    super.key,
    required this.entity,
    required this.thumbnailCache,
    required this.onRemove,
  });

  @override
  State<_SelectedTile> createState() => _SelectedTileState();
}

class _SelectedTileState extends State<_SelectedTile> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    final entity = widget.entity;
    if (entity == null) return;
    final cached = widget.thumbnailCache[entity.id];
    if (cached != null) {
      setState(() => _bytes = cached);
      return;
    }
    final bytes =
        await entity.thumbnailDataWithSize(const ThumbnailSize(200, 200));
    widget.thumbnailCache[entity.id] = bytes;
    if (mounted) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 56,
          height: 56,
          child: _bytes != null
              ? Image.memory(_bytes!, fit: BoxFit.cover)
              : Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.image),
                ),
        ),
      ),
      title: Text(widget.entity?.title ?? 'Unknown',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: widget.entity != null
          ? Text(
              '${widget.entity!.width}×${widget.entity!.height}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            color: Colors.red,
            onPressed: widget.onRemove,
          ),
          const Icon(Icons.drag_handle, color: Colors.grey),
        ],
      ),
    );
  }
}

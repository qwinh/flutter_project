import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../../managers/album_manager.dart';
import '../../managers/tag_manager.dart';
import '../../managers/image_selection_manager.dart';
import '../../models/album.dart';
import '../../models/tag.dart';
import '../../services/notification_service.dart';

class AlbumView extends StatefulWidget {
  final int albumId;
  const AlbumView({super.key, required this.albumId});

  @override
  State<AlbumView> createState() => _AlbumViewState();
}

class _AlbumViewState extends State<AlbumView> {
  Album? _album;
  List<String> _imageUris = [];
  final Map<String, AssetEntity?> _assetCache = {};
  List<Tag> _albumTags = [];
  bool _isLoading = true;
  bool _isEditing = false;

  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _assetCache.clear();
    final albumManager = context.read<AlbumManager>();
    final tagManager = context.read<TagManager>();

    _album = await albumManager.getAlbumById(widget.albumId);
    if (_album != null) {
      _imageUris = await albumManager.getAlbumImageUris(widget.albumId);
      await _resolveAssets(_imageUris);
      _albumTags = await tagManager.getTagsForAlbum(widget.albumId);
      _nameController.text = _album!.name;
      _descController.text = _album!.description;
    }
    setState(() => _isLoading = false);
  }

  Future<void> _resolveAssets(List<String> assetIds) async {
    for (final id in assetIds) {
      if (!_assetCache.containsKey(id)) {
        _assetCache[id] = await AssetEntity.fromId(id);
      }
    }
  }

  Future<void> _saveEdits() async {
    if (_album == null) return;
    final albumManager = context.read<AlbumManager>();
    final updated = _album!.copyWith(
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      dateLatestModify: DateTime.now(),
    );
    await albumManager.updateAlbum(updated);
    await NotificationService.instance.showNotification(
      title: 'Album Updated',
      body: '"${updated.name}" has been updated.',
    );
    setState(() {
      _album = updated;
      _isEditing = false;
    });
  }

  Future<void> _deleteAlbum() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Album'),
        content: Text('Delete "${_album?.name}"? This cannot be undone.'),
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
    if (confirmed == true && mounted) {
      await context.read<AlbumManager>().deleteAlbum(widget.albumId);
      if (mounted) context.pop();
    }
  }

  Future<void> _manageAlbumTags() async {
    final tagManager = context.read<TagManager>();
    await tagManager.loadTags();
    if (!mounted) return;

    final allTags = tagManager.tags;
    final selectedIds = _albumTags.map((t) => t.id!).toSet();

    final result = await showDialog<Set<int>>(
      context: context,
      builder: (context) {
        final tempSelected = Set<int>.from(selectedIds);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Manage Tags'),
              content: SizedBox(
                width: double.maxFinite,
                child: allTags.isEmpty
                    ? const Text('No tags created yet. Create tags first.')
                    : ListView(
                        shrinkWrap: true,
                        children: allTags.map((tag) {
                          return CheckboxListTile(
                            title: Text(tag.name),
                            subtitle: tag.description.isNotEmpty
                                ? Text(tag.description)
                                : null,
                            value: tempSelected.contains(tag.id),
                            onChanged: (checked) {
                              setDialogState(() {
                                if (checked == true) {
                                  tempSelected.add(tag.id!);
                                } else {
                                  tempSelected.remove(tag.id!);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, tempSelected),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      await tagManager.setTagsForAlbum(widget.albumId, result.toList());
      _albumTags = await tagManager.getTagsForAlbum(widget.albumId);
      setState(() {});
    }
  }

  Future<void> _commitSelectedImages() async {
    final selectionManager = context.read<ImageSelectionManager>();
    final albumManager = context.read<AlbumManager>();

    if (selectionManager.count == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No images selected.')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Selected Images'),
        content: Text(
          'Add ${selectionManager.count} selected image(s) to "${_album?.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await albumManager.addImagesToAlbum(
        widget.albumId,
        selectionManager.selectedList,
      );
      await selectionManager.clear();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Images added to album!')));
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectionManager = context.watch<ImageSelectionManager>();
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Album')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_album == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Album')),
        body: const Center(child: Text('Album not found.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: _isEditing ? const Text('Edit Album') : Text(_album!.name),
        actions: [
          if (!_isEditing) ...[
            if (selectionManager.count > 0)
              IconButton(
                icon: Badge(
                  label: Text('${selectionManager.count}'),
                  child: const Icon(Icons.add_photo_alternate),
                ),
                tooltip: 'Add selected images',
                onPressed: _commitSelectedImages,
              ),
            IconButton(
              icon: const Icon(Icons.label),
              tooltip: 'Manage Tags',
              onPressed: _manageAlbumTags,
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit',
              onPressed: () => setState(() => _isEditing = true),
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'Delete Album',
              onPressed: _deleteAlbum,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Save',
              onPressed: _saveEdits,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onPressed: () => setState(() {
                _isEditing = false;
                _nameController.text = _album!.name;
                _descController.text = _album!.description;
              }),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Edit fields or info header
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Album Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_album!.description.isNotEmpty)
                    Text(
                      _album!.description,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      ..._albumTags.map(
                        (tag) => Chip(
                          label: Text(
                            tag.name,
                            style: const TextStyle(fontSize: 12),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_imageUris.length} images',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          // Image grid
          Expanded(
            child: _imageUris.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.image_not_supported,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No images in this album.',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () => context.push('/images'),
                          icon: const Icon(Icons.add_photo_alternate),
                          label: const Text('Browse & Select Images'),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                    itemCount: _imageUris.length,
                    itemBuilder: (context, index) {
                      final uri = _imageUris[index];
                      return GestureDetector(
                        onTap: () {
                          // Create a list of resolved AssetEntity objects in the same order
                          // as the stored IDs so we can open the full-screen viewer.
                          final assets = _imageUris
                              .map((id) => _assetCache[id])
                              .whereType<AssetEntity>()
                              .toList();
                          final initialIndex = assets.indexWhere(
                            (a) => a.id == uri,
                          );
                          if (initialIndex == -1) return;

                          context.push(
                            '/images/view',
                            extra: {
                              'assets': assets,
                              'initialIndex': initialIndex,
                            },
                          );
                        },
                        onLongPress: () async {
                          final remove = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Remove Image'),
                              content: const Text(
                                'Remove this image from the album?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text(
                                    'Remove',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (remove == true) {
                            await context
                                .read<AlbumManager>()
                                .removeImageFromAlbum(widget.albumId, uri);
                            await _loadData();
                          }
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _buildAssetThumbnail(uri, theme),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetThumbnail(String assetId, ThemeData theme) {
    final asset = _assetCache[assetId];
    if (asset == null) {
      return Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.broken_image),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) {
          return Image.memory(bytes, fit: BoxFit.cover);
        }
        return Container(
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.image),
        );
      },
    );
  }
}

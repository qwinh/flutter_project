// lib/views/album_view.dart
// Shows album details: name, description, favorite, tags, and a grid of images.
// Supports inline editing. Shows "add selected images" badge button when
// the global selection pool has images.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/album_provider.dart';
import '../providers/selection_provider.dart';
import '../providers/tag_provider.dart';
import '../services/notification_service.dart';
import '../views/images_view.dart';
import '../widgets/widgets.dart';

class AlbumView extends StatefulWidget {
  final int albumId;
  final bool startInEditMode;

  const AlbumView({
    super.key,
    required this.albumId,
    this.startInEditMode = false,
  });

  @override
  State<AlbumView> createState() => _AlbumViewState();
}

class _AlbumViewState extends State<AlbumView> {
  bool _editMode = false;

  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  bool _isFavorite = false;

  // Cache: assetId → AssetEntity? so we don't re-resolve on every rebuild.
  final Map<String, AssetEntity?> _assetCache = {};
  List<String> _assetIds = [];
  List<int> _tagIds = [];
  bool _loading = true;

  final Set<String> _selectedAssetIds = {};
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _editMode = widget.startInEditMode;
    _nameCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ap = context.read<AlbumProvider>();
    final album = ap.getById(widget.albumId);
    if (album == null) return;

    _nameCtrl.text = album.name;
    _descCtrl.text = album.description;
    _isFavorite = album.isFavorite;

    final assetIds = await ap.getAssetIds(widget.albumId);
    final tagIds = await ap.getTagIds(widget.albumId);

    // Resolve only newly seen IDs (cache the rest)
    for (final id in assetIds) {
      if (!_assetCache.containsKey(id)) {
        _assetCache[id] = await AssetEntity.fromId(id);
      }
    }

    if (mounted) {
      setState(() {
        _assetIds = assetIds;
        _tagIds = tagIds;
        _loading = false;
      });
    }
  }

  Future<void> _saveEdits() async {
    final ap = context.read<AlbumProvider>();
    final album = ap.getById(widget.albumId);
    if (album == null) return;

    await ap.updateAlbum(
      album.copyWith(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        isFavorite: _isFavorite,
      ),
      tagIds: _tagIds,
    );

    if (mounted) {
      setState(() => _editMode = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Album updated')));
    }
  }

  Future<void> _pickTagsDialog() async {
    final tp = context.read<TagProvider>();
    final result = await showDialog<List<int>>(
      context: context,
      builder: (_) => TagPickerDialog(
        allTags: tp.tags.map((t) => (id: t.id!, name: t.name)).toList(),
        initialSelected: _tagIds.toSet(),
      ),
    );
    if (result != null) setState(() => _tagIds = result);
  }

  Future<void> _commitSelectedImages() async {
    final selProv = context.read<SelectionProvider>();
    final ap = context.read<AlbumProvider>();

    if (selProv.count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No images selected.')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final album = ap.getById(widget.albumId);
        return AlertDialog(
          title: const Text('Add Selected Images'),
          content: Text(
              'Add ${selProv.count} selected image(s) to "${album?.name}"?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add')),
          ],
        );
      },
    );

    if (confirmed == true) {
      await ap.addImagesToAlbum(widget.albumId, selProv.assetIds);
      await selProv.clearAll();
      // Reload to show the newly added images
      setState(() {
        _loading = true;
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Images added to album!')));
      }
    }
  }

  Future<void> _removeSelectedImages() async {
    final ap = context.read<AlbumProvider>();
    for (final aid in _selectedAssetIds) {
      await ap.removeImageFromAlbum(widget.albumId, aid);
    }
    setState(() {
      _assetIds =
          _assetIds.where((id) => !_selectedAssetIds.contains(id)).toList();
      _selectedAssetIds.clear();
      _selectionMode = false;
    });
    await NotificationService.instance
        .show('Images removed', 'Removed from album.');
  }

  @override
  Widget build(BuildContext context) {
    final ap = context.watch<AlbumProvider>();
    final tp = context.watch<TagProvider>();
    final selProv = context.watch<SelectionProvider>();
    final album = ap.getById(widget.albumId);

    if (album == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Album')),
        body: const Center(child: Text('Album not found.')),
      );
    }

    final tagNames = _tagIds
        .map((id) => tp.getById(id)?.name)
        .whereType<String>()
        .toList();

    // Build list of resolved entities in order
    final entities = _assetIds
        .map((id) => _assetCache[id])
        .whereType<AssetEntity>()
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: _editMode ? const Text('Edit Album') : Text(album.name),
        actions: _selectionMode
            ? [
                IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: _removeSelectedImages),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                          _selectionMode = false;
                          _selectedAssetIds.clear();
                        })),
              ]
            : [
                // Show badge button when global selection pool is non-empty
                if (!_editMode && selProv.count > 0)
                  IconButton(
                    icon: Badge(
                      label: Text('${selProv.count}'),
                      child: const Icon(Icons.add_photo_alternate),
                    ),
                    tooltip: 'Add selected images',
                    onPressed: _commitSelectedImages,
                  ),
                if (_editMode)
                  IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: _saveEdits,
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => setState(() => _editMode = true),
                  ),
              ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _editMode
                        ? _EditForm(
                            nameCtrl: _nameCtrl,
                            descCtrl: _descCtrl,
                            isFavorite: _isFavorite,
                            tagNames: tagNames,
                            onFavoriteToggle: (v) =>
                                setState(() => _isFavorite = v),
                            onPickTags: _pickTagsDialog,
                          )
                        : _ReadOnlyInfo(
                            album: album,
                            tagNames: tagNames,
                          ),
                  ),
                ),
                if (entities.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.all(8),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) {
                          final e = entities[i];
                          final selected =
                              _selectedAssetIds.contains(e.id);
                          return AssetThumb(
                            asset: e,
                            selected: selected,
                            onTap: () {
                              if (_selectionMode) {
                                setState(() {
                                  selected
                                      ? _selectedAssetIds.remove(e.id)
                                      : _selectedAssetIds.add(e.id);
                                });
                              } else {
                                context
                                    .read<FilteredListNotifier>()
                                    .setList(entities);
                                context.push('/images/view/$i');
                              }
                            },
                            onLongPress: () => setState(() {
                              _selectionMode = true;
                              _selectedAssetIds.add(e.id);
                            }),
                          );
                        },
                        childCount: entities.length,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 120,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                    ),
                  )
                else
                  const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.image_not_supported,
                                size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('No images in this album yet.'),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ReadOnlyInfo extends StatelessWidget {
  final AlbumModel album;
  final List<String> tagNames;

  const _ReadOnlyInfo({required this.album, required this.tagNames});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(album.name,
                  style: theme.textTheme.headlineSmall),
            ),
            if (album.isFavorite)
              const Icon(Icons.favorite, color: Colors.pink),
          ],
        ),
        if (album.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(album.description,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 6),
        Text(
          'Modified ${_formatDate(album.dateLatestModify)}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        if (tagNames.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: tagNames.map((n) => Chip(label: Text(n))).toList(),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _EditForm extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final bool isFavorite;
  final List<String> tagNames;
  final ValueChanged<bool> onFavoriteToggle;
  final VoidCallback onPickTags;

  const _EditForm({
    required this.nameCtrl,
    required this.descCtrl,
    required this.isFavorite,
    required this.tagNames,
    required this.onFavoriteToggle,
    required this.onPickTags,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: descCtrl,
          decoration: const InputDecoration(labelText: 'Description'),
          maxLines: 2,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Favorite'),
          value: isFavorite,
          onChanged: onFavoriteToggle,
        ),
        Row(
          children: [
            const Text('Tags: '),
            Expanded(
              child: tagNames.isEmpty
                  ? const Text('None',
                      style: TextStyle(color: Colors.grey))
                  : Wrap(
                      spacing: 4,
                      children: tagNames
                          .map((n) => Chip(label: Text(n)))
                          .toList(),
                    ),
            ),
            TextButton.icon(
              onPressed: onPickTags,
              icon: const Icon(Icons.label),
              label: const Text('Edit'),
            ),
          ],
        ),
      ],
    );
  }
}

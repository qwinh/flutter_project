import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../managers/album_manager.dart';
import '../../managers/tag_manager.dart';
import '../../managers/image_selection_manager.dart';
import '../../models/album.dart';
import '../../services/notification_service.dart';

class AlbumAdd extends StatefulWidget {
  const AlbumAdd({super.key});

  @override
  State<AlbumAdd> createState() => _AlbumAddState();
}

class _AlbumAddState extends State<AlbumAdd> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final Set<int> _selectedTagIds = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TagManager>().loadTags();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final albumManager = context.read<AlbumManager>();
    final tagManager = context.read<TagManager>();
    final selectionManager = context.read<ImageSelectionManager>();

    final now = DateTime.now();
    final album = Album(
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      dateCreated: now,
      dateLatestModify: now,
    );

    final albumId = await albumManager.addAlbum(album);

    // Set tags
    if (_selectedTagIds.isNotEmpty) {
      await tagManager.setTagsForAlbum(albumId, _selectedTagIds.toList());
    }

    // Commit selected images
    if (selectionManager.count > 0) {
      await albumManager.addImagesToAlbum(albumId, selectionManager.selectedList);
      await selectionManager.clear();
    }

    await NotificationService.instance.showNotification(
      title: 'Album Created',
      body: '"${album.name}" has been created with ${selectionManager.count} images.',
    );

    if (mounted) {
      context.pop();
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
    final tagManager = context.watch<TagManager>();
    final selectionManager = context.watch<ImageSelectionManager>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Album'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Album Name *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.photo_album),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter an album name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            // Tags selection
            Text('Tags', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (tagManager.tags.isEmpty)
              Text(
                'No tags available. Create tags first.',
                style: TextStyle(color: Colors.grey[500]),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: tagManager.tags.map((tag) {
                  final isSelected = _selectedTagIds.contains(tag.id);
                  return FilterChip(
                    label: Text(tag.name),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedTagIds.add(tag.id!);
                        } else {
                          _selectedTagIds.remove(tag.id!);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            const SizedBox(height: 24),
            // Selected images info
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: Icon(
                  Icons.photo_library,
                  color: selectionManager.count > 0
                      ? theme.colorScheme.primary
                      : Colors.grey,
                ),
                title: Text(
                  selectionManager.count > 0
                      ? '${selectionManager.count} images selected'
                      : 'No images selected',
                ),
                subtitle: const Text('These will be added to the album'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selectionManager.count > 0)
                      TextButton(
                        onPressed: () => context.push('/images/selected'),
                        child: const Text('View'),
                      ),
                    IconButton(
                      icon: const Icon(Icons.add_photo_alternate),
                      onPressed: () => context.push('/images'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create Album', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

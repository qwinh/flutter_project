import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../managers/tag_manager.dart';
import '../../managers/album_manager.dart';
import '../../models/tag.dart';
import '../../models/album.dart';

class TagView extends StatefulWidget {
  final int tagId;
  const TagView({super.key, required this.tagId});

  @override
  State<TagView> createState() => _TagViewState();
}

class _TagViewState extends State<TagView> {
  Tag? _tag;
  List<Album> _tagAlbums = [];
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
    final tagManager = context.read<TagManager>();
    final albumManager = context.read<AlbumManager>();

    _tag = await tagManager.getTagById(widget.tagId);
    if (_tag != null) {
      _nameController.text = _tag!.name;
      _descController.text = _tag!.description;
      _tagAlbums = await albumManager.getAlbumsByTag(widget.tagId);
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveEdits() async {
    if (_tag == null) return;
    final tagManager = context.read<TagManager>();
    final updated = _tag!.copyWith(
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
    );
    await tagManager.updateTag(updated);
    setState(() {
      _tag = updated;
      _isEditing = false;
    });
  }

  Future<void> _deleteTag() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tag'),
        content: Text('Delete "${_tag?.name}"?'),
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
      await context.read<TagManager>().deleteTag(widget.tagId);
      if (mounted) context.pop();
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
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tag')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_tag == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tag')),
        body: const Center(child: Text('Tag not found.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: _isEditing ? const Text('Edit Tag') : Text(_tag!.name),
        actions: [
          if (!_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteTag,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _saveEdits,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _isEditing = false;
                _nameController.text = _tag!.name;
                _descController.text = _tag!.description;
              }),
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isEditing) ...[
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tag Name',
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
          ] else ...[
            if (_tag!.description.isNotEmpty) ...[
              Text(
                _tag!.description,
                style: TextStyle(fontSize: 15, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
            ],
          ],
          const SizedBox(height: 16),
          Text('Albums with this tag', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_tagAlbums.isEmpty)
            Text(
              'No albums use this tag yet.',
              style: TextStyle(color: Colors.grey[500]),
            )
          else
            ...(_tagAlbums.map((album) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.photo_album, color: theme.colorScheme.onPrimaryContainer),
                    ),
                    title: Text(album.name),
                    onTap: () => context.push('/albums/${album.id}'),
                  ),
                ))),
        ],
      ),
    );
  }
}

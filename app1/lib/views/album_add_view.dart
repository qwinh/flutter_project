// Create a new album. If navigated from ImagesSelectedView, the selected
// images pool is pre-filled. Commits create the album and clear the pool.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/album_provider.dart';
import '../providers/image_provider.dart' as ip;
import '../providers/selection_provider.dart';
import '../services/notification_service.dart';
import '../widgets/widgets.dart';

class AlbumAddView extends StatefulWidget {
  const AlbumAddView({super.key});

  @override
  State<AlbumAddView> createState() => _AlbumAddViewState();
}

class _AlbumAddViewState extends State<AlbumAddView> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isFavorite = false;
  List<int> _tagIds = [];

  List<AssetEntity> _previewEntities = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFromSelection());
  }

  Future<void> _syncFromSelection() async {
    final sp = context.read<SelectionProvider>();
    await sp.resolveEntities();
    if (mounted) {
      setState(() => _previewEntities = List.of(sp.entities));
    }
  }

  void _removeImage(int index) {
    final entity = _previewEntities[index];
    context.read<SelectionProvider>().removeOne(entity.id);
    setState(() => _previewEntities.removeAt(index));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Album name is required.')));
      return;
    }

    setState(() => _submitting = true);

    final ap = context.read<AlbumProvider>();
    final sp = context.read<SelectionProvider>();
    final assetIds = _previewEntities.map((e) => e.id).toList();

    await ap.addAlbum(
      AlbumModel(
          name: name,
          description: _descCtrl.text.trim(),
          isFavorite: _isFavorite),
      tagIds: _tagIds,
      assetIds: assetIds,
    );

    await sp.clearAll();
    await NotificationService.instance.show('Album created', '"$name" created.');

    if (mounted) context.pop();
  }

  // Shared via tag_picker.dart — no longer duplicated with album_view.
  Future<void> _pickTagsDialog() async {
    final result =
        await showTagPickerDialog(context, currentTagIds: _tagIds);
    if (result != null) setState(() => _tagIds = result);
  }

  @override
  Widget build(BuildContext context) {
    // resolveTagNames also shared via tag_picker.dart.
    final tagNames = resolveTagNames(context, _tagIds);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Album'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: const Text('Create'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Form fields ──────────────────────────────────────────────────
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Album name *',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mark as favorite'),
            value: _isFavorite,
            onChanged: (v) => setState(() => _isFavorite = v),
          ),

          // ── Tags ─────────────────────────────────────────────────────────
          Row(
            children: [
              const Text('Tags:',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              Expanded(
                child: tagNames.isEmpty
                    ? const Text('None',
                        style: TextStyle(color: Colors.grey))
                    : Wrap(
                        spacing: 4,
                        children:
                            tagNames.map((n) => Chip(label: Text(n))).toList(),
                      ),
              ),
              TextButton.icon(
                onPressed: _pickTagsDialog,
                icon: const Icon(Icons.label_outline),
                label: const Text('Edit'),
              ),
            ],
          ),

          const Divider(height: 32),

          // ── Image preview grid ───────────────────────────────────────────
          Row(
            children: [
              Text(
                'Images (${_previewEntities.length})',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  await showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => _ImagePickerSheet(
                      alreadySelected:
                          _previewEntities.map((e) => e.id).toSet(),
                      onConfirm: (picked) async {
                        final sp = context.read<SelectionProvider>();
                        await sp.addMultiple(
                            picked.map((e) => e.id).toSet());
                      },
                    ),
                  );
                  await _syncFromSelection();
                },
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Add more'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_previewEntities.isEmpty)
            Container(
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(
                    color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('No images selected',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _previewEntities.length,
              gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 100,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemBuilder: (_, i) {
                final e = _previewEntities[i];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    AssetThumb(asset: e),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => _removeImage(i),
                        child: const CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close,
                              size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

// ── Inline image picker sheet ─────────────────────────────────────────────────

class _ImagePickerSheet extends StatefulWidget {
  final Set<String> alreadySelected;
  final Future<void> Function(List<AssetEntity> picked) onConfirm;

  const _ImagePickerSheet({
    required this.alreadySelected,
    required this.onConfirm,
  });

  @override
  State<_ImagePickerSheet> createState() => _ImagePickerSheetState();
}

class _ImagePickerSheetState extends State<_ImagePickerSheet> {
  final Set<String> _picked = {};
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _picked.addAll(widget.alreadySelected);
  }

  Future<void> _confirm(List<AssetEntity> all) async {
    setState(() => _confirming = true);
    final newOnes = all
        .where((e) =>
            _picked.contains(e.id) &&
            !widget.alreadySelected.contains(e.id))
        .toList();
    await widget.onConfirm(newOnes);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final imgProv = context.watch<ip.DeviceImageProvider>();
    final assets = imgProv.all;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) {
        return Column(
          children: [
            // Shared SheetHandle — no longer an inline duplicate.
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Select photos',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _confirming ? null : () => _confirm(assets),
                    child: Text(
                      _picked.isEmpty
                          ? 'Done'
                          : 'Add ${(_picked.difference(widget.alreadySelected)).length}',
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: imgProv.loading
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(2),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 2,
                        mainAxisSpacing: 2,
                      ),
                      itemCount: assets.length,
                      itemBuilder: (_, i) {
                        final e = assets[i];
                        final selected = _picked.contains(e.id);
                        return GestureDetector(
                          onTap: () => setState(() {
                            selected
                                ? _picked.remove(e.id)
                                : _picked.add(e.id);
                          }),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AssetEntityImage(
                                e,
                                isOriginal: false,
                                fit: BoxFit.cover,
                              ),
                              if (selected)
                                Container(
                                  color: Colors.blue.withOpacity(0.4),
                                  alignment: Alignment.topRight,
                                  padding: const EdgeInsets.all(4),
                                  child: const Icon(Icons.check_circle,
                                      color: Colors.white, size: 20),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

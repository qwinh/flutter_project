// lib/widgets/widgets.dart
// Reusable small widgets.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

// ── Animated asset thumbnail ──────────────────────────────────────────────────
//
// Shows a thumbnail from either a pre-fetched [bytes] cache or loads via
// photo_manager. When [selected] the tile scales down 10 %, shows a blue
// tint, and animates a checkmark badge.

class AssetThumb extends StatefulWidget {
  final AssetEntity asset;
  final double size;
  final bool selected;
  // Optional: if caller already has the bytes cached, pass them in to skip
  // the async load entirely.
  final Uint8List? cachedBytes;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AssetThumb({
    super.key,
    required this.asset,
    this.size = 80,
    this.selected = false,
    this.cachedBytes,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<AssetThumb> createState() => _AssetThumbState();
}

class _AssetThumbState extends State<AssetThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    if (widget.cachedBytes != null) {
      _bytes = widget.cachedBytes;
    } else {
      _loadThumbnail();
    }
  }

  @override
  void didUpdateWidget(AssetThumb old) {
    super.didUpdateWidget(old);
    if (widget.cachedBytes != null && widget.cachedBytes != old.cachedBytes) {
      setState(() => _bytes = widget.cachedBytes);
    }
  }

  Future<void> _loadThumbnail() async {
    final bytes = await widget.asset.thumbnailDataWithSize(
      ThumbnailSize.square(widget.size.toInt()),
    );
    if (mounted) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        transformAlignment: Alignment.center,
        transform: widget.selected
            ? (Matrix4.identity()..scale(0.90))
            : Matrix4.identity(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail image
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: _bytes != null
                  ? Image.memory(_bytes!, fit: BoxFit.cover)
                  : Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.image, color: Colors.grey),
                    ),
            ),
            // Blue tint + border when selected
            if (widget.selected)
              AnimatedOpacity(
                opacity: 1.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.blue.withValues(alpha: 0.30),
                    border: Border.all(color: Colors.blue, width: 2.5),
                  ),
                ),
              ),
            // Checkmark circle badge
            Positioned(
              top: 4,
              right: 4,
              child: AnimatedScale(
                scale: widget.selected ? 1.0 : 0.8,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.selected
                        ? Colors.blue
                        : Colors.black.withValues(alpha: 0.35),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: widget.selected
                      ? const Icon(Icons.check,
                          size: 16, color: Colors.white)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Confirm dialog ─────────────────────────────────────────────────────────────

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

// ── Tag chip picker dialog ─────────────────────────────────────────────────────

class TagPickerDialog extends StatefulWidget {
  final List<({int id, String name})> allTags;
  final Set<int> initialSelected;

  const TagPickerDialog({
    super.key,
    required this.allTags,
    required this.initialSelected,
  });

  @override
  State<TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends State<TagPickerDialog> {
  late Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialSelected);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Tags'),
      content: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: widget.allTags.map((tag) {
            final isSelected = _selected.contains(tag.id);
            return FilterChip(
              label: Text(tag.name),
              selected: isSelected,
              onSelected: (v) {
                setState(() {
                  v ? _selected.add(tag.id) : _selected.remove(tag.id);
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
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

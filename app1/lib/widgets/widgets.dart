// lib/widgets/widgets.dart
// Reusable small widgets.
// Re-exports so callers can import just 'widgets/widgets.dart' for everything.
export 'description_subtitle.dart';
export 'filterable_list.dart';
export 'sheet_handle.dart';
export 'tag_picker.dart';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

// ── Asset thumbnail ───────────────────────────────────────────────────────────

class AssetThumb extends StatelessWidget {
  final AssetEntity asset;
  final double size;
  final bool selected;
  // When non-null and selected, shows this 1-based position number
  // in the selection badge instead of a plain checkmark.
  final int? selectionIndex;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AssetThumb({
    super.key,
    required this.asset,
    this.size = 80,
    this.selected = false,
    this.selectionIndex,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AssetEntityImage(
            asset,
            isOriginal: false,
            thumbnailSize: ThumbnailSize.square(size.toInt()),
            fit: BoxFit.cover,
          ),
          if (selected) ...[
            Container(color: Colors.blue.withOpacity(0.35)),
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
                alignment: Alignment.center,
                child: Text(
                  selectionIndex != null ? '$selectionIndex' : '✓',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Confirm dialog ────────────────────────────────────────────────────────────

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

// ── Tag chip picker dialog ────────────────────────────────────────────────────

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

// ── Shared filter list widgets ────────────────────────────────────────────────

/// Scrollable constrained list with a visible scrollbar track.
class FilterScrollList extends StatefulWidget {
  final int itemCount;
  final double maxHeight;
  final IndexedWidgetBuilder itemBuilder;
  const FilterScrollList({
    super.key,
    required this.itemCount,
    required this.maxHeight,
    required this.itemBuilder,
  });
  @override
  State<FilterScrollList> createState() => _FilterScrollListState();
}

class _FilterScrollListState extends State<FilterScrollList> {
  final _ctrl = ScrollController();
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: cs.surfaceContainerHighest.withOpacity(0.45),
          child: RawScrollbar(
            controller: _ctrl,
            thumbVisibility: true,
            trackVisibility: true,
            thickness: 6,
            minThumbLength: 40,
            radius: const Radius.circular(3),
            thumbColor: cs.onSurfaceVariant.withOpacity(0.35),
            trackColor: cs.surfaceContainerHighest.withOpacity(0.2),
            child: ListView.separated(
              controller: _ctrl,
              padding: const EdgeInsets.fromLTRB(0, 4, 14, 4),
              itemCount: widget.itemCount,
              separatorBuilder: (_, __) => Divider(
                height: 1, indent: 14, endIndent: 0,
                color: cs.outlineVariant.withOpacity(0.3),
              ),
              itemBuilder: widget.itemBuilder,
            ),
          ),
        ),
      ),
    );
  }
}

class FilterListRow extends StatelessWidget {
  final String label;
  final bool included;
  final bool excluded;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const FilterListRow({
    super.key,
    required this.label,
    required this.included,
    required this.excluded,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Expanded(child: Text(label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: included ? cs.primary : excluded ? cs.error : null,
              fontWeight: (included || excluded) ? FontWeight.w500 : null,
            ))),
          if (included)
            Icon(Icons.check_circle_rounded, size: 16, color: cs.primary)
          else if (excluded)
            Icon(Icons.remove_circle_rounded, size: 16, color: cs.error)
          else
            const SizedBox(width: 16),
        ]),
      ),
    );
  }
}

class FilterPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;
  final bool bold;
  const FilterPill({
    super.key,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: textColor,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        letterSpacing: 0.4,
      )),
    ),
  );
}

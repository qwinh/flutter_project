// lib/widgets/filterable_list.dart
// Generic include/exclude filter header + scrollable list.
//
// Replaces the duplicated _TagFilterBar (albums_view) and the album-filter
// section inside _FilterSheet (images_view).  Both had identical tap/hold/
// include/exclude/AND-or-ANY/A-Z-sort logic wired to FilterScrollList +
// FilterListRow + FilterPill — only the item type differed.

import 'package:flutter/material.dart';
import 'widgets.dart';

class FilterableListView<T> extends StatefulWidget {
  /// All items to display.
  final List<T> items;

  /// Extracts the display label from an item.
  final String Function(T) labelOf;

  /// Currently included items.
  final Set<T> included;

  /// Currently excluded items.
  final Set<T> excluded;

  /// AND vs ANY mode.
  final bool andMode;

  /// Maximum height of the scrollable list area.
  final double maxHeight;

  /// Optional header label (e.g. 'Tags', 'Albums').
  final String? header;

  final ValueChanged<Set<T>> onIncludedChanged;
  final ValueChanged<Set<T>> onExcludedChanged;
  final ValueChanged<bool> onModeChanged;

  const FilterableListView({
    super.key,
    required this.items,
    required this.labelOf,
    required this.included,
    required this.excluded,
    required this.andMode,
    required this.onIncludedChanged,
    required this.onExcludedChanged,
    required this.onModeChanged,
    this.maxHeight = 180,
    this.header,
  });

  @override
  State<FilterableListView<T>> createState() => _FilterableListViewState<T>();
}

class _FilterableListViewState<T> extends State<FilterableListView<T>> {
  bool _sortActive = false;

  void _tap(T item) {
    if (widget.included.contains(item)) {
      widget.onIncludedChanged({...widget.included}..remove(item));
    } else if (widget.excluded.contains(item)) {
      widget.onExcludedChanged({...widget.excluded}..remove(item));
    } else {
      widget.onIncludedChanged({...widget.included, item});
      widget.onExcludedChanged({...widget.excluded}..remove(item));
    }
  }

  void _hold(T item) {
    widget.onExcludedChanged({...widget.excluded, item});
    widget.onIncludedChanged({...widget.included}..remove(item));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final hasFilter = widget.included.isNotEmpty || widget.excluded.isNotEmpty;

    final base = [...widget.items]
      ..sort((a, b) => widget.labelOf(a).compareTo(widget.labelOf(b)));
    final sorted = _sortActive
        ? [
            ...base.where((t) => widget.included.contains(t) || widget.excluded.contains(t)),
            ...base.where((t) => !widget.included.contains(t) && !widget.excluded.contains(t)),
          ]
        : base;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          if (widget.header != null)
            Text(widget.header!,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
          if (widget.header != null) const SizedBox(width: 6),
          FilterPill(
            label: widget.andMode ? 'ALL' : 'ANY',
            color: cs.secondaryContainer,
            textColor: cs.onSecondaryContainer,
            bold: true,
            onTap: () => widget.onModeChanged(!widget.andMode),
          ),
          const SizedBox(width: 6),
          FilterPill(
            label: _sortActive ? '● A-Z' : 'A-Z',
            color: _sortActive
                ? cs.tertiaryContainer
                : cs.surfaceContainerHighest.withOpacity(0.5),
            textColor: _sortActive ? cs.onTertiaryContainer : cs.onSurfaceVariant,
            onTap: () => setState(() => _sortActive = !_sortActive),
          ),
          const Spacer(),
          Text('tap · hold exclude',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant.withOpacity(0.5))),
          if (hasFilter) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                widget.onIncludedChanged({});
                widget.onExcludedChanged({});
              },
              child: Icon(Icons.close,
                  size: 15, color: cs.onSurfaceVariant.withOpacity(0.7)),
            ),
          ],
        ]),
        const SizedBox(height: 5),
        FilterScrollList(
          maxHeight: widget.maxHeight,
          itemCount: sorted.length,
          itemBuilder: (_, i) {
            final item = sorted[i];
            return FilterListRow(
              label: widget.labelOf(item),
              included: widget.included.contains(item),
              excluded: widget.excluded.contains(item),
              onTap: () => _tap(item),
              onLongPress: () => _hold(item),
            );
          },
        ),
      ],
    );
  }
}

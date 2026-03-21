// lib/widgets/tag_picker.dart
// Shared helper that shows the TagPickerDialog and returns the chosen
// tag IDs.  Replaces the copy-pasted _pickTagsDialog in album_view.dart
// and album_add_view.dart.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/tag_provider.dart';
import 'widgets.dart';

/// Shows a [TagPickerDialog] and returns the user's selected tag IDs,
/// or null if they cancelled.
Future<List<int>?> showTagPickerDialog(
  BuildContext context, {
  required List<int> currentTagIds,
}) {
  final tp = context.read<TagProvider>();
  return showDialog<List<int>>(
    context: context,
    builder: (_) => TagPickerDialog(
      allTags: tp.tags.map((t) => (id: t.id!, name: t.name)).toList(),
      initialSelected: currentTagIds.toSet(),
    ),
  );
}

/// Derives display names for a list of tag IDs using the [TagProvider].
/// Replaces the duplicated expression in album_view and album_add_view.
List<String> resolveTagNames(BuildContext context, List<int> tagIds) {
  final tp = context.read<TagProvider>();
  return tagIds
      .map((id) => tp.getById(id)?.name)
      .whereType<String>()
      .toList();
}

// lib/widgets/sheet_handle.dart
// The pill-shaped drag handle shown at the top of modal bottom sheets.
// Extracted from the duplicated inline Container in _ImagePickerSheet
// (album_add_view) and _FilterSheet (images_view).

import 'package:flutter/material.dart';

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

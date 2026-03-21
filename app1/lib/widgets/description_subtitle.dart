// lib/widgets/description_subtitle.dart
// Returns a one-line Text subtitle when [description] is non-empty,
// or null when it is empty. Replaces the duplicated ternary in
// _AlbumTile (albums_view) and _TagTile (tags_view).

import 'package:flutter/material.dart';

Widget? descriptionSubtitle(String description) =>
    description.isNotEmpty
        ? Text(description, maxLines: 1, overflow: TextOverflow.ellipsis)
        : null;

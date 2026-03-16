// lib/providers/notifiers.dart
// Lightweight ChangeNotifiers used across multiple layers.
// Kept here so views and router don't need to import each other.

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

/// Holds the list of assets passed to ImageView for swipe navigation.
class FilteredListNotifier extends ChangeNotifier {
  List<AssetEntity> _list = [];
  List<AssetEntity> get list => List.unmodifiable(_list);

  void setList(List<AssetEntity> list) {
    _list = list;
    notifyListeners();
  }
}

/// Mirrors SelectionProvider.count so the shell nav-bar badge can rebuild
/// without watching the full SelectionProvider.
class SelectionCountNotifier extends ChangeNotifier {
  int _count = 0;
  int get count => _count;

  void update(int count) {
    if (_count != count) {
      _count = count;
      notifyListeners();
    }
  }
}

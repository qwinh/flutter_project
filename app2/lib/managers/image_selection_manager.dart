import 'package:flutter/foundation.dart';
import '../services/image_selection_service.dart';

class ImageSelectionManager extends ChangeNotifier {
  final ImageSelectionService _service = ImageSelectionService();
  Set<String> _selectedUris = {};
  bool _isLoading = false;

  Set<String> get selectedUris => _selectedUris;
  int get count => _selectedUris.length;
  bool get isLoading => _isLoading;

  bool isSelected(String uri) => _selectedUris.contains(uri);

  Future<void> loadSelections() async {
    _isLoading = true;
    notifyListeners();

    _selectedUris = await _service.getAllAsSet();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> toggle(String uri) async {
    if (_selectedUris.contains(uri)) {
      await _service.remove(uri);
      _selectedUris.remove(uri);
    } else {
      await _service.add(uri);
      _selectedUris.add(uri);
    }
    notifyListeners();
  }

  Future<void> add(String uri) async {
    if (!_selectedUris.contains(uri)) {
      await _service.add(uri);
      _selectedUris.add(uri);
      notifyListeners();
    }
  }

  Future<void> remove(String uri) async {
    if (_selectedUris.contains(uri)) {
      await _service.remove(uri);
      _selectedUris.remove(uri);
      notifyListeners();
    }
  }

  Future<void> addAll(Set<String> uris) async {
    final toAdd = uris.difference(_selectedUris);
    if (toAdd.isEmpty) return;
    await _service.addMultiple(toAdd.toList());
    _selectedUris.addAll(toAdd);
    notifyListeners();
  }

  Future<void> removeAll(Set<String> uris) async {
    final toRemove = uris.intersection(_selectedUris);
    if (toRemove.isEmpty) return;
    await _service.removeMultiple(toRemove.toList());
    _selectedUris.removeAll(toRemove);
    notifyListeners();
  }

  Future<void> setSelection(Set<String> uris) async {
    final toAdd = uris.difference(_selectedUris);
    final toRemove = _selectedUris.difference(uris);
    if (toAdd.isEmpty && toRemove.isEmpty) return;
    if (toAdd.isNotEmpty) await _service.addMultiple(toAdd.toList());
    if (toRemove.isNotEmpty) await _service.removeMultiple(toRemove.toList());
    _selectedUris = Set<String>.from(uris);
    notifyListeners();
  }

  Future<void> clear() async {
    await _service.clear();
    _selectedUris.clear();
    notifyListeners();
  }

  List<String> get selectedList => _selectedUris.toList();
}

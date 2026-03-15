// lib/views/image_view.dart
// Full-screen image viewer with pin-to-zoom, swipe navigation,
// info bottom bar, and selection toggle.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../providers/selection_provider.dart';
import '../views/images_view.dart';

class ImageView extends StatefulWidget {
  final int initialIndex;

  const ImageView({super.key, required this.initialIndex});

  @override
  State<ImageView> createState() => _ImageViewState();
}

class _ImageViewState extends State<ImageView> {
  late PageController _pageController;
  late int _currentIndex;
  // Cache Future<File?> objects so we don't restart the load on every rebuild.
  final Map<String, Future<File?>> _fileFutureCache = {};

  List<AssetEntity> _assets = [];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Grab the shared list from FilteredListNotifier (set by the caller).
    final raw = context.read<FilteredListNotifier>().list;
    final assets = raw.whereType<AssetEntity>().toList();
    if (assets.isNotEmpty) _assets = assets;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selProv = context.watch<SelectionProvider>();

    if (_assets.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('No images to show.')),
      );
    }

    final current = _assets[_currentIndex.clamp(0, _assets.length - 1)];
    final isSelected = selProv.isSelected(current.id);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${_assets.length}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isSelected ? Icons.check_circle : Icons.check_circle_outline,
              color: isSelected ? Colors.blue : Colors.white,
            ),
            tooltip: isSelected ? 'Deselect' : 'Select',
            onPressed: () => selProv.toggle(current.id),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _assets.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (ctx, i) {
          final asset = _assets[i];
          final future = _fileFutureCache.putIfAbsent(
            asset.id,
            () => asset.file,
          );
          return _FullImagePage(asset: asset, fileFuture: future);
        },
      ),
      bottomNavigationBar: Container(
        color: Colors.black87,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                current.title ?? 'Image',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${current.width} × ${current.height}',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullImagePage extends StatelessWidget {
  final AssetEntity asset;
  final Future<File?> fileFuture;

  const _FullImagePage({required this.asset, required this.fileFuture});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: fileFuture,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.white));
        }
        final file = snap.data;
        if (file == null) {
          return const Center(
              child: Icon(Icons.broken_image,
                  size: 64, color: Colors.white54));
        }
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Center(
            child: Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image,
                  size: 64,
                  color: Colors.white54),
            ),
          ),
        );
      },
    );
  }
}

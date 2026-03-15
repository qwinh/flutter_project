import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../managers/image_selection_manager.dart';

class ImageView extends StatefulWidget {
  final List<AssetEntity> assets;
  final int initialIndex;

  const ImageView({
    super.key,
    required this.assets,
    required this.initialIndex,
  });

  @override
  State<ImageView> createState() => _ImageViewState();
}

class _ImageViewState extends State<ImageView> {
  late PageController _pageController;
  late int _currentIndex;
  final Map<String, Future<File?>> _fileFutureCache =
      {}; // cache futures to avoid reload flicker
  final Set<String> _precached = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheImage(_currentIndex);
      if (_currentIndex + 1 < widget.assets.length)
        _precacheImage(_currentIndex + 1);
      if (_currentIndex - 1 >= 0) _precacheImage(_currentIndex - 1);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _precacheImage(int index) async {
    if (index < 0 || index >= widget.assets.length) return;
    final asset = widget.assets[index];
    final key = asset.id;
    if (_precached.contains(key)) return;
    _precached.add(key);
    final file = await asset.file;
    if (file != null && mounted) {
      await precacheImage(FileImage(file), context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectionManager = context.watch<ImageSelectionManager>();
    final currentAsset = widget.assets[_currentIndex];
    final isSelected = selectionManager.isSelected(currentAsset.id);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.assets.length}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isSelected ? Icons.check_circle : Icons.check_circle_outline,
              color: isSelected ? Colors.blue : Colors.white,
            ),
            tooltip: isSelected ? 'Deselect' : 'Select',
            onPressed: () {
              selectionManager.toggle(currentAsset.id);
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.assets.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
          _precacheImage(index + 1);
          _precacheImage(index - 1);
        },
        itemBuilder: (context, index) {
          final asset = widget.assets[index];
          final future = _fileFutureCache.putIfAbsent(
            asset.id,
            () => asset.file,
          );
          return _FullImagePage(asset: asset, fileFuture: future);
        },
      ),
      bottomNavigationBar: Container(
        color: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              currentAsset.title ?? 'Image',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${currentAsset.width} × ${currentAsset.height}',
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
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        final file = snapshot.data;
        if (file == null) {
          return const Center(
            child: Icon(Icons.broken_image, size: 64, color: Colors.white54),
          );
        }
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image,
                size: 64,
                color: Colors.white54,
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A wrapper widget that adds Google Photos-style drag-to-select behaviour
/// on top of a scrollable grid.
///
/// Usage:
/// ```dart
/// DragSelectGrid(
///   scrollController: _scrollController,
///   crossAxisCount: 3,
///   itemCount: assets.length,
///   spacing: 4,
///   padding: EdgeInsets.all(4),
///   isItemSelected: (i) => selectedIds.contains(assets[i].id),
///   onSelectionStart: (startIndex) { ... },
///   onSelectionUpdate: (startIndex, endIndex) { ... },
///   onSelectionEnd: () { ... },
///   onItemTap: (index) { ... },
///   child: gridView,
/// )
/// ```
class DragSelectGrid extends StatefulWidget {
  /// The scroll controller attached to the inner GridView.
  final ScrollController scrollController;

  /// Number of columns in the grid.
  final int crossAxisCount;

  /// Total number of items in the grid.
  final int itemCount;

  /// Grid spacing (same for cross-axis and main-axis).
  final double spacing;

  /// Padding around the grid.
  final EdgeInsets padding;

  /// Whether the app is already in selection mode (has selections).
  final bool isInSelectionMode;

  /// Called when a long-press initiates selection mode.
  /// Provides the index of the initially long-pressed item.
  final void Function(int startIndex) onSelectionStart;

  /// Called continuously while dragging. Provides the current range
  /// [startIndex, endIndex] (inclusive) that should be selected.
  final void Function(int startIndex, int endIndex) onSelectionUpdate;

  /// Called when the drag gesture ends.
  final void Function() onSelectionEnd;

  /// Called when an item is tapped (for navigation or toggle in selection mode).
  final void Function(int index) onItemTap;

  /// The child GridView to wrap.
  final Widget child;

  const DragSelectGrid({
    super.key,
    required this.scrollController,
    required this.crossAxisCount,
    required this.itemCount,
    required this.spacing,
    required this.padding,
    required this.isInSelectionMode,
    required this.onSelectionStart,
    required this.onSelectionUpdate,
    required this.onSelectionEnd,
    required this.onItemTap,
    required this.child,
  });

  @override
  State<DragSelectGrid> createState() => _DragSelectGridState();
}

class _DragSelectGridState extends State<DragSelectGrid> {
  bool _isDragging = false;
  int _startIndex = -1;
  int _lastIndex = -1;
  Timer? _autoScrollTimer;

  // Cached cell dimensions (calculated on first layout).
  double _cellWidth = 0;
  double _cellHeight = 0;
  final GlobalKey _gridKey = GlobalKey();

  // Auto-scroll speed in logical pixels per timer tick (16ms).
  static const double _autoScrollSpeed = 8.0;
  // Fraction of visible height that triggers auto-scroll.
  static const double _edgeFraction = 0.10;

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Index calculation
  // ---------------------------------------------------------------------------

  void _computeCellSize(BoxConstraints constraints) {
    final totalHorizontalPadding = widget.padding.left + widget.padding.right;
    final availableWidth = constraints.maxWidth - totalHorizontalPadding;
    final totalSpacing = widget.spacing * (widget.crossAxisCount - 1);
    _cellWidth = (availableWidth - totalSpacing) / widget.crossAxisCount;
    _cellHeight = _cellWidth; // square cells
  }

  /// Convert a local-to-grid position (already accounting for padding) into a
  /// grid item index.
  int _indexFromLocalPosition(Offset localPosition) {
    final scrollOffset = widget.scrollController.offset;
    final adjustedX = localPosition.dx - widget.padding.left;
    final adjustedY = localPosition.dy + scrollOffset - widget.padding.top;

    final colStep = _cellWidth + widget.spacing;
    final rowStep = _cellHeight + widget.spacing;

    final col = (adjustedX / colStep).floor().clamp(0, widget.crossAxisCount - 1);
    final row = (adjustedY / rowStep).floor();
    final maxRow = ((widget.itemCount - 1) / widget.crossAxisCount).floor();
    final clampedRow = row.clamp(0, maxRow);

    final index = clampedRow * widget.crossAxisCount + col;
    return index.clamp(0, widget.itemCount - 1);
  }

  // ---------------------------------------------------------------------------
  // Auto-scroll
  // ---------------------------------------------------------------------------

  void _handleAutoScroll(Offset globalPosition) {
    final renderBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localY = renderBox.globalToLocal(globalPosition).dy;
    final height = renderBox.size.height;
    final topThreshold = height * _edgeFraction;
    final bottomThreshold = height * (1 - _edgeFraction);

    if (localY < topThreshold) {
      _startAutoScroll(-_autoScrollSpeed);
    } else if (localY > bottomThreshold) {
      _startAutoScroll(_autoScrollSpeed);
    } else {
      _stopAutoScroll();
    }
  }

  void _startAutoScroll(double delta) {
    // Already scrolling in the same direction?
    if (_autoScrollTimer != null) return;
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final pos = widget.scrollController.position;
      final target = (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      widget.scrollController.jumpTo(target);

      // Re-calculate the index under the user's finger while auto-scrolling.
      // We rely on the fact that onLongPressMoveUpdate will fire again soon.
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Gesture handlers
  // ---------------------------------------------------------------------------

  void _onLongPressStart(LongPressStartDetails details) {
    final renderBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final local = renderBox.globalToLocal(details.globalPosition);
    final index = _indexFromLocalPosition(local);

    HapticFeedback.mediumImpact();

    setState(() {
      _isDragging = true;
      _startIndex = index;
      _lastIndex = index;
    });

    widget.onSelectionStart(index);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isDragging) return;

    final renderBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final local = renderBox.globalToLocal(details.globalPosition);
    final index = _indexFromLocalPosition(local);

    _handleAutoScroll(details.globalPosition);

    if (index != _lastIndex) {
      _lastIndex = index;
      final start = _startIndex < index ? _startIndex : index;
      final end = _startIndex < index ? index : _startIndex;
      widget.onSelectionUpdate(start, end);
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    _stopAutoScroll();
    setState(() {
      _isDragging = false;
      _startIndex = -1;
      _lastIndex = -1;
    });
    widget.onSelectionEnd();
  }

  void _onTapUp(TapUpDetails details) {
    final renderBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final local = renderBox.globalToLocal(details.globalPosition);
    final index = _indexFromLocalPosition(local);
    if (index >= 0 && index < widget.itemCount) {
      widget.onItemTap(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _computeCellSize(constraints);
        return GestureDetector(
          onLongPressStart: _onLongPressStart,
          onLongPressMoveUpdate: _onLongPressMoveUpdate,
          onLongPressEnd: _onLongPressEnd,
          onTapUp: _onTapUp,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            key: _gridKey,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: widget.child,
          ),
        );
      },
    );
  }
}

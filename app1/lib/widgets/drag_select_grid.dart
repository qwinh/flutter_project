// lib/widgets/drag_select_grid.dart
// Google Photos-style drag-to-select wrapper for a scrollable GridView.
// Ported from app2; adapted to work with app1's SelectionProvider.
//
// Usage:
//   DragSelectGrid(
//     scrollController: _scrollController,
//     crossAxisCount: 3,
//     itemCount: assets.length,
//     spacing: 2,
//     padding: EdgeInsets.all(2),
//     isInSelectionMode: _selectionMode,
//     onSelectionStart: _onDragSelectionStart,
//     onSelectionUpdate: _onDragSelectionUpdate,
//     onSelectionEnd: _onDragSelectionEnd,
//     onItemTap: _onItemTap,
//     child: gridView,
//   )

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DragSelectGrid extends StatefulWidget {
  /// The scroll controller attached to the inner GridView.
  final ScrollController scrollController;

  /// Number of columns in the grid.
  final int crossAxisCount;

  /// Total number of items in the grid.
  final int itemCount;

  /// Grid spacing (applied uniformly to cross-axis and main-axis).
  final double spacing;

  /// Padding around the grid.
  final EdgeInsets padding;

  /// Whether the app is currently in selection mode.
  final bool isInSelectionMode;

  /// Called when a long-press initiates selection mode.
  /// Provides the index of the initially long-pressed item.
  final void Function(int startIndex) onSelectionStart;

  /// Called continuously while dragging.
  /// Provides the normalised range [startIndex, endIndex] (always start ≤ end).
  final void Function(int startIndex, int endIndex) onSelectionUpdate;

  /// Called when the drag gesture ends.
  final VoidCallback onSelectionEnd;

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

  double _cellWidth = 0;
  double _cellHeight = 0;
  final GlobalKey _gridKey = GlobalKey();

  static const double _autoScrollSpeed = 8.0;
  static const double _edgeFraction = 0.10;

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  // ── Index calculation ──────────────────────────────────────────────────────

  void _computeCellSize(BoxConstraints constraints) {
    final availableWidth =
        constraints.maxWidth - widget.padding.left - widget.padding.right;
    final totalSpacing = widget.spacing * (widget.crossAxisCount - 1);
    _cellWidth = (availableWidth - totalSpacing) / widget.crossAxisCount;
    _cellHeight = _cellWidth; // square cells
  }

  int _indexFromLocalPosition(Offset localPosition) {
    final scrollOffset = widget.scrollController.offset;
    final adjustedX = localPosition.dx - widget.padding.left;
    final adjustedY = localPosition.dy + scrollOffset - widget.padding.top;

    if (_cellWidth <= 0 || _cellHeight <= 0) return 0;

    final colStep = _cellWidth + widget.spacing;
    final rowStep = _cellHeight + widget.spacing;

    final col =
        (adjustedX / colStep).floor().clamp(0, widget.crossAxisCount - 1);
    final row = (adjustedY / rowStep).floor();
    final maxRow = ((widget.itemCount - 1) / widget.crossAxisCount).floor();
    final clampedRow = row.clamp(0, maxRow);

    return (clampedRow * widget.crossAxisCount + col)
        .clamp(0, widget.itemCount - 1);
  }

  // ── Auto-scroll ────────────────────────────────────────────────────────────

  void _handleAutoScroll(Offset globalPosition) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localY = box.globalToLocal(globalPosition).dy;
    final height = box.size.height;

    if (localY < height * _edgeFraction) {
      _startAutoScroll(-_autoScrollSpeed);
    } else if (localY > height * (1 - _edgeFraction)) {
      _startAutoScroll(_autoScrollSpeed);
    } else {
      _stopAutoScroll();
    }
  }

  void _startAutoScroll(double delta) {
    if (_autoScrollTimer != null) return;
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final pos = widget.scrollController.position;
      final target = (pos.pixels + delta)
          .clamp(pos.minScrollExtent, pos.maxScrollExtent);
      widget.scrollController.jumpTo(target);
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  // ── Gesture handlers ───────────────────────────────────────────────────────

  void _onLongPressStart(LongPressStartDetails details) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final local = box.globalToLocal(details.globalPosition);
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

    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final local = box.globalToLocal(details.globalPosition);
    final index = _indexFromLocalPosition(local);

    _handleAutoScroll(details.globalPosition);

    if (index != _lastIndex) {
      _lastIndex = index;
      final lo = _startIndex < index ? _startIndex : index;
      final hi = _startIndex < index ? index : _startIndex;
      widget.onSelectionUpdate(lo, hi);
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
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final local = box.globalToLocal(details.globalPosition);
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

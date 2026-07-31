import 'package:flutter/material.dart';

/// Which corners get the angled cut.
enum NotchCorner { topLeft, topRight, bottomLeft, bottomRight }

/// A rectangle whose chosen corners are cut at 45 degrees instead of being
/// square - the "angled-notch panel corners" of the Rift Cyan tactical HUD.
///
/// Implemented as an [OutlinedBorder] so it drops into `ShapeDecoration`,
/// buttons, and anything else that takes a shape. Kept self-contained in
/// this file so the whole notched-corner treatment can be reverted cleanly.
class NotchedBorder extends OutlinedBorder {
  /// Length of each corner cut (along each edge).
  final double notch;

  /// Which corners to cut.
  final Set<NotchCorner> corners;

  const NotchedBorder({
    super.side = BorderSide.none,
    this.notch = 12,
    this.corners = const {NotchCorner.topLeft, NotchCorner.bottomRight},
  });

  bool _has(NotchCorner c) => corners.contains(c);

  Path _pathFor(Rect rect) {
    // Clamp the notch so it never exceeds half of the smaller side.
    final n = notch.clamp(0.0, rect.shortestSide / 2);
    final l = rect.left, t = rect.top, r = rect.right, b = rect.bottom;
    final tl = _has(NotchCorner.topLeft);
    final tr = _has(NotchCorner.topRight);
    final bl = _has(NotchCorner.bottomLeft);
    final br = _has(NotchCorner.bottomRight);

    final path = Path()..moveTo(l + (tl ? n : 0), t);
    path.lineTo(r - (tr ? n : 0), t);
    if (tr) path.lineTo(r, t + n);
    path.lineTo(r, b - (br ? n : 0));
    if (br) path.lineTo(r - n, b);
    path.lineTo(l + (bl ? n : 0), b);
    if (bl) path.lineTo(l, b - n);
    path.lineTo(l, t + (tl ? n : 0));
    if (tl) path.lineTo(l + n, t);
    return path..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _pathFor(rect.deflate(side.strokeInset));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _pathFor(rect.deflate(side.strokeOutset));

  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) {
    canvas.drawPath(_pathFor(rect), paint);
  }

  @override
  bool get preferPaintInterior => true;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(_pathFor(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  NotchedBorder copyWith({
    BorderSide? side,
    double? notch,
    Set<NotchCorner>? corners,
  }) => NotchedBorder(
    side: side ?? this.side,
    notch: notch ?? this.notch,
    corners: corners ?? this.corners,
  );

  @override
  ShapeBorder scale(double t) =>
      NotchedBorder(side: side.scale(t), notch: notch * t, corners: corners);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);
}

/// An "open" tactical-bracket frame: the top-left and bottom-right corners
/// are chamfered (a drawn diagonal), while the top-right and bottom-left
/// corners are left open with a gap in the border. The fill (if any) still
/// covers the whole rounded-off rectangle. Used for the outlined panels and
/// outlined buttons in the Rift Cyan mockup.
class OpenNotchedBorder extends OutlinedBorder {
  /// Chamfer length on the top-left / bottom-right corners.
  final double notch;

  /// Opening length on the top-right / bottom-left corners.
  final double gap;

  const OpenNotchedBorder({
    super.side = BorderSide.none,
    this.notch = 14,
    this.gap = 12,
  });

  Path _fillPath(Rect r) {
    final n = notch.clamp(0.0, r.shortestSide / 2);
    return Path()
      ..moveTo(r.left + n, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right, r.bottom - n)
      ..lineTo(r.right - n, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..lineTo(r.left, r.top + n)
      ..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _fillPath(rect.deflate(side.strokeInset));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _fillPath(rect.deflate(side.strokeOutset));

  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) {
    canvas.drawPath(_fillPath(rect), paint);
  }

  @override
  bool get preferPaintInterior => true;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    final r = rect.deflate(side.width / 2);
    final n = notch.clamp(0.0, r.shortestSide / 2);
    final g = gap.clamp(0.0, r.shortestSide / 2);
    final l = r.left, t = r.top, rt = r.right, b = r.bottom;
    final p = side.toPaint();
    // Top edge, then top-left chamfer.
    canvas.drawLine(Offset(l + n, t), Offset(rt - g, t), p);
    canvas.drawLine(Offset(l, t + n), Offset(l + n, t), p);
    // Right edge (starts below the open top-right gap), then bottom-right chamfer.
    canvas.drawLine(Offset(rt, t + g), Offset(rt, b - n), p);
    canvas.drawLine(Offset(rt, b - n), Offset(rt - n, b), p);
    // Bottom edge (ends before the open bottom-left gap).
    canvas.drawLine(Offset(rt - n, b), Offset(l + g, b), p);
    // Left edge (starts above the open bottom-left gap).
    canvas.drawLine(Offset(l, b - g), Offset(l, t + n), p);
  }

  @override
  OpenNotchedBorder copyWith({BorderSide? side, double? notch, double? gap}) =>
      OpenNotchedBorder(
        side: side ?? this.side,
        notch: notch ?? this.notch,
        gap: gap ?? this.gap,
      );

  @override
  ShapeBorder scale(double t) =>
      OpenNotchedBorder(side: side.scale(t), notch: notch * t, gap: gap * t);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);
}

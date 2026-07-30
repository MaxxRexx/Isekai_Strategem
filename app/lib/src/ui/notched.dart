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

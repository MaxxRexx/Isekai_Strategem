import 'package:flutter/material.dart';

/// A rectangle with exactly two opposite corners cut at 45 degrees (the
/// top-left and bottom-right by default); the other two corners stay
/// square 90 degrees. This is the "angled-notch" corner of the Rift Cyan
/// tactical HUD.
///
/// Used both filled (a solid "closed" notch, e.g. primary buttons) and
/// outline-only (an "open" notch that shows the background through the cut,
/// e.g. bordered buttons and panels).
class NotchedBorder extends OutlinedBorder {
  /// Length of each corner cut, along each edge.
  final double notch;

  /// Whether the cut corners are the top-left/bottom-right pair (default)
  /// or the top-right/bottom-left pair.
  final bool mirror;

  const NotchedBorder({
    super.side = BorderSide.none,
    this.notch = 12,
    this.mirror = false,
  });

  Path _pathFor(Rect r) {
    final n = notch.clamp(0.0, r.shortestSide / 2);
    final l = r.left, t = r.top, rt = r.right, b = r.bottom;
    if (mirror) {
      // Top-right and bottom-left cut; top-left and bottom-right square.
      return Path()
        ..moveTo(l, t)
        ..lineTo(rt - n, t)
        ..lineTo(rt, t + n)
        ..lineTo(rt, b)
        ..lineTo(l + n, b)
        ..lineTo(l, b - n)
        ..close();
    }
    // Top-left and bottom-right cut; top-right and bottom-left square.
    return Path()
      ..moveTo(l + n, t)
      ..lineTo(rt, t)
      ..lineTo(rt, b - n)
      ..lineTo(rt - n, b)
      ..lineTo(l, b)
      ..lineTo(l, t + n)
      ..close();
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
  NotchedBorder copyWith({BorderSide? side, double? notch, bool? mirror}) =>
      NotchedBorder(
        side: side ?? this.side,
        notch: notch ?? this.notch,
        mirror: mirror ?? this.mirror,
      );

  @override
  ShapeBorder scale(double t) =>
      NotchedBorder(side: side.scale(t), notch: notch * t, mirror: mirror);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);
}

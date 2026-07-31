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

/// An "open" notch outline: the shape stays a full rectangle, but the drawn
/// border leaves the top-left and bottom-right corners OPEN - each edge
/// stops [notch] short of those corners, so the corner reads as an L-shaped
/// gap (no diagonal, no closing line). The top-right and bottom-left corners
/// stay closed 90 degrees. Used for outlined (no-fill) buttons and panels.
class OpenNotchBorder extends OutlinedBorder {
  final double notch;

  const OpenNotchBorder({super.side = BorderSide.none, this.notch = 11});

  // The fill/overlay area (what a hover/press highlight is clipped to) is
  // the 2-notch chamfered shape, so the click fill respects the notches
  // instead of showing square corners. The stroke (see paint) draws only
  // the open L-brackets - the diagonals here are left open.
  Path _fillPath(Rect r) {
    final n = notch.clamp(0.0, r.shortestSide / 2);
    final l = r.left, t = r.top, rt = r.right, b = r.bottom;
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
      _fillPath(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _fillPath(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    final r = rect.deflate(side.width / 2);
    final n = notch.clamp(0.0, r.shortestSide / 2);
    final l = r.left, t = r.top, rt = r.right, b = r.bottom;
    final p = side.toPaint();
    // Top edge: open on the left (starts at l+n), closed at top-right.
    canvas.drawLine(Offset(l + n, t), Offset(rt, t), p);
    // Right edge: closed at top-right, open at bottom-right (stops at b-n).
    canvas.drawLine(Offset(rt, t), Offset(rt, b - n), p);
    // Bottom edge: open on the right (starts at rt-n), closed at bottom-left.
    canvas.drawLine(Offset(rt - n, b), Offset(l, b), p);
    // Left edge: closed at bottom-left, open at top-left (stops at t+n).
    canvas.drawLine(Offset(l, b), Offset(l, t + n), p);
  }

  @override
  OpenNotchBorder copyWith({BorderSide? side, double? notch}) =>
      OpenNotchBorder(side: side ?? this.side, notch: notch ?? this.notch);

  @override
  ShapeBorder scale(double t) =>
      OpenNotchBorder(side: side.scale(t), notch: notch * t);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);
}

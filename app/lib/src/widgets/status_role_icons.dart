import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

/// One glyph per [StatusRole], drawn rather than picked from a font.
///
/// These are read at ten pixels on a status badge, which is far below what a
/// Material icon survives, so each one is two to four strokes and nothing
/// more. What matters at that size is the **silhouette**: a player should be
/// able to tell a bleed from a ward without resolving any detail inside the
/// shape, so no two of the sixteen share an outline.
///
/// Drawn from the role rather than from the effect's id on purpose. Sixty-two
/// bespoke icons would be sixty-two things to learn and sixty-two things to
/// maintain; sixteen is a vocabulary. The exact effect, its stat and its
/// magnitude are what the description is for.
class StatusRoleIcon extends StatelessWidget {
  final StatusRole role;
  final double size;
  final Color color;

  const StatusRoleIcon({
    super.key,
    required this.role,
    required this.color,
    this.size = 10,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _RoleGlyphPainter(role, color),
      );
}

class _RoleGlyphPainter extends CustomPainter {
  final StatusRole role;
  final Color color;
  const _RoleGlyphPainter(this.role, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final c = Offset(s / 2, s / 2);
    final r = s * 0.38;

    switch (role) {
      // The turn is gone. The heaviest mark in the set, because it is the
      // heaviest thing that can happen to a character.
      case StatusRole.actionDenied:
        stroke.strokeWidth = s * 0.19;
        canvas.drawLine(c + Offset(-r, -r), c + Offset(r, r), stroke);
        canvas.drawLine(c + Offset(r, -r), c + Offset(-r, r), stroke);

      // A padlock: something they could do is shut, but they still act.
      case StatusRole.optionDenied:
        final body = Rect.fromLTWH(c.dx - r * 0.8, c.dy - r * 0.1, r * 1.6, r);
        canvas.drawRect(body, fill);
        canvas.drawArc(
          Rect.fromCircle(center: Offset(c.dx, c.dy - r * 0.1), radius: r * 0.5),
          3.14159,
          3.14159,
          false,
          stroke,
        );

      // A teardrop, filled: health coming off, turn after turn.
      case StatusRole.damageOverTime:
        canvas.drawPath(_teardrop(c, r), fill);

      case StatusRole.healOverTime:
        stroke.strokeWidth = s * 0.19;
        canvas.drawLine(c + Offset(0, -r), c + Offset(0, r), stroke);
        canvas.drawLine(c + Offset(-r, 0), c + Offset(r, 0), stroke);

      // The Trion diamond the rest of the interface already uses.
      case StatusRole.trionDrain:
        canvas.drawPath(_diamond(c, r), fill);

      // The same diamond, hollow, over a chevron: about Trion, but about what
      // it costs you rather than about losing it. Hollow because nothing is
      // being taken away.
      case StatusRole.trionCheaper:
        _trionCost(canvas, stroke, c, r, cheaper: true);

      case StatusRole.trionDearer:
        _trionCost(canvas, stroke, c, r, cheaper: false);

      case StatusRole.takesLess:
        canvas.drawPath(_shield(c, r), stroke);

      // The same shield, broken across.
      case StatusRole.takesMore:
        canvas.drawPath(_shield(c, r), stroke);
        canvas.drawLine(c + Offset(-r, r * 0.5), c + Offset(r, -r * 0.7), stroke);

      // An impact star: damage leaving, not arriving.
      case StatusRole.dealsMore:
        _star(canvas, stroke, c, r);

      case StatusRole.dealsLess:
        _star(canvas, stroke, c, r * 0.8);
        canvas.drawLine(c + Offset(-r, r), c + Offset(r, -r), stroke);

      case StatusRole.statUp:
        _chevron(canvas, stroke, c, r, up: true);

      case StatusRole.statDown:
        _chevron(canvas, stroke, c, r, up: false);

      // Two chevrons: all the way down, not a step down.
      case StatusRole.statZeroed:
        _chevron(canvas, stroke, c + Offset(0, -r * 0.45), r * 0.85, up: false);
        _chevron(canvas, stroke, c + Offset(0, r * 0.45), r * 0.85, up: false);

      // A ring with the shot going wide of it.
      case StatusRole.aimSpoiled:
        canvas.drawCircle(c, r * 0.62, stroke);
        canvas.drawLine(
          c + Offset(-r * 1.05, r * 1.05),
          c + Offset(r * 0.35, -r * 0.35),
          stroke,
        );

      // A question mark, because "this one is unusual, read it" is the
      // message rather than a shortcoming of the drawing.
      case StatusRole.special:
        canvas.drawArc(
          Rect.fromCircle(center: Offset(c.dx, c.dy - r * 0.45), radius: r * 0.5),
          3.14159 * 0.85,
          3.14159 * 1.35,
          false,
          stroke,
        );
        canvas.drawLine(
          Offset(c.dx, c.dy - r * 0.05),
          Offset(c.dx, c.dy + r * 0.35),
          stroke,
        );
        canvas.drawCircle(Offset(c.dx, c.dy + r * 0.85), s * 0.085, fill);
    }
  }

  Path _teardrop(Offset c, double r) => Path()
    ..moveTo(c.dx, c.dy - r * 1.15)
    ..quadraticBezierTo(c.dx + r, c.dy - r * 0.1, c.dx + r * 0.72, c.dy + r * 0.5)
    ..quadraticBezierTo(c.dx, c.dy + r * 1.5, c.dx - r * 0.72, c.dy + r * 0.5)
    ..quadraticBezierTo(c.dx - r, c.dy - r * 0.1, c.dx, c.dy - r * 1.15)
    ..close();

  Path _diamond(Offset c, double r) => Path()
    ..moveTo(c.dx, c.dy - r * 1.1)
    ..lineTo(c.dx + r * 0.8, c.dy)
    ..lineTo(c.dx, c.dy + r * 1.1)
    ..lineTo(c.dx - r * 0.8, c.dy)
    ..close();

  Path _shield(Offset c, double r) => Path()
    ..moveTo(c.dx, c.dy - r * 1.1)
    ..lineTo(c.dx + r * 0.95, c.dy - r * 0.6)
    ..lineTo(c.dx + r * 0.95, c.dy + r * 0.2)
    ..quadraticBezierTo(
        c.dx + r * 0.8, c.dy + r, c.dx, c.dy + r * 1.2)
    ..quadraticBezierTo(
        c.dx - r * 0.8, c.dy + r, c.dx - r * 0.95, c.dy + r * 0.2)
    ..lineTo(c.dx - r * 0.95, c.dy - r * 0.6)
    ..close();

  void _chevron(Canvas canvas, Paint paint, Offset c, double r,
      {required bool up}) {
    final dy = up ? -1.0 : 1.0;
    canvas.drawLine(
      c + Offset(-r, -r * 0.5 * dy),
      c + Offset(0, r * 0.55 * dy),
      paint,
    );
    canvas.drawLine(
      c + Offset(0, r * 0.55 * dy),
      c + Offset(r, -r * 0.5 * dy),
      paint,
    );
  }

  /// A hollow Trion diamond with a chevron leading away from it: the cost of
  /// using an ability, going down or up.
  ///
  /// The two are mirror images rather than the same layout with the chevron
  /// flipped. Pointing an up-chevron at the underside of the diamond merges
  /// the two into one X-shaped blob at ten pixels, which is both illegible
  /// and, worse, close to the glyph for losing the turn.
  void _trionCost(Canvas canvas, Paint paint, Offset c, double r,
      {required bool cheaper}) {
    final lift = cheaper ? -1.0 : 1.0;
    final diamond = Offset(c.dx, c.dy + r * 0.42 * lift);
    canvas.drawPath(
      Path()
        ..moveTo(diamond.dx, diamond.dy - r * 0.62)
        ..lineTo(diamond.dx + r * 0.48, diamond.dy)
        ..lineTo(diamond.dx, diamond.dy + r * 0.62)
        ..lineTo(diamond.dx - r * 0.48, diamond.dy)
        ..close(),
      paint,
    );
    _chevron(canvas, paint, Offset(c.dx, c.dy - r * 0.72 * lift), r * 0.62,
        up: !cheaper);
  }

  void _star(Canvas canvas, Paint paint, Offset c, double r) {
    canvas.drawLine(c + Offset(0, -r), c + Offset(0, r), paint);
    canvas.drawLine(c + Offset(-r, 0), c + Offset(r, 0), paint);
    final d = r * 0.62;
    canvas.drawLine(c + Offset(-d, -d), c + Offset(d, d), paint);
    canvas.drawLine(c + Offset(d, -d), c + Offset(-d, d), paint);
  }

  @override
  bool shouldRepaint(covariant _RoleGlyphPainter old) =>
      old.role != role || old.color != color;
}

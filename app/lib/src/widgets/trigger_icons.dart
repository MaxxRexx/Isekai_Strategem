import 'dart:math' as math;

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../ui/palette.dart';

/// A distinct hand-drawn glyph per Trigger/Black Trigger, grounded in its
/// real damage type or mechanic rather than a shared category icon: every
/// slashing attack reads as crossed blades, every heal as a plus, every
/// passive tied to "will"/"core" language gets the same visual family, and
/// so on. Two triggers sharing a glyph (e.g. every piercing ranged single)
/// reflects that they really do share a mechanic, not a gap in coverage.
enum _Glyph {
  slash,
  pierce,
  blunt,
  acidDrop,
  poisonDrop,
  psychicSwirl,
  frost,
  flame,
  bolt,
  healPlus,
  buffChevron,
  debuffChevron,
  wardShield,
  siphon,
  crackedShard,
  sunburst,
  shieldCore,
  plateStack,
  linkedDots,
  anchor,
  clockHourglass,
  eye,
  plainDot,
}

const Map<String, _Glyph> _glyphById = {
  // Triggers
  'twin_fang_strike': _Glyph.slash,
  'cleave': _Glyph.slash,
  'marksmans_volley': _Glyph.pierce,
  'suppressing_fire': _Glyph.pierce,
  'shatterpoint': _Glyph.acidDrop,
  'venom_needle': _Glyph.poisonDrop,
  'binding_snare': _Glyph.blunt,
  'mind_spike': _Glyph.psychicSwirl,
  'dread_gaze': _Glyph.psychicSwirl,
  'charm_whisper': _Glyph.debuffChevron,
  'mending_light': _Glyph.healPlus,
  'vital_surge': _Glyph.buffChevron,
  'rally_cry': _Glyph.buffChevron,
  'war_chant': _Glyph.buffChevron,
  'fortify': _Glyph.wardShield,
  'adrenal_rush': _Glyph.buffChevron,
  'piercing_thrust': _Glyph.pierce,
  'whirlwind_slash': _Glyph.slash,
  'longshot': _Glyph.pierce,
  'scattershot': _Glyph.pierce,
  'flashbang_round': _Glyph.debuffChevron,
  'frost_lance': _Glyph.frost,
  'cinderburst': _Glyph.flame,
  'static_discharge': _Glyph.bolt,
  'acid_spray': _Glyph.acidDrop,
  'nightmare_pulse': _Glyph.psychicSwirl,
  'soul_siphon': _Glyph.siphon,
  'mind_shatter': _Glyph.psychicSwirl,
  'guardians_aegis': _Glyph.wardShield,
  'second_wind': _Glyph.healPlus,
  'bloodpact': _Glyph.siphon,
  'marked_for_death': _Glyph.pierce,
  'battle_cry': _Glyph.buffChevron,
  'cleansing_ward': _Glyph.wardShield,
  'guardians_bulwark': _Glyph.plateStack,
  'iron_will': _Glyph.shieldCore,
  'keen_eye': _Glyph.eye,
  'overcharged_core': _Glyph.bolt,
  'vanguards_discipline': _Glyph.buffChevron,
  'silver_tongue': _Glyph.psychicSwirl,
  // Black Triggers
  'ashbringer': _Glyph.flame,
  'fracture_edge': _Glyph.crackedShard,
  'solar_flare': _Glyph.sunburst,
  'aegis_core': _Glyph.shieldCore,
  'bastion_frame': _Glyph.plateStack,
  'wellspring': _Glyph.healPlus,
  'chorus_bond': _Glyph.linkedDots,
  'paradox_shard': _Glyph.psychicSwirl,
  'gravebind': _Glyph.anchor,
  'chrono_fragment': _Glyph.clockHourglass,
};

/// A bespoke icon for one regular Trigger (active or passive).
class TriggerIcon extends StatelessWidget {
  final Trigger trigger;
  final double size;
  final Color? color;
  const TriggerIcon({
    super.key,
    required this.trigger,
    this.size = 20,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _GlyphPainter(
        _glyphById[trigger.id] ?? _Glyph.plainDot,
        color ?? Palette.accent,
      ),
    );
  }
}

/// A bespoke icon for one Black Trigger.
class BlackTriggerIcon extends StatelessWidget {
  final BlackTrigger blackTrigger;
  final double size;
  final Color? color;
  const BlackTriggerIcon({
    super.key,
    required this.blackTrigger,
    this.size = 20,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _GlyphPainter(
        _glyphById[blackTrigger.id] ?? _Glyph.plainDot,
        color ?? Palette.accent,
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  final _Glyph glyph;
  final Color color;
  const _GlyphPainter(this.glyph, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.32;

    switch (glyph) {
      case _Glyph.slash:
        _drawBlade(canvas, paint, c, r, tiltUp: true);
        _drawBlade(canvas, paint, c, r, tiltUp: false);
        break;
      case _Glyph.pierce:
        canvas.drawLine(c + Offset(-r, r), c + Offset(r, -r), paint);
        final tip = c + Offset(r, -r);
        canvas.drawLine(tip, tip + Offset(-r * 0.55, 0), paint);
        canvas.drawLine(tip, tip + Offset(0, r * 0.55), paint);
        break;
      case _Glyph.blunt:
        canvas.drawPath(_polygon(c, r, 6), paint);
        break;
      case _Glyph.acidDrop:
        canvas.drawPath(_teardrop(c, r), paint);
        canvas.drawCircle(
          c + Offset(r * 0.9, r * 0.7),
          size.width * 0.045,
          paint,
        );
        break;
      case _Glyph.poisonDrop:
        canvas.drawPath(_teardrop(c, r), paint);
        for (final a in [-0.9, 0.0, 0.9]) {
          final dir = Offset(
            math.cos(a - math.pi / 2),
            math.sin(a - math.pi / 2),
          );
          canvas.drawLine(c + dir * (r * 1.15), c + dir * (r * 1.45), paint);
        }
        break;
      case _Glyph.psychicSwirl:
        _drawSpiral(canvas, paint, c, r);
        break;
      case _Glyph.frost:
        for (var i = 0; i < 3; i++) {
          final a = i * math.pi / 3;
          final dir = Offset(math.cos(a), math.sin(a));
          canvas.drawLine(c - dir * r, c + dir * r, paint);
        }
        for (var i = 0; i < 3; i++) {
          final a = i * math.pi / 3;
          final dir = Offset(math.cos(a), math.sin(a));
          final perp = Offset(-dir.dy, dir.dx);
          final base = c + dir * (r * 0.55);
          canvas.drawLine(
            base,
            base + perp * (r * 0.28) + dir * (r * 0.18),
            paint,
          );
          canvas.drawLine(
            base,
            base - perp * (r * 0.28) + dir * (r * 0.18),
            paint,
          );
          final baseNeg = c - dir * (r * 0.55);
          canvas.drawLine(
            baseNeg,
            baseNeg + perp * (r * 0.28) - dir * (r * 0.18),
            paint,
          );
          canvas.drawLine(
            baseNeg,
            baseNeg - perp * (r * 0.28) - dir * (r * 0.18),
            paint,
          );
        }
        break;
      case _Glyph.flame:
        canvas.drawPath(_flame(c, r), paint);
        break;
      case _Glyph.bolt:
        canvas.drawPath(_bolt(c, r), paint);
        break;
      case _Glyph.healPlus:
        canvas.drawLine(c + Offset(0, -r), c + Offset(0, r), paint);
        canvas.drawLine(c + Offset(-r, 0), c + Offset(r, 0), paint);
        break;
      case _Glyph.buffChevron:
        _drawChevron(canvas, paint, c, r, up: true);
        break;
      case _Glyph.debuffChevron:
        _drawChevron(canvas, paint, c, r, up: false);
        break;
      case _Glyph.wardShield:
        canvas.drawPath(_shield(c, r), paint);
        canvas.drawCircle(c + Offset(0, r * 0.05), size.width * 0.05, paint);
        break;
      case _Glyph.shieldCore:
        canvas.drawPath(_shield(c, r), paint);
        final fill = Paint()..color = color;
        canvas.drawCircle(c + Offset(0, r * 0.05), size.width * 0.09, fill);
        break;
      case _Glyph.siphon:
        canvas.drawCircle(c + Offset(-r * 0.7, 0), size.width * 0.11, paint);
        canvas.drawCircle(c + Offset(r * 0.7, 0), size.width * 0.07, paint);
        final path = Path()
          ..moveTo(c.dx - r * 0.4, c.dy)
          ..quadraticBezierTo(c.dx, c.dy - r * 0.5, c.dx + r * 0.45, c.dy);
        canvas.drawPath(path, paint);
        final tip = Offset(c.dx + r * 0.45, c.dy);
        canvas.drawLine(tip, tip + const Offset(-4, -3), paint);
        canvas.drawLine(tip, tip + const Offset(-2, 4), paint);
        break;
      case _Glyph.crackedShard:
        canvas.drawPath(_polygon(c, r, 4, rotate: math.pi / 4), paint);
        final crack = Path()
          ..moveTo(c.dx - r * 0.3, c.dy - r * 0.6)
          ..lineTo(c.dx + r * 0.1, c.dy - r * 0.1)
          ..lineTo(c.dx - r * 0.15, c.dy + r * 0.15)
          ..lineTo(c.dx + r * 0.35, c.dy + r * 0.6);
        canvas.drawPath(crack, paint);
        break;
      case _Glyph.sunburst:
        canvas.drawCircle(c, r * 0.42, paint);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          final dir = Offset(math.cos(a), math.sin(a));
          canvas.drawLine(c + dir * (r * 0.65), c + dir * r, paint);
        }
        break;
      case _Glyph.plateStack:
        for (var i = -1; i <= 1; i++) {
          final y = c.dy + i * r * 0.42;
          canvas.drawLine(
            Offset(c.dx - r * 0.85, y),
            Offset(c.dx + r * 0.85, y),
            paint,
          );
        }
        break;
      case _Glyph.linkedDots:
        final pts = [
          c + Offset(0, -r * 0.75),
          c + Offset(r * 0.8, r * 0.55),
          c + Offset(-r * 0.8, r * 0.55),
        ];
        canvas.drawLine(pts[0], pts[1], paint);
        canvas.drawLine(pts[1], pts[2], paint);
        canvas.drawLine(pts[2], pts[0], paint);
        for (final p in pts) {
          canvas.drawCircle(p, size.width * 0.06, paint);
        }
        break;
      case _Glyph.anchor:
        canvas.drawLine(c + Offset(0, -r), c + Offset(0, r * 0.7), paint);
        canvas.drawCircle(c + Offset(0, -r * 0.85), size.width * 0.06, paint);
        canvas.drawLine(
          c + Offset(-r * 0.5, -r * 0.35),
          c + Offset(r * 0.5, -r * 0.35),
          paint,
        );
        final hook = Path()
          ..moveTo(c.dx - r * 0.75, c.dy + r * 0.25)
          ..quadraticBezierTo(c.dx - r * 0.75, c.dy + r, c.dx, c.dy + r * 0.75)
          ..quadraticBezierTo(
            c.dx + r * 0.75,
            c.dy + r,
            c.dx + r * 0.75,
            c.dy + r * 0.25,
          );
        canvas.drawPath(hook, paint);
        break;
      case _Glyph.clockHourglass:
        final top = Path()
          ..moveTo(c.dx - r * 0.7, c.dy - r)
          ..lineTo(c.dx + r * 0.7, c.dy - r)
          ..lineTo(c.dx, c.dy)
          ..close();
        final bottom = Path()
          ..moveTo(c.dx - r * 0.7, c.dy + r)
          ..lineTo(c.dx + r * 0.7, c.dy + r)
          ..lineTo(c.dx, c.dy)
          ..close();
        canvas.drawPath(top, paint);
        canvas.drawPath(bottom, paint);
        break;
      case _Glyph.eye:
        final eyePath = Path()
          ..moveTo(c.dx - r, c.dy)
          ..quadraticBezierTo(c.dx, c.dy - r * 0.75, c.dx + r, c.dy)
          ..quadraticBezierTo(c.dx, c.dy + r * 0.75, c.dx - r, c.dy);
        canvas.drawPath(eyePath, paint);
        canvas.drawCircle(c, size.width * 0.07, paint);
        break;
      case _Glyph.plainDot:
        canvas.drawCircle(c, r * 0.5, paint);
        break;
    }
  }

  void _drawBlade(
    Canvas canvas,
    Paint paint,
    Offset c,
    double r, {
    required bool tiltUp,
  }) {
    final dy = tiltUp ? -1.0 : 1.0;
    final from = c + Offset(-r, r * dy * 0.55);
    final to = c + Offset(r, -r * dy * 0.55);
    canvas.drawLine(from, to, paint);
    final dir = (to - from);
    final len = dir.distance;
    final unit = Offset(dir.dx / len, dir.dy / len);
    final perp = Offset(-unit.dy, unit.dx);
    final guardCenter = from + unit * (len * 0.22);
    canvas.drawLine(
      guardCenter - perp * (r * 0.22),
      guardCenter + perp * (r * 0.22),
      paint,
    );
  }

  Path _polygon(Offset c, double r, int sides, {double rotate = -math.pi / 2}) {
    final path = Path();
    for (var i = 0; i < sides; i++) {
      final a = rotate + i * 2 * math.pi / sides;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    return path;
  }

  Path _teardrop(Offset c, double r) {
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + r, c.dy - r * 0.1, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - r, c.dy - r * 0.1, c.dx, c.dy - r);
  }

  void _drawSpiral(Canvas canvas, Paint paint, Offset c, double r) {
    final path = Path();
    const steps = 48;
    const turns = 1.6;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final angle = t * turns * 2 * math.pi;
      final radius = r * t;
      final p = c + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  Path _flame(Offset c, double r) {
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(
        c.dx + r * 0.9,
        c.dy - r * 0.2,
        c.dx + r * 0.4,
        c.dy + r * 0.5,
      )
      ..quadraticBezierTo(
        c.dx + r * 0.35,
        c.dy + r * 0.1,
        c.dx,
        c.dy + r * 0.35,
      )
      ..quadraticBezierTo(
        c.dx - r * 0.35,
        c.dy + r * 0.1,
        c.dx - r * 0.4,
        c.dy + r * 0.5,
      )
      ..quadraticBezierTo(c.dx - r * 0.9, c.dy - r * 0.2, c.dx, c.dy - r);
  }

  Path _bolt(Offset c, double r) {
    return Path()
      ..moveTo(c.dx + r * 0.25, c.dy - r)
      ..lineTo(c.dx - r * 0.45, c.dy + r * 0.15)
      ..lineTo(c.dx + r * 0.05, c.dy + r * 0.15)
      ..lineTo(c.dx - r * 0.25, c.dy + r)
      ..lineTo(c.dx + r * 0.45, c.dy - r * 0.15)
      ..lineTo(c.dx - r * 0.05, c.dy - r * 0.15)
      ..close();
  }

  void _drawChevron(
    Canvas canvas,
    Paint paint,
    Offset c,
    double r, {
    required bool up,
  }) {
    final dir = up ? -1.0 : 1.0;
    for (final dy in [-0.35, 0.35]) {
      final apex = c + Offset(0, dy * r);
      canvas.drawLine(apex + Offset(-r * 0.8, r * 0.4 * dir), apex, paint);
      canvas.drawLine(apex, apex + Offset(r * 0.8, r * 0.4 * dir), paint);
    }
  }

  Path _shield(Offset c, double r) {
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r * 0.8, c.dy - r * 0.55)
      ..lineTo(c.dx + r * 0.8, c.dy + r * 0.15)
      ..quadraticBezierTo(c.dx + r * 0.8, c.dy + r * 0.75, c.dx, c.dy + r)
      ..quadraticBezierTo(
        c.dx - r * 0.8,
        c.dy + r * 0.75,
        c.dx - r * 0.8,
        c.dy + r * 0.15,
      )
      ..lineTo(c.dx - r * 0.8, c.dy - r * 0.55)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}

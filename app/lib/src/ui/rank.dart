import 'package:flutter/material.dart';

import 'palette.dart';

/// A flavor rank shown on a character's portrait, earned through account-
/// wide mission objectives (not yet implemented, see [placeholderRanks]).
enum CharacterRank { s, a, b, c }

extension CharacterRankStyle on CharacterRank {
  String get label => switch (this) {
    CharacterRank.s => 'S',
    CharacterRank.a => 'A',
    CharacterRank.b => 'B',
    CharacterRank.c => 'C',
  };

  Color get color => switch (this) {
    CharacterRank.s => Palette.gold,
    CharacterRank.a => const Color(0xFFD7DCE1),
    CharacterRank.b => const Color(0xFFC98A4A),
    CharacterRank.c => const Color(0xFF9096A1),
  };
}

/// The small rotated rank-flag badge worn on the top-left corner of a
/// portrait tile: a squared-off tag with one angled-notch corner (the
/// "Rift Cyan" panel-corner treatment applied to a small tag), matching
/// the approved reference mockup.
class RankBadge extends StatelessWidget {
  final CharacterRank rank;
  final double size;

  /// Mirror the badge for the opponent's top-right corner: it tilts the
  /// other way (toward the right) and its cut corner is on the bottom
  /// right, so it reflects the player's top-left badge across the screen.
  final bool mirror;

  const RankBadge({
    super.key,
    required this.rank,
    this.size = 26,
    this.mirror = false,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: mirror ? 0.24 : -0.24,
      child: CustomPaint(
        size: Size(size, size * 0.9),
        painter: _RankFlagPainter(rank.color, mirror: mirror),
        child: SizedBox(
          width: size,
          height: size * 0.9,
          child: Align(
            alignment: const Alignment(0, 0.55),
            child: Text(
              rank.label,
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.78),
                fontWeight: FontWeight.w900,
                fontSize: size * 0.42,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RankFlagPainter extends CustomPainter {
  final Color color;
  final bool mirror;
  const _RankFlagPainter(this.color, {this.mirror = false});

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    final notch = size.width * 0.32;

    // A squared-off tag with one bottom corner cut at an angle, rather
    // than a rounded plate with a separate hanging tail. The cut is on the
    // bottom left normally; mirrored (opponent) it moves to the bottom
    // right so the two lanes' badges reflect each other.
    final flag = mirror
        ? (Path()
            ..moveTo(0, 0)
            ..lineTo(size.width, 0)
            ..lineTo(size.width, size.height - notch)
            ..lineTo(size.width - notch, size.height)
            ..lineTo(0, size.height)
            ..close())
        : (Path()
            ..moveTo(0, 0)
            ..lineTo(size.width, 0)
            ..lineTo(size.width, size.height)
            ..lineTo(notch, size.height)
            ..lineTo(0, size.height - notch)
            ..close());
    canvas.drawPath(flag, fill);

    // A thin fold/header line near the top, echoing the reference tag.
    final linePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.24)
      ..strokeWidth = size.height * 0.06;
    final lineY = size.height * 0.32;
    canvas.drawLine(
      Offset(size.width * 0.14, lineY),
      Offset(size.width * 0.86, lineY),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RankFlagPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.mirror != mirror;
}

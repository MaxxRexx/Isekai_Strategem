import 'package:flutter/material.dart';

import 'palette.dart';

/// A flavor rank shown on a character's portrait, earned through account-
/// wide mission objectives (not yet implemented — see [placeholderRanks]).
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

/// The small rotated rank-plate badge worn on the top-left corner of a
/// portrait tile, matching the approved reference mockup.
class RankBadge extends StatelessWidget {
  final CharacterRank rank;
  final double size;
  const RankBadge({super.key, required this.rank, this.size = 26});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.24,
      child: CustomPaint(
        size: Size(size, size * 0.83),
        painter: _RankPlatePainter(rank.color),
        child: SizedBox(
          width: size,
          height: size * 0.83,
          child: Align(
            alignment: const Alignment(0, -0.35),
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

class _RankPlatePainter extends CustomPainter {
  final Color color;
  const _RankPlatePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    final tailFill = Paint()..color = color.withValues(alpha: 0.6);
    final plateHeight = size.height * 0.78;

    final tail = Path()
      ..moveTo(size.width * 0.08, plateHeight)
      ..lineTo(size.width * 0.28, size.height)
      ..lineTo(size.width * 0.42, plateHeight)
      ..close();
    canvas.drawPath(tail, tailFill);

    final plate = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, plateHeight),
      const Radius.circular(3),
    );
    canvas.drawRRect(plate, fill);

    final shade = Paint()..color = Colors.black.withValues(alpha: 0.16);
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.12,
        plateHeight * 0.45,
        size.width * 0.76,
        plateHeight * 0.12,
      ),
      shade,
    );
  }

  @override
  bool shouldRepaint(covariant _RankPlatePainter oldDelegate) =>
      oldDelegate.color != color;
}

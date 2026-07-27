import 'package:flutter/material.dart';

import '../ui/palette.dart';

/// One earned (or not-yet-earned) rank badge shown in [PlayerPanel].
class _RankBadgeData {
  final String label;
  final Color color;
  final bool unlocked;
  const _RankBadgeData(this.label, this.color, this.unlocked);
}

/// Stand-in data for the account-wide mission/rank system - not yet
/// implemented. The actual objectives, rewards, and unlock rules are a
/// separate design pass; this only establishes the UI shell.
const _placeholderRanks = [
  _RankBadgeData('First Win', Palette.warn, true),
  _RankBadgeData('10 Streak', Color(0xFFC7CDD6), true),
  _RankBadgeData('Tutorial', Palette.accent, true),
  _RankBadgeData('Expert Slayer', Color(0xFF6B5B3A), false),
];

/// The player's account summary: title/skill-tier line, equipped hat, and
/// unlocked-rank badges. Shown on the Home screen and the Loadout step.
/// Every value here is a placeholder until the real progression system is
/// designed - see [_placeholderRanks].
class PlayerPanel extends StatelessWidget {
  const PlayerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.panel,
        border: Border.all(color: Palette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                'Player',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Tactician · Novice',
                style: TextStyle(
                  color: Palette.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'EQUIPPED HAT · UNLOCKED RANKS',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 9.5,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final rank in _placeholderRanks) ...[
                Expanded(child: _HatBadge(data: rank)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HatBadge extends StatelessWidget {
  final _RankBadgeData data;
  const _HatBadge({required this.data});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: data.unlocked ? 1 : 0.45,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: data.color.withValues(alpha: 0.22),
              border: Border.all(color: data.color, width: 1.5),
            ),
            child: CustomPaint(painter: _HatGlyphPainter(data.color)),
          ),
          const SizedBox(height: 4),
          Text(
            data.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

/// A small party-hat glyph: a cone with a puff at the tip, standing in for
/// a real cosmetic-hat icon.
class _HatGlyphPainter extends CustomPainter {
  final Color color;
  const _HatGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final c = Offset(size.width / 2, size.height / 2);
    final cone = Path()
      ..moveTo(c.dx, c.dy - size.height * 0.28)
      ..lineTo(c.dx + size.width * 0.22, c.dy + size.height * 0.2)
      ..lineTo(c.dx - size.width * 0.22, c.dy + size.height * 0.2)
      ..close();
    canvas.drawPath(cone, paint);
    canvas.drawCircle(
      c + Offset(0, -size.height * 0.28),
      size.width * 0.045,
      paint,
    );
    canvas.drawLine(
      Offset(c.dx - size.width * 0.26, c.dy + size.height * 0.2),
      Offset(c.dx + size.width * 0.26, c.dy + size.height * 0.2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HatGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}

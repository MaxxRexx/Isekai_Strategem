import 'package:flutter/material.dart';

import '../game/draft.dart';
import '../ui/palette.dart';
import 'portrait_tile.dart';

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

/// Stand-in data for the player's own account profile - level/ladder/
/// record/streak all await the real progression system (see
/// [_placeholderRanks]). A positive streak is a win streak, a negative one
/// a loss streak.
const _playerLevel = 9;
const _playerXp = 2000;
const _playerLadderRank = 12;
const _playerWins = 12;
const _playerLosses = 5;
const _playerStreak = 5;

/// The player's account summary: portrait, title/skill-tier line, level,
/// ladder rank, win-loss record, streak, equipped hat/unlocked ranks, and
/// the current squad's 3 portraits. Shown on the Home screen. Every value
/// here is a placeholder until the real progression system is designed -
/// see [_placeholderRanks] and the player-profile constants above.
class PlayerPanel extends StatelessWidget {
  final List<String> squadIds;

  const PlayerPanel({super.key, this.squadIds = const []});

  @override
  Widget build(BuildContext context) {
    final streakLabel = _playerStreak >= 0
        ? '+$_playerStreak'
        : '$_playerStreak';
    final streakColor = _playerStreak >= 0 ? Palette.good : Palette.danger;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PlayerPortrait(),
              const SizedBox(width: 12),
              Expanded(
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
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 2,
                      children: [
                        _statText('LEVEL', '$_playerLevel ($_playerXp XP)'),
                        _statText('LADDER RANK', '$_playerLadderRank'),
                        _statText('RECORD', '$_playerWins - $_playerLosses'),
                        _statText('STREAK', streakLabel, color: streakColor),
                      ],
                    ),
                  ],
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
          const SizedBox(height: 12),
          const Text(
            'YOUR SQUAD',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10.5,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                i < squadIds.length
                    ? PortraitTile(
                        characterId: squadIds[i],
                        name: roster[squadIds[i]].name,
                        type: roster[squadIds[i]].type,
                        size: 56,
                        showRank: false,
                      )
                    : Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white24,
                          size: 20,
                        ),
                      ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statText(String label, String value, {Color? color}) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(color: Colors.white38, fontSize: 9),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: color ?? Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A generic placeholder portrait for the player's own account - there's
/// no real player-avatar system yet, so this just borrows the app's tile
/// styling with a plain icon instead of a character's initials.
class _PlayerPortrait extends StatelessWidget {
  const _PlayerPortrait();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Palette.gold.withValues(alpha: 0.12),
        border: Border.all(color: Palette.gold, width: 1.5),
      ),
      child: const Icon(Icons.person, color: Palette.gold, size: 30),
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

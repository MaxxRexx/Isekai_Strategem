import 'package:flutter/material.dart';

import '../data/placeholder_ranks.dart';
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

/// The player's own display name - shown here and wherever else the
/// player's identity appears (e.g. the battle screen's top bar), so both
/// stay in sync until a real account/profile system exists.
const playerDisplayName = 'Player';

/// The player's account summary: portrait, title/skill-tier line, level,
/// ladder rank, win-loss record, streak, equipped hat/unlocked ranks, and
/// the current squad's 3 portraits. Shown on the Home screen, sharing a
/// panel with the roster grid ([bordered] false, [compact] true there) or
/// standalone. Every value here is a placeholder until the real
/// progression system is designed - see [_placeholderRanks] and the
/// player-profile constants above.
class PlayerPanel extends StatelessWidget {
  final List<String> squadIds;

  /// Whether this draws its own bordered/background container. Set false
  /// when embedded inside another panel that already provides one (e.g.
  /// sharing the roster grid's border), to avoid a double border.
  final bool bordered;

  /// Shrinks the portrait/hat/squad tile sizes for a narrow side-by-side
  /// layout instead of a full-width standalone section.
  final bool compact;

  /// Called with a squad member's character id when its tile is tapped,
  /// making "YOUR SQUAD" behave like the roster grid's character select
  /// (preview/select that character) instead of being purely decorative.
  /// Null (the default) keeps the tiles non-interactive, e.g. where
  /// there's no roster-preview concept to select into (the Guided
  /// Tutorial's locked squad).
  final ValueChanged<String>? onSquadMemberTap;

  /// Whether to render the "YOUR SQUAD" section. Off when the panel is shown
  /// somewhere the squad is already on screen (e.g. the battle screen's
  /// description panel), so it isn't repeated.
  final bool showSquad;

  const PlayerPanel({
    super.key,
    this.squadIds = const [],
    this.bordered = true,
    this.compact = false,
    this.onSquadMemberTap,
    this.showSquad = true,
  });

  @override
  Widget build(BuildContext context) {
    final streakLabel = _playerStreak >= 0
        ? '+$_playerStreak'
        : '$_playerStreak';
    final streakColor = _playerStreak >= 0 ? Palette.good : Palette.danger;
    final portraitSize = compact ? 40.0 : 56.0;
    final hatSize = compact ? 34.0 : 44.0;
    final squadSize = compact ? 40.0 : 56.0;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PlayerPortrait(size: portraitSize),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playerDisplayName,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: compact ? 13 : 15,
                    ),
                  ),
                  Text(
                    'Tactician · Novice',
                    style: TextStyle(
                      color: Palette.gold,
                      fontSize: compact ? 10.5 : 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 2,
          children: [
            _statText('LEVEL', '$_playerLevel ($_playerXp XP)'),
            _statText('LADDER RANK', '$_playerLadderRank'),
            _statText('RECORD', '$_playerWins - $_playerLosses'),
            _statText('STREAK', streakLabel, color: streakColor),
          ],
        ),
        SizedBox(height: compact ? 10 : 12),
        Text(
          'EQUIPPED HAT · UNLOCKED RANKS',
          style: TextStyle(
            color: Colors.white38,
            fontSize: compact ? 8.5 : 9.5,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final rank in _placeholderRanks)
              _HatBadge(data: rank, size: hatSize),
          ],
        ),
        if (showSquad) ...[
          SizedBox(height: compact ? 10 : 12),
          Text(
            'YOUR SQUAD',
            style: TextStyle(
              color: Colors.white38,
              fontSize: compact ? 9.5 : 10.5,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < 3; i++)
                i < squadIds.length
                    ? _SquadMemberTile(
                        characterId: squadIds[i],
                        size: squadSize,
                        onTap: onSquadMemberTap,
                      )
                    : Container(
                        width: squadSize,
                        height: squadSize,
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
          ),
        ],
      ],
    );

    if (!bordered) return content;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.panel,
        border: Border.all(color: Palette.hairline),
      ),
      child: content,
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

/// One "YOUR SQUAD" preview tile: the same portrait tile used everywhere
/// else the player's own characters appear (showing the account rank, not
/// a per-character one), made tappable like a roster/character-select
/// tile when [onTap] is provided.
class _SquadMemberTile extends StatelessWidget {
  final String characterId;
  final double size;
  final ValueChanged<String>? onTap;

  const _SquadMemberTile({
    required this.characterId,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final character = roster[characterId];
    final tile = PortraitTile(
      characterId: characterId,
      name: character.name,
      type: character.type,
      size: size,
      rank: playerAccountRank,
    );
    final callback = onTap;
    if (callback == null) return tile;
    return InkWell(onTap: () => callback(characterId), child: tile);
  }
}

/// A generic placeholder portrait for the player's own account - there's
/// no real player-avatar system yet, so this just borrows the app's tile
/// styling with a plain icon instead of a character's initials.
class _PlayerPortrait extends StatelessWidget {
  final double size;
  const _PlayerPortrait({this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Palette.gold.withValues(alpha: 0.12),
        border: Border.all(color: Palette.gold, width: 1.5),
      ),
      child: Icon(Icons.person, color: Palette.gold, size: size * 0.54),
    );
  }
}

class _HatBadge extends StatelessWidget {
  final _RankBadgeData data;
  final double size;
  const _HatBadge({required this.data, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: data.unlocked ? 1 : 0.45,
      child: SizedBox(
        width: size + 8,
        child: Column(
          children: [
            Container(
              width: size,
              height: size,
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

import 'package:flutter/material.dart';

import '../game/battle_models.dart';
import '../ui/notched.dart';
import '../ui/rank.dart';
import 'badges.dart';
import 'portrait_tile.dart';

/// One character's line in a team panel: portrait tile, HP bar (value
/// overlaid inside it), name, and status/FAT badges.
///
/// [compact] mirrors the row horizontally (name/status on the left,
/// portrait on the right, right-aligned text) for the opponent lane, so
/// its rows match the player's row height instead of stacking the name
/// below the portrait.
class FighterRow extends StatelessWidget {
  final FighterSnapshot fighter;
  final double portraitSize;
  final bool compact;

  /// Whether this row belongs to the enemy squad. Only read for the Bail Out
  /// pill, whose whole point is what *you* can do about the body, which is a
  /// different thing on each side of the board.
  final bool isOpponent;

  /// Overrides the per-character placeholder rank with a single squad-wide
  /// value (e.g. the opponent's account rank), so every row shows the same
  /// badge instead of varying per character.
  final CharacterRank? rank;

  /// Marks this fighter's portrait as a selected ability target (pulsing
  /// overlay), as a reachable one that has not been picked (steady ring),
  /// and makes it tappable, respectively - used by the battle screen's
  /// portrait-based target picker.
  final bool selected;
  final bool eligible;
  final VoidCallback? onTap;

  const FighterRow({
    super.key,
    required this.fighter,
    this.portraitSize = 64,
    this.compact = false,
    this.isOpponent = false,
    this.rank,
    this.selected = false,
    this.eligible = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final portrait = PortraitHealthBar(
      characterId: fighter.id,
      name: fighter.name,
      type: fighter.type,
      currentHealth: fighter.currentHealth,
      maxHealth: fighter.maxHealth,
      alive: fighter.alive,
      size: portraitSize,
      rank: rank,
      mirrorRank: compact,
      selected: selected,
      eligible: eligible,
      onTap: onTap,
    );
    final nameLine = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            fighter.name,
            overflow: TextOverflow.ellipsis,
            textAlign: compact ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              // A bailing body is neither fighting nor struck off the board,
              // so it gets neither the full white of the living nor the
              // strike-through of the defeated.
              color: fighter.alive
                  ? Colors.white
                  : (fighter.bailingOut ? Colors.white70 : Colors.white38),
              decoration: (fighter.alive || fighter.bailingOut)
                  ? null
                  : TextDecoration.lineThrough,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (fighter.fatTriggered) ...const [SizedBox(width: 4), FatBadge()],
        if (fighter.bailingOut) ...[
          const SizedBox(width: 4),
          BailingOutBadge(isOwnSquad: !isOpponent),
        ],
      ],
    );
    final effects = fighter.statusEffects.isEmpty
        ? null
        : Wrap(
            spacing: 3,
            runSpacing: 3,
            alignment: compact ? WrapAlignment.end : WrapAlignment.start,
            children: [
              for (final s in fighter.statusEffects)
                StatusBadge(
                  name: s.name,
                  remainingTurns: s.remainingTurns,
                  stacks: s.stacks,
                  id: s.id,
                ),
            ],
          );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  nameLine,
                  if (effects != null) ...[const SizedBox(height: 6), effects],
                ],
              ),
            ),
            const SizedBox(width: 10),
            portrait,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          portrait,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                nameLine,
                if (effects != null) ...[const SizedBox(height: 6), effects],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled panel listing a team's fighters.
class TeamPanel extends StatelessWidget {
  final String label;
  final Color color;
  final List<FighterSnapshot> fighters;
  final double portraitSize;
  final bool compact;

  /// Whether this row belongs to the enemy squad. Only read for the Bail Out
  /// pill, whose whole point is what *you* can do about the body, which is a
  /// different thing on each side of the board.
  final bool isOpponent;

  /// A single squad-wide rank for every row (see [FighterRow.rank]).
  final CharacterRank? rank;

  /// Ids of fighters whose portraits are currently selected as ability
  /// targets (pulsing overlay), ids the selected ability could reach but
  /// which have not been picked (steady ring), and a tap handler for
  /// portrait-based target selection. Empty/null leaves the panel
  /// non-interactive.
  final Set<String> selectedIds;
  final Set<String> eligibleIds;
  final void Function(String characterId)? onFighterTap;

  const TeamPanel({
    super.key,
    required this.label,
    required this.color,
    required this.fighters,
    this.portraitSize = 64,
    this.compact = false,
    this.isOpponent = false,
    this.rank,
    this.selectedIds = const {},
    this.eligibleIds = const {},
    this.onFighterTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        color: Theme.of(context).cardColor,
        shape: OpenNotchBorder(side: BorderSide(color: color), notch: 16),
      ),
      child: Column(
        crossAxisAlignment: compact
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 16),
          for (final f in fighters)
            FighterRow(
              fighter: f,
              portraitSize: portraitSize,
              compact: compact,
              isOpponent: isOpponent,
              rank: rank,
              selected: selectedIds.contains(f.id),
              eligible: eligibleIds.contains(f.id),
              onTap: onFighterTap == null ? null : () => onFighterTap!(f.id),
            ),
        ],
      ),
    );
  }
}

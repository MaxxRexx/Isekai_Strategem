import 'package:flutter/material.dart';

import '../game/battle_models.dart';
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

  /// Overrides the per-character placeholder rank with a single squad-wide
  /// value (e.g. the opponent's account rank), so every row shows the same
  /// badge instead of varying per character.
  final CharacterRank? rank;

  const FighterRow({
    super.key,
    required this.fighter,
    this.portraitSize = 64,
    this.compact = false,
    this.rank,
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
              color: fighter.alive ? Colors.white : Colors.white38,
              decoration: fighter.alive ? null : TextDecoration.lineThrough,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (fighter.fatTriggered) ...const [SizedBox(width: 4), FatBadge()],
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
                StatusBadge(name: s.name, remainingTurns: s.remainingTurns),
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

  /// A single squad-wide rank for every row (see [FighterRow.rank]).
  final CharacterRank? rank;

  const TeamPanel({
    super.key,
    required this.label,
    required this.color,
    required this.fighters,
    this.portraitSize = 64,
    this.compact = false,
    this.rank,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: color, width: 3)),
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
              rank: rank,
            ),
        ],
      ),
    );
  }
}

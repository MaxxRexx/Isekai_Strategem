import 'package:flutter/material.dart';

import '../game/battle_models.dart';
import 'badges.dart';
import 'portrait_tile.dart';

/// One character's line in a team panel: portrait tile, HP bar (value
/// overlaid inside it), name, and status/FAT badges.
///
/// [compact] switches to the mirrored, right-aligned column layout used
/// for the narrow opponent lane, where there's no room for a wide row.
class FighterRow extends StatelessWidget {
  final FighterSnapshot fighter;
  final double portraitSize;
  final bool compact;

  const FighterRow({
    super.key,
    required this.fighter,
    this.portraitSize = 64,
    this.compact = false,
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
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            portrait,
            const SizedBox(height: 4),
            nameLine,
            if (effects != null) ...[const SizedBox(height: 4), effects],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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

  const TeamPanel({
    super.key,
    required this.label,
    required this.color,
    required this.fighters,
    this.portraitSize = 64,
    this.compact = false,
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
          const SizedBox(height: 8),
          for (final f in fighters)
            FighterRow(
              fighter: f,
              portraitSize: portraitSize,
              compact: compact,
            ),
        ],
      ),
    );
  }
}

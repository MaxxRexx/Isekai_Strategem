import 'package:flutter/material.dart';

import '../game/battle_models.dart';
import '../ui/palette.dart';
import 'badges.dart';

/// One character's line in a team panel: name, HP bar, HP text, plus
/// FAT/status badges when present.
class FighterRow extends StatelessWidget {
  final FighterSnapshot fighter;
  const FighterRow({super.key, required this.fighter});

  @override
  Widget build(BuildContext context) {
    final frac = fighter.maxHealth > 0
        ? (fighter.currentHealth / fighter.maxHealth).clamp(0.0, 1.0)
        : 0.0;
    final barColor = !fighter.alive
        ? Colors.grey
        : frac <= 0.25
        ? Palette.danger
        : frac <= 0.5
        ? Palette.warn
        : Palette.good;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        fighter.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fighter.alive ? Colors.white : Colors.white38,
                          decoration: fighter.alive
                              ? null
                              : TextDecoration.lineThrough,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    if (fighter.fatTriggered) ...const [
                      SizedBox(width: 4),
                      FatBadge(),
                    ],
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 6,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(barColor),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${fighter.currentHealth}/${fighter.maxHealth}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          if (fighter.statusEffects.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Wrap(
                spacing: 3,
                runSpacing: 2,
                children: [
                  for (final s in fighter.statusEffects)
                    StatusBadge(name: s.name, remainingTurns: s.remainingTurns),
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
  const TeamPanel({
    super.key,
    required this.label,
    required this.color,
    required this.fighters,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          for (final f in fighters) FighterRow(fighter: f),
        ],
      ),
    );
  }
}

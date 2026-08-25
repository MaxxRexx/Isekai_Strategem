import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../data/flavor_text.dart';
import '../ui/palette.dart';
import 'pickers.dart' show CharacterStatRow;
import 'portrait_tile.dart';

/// The character-info + Trion budget/active-ability-count readout shown
/// above a [LoadoutBuilderPanel]: portrait, Side Effect, flavor, and full
/// battle
/// stats, then how much of the character's Trion Capacity is spent,
/// whether the required Active ability count is met, any validation
/// errors, and an optional Auto-fill shortcut. Shared by the Guided
/// Tutorial's Loadout step and the Home screen's inline squad builder.
class LoadoutBudgetPanel extends StatelessWidget {
  final Character character;
  final Loadout loadout;
  final List<String> errors;
  final String? startError;
  final VoidCallback? onAutoFill;

  /// Rendered inside this same bordered panel, below the budget readout -
  /// typically the matching [LoadoutBuilderPanel] (and a squad add/remove
  /// button), so the whole per-character Loadout workflow lives in one box
  /// instead of a separate panel further down the page.
  final Widget? trailing;

  const LoadoutBudgetPanel({
    super.key,
    required this.character,
    required this.loadout,
    this.errors = const [],
    this.startError,
    this.onAutoFill,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final budget = character.baseStats.trionCapacity;
    final totalCost = loadout.totalEquipCost;
    const rules = LoadoutRulesConfig.defaults;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: const Border(top: BorderSide(color: Palette.teamA, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PortraitTile(
                characterId: character.id,
                name: character.name,
                type: character.type,
                size: 64,
                showRank: false,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (character.sideEffect != null)
                      Text(
                        character.sideEffect!.name,
                        style: const TextStyle(
                          color: Palette.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (characterFlavor[character.id] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          characterFlavor[character.id]!,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    CharacterStatRow(stats: character.baseStats),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Trion Capacity $budget',
            style: const TextStyle(
              color: Palette.teamA,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'Trion Cost',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: budget > 0 ? (totalCost / budget).clamp(0, 1) : 0,
                    minHeight: 8,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(
                      totalCost > budget ? Palette.danger : Palette.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$totalCost / $budget',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                'Active Abilities',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(width: 10),
              Text(
                '${loadout.totalActiveAbilityCount} / ${rules.requiredActiveAbilityCount}',
                style: TextStyle(
                  color:
                      loadout.totalActiveAbilityCount ==
                          rules.requiredActiveAbilityCount
                      ? Palette.good
                      : Palette.warn,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (onAutoFill != null)
                TextButton(
                  onPressed: onAutoFill,
                  child: const Text('Auto-fill'),
                ),
            ],
          ),
          if (errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                errors.join(' '),
                style: const TextStyle(color: Palette.danger, fontSize: 11),
              ),
            ),
          if (startError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                startError!,
                style: const TextStyle(color: Palette.danger, fontSize: 11),
              ),
            ),
          if (trailing != null) ...[const SizedBox(height: 12), trailing!],
        ],
      ),
    );
  }
}

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../data/describe.dart';
import '../data/flavor_text.dart';
import '../ui/palette.dart';
import 'game_icons.dart';

/// The rich character card used in pickers and squad slots: type icon,
/// name, stat line, perk, and flavor text.
class CharacterCard extends StatelessWidget {
  final Character character;
  final bool compact;
  const CharacterCard({
    super.key,
    required this.character,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = character;
    final stats = c.baseStats;
    final statPairs = <(String, String)>[
      ('TC', '${stats.trionCapacity}'),
      ('TA', '${stats.trionAffinity}'),
      ('TS', '${stats.teamSpirit}'),
      ('ARM', '${stats.armor}'),
      ('ATK', '${stats.attack}'),
      ('DEF', '${stats.defense}'),
      ('CRIT', '${stats.criticalChance.round()}%'),
      ('FAT', '${stats.fatChance.round()}%'),
      ('INFL', '${stats.statusEffectInfliction}'),
      ('RES', '${stats.statusEffectResistance}'),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          GameIcons.forCharacterType(c.type),
          size: 20,
          color: Palette.accent,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      c.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TypeTag(label: typeLabel[c.type]!),
                ],
              ),
              const SizedBox(height: 3),
              Wrap(
                spacing: 8,
                runSpacing: 1,
                children: [
                  for (final (label, value) in statPairs)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: label,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                            ),
                          ),
                          TextSpan(
                            text: ' $value',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                c.perk?.name ?? 'No perk',
                style: const TextStyle(
                  color: Palette.warn,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!compact) ...[
                if (characterFlavor[c.id] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      characterFlavor[c.id]!,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                if (c.perk != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      c.perk!.description,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class TypeTag extends StatelessWidget {
  final String label;
  const TypeTag({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white54, fontSize: 9),
      ),
    );
  }
}

/// The rich AI profile card: name, skill class tag, description.
class ProfileCard extends StatelessWidget {
  final AiProfile profile;
  const ProfileCard({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                profile.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 6),
            TypeTag(label: skillClassLabel[profile.skillClass]!),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          profile.description,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }
}

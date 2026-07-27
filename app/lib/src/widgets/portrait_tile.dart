import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../data/placeholder_ranks.dart';
import '../ui/palette.dart';
import '../ui/rank.dart';
import 'game_icons.dart';

/// Square portrait tile: a type-colored gradient, the character's
/// initials standing in for real art, a corner badge naming the character
/// type, and a rank-plate badge overlapping the top-left corner. Matches
/// the approved "Rift Cyan" battle-screen and Squad Select mockups.
class PortraitTile extends StatelessWidget {
  final String characterId;
  final String name;
  final CharacterType type;
  final double size;
  final bool showRank;

  const PortraitTile({
    super.key,
    required this.characterId,
    required this.name,
    required this.type,
    this.size = 64,
    this.showRank = true,
  });

  static String initialsFor(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final letters = words.map((w) => w[0].toUpperCase()).take(2).join();
    return letters.isEmpty ? '?' : letters;
  }

  @override
  Widget build(BuildContext context) {
    final (top, bottom) = Palette.tileGradient[type]!;
    final rank = placeholderRanks[characterId];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [top, bottom],
            ),
            border: Border.all(color: Colors.black.withValues(alpha: 0.35)),
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  initialsFor(name),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.bold,
                    fontSize: size * 0.34,
                  ),
                ),
              ),
              Positioned(
                bottom: size * 0.03,
                right: size * 0.03,
                child: Icon(
                  GameIcons.forCharacterType(type),
                  size: size * 0.2,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
        if (showRank && rank != null)
          Positioned(
            top: -size * 0.14,
            left: -size * 0.13,
            child: RankBadge(rank: rank, size: size * 0.42),
          ),
      ],
    );
  }
}

/// The portrait tile plus its HP bar, stacked to a fixed [size] width, with
/// the HP value overlaid on the bar's right edge (not centered on it).
class PortraitHealthBar extends StatelessWidget {
  final String characterId;
  final String name;
  final CharacterType type;
  final int currentHealth;
  final int maxHealth;
  final bool alive;
  final double size;

  const PortraitHealthBar({
    super.key,
    required this.characterId,
    required this.name,
    required this.type,
    required this.currentHealth,
    required this.maxHealth,
    required this.alive,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    final frac = maxHealth > 0
        ? (currentHealth / maxHealth).clamp(0.0, 1.0)
        : 0.0;
    final barColor = !alive
        ? Colors.grey
        : frac <= 0.25
        ? Palette.danger
        : frac <= 0.5
        ? Palette.warn
        : Palette.good;
    return SizedBox(
      width: size,
      child: Column(
        children: [
          Opacity(
            opacity: alive ? 1 : 0.4,
            child: PortraitTile(
              characterId: characterId,
              name: name,
              type: type,
              size: size,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: size,
            height: 13,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              border: Border.all(color: Colors.black.withValues(alpha: 0.5)),
            ),
            child: Stack(
              children: [
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: frac == 0 ? 0.001 : frac,
                  child: Container(color: barColor),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Text(
                      '$currentHealth/$maxHealth',
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

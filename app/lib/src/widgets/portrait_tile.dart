import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../ui/palette.dart';
import 'game_icons.dart';

/// Square portrait tile: a type-colored gradient, the character's
/// initials standing in for real art, and a corner badge naming the
/// character type. Matches the approved "Rift Cyan" battle-screen mockup.
class PortraitTile extends StatelessWidget {
  final String name;
  final CharacterType type;
  final double size;

  const PortraitTile({
    super.key,
    required this.name,
    required this.type,
    this.size = 64,
  });

  static String initialsFor(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final letters = words.map((w) => w[0].toUpperCase()).take(2).join();
    return letters.isEmpty ? '?' : letters;
  }

  @override
  Widget build(BuildContext context) {
    final (top, bottom) = Palette.tileGradient[type]!;
    return Container(
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
    );
  }
}

/// The portrait tile plus its HP bar, stacked to a fixed [size] width, with
/// the HP value overlaid inside the bar (not shown beside it).
class PortraitHealthBar extends StatelessWidget {
  final String name;
  final CharacterType type;
  final int currentHealth;
  final int maxHealth;
  final bool alive;
  final double size;

  const PortraitHealthBar({
    super.key,
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
            child: PortraitTile(name: name, type: type, size: size),
          ),
          Container(
            width: size,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              border: Border.all(color: Colors.black.withValues(alpha: 0.5)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: frac == 0 ? 0.001 : frac,
                  child: Container(color: barColor),
                ),
                Text(
                  '$currentHealth/$maxHealth',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
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

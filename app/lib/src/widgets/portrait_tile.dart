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

  /// Overrides the per-character placeholder rank lookup - pass the
  /// player's own account rank ([playerAccountRank]) when this tile shows
  /// one of the player's own squad members, so it doesn't vary per
  /// character the way an AI opponent's or the roster browser's does.
  final CharacterRank? rank;

  /// Flips the rank badge to the top-right corner - used for the opponent
  /// lane so its badges sit on the outer edge, mirroring the player's
  /// top-left badges across the battle screen's center.
  final bool mirrorRank;

  const PortraitTile({
    super.key,
    required this.characterId,
    required this.name,
    required this.type,
    this.size = 64,
    this.showRank = true,
    this.rank,
    this.mirrorRank = false,
  });

  static String initialsFor(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final letters = words.map((w) => w[0].toUpperCase()).take(2).join();
    return letters.isEmpty ? '?' : letters;
  }

  @override
  Widget build(BuildContext context) {
    final (top, bottom) = Palette.tileGradient[type]!;
    final effectiveRank = rank ?? placeholderRanks[characterId];
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
        if (showRank && effectiveRank != null)
          Positioned(
            top: -size * 0.14,
            left: mirrorRank ? null : -size * 0.13,
            right: mirrorRank ? -size * 0.13 : null,
            child: RankBadge(
              rank: effectiveRank,
              size: size * 0.42,
              mirror: mirrorRank,
            ),
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
  final CharacterRank? rank;
  final bool mirrorRank;

  /// When true, an animated color overlay pulses over the portrait to mark
  /// it as a currently selected ability target.
  final bool selected;

  /// Makes the portrait tappable (target selection / info preview in the
  /// battle screen). Null leaves it non-interactive (Simulate results, etc.).
  final VoidCallback? onTap;

  const PortraitHealthBar({
    super.key,
    required this.characterId,
    required this.name,
    required this.type,
    required this.currentHealth,
    required this.maxHealth,
    required this.alive,
    this.size = 64,
    this.rank,
    this.mirrorRank = false,
    this.selected = false,
    this.onTap,
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
    Widget portrait = Opacity(
      opacity: alive ? 1 : 0.4,
      child: PortraitTile(
        characterId: characterId,
        name: name,
        type: type,
        size: size,
        rank: rank,
        mirrorRank: mirrorRank,
      ),
    );
    if (selected || onTap != null) {
      portrait = Stack(
        children: [
          portrait,
          if (selected)
            const Positioned.fill(
              child: IgnorePointer(child: _SelectionPulse()),
            ),
          if (onTap != null)
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: onTap),
              ),
            ),
        ],
      );
    }
    return SizedBox(
      width: size,
      child: Column(
        children: [
          portrait,
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

/// A pulsing gold overlay laid over a selected portrait, so a chosen
/// ability target reads as an "animated color overlay" rather than a
/// static tint.
class _SelectionPulse extends StatefulWidget {
  const _SelectionPulse();

  @override
  State<_SelectionPulse> createState() => _SelectionPulseState();
}

class _SelectionPulseState extends State<_SelectionPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(
    begin: 0.18,
    end: 0.5,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A gold border is always fully visible so the selection reads clearly
    // at any point in the pulse; the fill breathes on top of it.
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Palette.gold, width: 2.5),
      ),
      child: FadeTransition(
        opacity: _opacity,
        child: const ColoredBox(color: Palette.gold),
      ),
    );
  }
}

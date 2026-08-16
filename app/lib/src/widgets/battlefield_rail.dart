import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../game/battle_models.dart';
import '../ui/palette.dart';

/// The battlefield as six stacked lines, your back line at the top and the
/// opponent's back line at the bottom, with the two front lines meeting at the
/// divider in the middle.
///
/// Stacking them this way makes distance readable off the picture: the gap
/// between an enemy line and yours *is* the distance the range bands are
/// measured in (two lines touching across the divider is distance 0). That is
/// the whole point of the panel - "am I in range?" should be a glance, not a
/// calculation.
///
/// When an ability is selected, [reachFrom] and [reachBand] shade the enemy
/// lines it can actually hit from the position the acting character will be
/// standing in once the queue resolves.
class BattlefieldRail extends StatelessWidget {
  final List<FighterSnapshot> teamA;
  final List<FighterSnapshot> teamB;

  /// Where each of the player's characters will be standing once the queue
  /// resolves, by character id. A character with a queued move is drawn on
  /// their destination line, ghosted, so the plan is visible before it runs.
  final Map<String, BattlePosition> projected;

  /// The selected ability's owner and band, or null when nothing is selected.
  final BattlePosition? reachFrom;
  final RangeTag? reachBand;

  /// Highlighted character (the one whose ability is selected).
  final String? focusedId;

  const BattlefieldRail({
    super.key,
    required this.teamA,
    required this.teamB,
    this.projected = const {},
    this.reachFrom,
    this.reachBand,
    this.focusedId,
  });

  @override
  Widget build(BuildContext context) {
    // Top to bottom: your back line down to your front line, the divider,
    // then the opponent's front line down to their back line.
    const ours = [
      BattlePosition.back,
      BattlePosition.middle,
      BattlePosition.front,
    ];
    const theirs = [
      BattlePosition.front,
      BattlePosition.middle,
      BattlePosition.back,
    ];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: Border.all(color: Palette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'BATTLEFIELD',
            style: TextStyle(
              color: Colors.white54,
              fontWeight: FontWeight.bold,
              fontSize: 10,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          for (final line in ours)
            _line(
              position: line,
              color: Palette.teamA,
              fighters: [
                for (final f in teamA)
                  if ((projected[f.id] ?? f.position) == line) f,
              ],
              moving: {
                for (final f in teamA)
                  if (projected[f.id] != null && projected[f.id] != f.position)
                    f.id,
              },
              inBand: false,
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 5),
            child: Divider(height: 1, thickness: 1, color: Colors.white24),
          ),
          for (final line in theirs)
            _line(
              position: line,
              color: Palette.teamB,
              fighters: [
                for (final f in teamB)
                  if (f.position == line) f,
              ],
              moving: const {},
              inBand: _bandReaches(line),
            ),
          if (reachBand != null) ...[
            const SizedBox(height: 8),
            Text(
              '${reachBand!.label} reaches ${reachBand!.windowLabel}',
              style: const TextStyle(
                color: Palette.accent,
                fontSize: 9,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Whether the selected ability's band covers an enemy standing on [line].
  bool _bandReaches(BattlePosition line) {
    final from = reachFrom;
    final band = reachBand;
    if (from == null || band == null) return false;
    return band.reaches(BattleDistance.betweenEnemies(from, line));
  }

  Widget _line({
    required BattlePosition position,
    required Color color,
    required List<FighterSnapshot> fighters,
    required Set<String> moving,
    required bool inBand,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: inBand ? Palette.accent.withValues(alpha: 0.12) : null,
        border: Border(
          left: BorderSide(
            color: inBand ? Palette.accent : color.withValues(alpha: 0.35),
            width: inBand ? 2 : 1,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              position.label.toUpperCase(),
              style: TextStyle(
                color: color.withValues(alpha: 0.75),
                fontSize: 8,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 3,
              runSpacing: 3,
              children: [
                for (final f in fighters)
                  _token(f, color, ghosted: moving.contains(f.id)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _token(FighterSnapshot fighter, Color color, {required bool ghosted}) {
    final focused = fighter.id == focusedId;
    return Tooltip(
      message: ghosted
          ? '${fighter.name} (moving here this turn)'
          : fighter.name,
      child: Opacity(
        opacity: fighter.alive ? 1 : 0.3,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: focused ? color.withValues(alpha: 0.25) : null,
            border: Border.all(
              color: color.withValues(alpha: ghosted ? 0.45 : 1),
              // A dashed border is not worth a custom painter here: the
              // ghosted token is already set apart by its dimmer edge and
              // the arrow prefix.
              width: focused ? 1.5 : 1,
            ),
          ),
          child: Text(
            '${ghosted ? '> ' : ''}${_initials(fighter.name)}',
            style: TextStyle(
              color: fighter.alive ? Colors.white : Colors.white38,
              fontSize: 9,
              fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
              decoration: fighter.alive ? null : TextDecoration.lineThrough,
            ),
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length.clamp(0, 3));
    }
    return parts.take(2).map((p) => p[0]).join();
  }
}

/// The three lines one character can stand on, as a compact tappable strip.
/// The current (or projected) line is filled; a line one step away is
/// tappable and queues a move there. Anything further is inert, because a
/// Reposition is one step and costs the character an ability use.
class PositionStepper extends StatelessWidget {
  final BattlePosition current;
  final Set<BattlePosition> legal;
  final bool pending;
  final ValueChanged<BattlePosition>? onStep;

  const PositionStepper({
    super.key,
    required this.current,
    required this.legal,
    this.pending = false,
    this.onStep,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final position in BattlePosition.values)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _pip(position),
          ),
        if (pending)
          const Padding(
            padding: EdgeInsets.only(left: 2),
            child: Text(
              'MOVING',
              style: TextStyle(
                color: Palette.warn,
                fontSize: 8,
                letterSpacing: 0.4,
              ),
            ),
          ),
      ],
    );
  }

  Widget _pip(BattlePosition position) {
    final here = position == current;
    final canStep = !here && legal.contains(position) && onStep != null;
    final color = here
        ? Palette.accent
        : canStep
        ? Colors.white70
        : Colors.white24;
    return Tooltip(
      message: here
          ? 'Standing on the ${position.label.toLowerCase()} line'
          : canStep
          ? 'Move to the ${position.label.toLowerCase()} line '
                '(costs an ability use)'
          : '${position.label} is out of one step',
      child: InkWell(
        onTap: canStep ? () => onStep!(position) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: here ? Palette.accent.withValues(alpha: 0.15) : null,
            border: Border.all(color: color),
          ),
          child: Text(
            position.label.substring(0, 1).toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: here ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

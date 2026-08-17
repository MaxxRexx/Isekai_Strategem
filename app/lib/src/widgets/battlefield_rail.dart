import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../game/battle_models.dart';
import '../ui/palette.dart';

/// The battlefield as six cells left to right: your back line on the far left
/// through to the opponent's back line on the far right, with the two front
/// lines meeting at the divider in the middle.
///
/// Laid out horizontally because that is how the two squads face each other on
/// screen, and full width because the distance ruler, the band shading and the
/// move controls all need the room. The gap you see between two cells is the
/// distance the range bands are measured in, so "am I in range" is a glance
/// rather than arithmetic.
///
/// Tapping one of your own cells queues a step to that line, when the step is
/// legal. That makes this the single place position is both read and changed.
class BattlefieldRail extends StatelessWidget {
  final List<FighterSnapshot> teamA;
  final List<FighterSnapshot> teamB;

  /// Where each of your characters will be standing once the queue resolves,
  /// by character id. A character with a queued move is drawn on their
  /// destination, ghosted, so the plan is visible before it runs.
  final Map<String, BattlePosition> projected;

  /// The selected ability's band and the line it is measured from, or null
  /// when nothing is selected. Shades the enemy lines it reaches.
  final BattlePosition? reachFrom;
  final RangeTag? reachBand;

  /// The character whose position the ruler and the move controls refer to.
  final String? focusedId;

  /// Lines [focusedId] could legally step to right now.
  final Set<BattlePosition> legalSteps;

  /// Called when one of your cells is tapped and a step there is legal.
  final ValueChanged<BattlePosition>? onStep;

  const BattlefieldRail({
    super.key,
    required this.teamA,
    required this.teamB,
    this.projected = const {},
    this.reachFrom,
    this.reachBand,
    this.focusedId,
    this.legalSteps = const {},
    this.onStep,
  });

  /// Left to right: your back line in to your front line, then theirs back out.
  static const _ourLines = [
    BattlePosition.back,
    BattlePosition.middle,
    BattlePosition.front,
  ];
  static const _theirLines = [
    BattlePosition.front,
    BattlePosition.middle,
    BattlePosition.back,
  ];

  @override
  Widget build(BuildContext context) {
    final moving = {
      for (final f in teamA)
        if (projected[f.id] != null && projected[f.id] != f.position) f.id,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: Border.all(color: Palette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'BATTLEFIELD',
                style: TextStyle(
                  color: Colors.white54,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 0.7,
                ),
              ),
              const Spacer(),
              if (reachBand != null)
                Text(
                  '${reachBand!.label} reaches ${reachBand!.windowLabel}',
                  style: const TextStyle(
                    color: Palette.accent,
                    fontSize: 10,
                    letterSpacing: 0.3,
                  ),
                )
              else if (onStep != null && legalSteps.isNotEmpty)
                const Text(
                  'Tap a line to move there',
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Horizontal scroll rather than squeezing: six cells plus a divider
          // have a floor below which the names stop being readable.
          LayoutBuilder(
            builder: (context, constraints) {
              final content = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // IntrinsicHeight so every cell matches the tallest one:
                  // stretch alone has no height to stretch to inside a
                  // vertically unbounded column.
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final line in _ourLines)
                          Expanded(child: _ourCell(line, moving)),
                        _divider(),
                        for (final line in _theirLines)
                          Expanded(child: _theirCell(line)),
                      ],
                    ),
                  ),
                  _ruler(),
                ],
              );
              const minWidth = 560.0;
              if (constraints.maxWidth >= minWidth) return content;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: minWidth, child: content),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
    width: 3,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: Colors.white24,
  );

  Widget _ourCell(BattlePosition line, Set<String> moving) {
    final occupants = [
      for (final f in teamA)
        if ((projected[f.id] ?? f.position) == line) f,
    ];
    final canStep = onStep != null && legalSteps.contains(line);
    final standingHere =
        focusedId != null && (projected[focusedId] ?? _liveOf(focusedId!)) == line;

    return _cell(
      label: 'YOUR ${line.label.toUpperCase()}',
      color: Palette.teamA,
      inBand: false,
      highlighted: standingHere,
      stepTarget: canStep,
      onTap: canStep ? () => onStep!(line) : null,
      children: [
        for (final f in occupants)
          _token(f, Palette.teamA, ghosted: moving.contains(f.id)),
      ],
    );
  }

  Widget _theirCell(BattlePosition line) {
    final occupants = [
      for (final f in teamB)
        if (f.position == line) f,
    ];
    return _cell(
      label: 'THEIR ${line.label.toUpperCase()}',
      color: Palette.teamB,
      inBand: _bandReaches(line),
      highlighted: false,
      stepTarget: false,
      onTap: null,
      children: [
        for (final f in occupants) _token(f, Palette.teamB, ghosted: false),
      ],
    );
  }

  BattlePosition _liveOf(String id) {
    for (final f in teamA) {
      if (f.id == id) return f.position;
    }
    return BattlePosition.middle;
  }

  /// Whether the selected ability's band covers an enemy standing on [line].
  bool _bandReaches(BattlePosition line) {
    final from = reachFrom;
    final band = reachBand;
    if (from == null || band == null) return false;
    return band.reaches(BattleDistance.betweenEnemies(from, line));
  }

  Widget _cell({
    required String label,
    required Color color,
    required bool inBand,
    required bool highlighted,
    required bool stepTarget,
    required VoidCallback? onTap,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: inBand
            ? Palette.accent.withValues(alpha: 0.10)
            : highlighted
            ? color.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.02),
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 66),
            padding: const EdgeInsets.fromLTRB(6, 5, 6, 7),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: inBand
                      ? Palette.accent
                      : stepTarget
                      ? color.withValues(alpha: 0.8)
                      : color.withValues(alpha: 0.35),
                  width: inBand || stepTarget ? 2 : 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color.withValues(alpha: 0.75),
                          fontSize: 8,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    if (stepTarget)
                      const Icon(
                        Icons.add_location_alt_outlined,
                        size: 11,
                        color: Palette.teamA,
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(spacing: 3, runSpacing: 3, children: children),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _token(FighterSnapshot fighter, Color color, {required bool ghosted}) {
    final focused = fighter.id == focusedId;
    return Tooltip(
      message: ghosted
          ? '${fighter.name} moves here this turn'
          : '${fighter.name}: ${fighter.currentHealth}/${fighter.maxHealth}',
      child: Opacity(
        opacity: fighter.alive ? 1 : 0.3,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: focused ? color.withValues(alpha: 0.22) : null,
            border: Border.all(
              color: color.withValues(alpha: ghosted ? 0.5 : 1),
              width: focused ? 1.5 : 1,
            ),
          ),
          child: Text(
            '${ghosted ? '> ' : ''}${_shortName(fighter.name)}',
            style: TextStyle(
              color: fighter.alive ? Colors.white : Colors.white38,
              fontSize: 9.5,
              fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
              decoration: fighter.alive ? null : TextDecoration.lineThrough,
            ),
          ),
        ),
      ),
    );
  }

  /// The distance from the focused character's projected line to each enemy
  /// line, printed under the enemy half. This is the number the range bands
  /// are compared against, so showing it removes the arithmetic entirely.
  Widget _ruler() {
    final from = focusedId == null
        ? null
        : (projected[focusedId] ?? _liveOf(focusedId!));
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          for (var i = 0; i < _ourLines.length; i++)
            const Expanded(child: SizedBox()),
          const SizedBox(width: 11),
          for (final line in _theirLines)
            Expanded(
              child: _rulerCell(
                from == null
                    ? null
                    : BattleDistance.betweenEnemies(from, line),
                inBand: _bandReaches(line),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rulerCell(int? distance, {required bool inBand}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        padding: const EdgeInsets.only(top: 3),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: inBand ? Palette.accent : Palette.hairline,
            ),
          ),
        ),
        child: Text(
          distance == null ? ' ' : '$distance',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: inBand ? Palette.accent : Colors.white38,
            fontSize: 9.5,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  static String _shortName(String name) {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.first;
  }
}

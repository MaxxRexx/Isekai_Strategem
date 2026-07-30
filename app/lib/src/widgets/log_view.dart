import 'package:flutter/material.dart';

import '../game/battle_models.dart';
import '../ui/palette.dart';

/// The scrollable battle log: one block per team turn, one line per
/// (action, target) pair, mirroring the HTML demo's log composition.
class BattleLogView extends StatefulWidget {
  final List<LogRound> rounds;
  final String title;

  /// Team labels in round headings ('Squad A'/'Squad B' for Simulate,
  /// 'You'/'Opponent' for Play mode).
  final String teamAName;
  final String teamBName;

  /// Height of the scrollable log body when the panel is expanded.
  final double bodyHeight;

  /// Whether the dropdown starts expanded, in uncontrolled mode. Ignored
  /// when [open] is provided (controlled mode).
  final bool initiallyOpen;

  /// Controlled open state. When non-null, the caller owns the open/closed
  /// state (so it survives this widget being rebuilt as siblings come and
  /// go) and must update it via [onToggle]. When null, the widget keeps its
  /// own state seeded from [initiallyOpen].
  final bool? open;
  final VoidCallback? onToggle;

  const BattleLogView({
    super.key,
    required this.rounds,
    this.title = 'BATTLE LOG',
    this.teamAName = 'Squad A',
    this.teamBName = 'Squad B',
    this.bodyHeight = 260,
    this.initiallyOpen = true,
    this.open,
    this.onToggle,
  });

  @override
  State<BattleLogView> createState() => _BattleLogViewState();
}

class _BattleLogViewState extends State<BattleLogView> {
  // Uncontrolled fallback state (used only when widget.open is null).
  late bool _internalOpen = widget.initiallyOpen;

  bool get _open => widget.open ?? _internalOpen;

  void _toggle() {
    if (widget.onToggle != null) {
      widget.onToggle!();
    } else {
      setState(() => _internalOpen = !_internalOpen);
    }
  }

  int get _eventCount {
    var count = 0;
    for (final round in widget.rounds) {
      count += round.actions.isEmpty
          ? 1
          : round.actions.fold<int>(
              0,
              (sum, a) => sum + a.targets.length.clamp(1, 99),
            );
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '$_eventCount events',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _open ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const Divider(height: 1, color: Colors.white12),
            SizedBox(
              height: widget.bodyHeight,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: widget.rounds.length,
                itemBuilder: (context, i) => RoundEntry(
                  round: widget.rounds[i],
                  teamAName: widget.teamAName,
                  teamBName: widget.teamBName,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class RoundEntry extends StatelessWidget {
  final LogRound round;
  final String teamAName;
  final String teamBName;
  const RoundEntry({
    super.key,
    required this.round,
    this.teamAName = 'Squad A',
    this.teamBName = 'Squad B',
  });

  @override
  Widget build(BuildContext context) {
    final actorColor = round.team == 'A' ? Palette.teamA : Palette.teamB;
    final teamName = round.team == 'A' ? teamAName : teamBName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '- Round ${round.roundNumber}, $teamName -',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          if (round.actions.isEmpty)
            const Text(
              '(no legal action taken)',
              style: TextStyle(
                color: Colors.white38,
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
            ),
          for (final action in round.actions)
            for (final t in action.targets)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: LogLine(action: action, target: t, color: actorColor),
              ),
        ],
      ),
    );
  }
}

class LogLine extends StatefulWidget {
  final LogAction action;
  final LogTargetResult target;
  final Color color;
  const LogLine({
    super.key,
    required this.action,
    required this.target,
    required this.color,
  });

  @override
  State<LogLine> createState() => _LogLineState();
}

class _LogLineState extends State<LogLine> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final t = widget.target;
    final rollBits = <String>[
      if (t.crits > 0) '${t.crits} crit',
      if (t.hits - t.crits - t.misses > 0) '${t.hits - t.crits - t.misses} hit',
      if (t.misses > 0) '${t.misses} miss',
    ];
    final hasBreakdown = t.rolls.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                  children: [
                    TextSpan(
                      text: action.characterName,
                      style: TextStyle(
                        color: widget.color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (action.fatTriggered)
                      const TextSpan(
                        text: ' [FAT]',
                        style: TextStyle(
                          color: Palette.warn,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const TextSpan(text: ' uses '),
                    TextSpan(
                      text: action.triggerName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: ' on ${t.targetName}'),
                    if (rollBits.isNotEmpty)
                      TextSpan(text: ' (${rollBits.join(', ')})'),
                    if (t.damage > 0)
                      TextSpan(
                        text: ' ${t.damage} dmg',
                        style: const TextStyle(color: Palette.danger),
                      ),
                    if (t.statusEffectsApplied.isNotEmpty)
                      TextSpan(
                        text: ' [${t.statusEffectsApplied.join(', ')}]',
                        style: const TextStyle(color: Palette.accent),
                      ),
                    TextSpan(text: ' -> HP ${t.healthAfter}'),
                    if (t.died)
                      const TextSpan(
                        text: ' DEFEATED',
                        style: TextStyle(
                          color: Palette.danger,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (hasBreakdown)
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: Colors.white38,
                  ),
                ),
              ),
          ],
        ),
        if (_expanded && hasBreakdown) RollBreakdownView(rolls: t.rolls),
      ],
    );
  }
}

/// The exact roll-by-roll math behind one Battle Log line, revealed by its
/// expand button - what actually decided a hit/crit/miss and how much
/// damage it dealt.
class RollBreakdownView extends StatelessWidget {
  final List<LogRollBreakdown> rolls;
  const RollBreakdownView({super.key, required this.rolls});

  String _outcomeLabel(LogRollBreakdown b) {
    if (b.isCriticalMiss) return 'CRIT MISS';
    if (b.isCriticalHit) return 'CRIT HIT';
    return b.isHit ? 'HIT' : 'MISS';
  }

  Color _outcomeColor(LogRollBreakdown b) {
    if (b.isCriticalMiss) return Palette.danger;
    if (b.isCriticalHit) return Palette.good;
    return b.isHit ? Palette.accent : Colors.white38;
  }

  /// The damage-formula trail as its own line: the Trigger's own damage
  /// dice roll (entirely separate from the ATK/DEF roll above, which only
  /// ever decides hit/miss/crit) through Team Spirit/crit/Armor/
  /// resistance to the final number - each step only shown if it actually
  /// applied, so a plain hit reads as just "roll = total = X dmg".
  List<InlineSpan> _damageFormulaSpans(LogDamageDetail d) {
    const stepStyle = TextStyle(color: Colors.white54);
    const arrow = TextSpan(text: '  ->  ', style: stepStyle);

    if (d.prevented) {
      return const [
        TextSpan(text: 'Damage roll: '),
        TextSpan(
          text: 'PREVENTED',
          style: TextStyle(color: Palette.accent, fontWeight: FontWeight.bold),
        ),
      ];
    }

    final spans = <InlineSpan>[
      TextSpan(text: 'Damage roll: ${d.diceDescribe} = ${d.diceTotal}'),
    ];

    final afterMultiplier = (d.diceTotal * d.preCritMultiplier).round();
    if (d.preCritMultiplier != 1.0) {
      spans.add(arrow);
      spans.add(
        TextSpan(
          text: '×${d.preCritMultiplier.toStringAsFixed(2)} = $afterMultiplier',
        ),
      );
    }

    if (d.criticalHitApplied) {
      spans.add(arrow);
      spans.add(
        TextSpan(
          text:
              'CRIT ×${d.criticalHitMultiplier.toStringAsFixed(0)} = '
              '${d.afterCriticalHit}',
          style: const TextStyle(color: Palette.good),
        ),
      );
    }

    spans.add(arrow);
    spans.add(TextSpan(text: 'Armor −${d.armor} = ${d.afterArmor}'));

    if (d.statusDamageTypeMultiplier != 1.0 || d.damageResistanceApplied) {
      final combined =
          d.statusDamageTypeMultiplier * (d.damageResistanceApplied ? 0.5 : 1);
      spans.add(arrow);
      spans.add(TextSpan(text: '×${combined.toStringAsFixed(2)}'));
    }

    spans.add(arrow);
    spans.add(
      TextSpan(
        text: '${d.finalDamage} dmg',
        style: const TextStyle(
          color: Palette.danger,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        border: const Border(left: BorderSide(color: Palette.accent, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rolls.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i > 0 ? 6 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      children: [
                        if (rolls.length > 1) TextSpan(text: 'Roll ${i + 1}: '),
                        TextSpan(text: 'ATK ${rolls[i].attackerRoll.describe}'),
                        const TextSpan(text: '  vs  '),
                        TextSpan(text: 'DEF ${rolls[i].defenderRoll.describe}'),
                        const TextSpan(text: '  '),
                        TextSpan(
                          text: _outcomeLabel(rolls[i]),
                          style: TextStyle(
                            color: _outcomeColor(rolls[i]),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (rolls[i].damageDetail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 8),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white54,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                          children: _damageFormulaSpans(rolls[i].damageDetail!),
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

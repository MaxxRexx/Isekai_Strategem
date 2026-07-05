import 'package:flutter/material.dart';

import '../game/battle_models.dart';
import '../ui/palette.dart';

/// The scrollable battle log: one block per team turn, one line per
/// (action, target) pair, mirroring the HTML demo's log composition.
class BattleLogView extends StatelessWidget {
  final List<LogRound> rounds;
  final String title;

  /// Team labels in round headings ('Squad A'/'Squad B' for Simulate,
  /// 'You'/'Opponent' for Play mode).
  final String teamAName;
  final String teamBName;

  const BattleLogView({
    super.key,
    required this.rounds,
    this.title = 'BATTLE LOG',
    this.teamAName = 'Squad A',
    this.teamBName = 'Squad B',
  });

  int get _eventCount {
    var count = 0;
    for (final round in rounds) {
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  '$_eventCount events',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: rounds.length,
              itemBuilder: (context, i) => RoundEntry(
                round: rounds[i],
                teamAName: teamAName,
                teamBName: teamBName,
              ),
            ),
          ),
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

class LogLine extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final t = target;
    final rollBits = <String>[
      if (t.crits > 0) '${t.crits} crit',
      if (t.hits - t.crits - t.misses > 0) '${t.hits - t.crits - t.misses} hit',
      if (t.misses > 0) '${t.misses} miss',
    ];
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12, color: Colors.white70),
        children: [
          TextSpan(
            text: action.characterName,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          if (action.fatTriggered)
            const TextSpan(
              text: ' [FAT]',
              style: TextStyle(
                color: Palette.warn,
                fontWeight: FontWeight.bold,
              ),
            ),
          TextSpan(text: ' uses '),
          TextSpan(
            text: action.triggerName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: ' on ${t.targetName}'),
          if (rollBits.isNotEmpty) TextSpan(text: ' (${rollBits.join(', ')})'),
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
    );
  }
}

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../widgets/log_view.dart' show RollBreakdownView;
import 'quick_battle_controller.dart';
import 'quick_battle_result.dart';

class QuickBattleScreen extends StatefulWidget {
  const QuickBattleScreen({super.key});

  @override
  State<QuickBattleScreen> createState() => _QuickBattleScreenState();
}

class _QuickBattleScreenState extends State<QuickBattleScreen> {
  late QuickBattleResult _result;

  @override
  void initState() {
    super.initState();
    _result = runQuickBattle();
  }

  void _runAnother() {
    setState(() => _result = runQuickBattle());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quick Battle')),
      body: SafeArea(
        child: Column(
          children: [
            _OutcomeBanner(result: _result),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _TeamPanel(
                      label: 'Squad A',
                      color: const Color(0xFF34D1C8),
                      fighters: _result.finalTeamA,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TeamPanel(
                      label: 'Squad B',
                      color: const Color(0xFFFF8A52),
                      fighters: _result.finalTeamB,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _BattleLog(rounds: _result.rounds)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: _runAnother,
                child: const Text('RUN ANOTHER BATTLE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutcomeBanner extends StatelessWidget {
  final QuickBattleResult result;
  const _OutcomeBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (result.outcome) {
      BattleOutcome.teamAWins => ('SQUAD A WINS', const Color(0xFF34D1C8)),
      BattleOutcome.teamBWins => ('SQUAD B WINS', const Color(0xFFFF8A52)),
      BattleOutcome.draw => ('MUTUAL DEFEAT', Colors.grey),
      BattleOutcome.ongoing => (
        'NO CONCLUSION REACHED',
        const Color(0xFFFFAB4D),
      ),
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 4)),
        color: Theme.of(context).cardColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          Text(
            result.concluded
                ? 'Concluded in ${result.roundsPlayed} round(s).'
                : 'Still contesting after ${result.roundsPlayed} round(s) (cap reached).',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TeamPanel extends StatelessWidget {
  final String label;
  final Color color;
  final List<QuickBattleFighter> fighters;
  const _TeamPanel({
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
          for (final f in fighters) _FighterRow(fighter: f),
        ],
      ),
    );
  }
}

class _FighterRow extends StatelessWidget {
  final QuickBattleFighter fighter;
  const _FighterRow({required this.fighter});

  @override
  Widget build(BuildContext context) {
    final frac = fighter.maxHealth > 0
        ? (fighter.currentHealth / fighter.maxHealth).clamp(0.0, 1.0)
        : 0.0;
    final barColor = !fighter.alive
        ? Colors.grey
        : frac <= 0.25
        ? const Color(0xFFFF5468)
        : frac <= 0.5
        ? const Color(0xFFFFAB4D)
        : const Color(0xFF57D98A);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              fighter.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fighter.alive ? Colors.white : Colors.white38,
                decoration: fighter.alive ? null : TextDecoration.lineThrough,
                fontSize: 12.5,
              ),
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
    );
  }
}

class _BattleLog extends StatelessWidget {
  final List<QuickBattleRound> rounds;
  const _BattleLog({required this.rounds});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              'BATTLE LOG',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: rounds.length,
              itemBuilder: (context, i) => _RoundEntry(round: rounds[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundEntry extends StatelessWidget {
  final QuickBattleRound round;
  const _RoundEntry({required this.round});

  @override
  Widget build(BuildContext context) {
    final actorColor = round.team == 'A'
        ? const Color(0xFF34D1C8)
        : const Color(0xFFFF8A52);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '- Round ${round.roundNumber}, Squad ${round.team} -',
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
                child: _QuickLogLine(
                  action: action,
                  target: t,
                  color: actorColor,
                ),
              ),
        ],
      ),
    );
  }
}

/// One (action, target) line, expandable to reveal the exact roll-by-roll
/// breakdown behind its hit/crit/miss/damage summary.
class _QuickLogLine extends StatefulWidget {
  final QuickBattleAction action;
  final QuickBattleTargetResult target;
  final Color color;

  const _QuickLogLine({
    required this.action,
    required this.target,
    required this.color,
  });

  @override
  State<_QuickLogLine> createState() => _QuickLogLineState();
}

class _QuickLogLineState extends State<_QuickLogLine> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final t = widget.target;
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
                          color: Color(0xFFFFAB4D),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    TextSpan(
                      text: ' uses ${action.triggerName} on ${t.targetName}',
                    ),
                    if (t.crits > 0)
                      TextSpan(
                        text: ' ${t.crits} crit',
                        style: const TextStyle(color: Color(0xFFFFAB4D)),
                      ),
                    if (t.damage > 0) TextSpan(text: ' ${t.damage} dmg'),
                    if (t.statusEffectsApplied.isNotEmpty)
                      TextSpan(
                        text: ' [${t.statusEffectsApplied.join(', ')}]',
                        style: const TextStyle(color: Color(0xFF34D1C8)),
                      ),
                    TextSpan(text: ' -> HP ${t.healthAfter}'),
                    if (t.died)
                      const TextSpan(
                        text: ' DEFEATED',
                        style: TextStyle(
                          color: Color(0xFFFF5468),
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
        if (_expanded && hasBreakdown)
          RollBreakdownView(
            actorName: action.characterName,
            abilityName: action.triggerName,
            targetName: t.targetName,
            rolls: t.rolls,
            statusEffectsApplied: t.statusEffectsApplied,
            healthAfter: t.healthAfter,
            died: t.died,
          ),
      ],
    );
  }
}

import 'package:battle_engine/battle_engine.dart';

import '../widgets/outcome_banner.dart';
import 'battle_models.dart';
import 'draft.dart';
import 'simulate.dart';

String _logLines(List<LogRound> rounds, String Function(String team) teamName) {
  final buf = StringBuffer();
  for (final round in rounds) {
    buf.writeln('Round ${round.roundNumber}, ${teamName(round.team)}:');
    if (round.actions.isEmpty) {
      buf.writeln('  (no legal action taken)');
      continue;
    }
    for (final action in round.actions) {
      for (final t in action.targets) {
        final bits = <String>[
          if (t.crits > 0) '${t.crits} crit',
          if (t.hits - t.crits - t.misses > 0)
            '${t.hits - t.crits - t.misses} hit',
          if (t.misses > 0) '${t.misses} miss',
        ];
        final entry = StringBuffer(
          '  ${action.characterName}'
          '${action.fatTriggered ? ' [FAT]' : ''}'
          ' uses ${action.triggerName} on ${t.targetName}'
          ' (${bits.join(', ')})',
        );
        if (t.damage > 0) entry.write(' ${t.damage} dmg');
        if (t.statusEffectsApplied.isNotEmpty) {
          entry.write(' [${t.statusEffectsApplied.join(', ')}]');
        }
        entry.write(' -> HP ${t.healthAfter}');
        if (t.died) entry.write(' DEFEATED');
        buf.writeln(entry);
      }
    }
  }
  return buf.toString();
}

String _finalStateLines(List<FighterSnapshot> fighters) => [
  for (final f in fighters)
    '  ${f.name}: ${f.currentHealth}/${f.maxHealth}'
        '${f.alive ? '' : ' (defeated)'}',
].join('\n');

String _loadoutLines(Map<String, Loadout> loadouts) {
  final buf = StringBuffer();
  for (final entry in loadouts.entries) {
    buf.writeln('${roster[entry.key].name}:');
    buf.writeln('  Black Trigger: ${entry.value.blackTrigger?.name ?? 'none'}');
    buf.writeln(
      '  Triggers: ${entry.value.triggers.map((t) => t.name).join(', ')}',
    );
  }
  return buf.toString();
}

/// The plain-text engagement report for a completed simulation, meant to
/// be copied and pasted back to Claude for balance analysis.
String buildSimulationReport(SimulationConfig config, SimulationResult result) {
  final (outcomeText, _) = outcomeCopy(result.outcome);
  return '''
=== Isekai Strategem Engagement Report ===

Squad A: ${config.teamAIds.map((id) => roster[id].name).join(', ')}  [AI: ${profileById(config.teamAProfileId).name}]
Squad B: ${config.teamBIds.map((id) => roster[id].name).join(', ')}  [AI: ${profileById(config.teamBProfileId).name}]
Round cap: ${config.maxRounds}

OUTCOME: $outcomeText${result.concluded ? ' (concluded in ${result.roundsPlayed} round(s))' : ' (round cap reached after ${result.roundsPlayed} round(s), not concluded)'}

--- Final State ---
Squad A:
${_finalStateLines(result.finalTeamA)}
Squad B:
${_finalStateLines(result.finalTeamB)}

--- Drafted Loadouts ---
${_loadoutLines({...result.teamALoadouts, ...result.teamBLoadouts})}
--- Engagement Log ---
${_logLines(result.rounds, (team) => team == 'A' ? 'Squad A' : 'Squad B')}''';
}

/// The plain-text report for a finished Play mode session.
String buildPlayReport({
  required List<String> playerIds,
  required List<String> opponentIds,
  required String opponentProfileId,
  required BattleOutcome outcome,
  required int roundNumber,
  required List<FighterSnapshot> teamA,
  required List<FighterSnapshot> teamB,
  required Map<String, Loadout> loadouts,
  required List<LogRound> rounds,
}) {
  final (outcomeText, _) = outcomeCopy(outcome);
  return '''
=== Isekai Strategem Play Session Report ===

Your Squad: ${playerIds.map((id) => roster[id].name).join(', ')}
Opponent Squad: ${opponentIds.map((id) => roster[id].name).join(', ')}  [AI: ${profileById(opponentProfileId).name}]

OUTCOME: $outcomeText (concluded in $roundNumber round(s))

--- Final State ---
Your Squad:
${_finalStateLines(teamA)}
Opponent Squad:
${_finalStateLines(teamB)}

--- Loadouts ---
${_loadoutLines(loadouts)}
--- Battle Log ---
${_logLines(rounds, (team) => team == 'A' ? 'You' : 'Opponent')}''';
}

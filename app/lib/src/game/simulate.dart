import 'package:battle_engine/battle_engine.dart';

import 'battle_models.dart';
import 'draft.dart';
import 'team_efficiency.dart';

class SimulationConfig {
  final List<String> teamAIds;
  final List<String> teamBIds;
  final String teamAProfileId;
  final String teamBProfileId;
  final int maxRounds;

  const SimulationConfig({
    required this.teamAIds,
    required this.teamBIds,
    required this.teamAProfileId,
    required this.teamBProfileId,
    this.maxRounds = 40,
  });
}

/// Runs one full AI-vs-AI battle, collecting a turn-by-turn log for the
/// UI to render, up to [SimulationConfig.maxRounds] (a battle that hasn't
/// concluded by then reports `concluded: false` rather than looping
/// forever).
SimulationResult runSimulation(SimulationConfig config) {
  final teamADraft = DraftedTeam.draftWithProfile(
    teamId: 'team-a',
    characterIds: config.teamAIds,
    profile: profileById(config.teamAProfileId),
  );
  final teamBDraft = DraftedTeam.draftWithProfile(
    teamId: 'team-b',
    characterIds: config.teamBIds,
    profile: profileById(config.teamBProfileId),
  );
  final teamAAi = ProfileDrivenAi(profileById(config.teamAProfileId));
  final teamBAi = ProfileDrivenAi(profileById(config.teamBProfileId));

  // The opening turn is weighted by each squad's Team Efficiency Grade, the
  // same rule the player-facing session uses (see `openingTurnChanceFor`).
  final teamAEfficiency = computeTeamEfficiency(
    characterIds: config.teamAIds,
    loadouts: teamADraft.loadoutsByCharacterId,
  );
  final teamBEfficiency = computeTeamEfficiency(
    characterIds: config.teamBIds,
    loadouts: teamBDraft.loadoutsByCharacterId,
  );

  final battle = Battle(
    teamA: teamADraft.team,
    teamB: teamBDraft.team,
    states: {...teamADraft.states, ...teamBDraft.states},
    teamAGoesFirst:
        rollsOpeningTurn(teamAEfficiency.tier, teamBEfficiency.tier),
  );

  final rounds = <LogRound>[];
  var concluded = false;

  for (var i = 0; i < config.maxRounds * 2; i++) {
    if (battle.isOver) {
      concluded = true;
      break;
    }

    final teamLabel = battle.isTeamATurn ? 'A' : 'B';
    final activeDraft = battle.isTeamATurn ? teamADraft : teamBDraft;
    final activeAi = battle.isTeamATurn ? teamAAi : teamBAi;

    battle.startTurn(
      equippedActiveTriggers: activeDraft.equippedActiveTriggers,
    );
    if (battle.isOver) {
      rounds.add(
        LogRound(
          roundNumber: battle.roundNumber,
          team: teamLabel,
          actions: const [],
        ),
      );
      concluded = true;
      break;
    }

    final actionResults = activeAi.takeTurn(
      battle,
      equippedActiveTriggers: activeDraft.equippedActiveTriggers,
    );

    rounds.add(
      LogRound(
        roundNumber: battle.roundNumber,
        team: teamLabel,
        actions: [
          for (final result in actionResults)
            logActionFor(
              battle,
              activeDraft.equippedActiveTriggers[result.characterId]!
                  .firstWhere((t) => t.id == result.triggerId),
              result,
            ),
        ],
      ),
    );

    if (battle.isOver) {
      concluded = true;
      break;
    }
    battle.endTurn();
  }

  return SimulationResult(
    concluded: concluded,
    outcome: battle.outcome,
    roundsPlayed: battle.roundNumber,
    rounds: rounds,
    finalTeamA: [
      for (final s in battle.statesOf(teamADraft.team)) fighterSnapshot(s),
    ],
    finalTeamB: [
      for (final s in battle.statesOf(teamBDraft.team)) fighterSnapshot(s),
    ],
    teamALoadouts: teamADraft.loadouts,
    teamBLoadouts: teamBDraft.loadouts,
  );
}

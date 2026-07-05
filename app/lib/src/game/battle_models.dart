import 'package:battle_engine/battle_engine.dart';

/// UI-facing result of one ability use against one target, mirroring the
/// per-target log entries the engine's [TargetHitResult] describes but
/// flattened to plain display values.
class LogTargetResult {
  final String targetId;
  final String targetName;
  final int hits;
  final int crits;
  final int misses;
  final int damage;
  final List<String> statusEffectsApplied; // display names, not ids
  final int healthAfter;
  final bool died;

  const LogTargetResult({
    required this.targetId,
    required this.targetName,
    required this.hits,
    required this.crits,
    required this.misses,
    required this.damage,
    required this.statusEffectsApplied,
    required this.healthAfter,
    required this.died,
  });
}

/// One ability use by one character (either side) in the battle log.
class LogAction {
  final String characterId;
  final String characterName;
  final String triggerId;
  final String triggerName;
  final bool fatTriggered;
  final List<LogTargetResult> targets;

  const LogAction({
    required this.characterId,
    required this.characterName,
    required this.triggerId,
    required this.triggerName,
    required this.fatTriggered,
    required this.targets,
  });
}

/// One team's turn within a round, holding every action taken in it.
class LogRound {
  final int roundNumber;
  final String team; // 'A' or 'B'
  final List<LogAction> actions;

  const LogRound({
    required this.roundNumber,
    required this.team,
    required this.actions,
  });
}

/// A character's live state as shown in the battle UI.
class FighterSnapshot {
  final String id;
  final String name;
  final int currentHealth;
  final int maxHealth;
  final bool alive;
  final bool fatTriggered;
  final List<StatusBadgeInfo> statusEffects;

  const FighterSnapshot({
    required this.id,
    required this.name,
    required this.currentHealth,
    required this.maxHealth,
    required this.alive,
    this.fatTriggered = false,
    this.statusEffects = const [],
  });
}

class StatusBadgeInfo {
  final String id;
  final String name;
  final int? remainingTurns;

  const StatusBadgeInfo({
    required this.id,
    required this.name,
    required this.remainingTurns,
  });
}

/// Everything an AI-vs-AI simulation produces for the results UI.
class SimulationResult {
  final bool concluded;
  final BattleOutcome outcome;
  final int roundsPlayed;
  final List<LogRound> rounds;
  final List<FighterSnapshot> finalTeamA;
  final List<FighterSnapshot> finalTeamB;
  final Map<String, Loadout> teamALoadouts;
  final Map<String, Loadout> teamBLoadouts;

  const SimulationResult({
    required this.concluded,
    required this.outcome,
    required this.roundsPlayed,
    required this.rounds,
    required this.finalTeamA,
    required this.finalTeamB,
    required this.teamALoadouts,
    required this.teamBLoadouts,
  });
}

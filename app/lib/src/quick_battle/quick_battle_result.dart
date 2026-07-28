import 'package:battle_engine/battle_engine.dart';

import '../game/battle_models.dart' show LogRollBreakdown;

/// One target hit within a single [QuickBattleAction], rendering-ready.
class QuickBattleTargetResult {
  final String targetName;
  final int hits;
  final int crits;
  final int misses;
  final int damage;
  final List<String> statusEffectsApplied;
  final int healthAfter;
  final int maxHealth;
  final bool died;

  /// The full per-roll breakdown behind [hits]/[crits]/[misses]/[damage].
  final List<LogRollBreakdown> rolls;

  const QuickBattleTargetResult({
    required this.targetName,
    required this.hits,
    required this.crits,
    required this.misses,
    required this.damage,
    required this.statusEffectsApplied,
    required this.healthAfter,
    required this.maxHealth,
    required this.died,
    this.rolls = const [],
  });
}

/// One character's ability use, resolved against 1+ targets.
class QuickBattleAction {
  final String characterName;
  final String triggerName;
  final bool fatTriggered;
  final List<QuickBattleTargetResult> targets;

  const QuickBattleAction({
    required this.characterName,
    required this.triggerName,
    required this.fatTriggered,
    required this.targets,
  });
}

/// Every action taken during one team's turn.
class QuickBattleRound {
  final int roundNumber;
  final String team;
  final List<QuickBattleAction> actions;

  const QuickBattleRound({
    required this.roundNumber,
    required this.team,
    required this.actions,
  });
}

/// A snapshot of one character's health at the end of the battle.
class QuickBattleFighter {
  final String name;
  final int currentHealth;
  final int maxHealth;
  final bool alive;

  const QuickBattleFighter({
    required this.name,
    required this.currentHealth,
    required this.maxHealth,
    required this.alive,
  });
}

/// The full outcome of a [runQuickBattle] call, ready to render.
class QuickBattleResult {
  final bool concluded;
  final BattleOutcome outcome;
  final int roundsPlayed;
  final List<QuickBattleRound> rounds;
  final List<QuickBattleFighter> finalTeamA;
  final List<QuickBattleFighter> finalTeamB;

  const QuickBattleResult({
    required this.concluded,
    required this.outcome,
    required this.roundsPlayed,
    required this.rounds,
    required this.finalTeamA,
    required this.finalTeamB,
  });
}

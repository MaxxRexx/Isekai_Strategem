import 'package:battle_engine/battle_engine.dart';

/// One d20 roll's full detail (raw dice, advantage/disadvantage mode,
/// modifier, total) - the Battle Log's "show exact rolls" breakdown reads
/// straight off this instead of just a hit/miss summary.
class LogDiceRoll {
  final List<int> rawRolls;
  final int kept;
  final RollMode mode;
  final int modifier;
  final int total;

  const LogDiceRoll({
    required this.rawRolls,
    required this.kept,
    required this.mode,
    required this.modifier,
    required this.total,
  });

  factory LogDiceRoll.from(D20RollResult roll) => LogDiceRoll(
    rawRolls: roll.rawRolls,
    kept: roll.kept,
    mode: roll.mode,
    modifier: roll.modifier,
    total: roll.total,
  );

  /// Dice notation for display, e.g. "14+27=41" for a normal roll or
  /// "14/9→14+27=41" when advantage/disadvantage rolled more than one die.
  String get describe {
    final dice = mode == RollMode.normal
        ? '${rawRolls.single}'
        : '${rawRolls.join('/')}→$kept';
    final sign = modifier >= 0 ? '+' : '';
    return '$dice$sign$modifier=$total';
  }
}

/// The damage-formula trail behind one damaging roll, mirroring the
/// engine's [HitDamageDetail]/[DamageBreakdown] in plain display values -
/// the attacker/defender roll shown alongside this only ever decided hit/
/// miss/crit, never the damage number itself, which comes from an
/// entirely separate dice roll on the Trigger's own damage expression.
class LogDamageDetail {
  final List<int> diceRawRolls;
  final int diceFlatBonus;

  /// The Trigger's own damage roll, before any multiplier - rawRolls
  /// summed plus diceFlatBonus.
  final int diceTotal;

  /// Combined Team Spirit/perk/status outgoing-damage multiplier applied
  /// to [diceTotal] before the critical bonus (1.0 if nothing applies).
  final double preCritMultiplier;

  final bool prevented;
  final bool criticalHitApplied;
  final double criticalHitMultiplier;

  /// What the critical hit added on top: a crit rolls the ability's damage
  /// dice a second time and leaves the flat bonus alone, so this is the
  /// dice half of the roll again, not the whole number.
  final int criticalBonusDamage;

  final int afterCriticalHit;
  final int armor;
  final int afterArmor;
  final double statusDamageTypeMultiplier;
  final bool damageResistanceApplied;
  final int finalDamage;

  const LogDamageDetail({
    required this.diceRawRolls,
    required this.diceFlatBonus,
    required this.diceTotal,
    required this.preCritMultiplier,
    required this.prevented,
    required this.criticalHitApplied,
    required this.criticalHitMultiplier,
    required this.criticalBonusDamage,
    required this.afterCriticalHit,
    required this.armor,
    required this.afterArmor,
    required this.statusDamageTypeMultiplier,
    required this.damageResistanceApplied,
    required this.finalDamage,
  });

  factory LogDamageDetail.from(HitDamageDetail detail) => LogDamageDetail(
    diceRawRolls: detail.diceRoll.rawRolls,
    diceFlatBonus: detail.diceRoll.flatBonus,
    diceTotal: detail.diceRoll.total,
    preCritMultiplier: detail.preCritMultiplier,
    prevented: detail.breakdown.prevented,
    criticalHitApplied: detail.breakdown.criticalHitApplied,
    criticalHitMultiplier: detail.breakdown.criticalHitMultiplier,
    criticalBonusDamage: detail.breakdown.criticalBonusDamage,
    afterCriticalHit: detail.breakdown.afterCriticalHit,
    armor: detail.breakdown.armor,
    afterArmor: detail.breakdown.afterArmor,
    statusDamageTypeMultiplier: detail.breakdown.statusDamageTypeMultiplier,
    damageResistanceApplied: detail.breakdown.damageResistanceApplied,
    finalDamage: detail.breakdown.finalDamage,
  );

  /// Dice notation for display, e.g. "14+27+3" for a 2d20+3 roll.
  String get diceDescribe {
    final sign = diceFlatBonus > 0
        ? '+$diceFlatBonus'
        : diceFlatBonus < 0
        ? '$diceFlatBonus'
        : '';
    return '${diceRawRolls.join('+')}$sign';
  }
}

/// One resolved attack roll within a [LogTargetResult]: the attacker's and
/// defender's dice, the outcome, and the damage that specific roll dealt.
/// A Burst ability produces one of these per hit; everything else
/// produces exactly one.
class LogRollBreakdown {
  final LogDiceRoll attackerRoll;
  final LogDiceRoll defenderRoll;
  final bool isHit;
  final bool isCriticalHit;
  final bool isCriticalMiss;
  final int damage;

  /// The damage-formula trail behind [damage] - null when this roll dealt
  /// no damage (a miss, or a status-only Trigger with no damageType).
  final LogDamageDetail? damageDetail;

  const LogRollBreakdown({
    required this.attackerRoll,
    required this.defenderRoll,
    required this.isHit,
    required this.isCriticalHit,
    required this.isCriticalMiss,
    required this.damage,
    this.damageDetail,
  });
}

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

  /// The full per-roll breakdown behind [hits]/[crits]/[misses]/[damage] -
  /// what the Battle Log's expand button reveals.
  final List<LogRollBreakdown> rolls;

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
    this.rolls = const [],
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
  final CharacterType type;
  final int currentHealth;
  final int maxHealth;
  final bool alive;
  final bool fatTriggered;
  final List<StatusBadgeInfo> statusEffects;

  /// Which line of the battlefield this fighter is standing on. Distance to
  /// an enemy is the two sides' steps added together, so hanging back opens
  /// the gap; distance to an ally is the difference.
  final BattlePosition position;

  const FighterSnapshot({
    required this.id,
    required this.name,
    required this.type,
    required this.currentHealth,
    required this.maxHealth,
    required this.alive,
    this.fatTriggered = false,
    this.statusEffects = const [],
    this.position = BattlePosition.middle,
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

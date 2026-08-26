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

  /// Combined Team Spirit/Side Effect/status outgoing-damage multiplier applied
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

  /// How many faces each of [diceRawRolls] had, so the log can name the
  /// expression ("6d6") instead of printing a chain of numbers in which the
  /// flat bonus looks like one more die. A playtester read
  /// `1+6+2+3+2+6+23` and asked, reasonably, what it meant.
  final int diceSides;

  const LogDamageDetail({
    required this.diceRawRolls,
    required this.diceFlatBonus,
    required this.diceTotal,
    required this.diceSides,
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
    diceSides: detail.diceRoll.sides,
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

  /// The expression the ability rolls, e.g. "6d6".
  String get diceNotation => '${diceRawRolls.length}d$diceSides';

  /// Just the dice, summed: "1+6+2+3+2+6". The flat bonus is deliberately
  /// not in here, because running the two together is what made this
  /// unreadable.
  String get diceRollsDescribe => diceRawRolls.join('+');

  /// What the dice alone came to, before the ability's flat bonus.
  int get diceRollsTotal => diceRawRolls.fold(0, (sum, d) => sum + d);

  /// The ability's flat bonus with its sign, or an empty string when it has
  /// none.
  String get flatBonusDescribe => diceFlatBonus > 0
      ? '+$diceFlatBonus'
      : diceFlatBonus < 0
          ? '$diceFlatBonus'
          : '';
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

  /// This hit dropped the target to zero and opened their Bail Out window:
  /// the operator is leaving, but the body is still on the board for one
  /// contested turn. The log says so instead of "and is defeated", which is
  /// not what happened.
  final bool startedBailingOut;

  /// This hit landed on a body that was already Bailing Out and destroyed it,
  /// denying that squad the Trion Salvage.
  final bool bodyDestroyed;

  /// Trion this hit paid the attacker's own squad for destroying the body.
  final int trionFromBody;

  /// The target refused to bail: they stayed standing at 1 health instead of
  /// dropping, and are gone for good at the end of their next turn.
  final bool refusedToBail;

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
    this.startedBailingOut = false,
    this.bodyDestroyed = false,
    this.trionFromBody = 0,
    this.refusedToBail = false,
    this.rolls = const [],
  });
}

/// One ability use by one character (either side) in the battle log.
/// Why a shot bent, carried to the battle log so it can explain itself.
///
/// A bend is the one thing in a turn the player did not ask for, so the log
/// has to answer all four questions they will have: why was this legal when I
/// queued it, what changed, why did it still hit, and what did it cost.
class LogBend {
  /// The target the shot bent to reach.
  final String targetName;

  /// The band's label and window, e.g. "Long Range" and "2 to 4".
  final String bandLabel;
  final String bandWindow;
  final int bandMinimum;

  /// The effective distance when the action was committed, and now.
  final int distanceWhenCommitted;
  final int distanceNow;

  /// How many of the target's squad were screening them when the action was
  /// committed, and the names of the ones who died in between. Empty when the
  /// target simply moved rather than lost a screen.
  final int screensWhenCommitted;
  final List<String> screensBroken;

  /// The Trion the squad's income is capped at next turn.
  final int backlashTier;

  const LogBend({
    required this.targetName,
    required this.bandLabel,
    required this.bandWindow,
    required this.bandMinimum,
    required this.distanceWhenCommitted,
    required this.distanceNow,
    required this.screensWhenCommitted,
    required this.screensBroken,
    required this.backlashTier,
  });
}

/// A status reaction (item 3b) firing during an action.
///
/// Without a line in the log a reaction is invisible: the player sees a badge
/// disappear and a bigger number and has no way to connect the two. This is
/// what the log needs to say "the Frozen shattered".
class LogReaction {
  /// Who was carrying the reacting status.
  final String characterName;

  /// The reacting status and what it turned into, by display name. [became]
  /// is null for a reaction whose whole effect was on the hit.
  final String reactingName;
  final String? became;

  /// The damage type that set it off, already in player-facing words.
  final String damageTypeLabel;

  /// Whether the reacting status was spent doing it.
  final bool consumed;

  /// The multiplier the reaction put on the triggering hit. 1.0 for the rows
  /// that only change statuses.
  final double damageMultiplier;

  /// Who it arced to, for the one row that arcs.
  final String? arcedToName;

  const LogReaction({
    required this.characterName,
    required this.reactingName,
    required this.damageTypeLabel,
    this.became,
    this.consumed = false,
    this.damageMultiplier = 1.0,
    this.arcedToName,
  });
}

class LogAction {
  final String characterId;
  final String characterName;
  final String triggerId;
  final String triggerName;
  final bool fatTriggered;
  final List<LogTargetResult> targets;

  /// Set when this shot bent to reach a target that had come too close.
  final LogBend? bend;

  /// Item 3b's reactions this action set off, in the order they fired.
  final List<LogReaction> reactions;

  const LogAction({
    required this.characterId,
    required this.characterName,
    required this.triggerId,
    required this.triggerName,
    required this.fatTriggered,
    required this.targets,
    this.bend,
    this.reactions = const [],
  });
}

/// A Bail Out window closing at a turn boundary: either the body was left
/// alone and the operator was recalled, or a Refuse to Bail has run out of
/// the turn it bought.
///
/// Not a [LogAction], because nobody did it. It is what the turn ending
/// settled, so it is rendered on its own line under the round it settled in.
class LogBailOut {
  final String characterId;
  final String characterName;

  /// 'A' or 'B': whose squad the body belonged to, which is also whose pool
  /// the Salvage went into.
  final String team;

  /// Trion the body's own squad banked. Zero for a spent refusal, which is
  /// exactly what refusing costs.
  final int trionSalvaged;

  /// Whether this was a Refuse to Bail expiring rather than a recall.
  final bool refused;

  const LogBailOut({
    required this.characterId,
    required this.characterName,
    required this.team,
    required this.trionSalvaged,
    required this.refused,
  });
}

/// One team's turn within a round, holding every action taken in it.
class LogRound {
  final int roundNumber;
  final String team; // 'A' or 'B'
  final List<LogAction> actions;

  /// Bail Out windows that closed as this turn ended. Usually empty.
  final List<LogBailOut> bailOuts;

  const LogRound({
    required this.roundNumber,
    required this.team,
    required this.actions,
    this.bailOuts = const [],
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

  /// The operator is leaving, but the body is still standing on its line:
  /// targetable by an attack, and still screening whoever is behind it.
  /// Never true at the same time as [alive].
  final bool bailingOut;

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
    this.bailingOut = false,
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

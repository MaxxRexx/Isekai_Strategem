import 'dart:math';

import 'package:battle_engine/battle_engine.dart';

import 'draft.dart';

/// Team Efficiency Grade tier, D (worst) through SSS (best).
enum TegTier { d, c, b, a, s, ss, sss }

extension TegTierLabel on TegTier {
  String get label => switch (this) {
    TegTier.d => 'D',
    TegTier.c => 'C',
    TegTier.b => 'B',
    TegTier.a => 'A',
    TegTier.s => 'S',
    TegTier.ss => 'SS',
    TegTier.sss => 'SSS',
  };
}

/// Maps a [TegTier] to the engine-consumed [TegRollProfile] (Combat-v2
/// section 5.2, Effects 1/2/5): the offensive advantage chance climbs with
/// grade (Effect 1), the defensive advantage chance is inverted (Effect 2),
/// and only SSS widens the crit threshold to nat-18 (Effect 5). Numbers are
/// the first-pass 5.2 tables (tunable in Phase H).
TegRollProfile tegRollProfileFor(TegTier tier) {
  final offense = switch (tier) {
    TegTier.d => 0,
    TegTier.c => 3,
    TegTier.b => 6,
    TegTier.a => 9,
    TegTier.s => 12,
    TegTier.ss => 16,
    TegTier.sss => 20,
  };
  final defense = switch (tier) {
    TegTier.d => 20,
    TegTier.c => 16,
    TegTier.b => 12,
    TegTier.a => 9,
    TegTier.s => 6,
    TegTier.ss => 3,
    TegTier.sss => 0,
  };
  // Effect 3: setup->payoff Trion refund. Scales up to SS; SSS is 0 (it takes
  // the crit widener instead).
  final refund = switch (tier) {
    TegTier.d => 0,
    TegTier.c => 4,
    TegTier.b => 8,
    TegTier.a => 12,
    TegTier.s => 16,
    TegTier.ss => 20,
    TegTier.sss => 0,
  };
  return TegRollProfile(
    offenseAdvantagePercent: offense,
    defenseAdvantagePercent: defense,
    maxCritThreshold: tier == TegTier.sss ? 18 : 20,
    trionRefundPercent: refund,
  );
}

/// How much of the opening turn a single tier of Team Efficiency Grade
/// advantage is worth, and the ceiling on that advantage. Three tiers of
/// separation gets you to the ceiling.
const _openingTurnChancePerTier = 0.05;
const _maxOpeningTurnChance = 0.65;

/// The chance in [0, 1] that the squad graded [own] takes the opening turn
/// against a squad graded [other].
///
/// Who moves first used to be a straight coin flip, which made the single
/// most decisive variable in a lethal game the one thing a player could not
/// build toward. It is now weighted by the Team Efficiency Grade, the one
/// number that already measures how well a squad is put together: two evenly
/// graded squads still flip a fair coin, and every tier of separation moves
/// the odds five points, up to 65/35 at three tiers or more.
///
/// Deliberately not a guarantee. The underdog keeps a real chance of the
/// opening move (35% at worst), so the grade tilts the fight rather than
/// deciding it before anyone rolls, and the first-move Trion handicap (see
/// `Battle.startTurn`) still means going first costs something.
double openingTurnChanceFor(TegTier own, TegTier other) {
  final tierGap = own.index - other.index;
  final chance = 0.5 + tierGap * _openingTurnChancePerTier;
  final ceiling = _maxOpeningTurnChance;
  return chance.clamp(1 - ceiling, ceiling);
}

/// Rolls [openingTurnChanceFor] and returns whether the [own]-graded squad
/// takes the opening turn. Takes a [Random] so callers (and tests) can seed
/// it.
bool rollsOpeningTurn(TegTier own, TegTier other, {Random? random}) =>
    (random ?? Random()).nextDouble() < openingTurnChanceFor(own, other);

/// Draegor's "raise TEG 2 tiers" effect: the profile a team two tiers higher
/// would have, or null when the team is already SS/SSS (Draegor then runs its
/// fallback instead). The engine swaps to this profile while the boost lasts.
TegRollProfile? tegBoostedProfileFor(TegTier tier) {
  if (tier.index >= TegTier.ss.index) return null;
  final boosted = (tier.index + 2).clamp(0, TegTier.sss.index);
  return tegRollProfileFor(TegTier.values[boosted]);
}

/// The Team Efficiency Grade for one squad: how well tuned its loadouts are
/// (not how powerful), scored from six weighted sub-scores. It drives
/// cross-team Initiative (the higher-grade team resolves first when both
/// teams' effects would land at the same instant) and is shown under Player
/// info. Weights and thresholds are deliberately tunable.
class TeamEfficiency {
  final double teamSpiritAlignment;
  final double statCoherence;
  final double loadoutSynergy;
  final double sideEffectUtilization;
  final double trionEconomy;

  /// Null when the squad equips no Black Triggers (its weight is then
  /// redistributed across the other five sub-scores).
  final double? resonanceFit;

  /// Weighted composite in [0, 100].
  final double composite;
  final TegTier tier;

  const TeamEfficiency({
    required this.teamSpiritAlignment,
    required this.statCoherence,
    required this.loadoutSynergy,
    required this.sideEffectUtilization,
    required this.trionEconomy,
    required this.resonanceFit,
    required this.composite,
    required this.tier,
  });
}

// Sub-score weights (tunable).
const _wAlignment = 0.25;
const _wStat = 0.20;
const _wSynergy = 0.20;
const _wSideEffect = 0.15;
const _wEconomy = 0.10;
const _wResonance = 0.10;

/// Computes the [TeamEfficiency] for a squad from its characters and their
/// chosen loadouts.
TeamEfficiency computeTeamEfficiency({
  required List<String> characterIds,
  required Map<String, Loadout> loadouts,
}) {
  final chars = [for (final id in characterIds) roster[id]];
  final los = [for (final id in characterIds) loadouts[id]!];

  final alignment = _alignment(chars, los);
  final coherence = _statCoherence(chars, los);
  final synergy = _loadoutSynergy(los);
  final sideEffect = _sideEffectUtilization(chars, los);
  final economy = _trionEconomy(chars, los);
  final resonance = _resonanceFit(chars, los);

  final double weightSum;
  var weighted =
      alignment * _wAlignment +
      coherence * _wStat +
      synergy * _wSynergy +
      sideEffect * _wSideEffect +
      economy * _wEconomy;
  if (resonance == null) {
    weightSum = _wAlignment + _wStat + _wSynergy + _wSideEffect + _wEconomy;
  } else {
    weighted += resonance * _wResonance;
    weightSum = 1.0;
  }
  final composite = (weighted / weightSum).clamp(0, 100).toDouble();

  return TeamEfficiency(
    teamSpiritAlignment: alignment,
    statCoherence: coherence,
    loadoutSynergy: synergy,
    sideEffectUtilization: sideEffect,
    trionEconomy: economy,
    resonanceFit: resonance,
    composite: composite,
    tier: _tierFor(composite),
  );
}

TegTier _tierFor(double c) {
  if (c >= 96) return TegTier.sss;
  if (c >= 89) return TegTier.ss;
  if (c >= 79) return TegTier.s;
  if (c >= 68) return TegTier.a;
  if (c >= 55) return TegTier.b;
  if (c >= 40) return TegTier.c;
  return TegTier.d;
}

// --- Helpers ---

List<ActiveTrigger> _actives(Loadout l) => [
  ...l.triggers.whereType<ActiveTrigger>(),
  ...?l.blackTrigger?.activeAbilities,
];

bool _isDamage(ActiveTrigger t) => t.damageType != null && t.damage != null;

bool _isSupport(ActiveTrigger t) =>
    t.targetAffiliation != TargetAffiliation.opponent && !_isDamage(t);

bool _isEnemyDebuff(ActiveTrigger t) =>
    t.targetAffiliation == TargetAffiliation.opponent &&
    t.inflictedStatusEffects.isNotEmpty;

/// Each character's loadout lean (offense vs sustain) vs whether their Team
/// Spirit sits on the matching pole (offense wants low TS, sustain high).
double _alignment(List<Character> chars, List<Loadout> los) {
  var sum = 0.0;
  for (var i = 0; i < chars.length; i++) {
    final actives = _actives(los[i]);
    final offense = actives.where(_isDamage).length;
    final support = actives.where(_isSupport).length;
    final dev = (chars[i].baseStats.teamSpirit - 50) / 50.0; // -1..+1
    final double a;
    if (offense > support) {
      a = -dev * 0.5 + 0.5; // offense wants low TS
    } else if (support > offense) {
      a = dev * 0.5 + 0.5; // sustain wants high TS
    } else {
      a = 1 - dev.abs(); // neutral wants the midpoint
    }
    sum += a.clamp(0.0, 1.0) * 100;
  }
  return sum / chars.length;
}

/// Each character's stats fitting their loadout's dominant demand.
double _statCoherence(List<Character> chars, List<Loadout> los) {
  var sum = 0.0;
  for (var i = 0; i < chars.length; i++) {
    final actives = _actives(los[i]);
    final s = chars[i].baseStats;
    final dmg = actives.where(_isDamage).length;
    final debuff = actives.where(_isEnemyDebuff).length;
    final support = actives.where(_isSupport).length;
    final double score;
    if (dmg >= debuff && dmg >= support) {
      score =
          (s.attack / 30).clamp(0.0, 1.0) * 0.7 +
          (s.criticalChance / 20).clamp(0.0, 1.0) * 0.3;
    } else if (debuff >= support) {
      score = (s.statusEffectInfliction / 14).clamp(0.0, 1.0);
    } else {
      // Support: healing scales with high Team Spirit (health-regen pole).
      score = (s.teamSpirit / 100).clamp(0.0, 1.0);
    }
    sum += score * 100;
  }
  return sum / chars.length;
}

/// Squad-wide complementary-ability signals.
double _loadoutSynergy(List<Loadout> los) {
  final all = [for (final l in los) ..._actives(l)];
  final hasDebuff = all.any(_isEnemyDebuff);
  final hasBigDamage = all.any(
    (t) => _isDamage(t) && (t.damage?.average ?? 0) >= 30,
  );
  final hasSupport = all.any(_isSupport);
  final hasAoe = all.any((t) => t.attackSubtype == AttackSubtype.aoe);
  final hasFinisher = all.any(
    (t) => _isDamage(t) && t.attackSubtype == AttackSubtype.single,
  );
  final damageTypes = {
    for (final t in all)
      if (t.damageType != null) t.damageType,
  }.length;

  var signals = 0;
  if (hasDebuff && hasBigDamage) signals++; // setup + payoff
  if (hasSupport && hasBigDamage) signals++; // protector + carry
  if (hasAoe && hasFinisher) signals++; // wide + focused
  if (damageTypes >= 3) signals++; // damage-type coverage
  return signals / 4 * 100;
}

/// Whether each character's loadout plays to its Side Effect.
double _sideEffectUtilization(List<Character> chars, List<Loadout> los) {
  var sum = 0.0;
  for (var i = 0; i < chars.length; i++) {
    final sideEffect = chars[i].sideEffect;
    if (sideEffect == null) {
      sum += 50;
      continue;
    }
    final actives = _actives(los[i]);
    final dmg = actives.where(_isDamage).length;
    final support = actives.where(_isSupport).length;
    final debuff = actives.where(_isEnemyDebuff).length;
    final aoe = actives
        .where((t) => t.attackSubtype == AttackSubtype.aoe)
        .length;

    double score = 50; // neutral default when a sideEffect fits no clear kit
    if (sideEffect.firstAttackCritBonusVsFullHealthTarget != null ||
        sideEffect.doublesCritChanceWhenLastAlive ||
        sideEffect.firstTurnAttackBonus != null ||
        sideEffect.maxDamageBonusPercentAtZeroHealth != null ||
        sideEffect.perExtraAbilityDamageBonusPercent != null ||
        sideEffect.canRerollOwnAttackRollOncePerBattle) {
      score = dmg / 4 * 100;
    } else if (sideEffect.aoeDamageBonusPercentVsDebuffedTarget != null) {
      score = (aoe > 0 && debuff > 0)
          ? 100
          : aoe > 0
          ? 70
          : 30;
    } else if (sideEffect.incomingHealBonusPercent != null ||
        sideEffect.healBonusPercentVsAllyBelowHalfHealth != null ||
        sideEffect.bonusStatusResistanceGrantedByAllyBuffs != null ||
        sideEffect.teamTrionGainModifierWhileAlive != null) {
      score = support / 4 * 100;
    } else if (sideEffect.bonusDurationVsAlreadyAffectedTarget != null) {
      score = debuff / 4 * 100;
    } else if (sideEffect.doublesArmorWhileAllyBelowQuarterHealth ||
        sideEffect.firstDamageInstanceReductionPercent != null ||
        sideEffect.attackStackBonusOnMeleeMissAgainstSelf != null ||
        sideEffect.firstIncomingAttackHasDisadvantage) {
      score = 60; // a defensive SE rewards a non-glass-cannon kit
    }
    sum += score.clamp(0.0, 100.0);
  }
  return sum / chars.length;
}

/// Whether the squad can afford to act each turn: cheap-castable abilities
/// plus equip-budget headroom.
double _trionEconomy(List<Character> chars, List<Loadout> los) {
  const income = 35.0; // a high-tier turn (tunable)
  var sum = 0.0;
  for (var i = 0; i < chars.length; i++) {
    final actives = _actives(los[i]);
    if (actives.isEmpty) continue;
    final minCost = actives
        .map((t) => t.trionCost)
        .reduce((a, b) => a < b ? a : b)
        .toDouble();
    final afford = (1 - minCost / income).clamp(0.0, 1.0);
    final headroom =
        (1 - los[i].totalEquipCost / chars[i].baseStats.trionCapacity).clamp(
          0.0,
          1.0,
        );
    sum += (afford * 0.6 + headroom * 0.4) * 100;
  }
  return sum / chars.length;
}

/// Average resonance grade of equipped Black Triggers with their wielders'
/// types. Null when the squad runs no Black Triggers.
double? _resonanceFit(List<Character> chars, List<Loadout> los) {
  final grades = <double>[];
  for (var i = 0; i < chars.length; i++) {
    final bt = los[i].blackTrigger;
    if (bt == null) continue;
    grades.add(switch (ResonanceGrid.defaultGrid.lookup(
      chars[i].type,
      bt.type,
    )) {
      ResonanceGrade.a => 100.0,
      ResonanceGrade.b => 75.0,
      ResonanceGrade.c => 50.0,
      ResonanceGrade.d => 25.0,
    });
  }
  if (grades.isEmpty) return null;
  return grades.reduce((a, b) => a + b) / grades.length;
}

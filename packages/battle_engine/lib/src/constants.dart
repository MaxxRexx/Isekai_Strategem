/// All tunable numeric knobs for the battle engine, grouped by system.
/// Nothing in the engine hardcodes a magic number outside of these
/// classes - to rebalance, change values here (or construct an alternate
/// config instance and inject it).

/// Config for the Team Spirit dual-direction curve (see
/// `TeamSpiritCurve`).
///
/// Team Spirit is assumed to range [statMin, statMax] with [midpoint]
/// being neutral (no bonus either direction). Two independent linear
/// scalers run from the midpoint to each extreme:
/// - Below midpoint: scales towards `low*` bonuses (attack/burst damage,
///   crit chance).
/// - Above midpoint: scales towards `high*` bonuses (heal regen, FAT
///   chance).
class TeamSpiritCurveConfig {
  final double statMin;
  final double statMax;
  final double midpoint;

  /// Multiplicative damage bonus applied at the low extreme (e.g. 0.30 =
  /// +30% at statMin), scaling linearly to 0 at the midpoint.
  final double maxSingleTargetDamageBonus;
  final double maxBurstDamageBonus;

  /// Additive percentage-point bonus to Critical Chance at the low
  /// extreme, scaling linearly to 0 at the midpoint.
  final double maxCriticalChanceBonus;

  /// Multiplicative bonus to Health Regeneration amount at the high
  /// extreme, scaling linearly to 0 at the midpoint.
  final double maxHealthRegenBonus;

  /// Additive percentage-point bonus to FAT Chance at the high extreme,
  /// scaling linearly to 0 at the midpoint.
  final double maxFatChanceBonus;

  const TeamSpiritCurveConfig({
    this.statMin = 0,
    this.statMax = 100,
    this.midpoint = 50,
    this.maxSingleTargetDamageBonus = 0.30,
    this.maxBurstDamageBonus = 0.30,
    this.maxCriticalChanceBonus = 20,
    this.maxHealthRegenBonus = 0.30,
    this.maxFatChanceBonus = 20,
  });

  static const TeamSpiritCurveConfig defaults = TeamSpiritCurveConfig();
}

/// Config for the per-turn Trion tier gain roll.
///
/// Modeled as two sequential upgrade checks rather than one three-way
/// roll: start at Low, roll to upgrade to Medium using
/// `baseChanceLowToMedium + affinityWeightPerPoint * sumTrionAffinity +
/// modifiers`; if that succeeds, roll again (independently configurable)
/// to upgrade Medium -> High. This directly implements the spec's wording
/// ("probability of a higher tier = base chance + sum of ... Trion
/// Affinity + modifiers") as a reusable formula applied at each step,
/// and keeps the whole thing tunable via these constants. See
/// `TrionGainEngine` doc comment for the full rationale (flagged as an
/// interpretation of an underspecified rule).
class TrionTierConfig {
  final double baseChanceLowToMedium;
  final double baseChanceMediumToHigh;
  final double affinityWeightPerPoint;

  final int lowAmount;
  final int mediumAmount;
  final int highAmount;

  const TrionTierConfig({
    this.baseChanceLowToMedium = 0.35,
    this.baseChanceMediumToHigh = 0.20,
    this.affinityWeightPerPoint = 0.01,
    this.lowAmount = 10,
    this.mediumAmount = 20,
    this.highAmount = 35,
  });

  static const TrionTierConfig defaults = TrionTierConfig();
}

/// Config for Full Arms Trigger (FAT).
class FatConfig {
  /// Turns FAT stays locked out after triggering, before modifiers.
  final int baseFatCooldownTurns;

  /// Max abilities usable in a turn where FAT triggered.
  final int maxAbilitiesOnFatTrigger;

  /// Abilities usable in a turn without FAT.
  final int normalAbilitiesPerTurn;

  /// Abilities used in one turn at/above this count counts as "FAT
  /// actually used for 2+ abilities" and applies the penalty.
  final int multiAbilityPenaltyThreshold;

  final double cooldownDoubleMultiplier;
  final double trionAffinityPenaltyMultiplier;

  const FatConfig({
    this.baseFatCooldownTurns = 3,
    this.maxAbilitiesOnFatTrigger = 3,
    this.normalAbilitiesPerTurn = 1,
    this.multiAbilityPenaltyThreshold = 2,
    this.cooldownDoubleMultiplier = 2.0,
    this.trionAffinityPenaltyMultiplier = 0.5,
  });

  static const FatConfig defaults = FatConfig();
}

/// Default durations/magnitudes for the built-in 50-entry status effect
/// catalog (see `StatusEffectCatalog`), tuned against the baseline stat
/// block in `Stats`/`testStats` (100 max Health, ~10 Attack/Defense, 5
/// Armor, 100 Trion Capacity, Team Spirit centered on 50). Two values are
/// given explicitly by the original design brief (Sickened's 4 random
/// damage types, Sapped's 25% Trion Capacity drain); everything else is
/// collected here as an explicit, tunable value rather than a silently
/// hardcoded magic number - to rebalance, change values here (or
/// construct an alternate config instance and inject it).
class StatusEffectMagnitudes {
  // --- Original 18 ---
  final int acidArmorReduction;
  final int acidDurationTurns;
  final int wetDurationTurns;
  final int stunnedDurationTurns;
  final int threatenedDurationTurns;
  final int sickenedDurationTurns;
  final int sickenedVulnerableDamageTypeCount;
  final int sappedDurationTurns;
  final double sappedDrainPercentOfTrionCapacity;
  final int reelingDurationTurns;
  final int ralliedDurationTurns;
  final int ralliedMaxHealthBonus;
  final int proneDurationTurns;
  final int preparedDurationTurns;
  final int poisonedDurationTurns;
  final int frozenDurationTurns;
  final int bleedingDurationTurns;
  final int bleedingDamagePerTurn;
  final int blindedDurationTurns;
  final int bracedDurationTurns;
  final int charmedDurationTurns;
  final int electrocutedDurationTurns;
  final int regeneratingDurationTurns;
  final int regeneratingHealPerTurn;

  // --- 32 additions (D&D / Naruto-Arena / World Trigger inspired) ---
  final int empoweredDurationTurns;
  final double empoweredOutgoingDamageMultiplier;
  final int weakenedDurationTurns;
  final double weakenedOutgoingDamageMultiplier;
  final int focusedDurationTurns;
  final int guardedDurationTurns;
  final double guardedAllDamageTakenMultiplier;
  final int exposedDurationTurns;
  final double exposedAllDamageTakenMultiplier;
  final int markedDurationTurns;
  final double markedAllDamageTakenMultiplier;
  final int cursedDurationTurns;
  final int silencedDurationTurns;
  final int enragedDurationTurns;
  final double enragedOutgoingDamageMultiplier;
  final int enragedDefensePenalty;
  final int fatiguedDurationTurns;
  final int fatiguedAttackPenalty;
  final int fatiguedDefensePenalty;
  final int inspiredDurationTurns;
  final int inspiredAttackBonus;
  final int inspiredDefenseBonus;
  final int shatteredGuardDurationTurns;
  final int overchargedDurationTurns;
  final double overchargedTrionCostMultiplier;
  final int chokedDurationTurns;
  final double chokedTrionCostMultiplier;
  final int petrifiedDurationTurns;
  final double petrifiedAllDamageTakenMultiplier;
  final int terrifiedDurationTurns;
  final int slowedDurationTurns;
  final int slowedDefensePenaltyPerTurn;
  final int hastenedDurationTurns;
  final int hastenedAttackBonusPerTurn;
  final int scorchedDurationTurns;
  final int scorchedDamagePerTurn;
  final int chilledDurationTurns;
  final int chilledAttackPenaltyPerTurn;
  final int corrodedDurationTurns;
  final int corrodedArmorReduction;
  final int shadowBoundDurationTurns;
  final int genjutsuTrappedDurationTurns;
  final double genjutsuTrappedDrainPercentOfTrionCapacity;
  final int sealedDurationTurns;
  final int overwhelmedDurationTurns;
  final int adrenalineRushDurationTurns;
  final int adrenalineRushCriticalChanceBonus;
  final int battleTranceDurationTurns;
  final int battleTranceFatChanceBonus;
  final int suppressedDurationTurns;
  final int suppressedInflictionPenalty;
  final int wardedDurationTurns;
  final int wardedResistanceBonus;
  final int hexedDurationTurns;
  final int hexedResistancePenalty;
  final int radiantBlessingDurationTurns;
  final int radiantBlessingHealPerTurn;
  final int radiantBlessingMaxHealthBonus;
  final double radiantBlessingAllDamageTakenMultiplier;
  final int necroticWoundDurationTurns;
  final int necroticWoundDamagePerTurn;

  const StatusEffectMagnitudes({
    this.acidArmorReduction = 5,
    this.acidDurationTurns = 3,
    this.wetDurationTurns = 3,
    this.stunnedDurationTurns = 1,
    this.threatenedDurationTurns = 2,
    this.sickenedDurationTurns = 3,
    this.sickenedVulnerableDamageTypeCount = 4,
    this.sappedDurationTurns = 3,
    this.sappedDrainPercentOfTrionCapacity = 0.25,
    this.reelingDurationTurns = 3,
    this.ralliedDurationTurns = 3,
    this.ralliedMaxHealthBonus = 20,
    this.proneDurationTurns = 1,
    this.preparedDurationTurns = 3,
    this.poisonedDurationTurns = 3,
    this.frozenDurationTurns = 1,
    this.bleedingDurationTurns = 3,
    this.bleedingDamagePerTurn = 8,
    this.blindedDurationTurns = 2,
    this.bracedDurationTurns = 3,
    this.charmedDurationTurns = 3,
    this.electrocutedDurationTurns = 2,
    this.regeneratingDurationTurns = 3,
    this.regeneratingHealPerTurn = 3,
    this.empoweredDurationTurns = 2,
    this.empoweredOutgoingDamageMultiplier = 1.25,
    this.weakenedDurationTurns = 3,
    this.weakenedOutgoingDamageMultiplier = 0.75,
    this.focusedDurationTurns = 2,
    this.guardedDurationTurns = 2,
    this.guardedAllDamageTakenMultiplier = 0.75,
    this.exposedDurationTurns = 2,
    this.exposedAllDamageTakenMultiplier = 1.25,
    this.markedDurationTurns = 1,
    this.markedAllDamageTakenMultiplier = 1.5,
    this.cursedDurationTurns = 3,
    this.silencedDurationTurns = 1,
    this.enragedDurationTurns = 2,
    this.enragedOutgoingDamageMultiplier = 1.5,
    this.enragedDefensePenalty = 3,
    this.fatiguedDurationTurns = 3,
    this.fatiguedAttackPenalty = 2,
    this.fatiguedDefensePenalty = 2,
    this.inspiredDurationTurns = 2,
    this.inspiredAttackBonus = 2,
    this.inspiredDefenseBonus = 2,
    this.shatteredGuardDurationTurns = 2,
    this.overchargedDurationTurns = 2,
    this.overchargedTrionCostMultiplier = 0.5,
    this.chokedDurationTurns = 2,
    this.chokedTrionCostMultiplier = 2.0,
    this.petrifiedDurationTurns = 2,
    this.petrifiedAllDamageTakenMultiplier = 0.5,
    this.terrifiedDurationTurns = 2,
    this.slowedDurationTurns = 2,
    this.slowedDefensePenaltyPerTurn = 1,
    this.hastenedDurationTurns = 2,
    this.hastenedAttackBonusPerTurn = 1,
    this.scorchedDurationTurns = 2,
    this.scorchedDamagePerTurn = 12,
    this.chilledDurationTurns = 2,
    this.chilledAttackPenaltyPerTurn = 1,
    this.corrodedDurationTurns = 2,
    this.corrodedArmorReduction = 3,
    this.shadowBoundDurationTurns = 2,
    this.genjutsuTrappedDurationTurns = 1,
    this.genjutsuTrappedDrainPercentOfTrionCapacity = 0.15,
    this.sealedDurationTurns = 2,
    this.overwhelmedDurationTurns = 2,
    this.adrenalineRushDurationTurns = 2,
    this.adrenalineRushCriticalChanceBonus = 15,
    this.battleTranceDurationTurns = 2,
    this.battleTranceFatChanceBonus = 20,
    this.suppressedDurationTurns = 2,
    this.suppressedInflictionPenalty = 5,
    this.wardedDurationTurns = 2,
    this.wardedResistanceBonus = 10,
    this.hexedDurationTurns = 2,
    this.hexedResistancePenalty = 10,
    this.radiantBlessingDurationTurns = 3,
    this.radiantBlessingHealPerTurn = 1,
    this.radiantBlessingMaxHealthBonus = 10,
    this.radiantBlessingAllDamageTakenMultiplier = 0.9,
    this.necroticWoundDurationTurns = 3,
    this.necroticWoundDamagePerTurn = 12,
  });

  static const StatusEffectMagnitudes defaults = StatusEffectMagnitudes();
}

/// Config for core combat resolution.
class CombatConfig {
  final double criticalHitDamageMultiplier;
  final double criticalMissDefensePenaltyPct;
  final double criticalMissTeamSpiritPenaltyPct;
  final int criticalMissPenaltyDurationTurns;

  const CombatConfig({
    this.criticalHitDamageMultiplier = 2.0,
    this.criticalMissDefensePenaltyPct = 0.20,
    this.criticalMissTeamSpiritPenaltyPct = 0.20,
    this.criticalMissPenaltyDurationTurns = 1,
  });

  static const CombatConfig defaults = CombatConfig();
}

/// Config for how the Critical Chance stat lowers the natural-roll
/// threshold at which an attack roll crits.
///
/// Critical Chance is a percentage in [minChancePercent, maxChancePercent]
/// (0-90 by design - crit chance intentionally can't reach 100%, which
/// would make every attack roll fixed). It maps *linearly* onto the
/// natural die threshold that counts as a crit: at [minChancePercent] only
/// a natural [thresholdAtMinChance] (20) crits; at [maxChancePercent] a
/// natural [thresholdAtMaxChance] (5) or higher crits. See
/// `CombatEngine.criticalHitThreshold`.
class CriticalChanceConfig {
  final double minChancePercent;
  final double maxChancePercent;
  final int thresholdAtMinChance;
  final int thresholdAtMaxChance;

  const CriticalChanceConfig({
    this.minChancePercent = 0,
    this.maxChancePercent = 90,
    this.thresholdAtMinChance = 20,
    this.thresholdAtMaxChance = 5,
  });

  static const CriticalChanceConfig defaults = CriticalChanceConfig();
}

/// Config for the pre-match Loadout phase's equip rules.
class LoadoutRulesConfig {
  /// Max total equipped items (regular Triggers plus the Black Trigger,
  /// if any, counted together) - a ceiling, not a required target.
  final int maxEquippedTriggers;

  /// Exact number of active abilities a valid Loadout must provide,
  /// summing 1 per equipped `ActiveTrigger` plus however many of the
  /// Black Trigger's abilities are active. Passive count is uncapped
  /// beyond `maxEquippedTriggers` and the Trion Capacity budget.
  final int requiredActiveAbilityCount;

  const LoadoutRulesConfig({
    this.maxEquippedTriggers = 8,
    this.requiredActiveAbilityCount = 4,
  });

  static const LoadoutRulesConfig defaults = LoadoutRulesConfig();
}

/// Config for the per-team turn timer: how long a team has to lock in
/// their actions and pass/end the turn before it's forfeited
/// automatically with nothing committed. The countdown itself (starting
/// it, ticking it, detecting expiry) is a host-app/UI concern, not
/// something this synchronous engine owns; this is just the tunable base
/// duration, which a Black Trigger's World ability can raise or lower for
/// a team (see `WorldAbilityEffect.turnTimerSecondsDelta`).
class TurnTimerConfig {
  final int secondsPerTurn;
  const TurnTimerConfig({this.secondsPerTurn = 15});
  static const TurnTimerConfig defaults = TurnTimerConfig();
}

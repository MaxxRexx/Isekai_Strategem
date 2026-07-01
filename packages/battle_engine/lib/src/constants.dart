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

/// Default durations/magnitudes for the built-in status effect catalog.
/// Two values are given explicitly by the design brief (Sickened's 4
/// random damage types, Sapped's 25% Trion Capacity drain); everything
/// else (durations, flat magnitudes) is an unspecified "X turns" / "value
/// X" placeholder in the brief, so it's collected here as an explicit,
/// tunable guess rather than a silently hardcoded magic number.
class StatusEffectMagnitudes {
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
    this.bleedingDamagePerTurn = 2,
    this.blindedDurationTurns = 2,
    this.bracedDurationTurns = 3,
    this.charmedDurationTurns = 3,
    this.electrocutedDurationTurns = 2,
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

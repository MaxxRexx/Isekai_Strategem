import '../constants.dart';

/// Bundle of bonuses derived from a character's current Team Spirit
/// value. See [TeamSpiritCurveConfig] for the tunable knobs.
class TeamSpiritBonuses {
  /// Multiplicative bonus to single-target attack damage, e.g. 0.15 = +15%.
  final double singleTargetDamageBonus;

  /// Multiplicative bonus to Burst Attack damage.
  final double burstDamageBonus;

  /// Additive percentage points added to Critical Chance.
  final double criticalChanceBonus;

  /// Multiplicative bonus to Health Regeneration amount when healed.
  final double healthRegenBonus;

  /// Additive percentage points added to FAT Chance.
  final double fatChanceBonus;

  const TeamSpiritBonuses({
    required this.singleTargetDamageBonus,
    required this.burstDamageBonus,
    required this.criticalChanceBonus,
    required this.healthRegenBonus,
    required this.fatChanceBonus,
  });
}

/// Team Spirit is a dual-direction stat: values below the midpoint boost
/// offense (attack/burst damage, crit chance), values above the midpoint
/// boost sustain/utility (heal regen, FAT chance). Implemented as two
/// independent linear scalers running from the midpoint out to each
/// extreme, per the design brief's suggestion, so each side can be tuned
/// (or made non-linear later) without touching the other.
class TeamSpiritCurve {
  final TeamSpiritCurveConfig config;

  const TeamSpiritCurve([this.config = TeamSpiritCurveConfig.defaults]);

  TeamSpiritBonuses bonusesFor(num teamSpirit) {
    final clamped = teamSpirit.clamp(config.statMin, config.statMax).toDouble();
    final deviation = clamped - config.midpoint;

    double lowFactor = 0;
    double highFactor = 0;

    if (deviation < 0) {
      final range = config.midpoint - config.statMin;
      lowFactor = range == 0 ? 0 : (-deviation) / range;
    } else if (deviation > 0) {
      final range = config.statMax - config.midpoint;
      highFactor = range == 0 ? 0 : deviation / range;
    }

    return TeamSpiritBonuses(
      singleTargetDamageBonus: lowFactor * config.maxSingleTargetDamageBonus,
      burstDamageBonus: lowFactor * config.maxBurstDamageBonus,
      criticalChanceBonus: lowFactor * config.maxCriticalChanceBonus,
      healthRegenBonus: highFactor * config.maxHealthRegenBonus,
      fatChanceBonus: highFactor * config.maxFatChanceBonus,
    );
  }
}

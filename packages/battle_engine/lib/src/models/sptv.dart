import '../constants.dart';
import '../content/trigger_catalog.dart';
import 'damage_type.dart';
import 'status_effect.dart';
import 'status_effect_catalog.dart';
import 'trigger.dart';

/// SPTV: what a status effect is worth, and what an ability is worth.
///
/// **Item #3's rule, wave 1.** The pass that re-prices the catalogue is wave
/// 4's; this is the rule it will run.
///
/// One Status Point is one point of damage. There is no conversion constant
/// between them, so there is nothing to get wrong (decision #A). What a status
/// is worth is read off **its own declarative fields**, one conversion per
/// field, each conversion derived from a measured baseline (decision #B). No
/// status carries a hand-written price, so a price cannot drift from the
/// content it is pricing: re-tune a magnitude and its price re-derives itself.
///
///     SP = sum of each field's damage-equivalent per turn
///          x turns covered x targets
///
///     TV = (payload + SP x rider factor) / Trion cost x cooldown factor
///
/// The rider factor is the infliction contest: a status aimed at an opponent
/// has to win one and the damage on the same hit does not, so it is worth
/// [SptvBaselines.riderLandsGivenHit] of its face value. A status granted to
/// yourself or an ally is never contested and counts in full.
///
/// **What is deliberately not priced.** Five fields need a measurement the
/// baseline tool does not take yet, and pricing them by eye is exactly what
/// this rule exists to replace. They are named in [unpricedFields] and every
/// price says which ones it had to skip, so an under-priced status is visible
/// rather than silent.
abstract final class Sptv {
  /// Fields whose conversion has not been derived yet. A status carrying one
  /// of these is priced on everything else it does, and its price is flagged
  /// as incomplete rather than quietly rounded down.
  static const Set<String> unpricedFields = {
    'misfireChance',
    'preventsTargeting',
    'cannotTargetSource',
    'locksRandomAbilityEachTurn',
    'reactions',
  };

  /// Cooldown factor from the design-director synthesis: the same payload on
  /// a short cooldown is worth more, because you get it more often.
  static double cooldownFactor(int cooldownTurns) => switch (cooldownTurns) {
        <= 1 => 1.5,
        2 => 1.0,
        3 => 0.8,
        _ => 0.7,
      };

  /// Probability that an attacker with modifier advantage [gap] beats a
  /// defender in the opposed d20 contest, ties to the attacker.
  ///
  /// Derived rather than measured: it is a property of two dice, not of how
  /// the game happens to be played.
  static double hitChance(int gap) {
    var wins = 0;
    for (var a = 1; a <= 20; a++) {
      for (var d = 1; d <= 20; d++) {
        if (a + gap >= d) wins++;
      }
    }
    return wins / 400;
  }

  /// How much one point of an opposed stat (Attack, Defense, Infliction,
  /// Resistance) moves the contest, as a share. About 4.5 percentage points.
  static double get opposedStatPointWinChance => hitChance(1) - hitChance(0);

  /// What rolling two dice and keeping the higher is worth, in points of flat
  /// modifier. Solved against [hitChance] rather than asserted.
  static double get advantageInStatPoints {
    // Advantage's win chance at gap 0: 1 - P(both dice lose).
    var wins = 0;
    for (var a1 = 1; a1 <= 20; a1++) {
      for (var a2 = 1; a2 <= 20; a2++) {
        for (var d = 1; d <= 20; d++) {
          if ((a1 > a2 ? a1 : a2) >= d) wins++;
        }
      }
    }
    final withAdvantage = wins / 8000;
    // The flat modifier that buys the same win chance, to a tenth of a point.
    for (var tenths = 0; tenths <= 200; tenths++) {
      final gap = tenths / 10;
      final low = hitChance(gap.floor());
      final high = hitChance(gap.floor() + 1);
      final interpolated = low + (high - low) * (gap - gap.floor());
      if (interpolated >= withAdvantage) return gap;
    }
    return 0;
  }

  /// Damage-equivalent of one point of an opposed stat, per turn: it moves
  /// [SptvBaselines.attackRollsPerCharacterTurn] rolls by
  /// [opposedStatPointWinChance], each worth
  /// [SptvBaselines.damagePerLandedRoll].
  static double damagePerOpposedStatPoint(SptvBaselines b) =>
      opposedStatPointWinChance *
      b.attackRollsPerCharacterTurn *
      b.damagePerLandedRoll;

  /// Damage-equivalent of one point of Armor per turn. Armor subtracts once
  /// per landed hit rather than per roll.
  static double damagePerArmorPoint(SptvBaselines b) =>
      b.landedRollsPerCharacterTurn;

  /// Damage-equivalent of advantage (or disadvantage) on a roll, per turn.
  static double damagePerAdvantage(SptvBaselines b) =>
      advantageInStatPoints * damagePerOpposedStatPoint(b);

  /// How often [type] shows up as an attack's damage type in the Trigger
  /// catalogue, which is how much an immunity or vulnerability to it is worth.
  static double damageTypeFrequency(
    DamageType type, {
    TriggerCatalog? triggers,
  }) {
    final catalog = triggers ?? TriggerCatalog.defaultCatalog;
    var total = 0;
    var matching = 0;
    for (final t in catalog.activeTriggers) {
      if (t.damageType == null || t.damage == null) continue;
      total++;
      if (t.damageType == type) matching++;
    }
    return total == 0 ? 0 : matching / total;
  }

  /// Prices [def] in damage-equivalent.
  ///
  /// [stacks] multiplies every magnitude, exactly as the engine does
  /// (decision #F): the price of three stacks is three times the price of one.
  /// [durationTurns] defaults to the definition's own, and [targets] to one.
  static StatusPrice priceStatus(
    StatusEffectDefinition def, {
    SptvBaselines baselines = SptvBaselines.defaults,
    int stacks = 1,
    int? durationTurns,
    int targets = 1,
    TriggerCatalog? triggers,
  }) {
    final b = baselines;
    final perTurn = <String, double>{};
    final skipped = <String>[];

    void add(String field, double value) {
      if (value == 0) return;
      perTurn[field] = (perTurn[field] ?? 0) + value * stacks;
    }

    // Ticks are damage that cannot miss, and a heal is damage undone.
    if (def.turnStartDamage != null) {
      add('turnStartDamage', def.turnStartDamage!.average);
    }
    if (def.turnStartHeal != null) {
      add('turnStartHeal', def.turnStartHeal!.average);
    }

    // Stat steps.
    def.flatStatModifiers.forEach((stat, delta) {
      final per = _statPointValue(stat, b);
      if (per == null) {
        skipped.add('flatStatModifiers.${stat.name}');
        return;
      }
      add('flatStatModifiers', delta.abs() * per);
    });

    // A per-remaining-turn step decays with its own duration, so it is worth
    // its average over the turns it is up: n x (D + 1) / 2.
    final duration = durationTurns ?? def.defaultDurationTurns;
    def.perRemainingTurnStatModifiers.forEach((stat, delta) {
      final per = _statPointValue(stat, b);
      if (per == null) {
        skipped.add('perRemainingTurnStatModifiers.${stat.name}');
        return;
      }
      final d = duration ?? 1;
      add('perRemainingTurnStatModifiers',
          delta.abs() * per * (d + 1) / 2);
    });

    for (final stat in def.zeroedStats) {
      final per = _statPointValue(stat, b);
      if (per == null) {
        skipped.add('zeroedStats.${stat.name}');
        continue;
      }
      // Zeroing takes the whole stat, and the roster's own values are what it
      // takes. Priced at the roster average for that stat by the caller's
      // convention: here, one stat's worth of points is the honest floor.
      add('zeroedStats', per * _averageStatValue(stat));
    }

    // Denying an action is worth an action.
    if (def.preventsActions) {
      add('preventsActions', b.damagePerDamagingUse);
    }

    // Damage in and out.
    if (def.allDamageTakenMultiplier != null) {
      add('allDamageTakenMultiplier',
          (1 - def.allDamageTakenMultiplier!).abs() * b.damagePerCharacterTurn);
    }
    if (def.outgoingDamageMultiplier != null) {
      add('outgoingDamageMultiplier',
          (def.outgoingDamageMultiplier! - 1).abs() * b.damagePerCharacterTurn);
    }

    // Rolls.
    if (def.advantageRollTags.isNotEmpty) {
      add('advantageRollTags', damagePerAdvantage(b));
    }
    if (def.disadvantageRollTags.isNotEmpty) {
      add('disadvantageRollTags', damagePerAdvantage(b));
    }

    // Damage types, weighted by how often each shows up in the catalogue.
    for (final rule in def.damageTypeInteractions) {
      final share = damageTypeFrequency(rule.damageType, triggers: triggers);
      final swing = rule.kind == DamageInteractionKind.immune
          ? 1.0
          : (rule.vulnerableMultiplier - 1).abs();
      add('damageTypeInteractions',
          b.damagePerCharacterTurn * share * swing);
    }
    if (def.vulnerableToRandomDamageTypesCount != null) {
      // Random types, so the average share across the catalogue's types.
      final n = def.vulnerableToRandomDamageTypesCount!;
      final share = n / DamageType.values.length;
      add('vulnerableToRandomDamageTypesCount',
          b.damagePerCharacterTurn * share);
    }

    // The economy.
    if (def.trionCostMultiplier != null) {
      add('trionCostMultiplier',
          (def.trionCostMultiplier! - 1).abs() * b.damagePerDamagingUse);
    }
    if (def.trionCapacityDrainPercentToCauser != null) {
      add(
        'trionCapacityDrainPercentToCauser',
        def.trionCapacityDrainPercentToCauser! *
            b.averageTrionCapacity *
            b.damagePerTrion,
      );
    }

    // Denying a heal is worth the healing a character receives in a turn.
    if (def.preventsHealing) {
      add('preventsHealing', b.healingPerCharacterTurn);
    }

    // Being attacked at an advantage is the same swing as rolling at a
    // disadvantage, seen from the other side of the contest.
    if (def.sourceHasAdvantageAgainstTarget) {
      add('sourceHasAdvantageAgainstTarget', damagePerAdvantage(b));
    }

    // One attack denied, rather than a whole action.
    if (def.forcesNextAttackMiss || def.forcesNextAttackCriticalMiss) {
      add('forcesNextAttackMiss', b.damagePerAttackRoll);
    }

    // Everything with no derived conversion yet.
    if (def.misfireChance != null) skipped.add('misfireChance');
    if (def.preventsTargeting) skipped.add('preventsTargeting');
    if (def.cannotTargetSource) skipped.add('cannotTargetSource');
    if (def.locksRandomAbilityEachTurn) skipped.add('locksRandomAbilityEachTurn');
    if (def.reactions.isNotEmpty) skipped.add('reactions');
    if (def.preventsReposition) skipped.add('preventsReposition');
    if (def.preventsAllyInteraction) skipped.add('preventsAllyInteraction');
    if (def.forcesRepetitionOfLastAbility) {
      skipped.add('forcesRepetitionOfLastAbility');
    }
    if (def.locksOriginFromData) skipped.add('locksOriginFromData');
    if (def.locksToSingleChosenAbility) {
      skipped.add('locksToSingleChosenAbility');
    }
    if (def.sharesMagnitudeWithBoundEnemy) {
      skipped.add('sharesMagnitudeWithBoundEnemy');
    }
    if (def.randomizesOwnTargeting) skipped.add('randomizesOwnTargeting');
    if (def.repeatAbilityDamageMultiplier != null) {
      skipped.add('repeatAbilityDamageMultiplier');
    }
    if (def.rangedTargetsReducedByOne) {
      skipped.add('rangedTargetsReducedByOne');
    }

    final sum = perTurn.values.fold<double>(0, (a, b) => a + b);
    // An untimed effect is priced over one turn, because how long it lasts is
    // whatever removes it, and pricing it as infinite prices nothing.
    final turns = (duration ?? 1).toDouble();

    return StatusPrice(
      statusId: def.id,
      perTurn: sum,
      turns: turns,
      targets: targets,
      stacks: stacks,
      byField: perTurn,
      unpriced: skipped,
    );
  }

  /// What one use of [trigger] is worth against what it costs.
  ///
  ///     TV = (payload + SP x rider factor) / Trion cost x cooldown factor
  ///
  /// The payload is the damage it deals plus the health it restores, both
  /// scaled by how many targets it reaches and how many times it strikes,
  /// because the conversion table already treats health restored as damage
  /// undone and it would be incoherent to price a heal-over-time and not a
  /// heal.
  static double triggerValue(
    ActiveTrigger trigger, {
    SptvBaselines baselines = SptvBaselines.defaults,
    StatusEffectCatalog? statuses,
    TriggerCatalog? triggers,
  }) {
    if (trigger.trionCost == 0) return double.infinity;
    final catalog = statuses ?? StatusEffectCatalog.defaultCatalog;
    final reach = trigger.targetCount * trigger.hitsPerUse;

    var payload = 0.0;
    if (trigger.damage != null) payload += trigger.damage!.average * reach;
    if (trigger.healAmount != null) {
      payload += trigger.healAmount!.average * trigger.targetCount;
    }

    var statusPoints = 0.0;
    for (final application in trigger.inflictedStatusEffects) {
      if (!catalog.contains(application.statusEffectId)) continue;
      final price = priceStatus(
        catalog[application.statusEffectId],
        baselines: baselines,
        durationTurns: application.durationTurnsOverride,
        targets: trigger.targetCount,
        triggers: triggers,
      );
      statusPoints += price.total;
    }

    final riderFactor =
        trigger.targetAffiliation == TargetAffiliation.opponent
            ? baselines.riderLandsGivenHit
            : 1.0;

    return (payload + statusPoints * riderFactor) /
        trigger.trionCost *
        cooldownFactor(trigger.cooldownTurns);
  }

  /// Damage-equivalent of one point of [stat] per turn, or null when the
  /// conversion has not been derived yet.
  static double? _statPointValue(ModifiableStat stat, SptvBaselines b) =>
      switch (stat) {
        ModifiableStat.attack ||
        ModifiableStat.defense ||
        ModifiableStat.statusEffectInfliction ||
        ModifiableStat.statusEffectResistance =>
          damagePerOpposedStatPoint(b),
        ModifiableStat.armor => damagePerArmorPoint(b),
        ModifiableStat.maxHealth => 1.0,
        // Team Spirit, Trion Affinity, Critical Chance and FAT Chance each
        // need their own measurement, and none has been taken.
        ModifiableStat.teamSpirit ||
        ModifiableStat.trionAffinity ||
        ModifiableStat.criticalChance ||
        ModifiableStat.fatChance =>
          null,
      };

  /// The roster-average value of [stat], used when an effect takes the whole
  /// of it rather than a step of it.
  static double _averageStatValue(ModifiableStat stat) => switch (stat) {
        ModifiableStat.armor => 6.0,
        ModifiableStat.defense => 7.0,
        ModifiableStat.attack => 9.0,
        _ => 0.0,
      };
}

/// What one status effect is worth, and what the rule could not price.
class StatusPrice {
  final String statusId;

  /// Damage-equivalent per turn, one target, at [stacks] stacks.
  final double perTurn;

  /// Turns the price is counted over.
  final double turns;

  final int targets;
  final int stacks;

  /// Per-turn contribution of each field that could be priced.
  final Map<String, double> byField;

  /// Fields this status carries that have no derived conversion. A price with
  /// entries here is a floor, not an answer.
  final List<String> unpriced;

  const StatusPrice({
    required this.statusId,
    required this.perTurn,
    required this.turns,
    required this.targets,
    required this.stacks,
    required this.byField,
    required this.unpriced,
  });

  /// The Status Points this effect is worth: per-turn value over its whole
  /// duration, across every target it lands on.
  double get total => perTurn * turns * targets;

  /// Whether every field this status carries has a derived conversion.
  bool get isComplete => unpriced.isEmpty;
}

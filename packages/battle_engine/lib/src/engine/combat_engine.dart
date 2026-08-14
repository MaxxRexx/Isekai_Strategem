import '../constants.dart';
import '../models/damage_type.dart';
import '../models/status_effect.dart';
import '../util/dice.dart';
import 'character_battle_state.dart';

/// Outcome of a single opposed d20 attack roll.
class AttackRollOutcome {
  final D20RollResult attackerRoll;
  final D20RollResult defenderRoll;
  final bool isHit;
  final bool isCriticalHit;
  final bool isCriticalMiss;

  /// The natural-roll threshold that was in effect for [isCriticalHit],
  /// derived from the attacker's Critical Chance (see
  /// `CombatEngine.criticalHitThreshold`). Exposed mainly for tests/UI.
  final int criticalHitThreshold;

  const AttackRollOutcome({
    required this.attackerRoll,
    required this.defenderRoll,
    required this.isHit,
    required this.isCriticalHit,
    required this.isCriticalMiss,
    required this.criticalHitThreshold,
  });
}

/// The full step-by-step damage math behind one [CombatEngine.
/// resolveDamage] call - what a UI needs to explain "how did an attack
/// with this baseDamage end up dealing finalDamage" instead of only
/// showing the final number.
class DamageBreakdown {
  /// True iff a World-ability damage-prevention charge fully negated this
  /// hit - every other field is moot (0/unchanged) when this is true.
  final bool prevented;

  final int baseDamage;
  final bool criticalHitApplied;
  final double criticalHitMultiplier;

  /// Extra damage the critical hit added on top of [baseDamage] - 0 when
  /// [criticalHitApplied] is false. A crit doubles the *dice* only (see
  /// [CombatEngine.resolveDamageBreakdown]), so this is normally the
  /// ability's rolled dice again rather than the whole base.
  final int criticalBonusDamage;

  /// baseDamage plus [criticalBonusDamage] (rounded for display - armor is
  /// subtracted from the unrounded value internally, so this may be off by
  /// a fraction of 1 from that subtraction's actual input; shown for a
  /// human-readable crit step, not bit-for-bit reproduction of the
  /// internal float math).
  final int afterCriticalHit;

  final int armor;

  /// afterCriticalHit minus armor, floored at 0.
  final int afterArmor;

  /// Combined status-effect (e.g. Wet) damage-type multiplier - 1.0 if
  /// none apply.
  final double statusDamageTypeMultiplier;

  final bool damageResistanceApplied;

  final int finalDamage;

  const DamageBreakdown({
    required this.prevented,
    required this.baseDamage,
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
}

/// Resolves d20-based attack rolls and the post-hit damage pipeline
/// (crit doubling -> flat Armor reduction -> damage-type multipliers,
/// combining status effect interactions like Wet with static Damage
/// Resistance in one step). This mirrors the convention shared by both
/// D&D 5e/Baldur's Gate 3 (flat reductions like Heavy Armor Master apply
/// before resistance/vulnerability multipliers, which are combined into a
/// single multiplier rather than applied as separate sequential steps)
/// and Warhammer 40k-derived systems like Rogue Trader (flat Armor/
/// Toughness soak happens before any type-based multiplier). The brief
/// only pins down that Damage Resistance halving is applied "after all
/// other modifiers"; this ordering satisfies that while also giving
/// vulnerability (from status effects) and resistance the same treatment
/// instead of splitting them across opposite ends of the pipeline.
class CombatEngine {
  final CombatConfig config;
  final CriticalChanceConfig criticalChanceConfig;
  final DiceRoller diceRoller;

  CombatEngine({
    this.config = CombatConfig.defaults,
    this.criticalChanceConfig = CriticalChanceConfig.defaults,
    DiceRoller? diceRoller,
  }) : diceRoller = diceRoller ?? DiceRoller();

  /// The natural-roll threshold that counts as a critical hit for an
  /// attacker with [critChancePercent] Critical Chance: linear from
  /// `thresholdAtMinChance` (20) at `minChancePercent` (0%) down to
  /// `thresholdAtMaxChance` (5) at `maxChancePercent` (90%). Input is
  /// clamped to the configured range; the result is rounded to the
  /// nearest whole die face.
  int criticalHitThreshold(double critChancePercent) {
    final c = criticalChanceConfig;
    final clamped =
        critChancePercent.clamp(c.minChancePercent, c.maxChancePercent);
    final t = (clamped - c.minChancePercent) /
        (c.maxChancePercent - c.minChancePercent);
    final threshold = c.thresholdAtMinChance +
        t * (c.thresholdAtMaxChance - c.thresholdAtMinChance);
    return threshold.round();
  }

  /// Resolves one opposed attack roll: attacker d20+Attack vs. defender
  /// d20+Defense (or whatever stat an effect/ability substitutes - callers
  /// pass in whichever value is appropriate). Higher total hits; a tie
  /// favors the attacker (hits).
  ///
  /// [attackerCriticalChancePercent] is the attacker's effective Critical
  /// Chance (base stat + Team Spirit bonus - see `TeamSpiritCurve`),
  /// which lowers the natural-roll threshold for a critical hit (see
  /// `criticalHitThreshold`); it defaults to 0, i.e. only a natural 20
  /// crits, matching the stat's own floor. A roll meeting that threshold
  /// is a critical hit (auto-hit, doubled damage dice) regardless of
  /// totals; a
  /// natural 1 is always a critical miss (auto-miss) - Critical Chance
  /// only ever raises the crit rate, it never touches critical misses.
  AttackRollOutcome resolveAttackRoll({
    required int attackerAttack,
    required int defenderDefense,
    double attackerCriticalChancePercent = 0,
    RollContext? attackerContext,
    RollContext? defenderContext,
    int maxCritThreshold = 20,
  }) {
    final attackerRoll = diceRoller.rollD20(
      mode: (attackerContext ?? RollContext()).netMode,
      modifier: attackerAttack,
    );
    final defenderRoll = diceRoller.rollD20(
      mode: (defenderContext ?? RollContext()).netMode,
      modifier: defenderDefense,
    );

    // TEG Effect 5 (SSS crit widener) lowers the crit threshold ceiling:
    // the kept die crits when it meets the better (lower) of the
    // crit-chance threshold and the team's [maxCritThreshold] (18 at SSS).
    final baseThreshold = criticalHitThreshold(attackerCriticalChancePercent);
    final threshold =
        baseThreshold < maxCritThreshold ? baseThreshold : maxCritThreshold;
    final isCriticalHit = attackerRoll.kept >= threshold;
    final isCriticalMiss = attackerRoll.isCriticalMiss;
    final isHit = isCriticalHit ||
        (!isCriticalMiss && attackerRoll.total >= defenderRoll.total);

    return AttackRollOutcome(
      attackerRoll: attackerRoll,
      defenderRoll: defenderRoll,
      isHit: isHit,
      isCriticalHit: isCriticalHit,
      isCriticalMiss: isCriticalMiss,
      criticalHitThreshold: threshold,
    );
  }

  /// Resolves a Burst attack's multiple individual hits, each with its
  /// own to-hit roll.
  List<AttackRollOutcome> resolveBurst({
    required int hits,
    required int attackerAttack,
    required int defenderDefense,
    double attackerCriticalChancePercent = 0,
    RollContext? attackerContext,
    RollContext? defenderContext,
  }) {
    return List.generate(
      hits,
      (_) => resolveAttackRoll(
        attackerAttack: attackerAttack,
        defenderDefense: defenderDefense,
        attackerCriticalChancePercent: attackerCriticalChancePercent,
        attackerContext: attackerContext,
        defenderContext: defenderContext,
      ),
    );
  }

  /// Applies the critical-miss penalty to the attacker: "attacker's
  /// Defense and Team Spirit reduced 20% for 1 turn".
  void applyCriticalMissPenalty(CharacterBattleState attacker) {
    attacker.applyPercentPenalty(
      ModifiableStat.defense,
      config.criticalMissDefensePenaltyPct,
      config.criticalMissPenaltyDurationTurns,
    );
    attacker.applyPercentPenalty(
      ModifiableStat.teamSpirit,
      config.criticalMissTeamSpiritPenaltyPct,
      config.criticalMissPenaltyDurationTurns,
    );
  }

  /// Resolves final damage dealt to [target] for one hit of [damageType],
  /// given the pre-mitigation [baseDamage].
  ///
  /// Order: World-ability damage prevention (fully negates the whole
  /// instance, consuming one charge, if [target] has any remaining) ->
  /// critical dice doubling -> Armor (flat reduction, floor 0) -> combined
  /// damage-type multiplier (status effect interactions like Wet, and
  /// static/passive-granted Damage Resistance, multiplied together in one
  /// step). Flat reduction before type-based multipliers, with
  /// resistance/vulnerability combined rather than sequenced, matches
  /// both the 5e/BG3 convention (Sage Advice: flat reducers like Heavy
  /// Armor Master apply before resistance) and Rogue Trader-style
  /// Armor/Toughness soak.
  int resolveDamage({
    required int baseDamage,
    required DamageType damageType,
    required bool isCriticalHit,
    required CharacterBattleState target,
    int? criticalDiceComponent,
  }) =>
      resolveDamageBreakdown(
        baseDamage: baseDamage,
        damageType: damageType,
        isCriticalHit: isCriticalHit,
        target: target,
        criticalDiceComponent: criticalDiceComponent,
      ).finalDamage;

  /// Same pipeline as [resolveDamage], returning every intermediate step
  /// (see [DamageBreakdown]) instead of just the final number - what the
  /// Battle Log's roll-breakdown view uses to actually explain a hit's
  /// damage instead of presenting it as an unexplained number.
  /// [criticalDiceComponent] is the portion of [baseDamage] that came from
  /// the ability's own damage dice (already carrying whatever pre-crit
  /// multipliers were applied to [baseDamage]). A critical hit doubles
  /// *that* rather than the whole number, i.e. it rolls the damage dice
  /// twice and leaves the flat bonus alone - the 5e/BG3 convention. Pass
  /// null for damage that has no dice component to speak of (status ticks,
  /// flat unique-behavior damage), in which case a crit falls back to
  /// doubling the whole amount.
  ///
  /// Balance pass: doubling the whole number made a crit worth an entire
  /// extra attack, because most of an ability's damage lived in its flat
  /// bonus. Doubling only the dice keeps crits exciting without letting
  /// one lucky die decide the match.
  DamageBreakdown resolveDamageBreakdown({
    required int baseDamage,
    required DamageType damageType,
    required bool isCriticalHit,
    required CharacterBattleState target,
    int? criticalDiceComponent,
  }) {
    final criticalBonus = isCriticalHit
        ? (criticalDiceComponent ?? baseDamage) *
            (config.criticalHitDamageMultiplier - 1)
        : 0.0;

    final remainingPrevention = target.remainingDamagePreventionInstances;
    if (remainingPrevention != null && remainingPrevention > 0) {
      target.remainingDamagePreventionInstances = remainingPrevention - 1;
      return DamageBreakdown(
        prevented: true,
        baseDamage: baseDamage,
        criticalHitApplied: isCriticalHit,
        criticalHitMultiplier: config.criticalHitDamageMultiplier,
        criticalBonusDamage: criticalBonus.round(),
        afterCriticalHit: 0,
        armor: 0,
        afterArmor: 0,
        statusDamageTypeMultiplier: 1,
        damageResistanceApplied: false,
        finalDamage: 0,
      );
    }

    double damage = baseDamage + criticalBonus;
    final afterCriticalHit = damage.round();

    final armor = target.effectiveStats().armor;
    damage = (damage - armor).clamp(0, double.infinity);
    final afterArmor = damage.round();

    final statusMultiplier = target.statusDamageTypeMultiplier(damageType);
    damage *= statusMultiplier;
    final resistanceApplied = target.hasDamageResistance(damageType);
    if (resistanceApplied) {
      damage *= 0.5;
    }

    return DamageBreakdown(
      prevented: false,
      baseDamage: baseDamage,
      criticalHitApplied: isCriticalHit,
      criticalHitMultiplier: config.criticalHitDamageMultiplier,
      criticalBonusDamage: criticalBonus.round(),
      afterCriticalHit: afterCriticalHit,
      armor: armor,
      afterArmor: afterArmor,
      statusDamageTypeMultiplier: statusMultiplier,
      damageResistanceApplied: resistanceApplied,
      finalDamage: damage.round(),
    );
  }
}

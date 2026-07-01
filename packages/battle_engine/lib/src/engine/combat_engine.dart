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

  const AttackRollOutcome({
    required this.attackerRoll,
    required this.defenderRoll,
    required this.isHit,
    required this.isCriticalHit,
    required this.isCriticalMiss,
  });
}

/// Resolves d20-based attack rolls and the post-hit damage pipeline
/// (crit doubling -> status damage-type interactions -> Armor ->
/// Damage Resistance, in that order - the brief only pins down that
/// Damage Resistance halving is applied "after all other modifiers", so
/// this ordering for the earlier steps is a documented assumption).
class CombatEngine {
  final CombatConfig config;
  final DiceRoller diceRoller;

  CombatEngine({
    this.config = CombatConfig.defaults,
    DiceRoller? diceRoller,
  }) : diceRoller = diceRoller ?? DiceRoller();

  /// Resolves one opposed attack roll: attacker d20+Attack vs. defender
  /// d20+Defense (or whatever stat an effect/ability substitutes - callers
  /// pass in whichever value is appropriate). Higher total hits; a tie is
  /// a miss (the brief only specifies "higher result hits", so equal
  /// totals favor the defender as the more conservative reading). A
  /// natural 20 on the attacker's kept die is always a critical hit
  /// (auto-hit, double damage) regardless of totals; a natural 1 is
  /// always a critical miss (auto-miss).
  AttackRollOutcome resolveAttackRoll({
    required int attackerAttack,
    required int defenderDefense,
    RollContext? attackerContext,
    RollContext? defenderContext,
  }) {
    final attackerRoll = diceRoller.rollD20(
      mode: (attackerContext ?? RollContext()).netMode,
      modifier: attackerAttack,
    );
    final defenderRoll = diceRoller.rollD20(
      mode: (defenderContext ?? RollContext()).netMode,
      modifier: defenderDefense,
    );

    final isCriticalHit = attackerRoll.isCriticalHit;
    final isCriticalMiss = attackerRoll.isCriticalMiss;
    final isHit = isCriticalHit ||
        (!isCriticalMiss && attackerRoll.total > defenderRoll.total);

    return AttackRollOutcome(
      attackerRoll: attackerRoll,
      defenderRoll: defenderRoll,
      isHit: isHit,
      isCriticalHit: isCriticalHit,
      isCriticalMiss: isCriticalMiss,
    );
  }

  /// Resolves a Burst attack's multiple individual hits, each with its
  /// own to-hit roll.
  List<AttackRollOutcome> resolveBurst({
    required int hits,
    required int attackerAttack,
    required int defenderDefense,
    RollContext? attackerContext,
    RollContext? defenderContext,
  }) {
    return List.generate(
      hits,
      (_) => resolveAttackRoll(
        attackerAttack: attackerAttack,
        defenderDefense: defenderDefense,
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
  /// Order: critical doubling -> status effect damage-type interactions
  /// (e.g. Wet) -> Armor (flat reduction, floor 0) -> Damage Resistance
  /// (halves, applied last per the brief).
  int resolveDamage({
    required int baseDamage,
    required DamageType damageType,
    required bool isCriticalHit,
    required CharacterBattleState target,
  }) {
    double damage = baseDamage.toDouble();

    if (isCriticalHit) damage *= config.criticalHitDamageMultiplier;

    damage *= target.statusDamageTypeMultiplier(damageType);

    final armor = target.effectiveStats().armor;
    damage = (damage - armor).clamp(0, double.infinity);

    if (target.character.damageResistances.contains(damageType)) {
      damage *= 0.5;
    }

    return damage.round();
  }
}

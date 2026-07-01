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
  final DiceRoller diceRoller;

  CombatEngine({
    this.config = CombatConfig.defaults,
    DiceRoller? diceRoller,
  }) : diceRoller = diceRoller ?? DiceRoller();

  /// Resolves one opposed attack roll: attacker d20+Attack vs. defender
  /// d20+Defense (or whatever stat an effect/ability substitutes - callers
  /// pass in whichever value is appropriate). Higher total hits; a tie
  /// favors the attacker (hits). A natural 20 on the attacker's kept die
  /// is always a critical hit (auto-hit, double damage) regardless of
  /// totals; a natural 1 is always a critical miss (auto-miss).
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
        (!isCriticalMiss && attackerRoll.total >= defenderRoll.total);

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
  /// Order: critical doubling -> Armor (flat reduction, floor 0) ->
  /// combined damage-type multiplier (status effect interactions like
  /// Wet, and static Damage Resistance, multiplied together in one step).
  /// Flat reduction before type-based multipliers, with
  /// resistance/vulnerability combined rather than sequenced, matches
  /// both the 5e/BG3 convention (Sage Advice: flat reducers like Heavy
  /// Armor Master apply before resistance) and Rogue Trader-style
  /// Armor/Toughness soak.
  int resolveDamage({
    required int baseDamage,
    required DamageType damageType,
    required bool isCriticalHit,
    required CharacterBattleState target,
  }) {
    double damage = baseDamage.toDouble();

    if (isCriticalHit) damage *= config.criticalHitDamageMultiplier;

    final armor = target.effectiveStats().armor;
    damage = (damage - armor).clamp(0, double.infinity);

    damage *= target.statusDamageTypeMultiplier(damageType);
    if (target.character.damageResistances.contains(damageType)) {
      damage *= 0.5;
    }

    return damage.round();
  }
}

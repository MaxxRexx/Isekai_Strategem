import '../constants.dart';
import '../models/character.dart';
import '../models/damage_type.dart';
import '../models/passive_effect.dart';
import '../models/stats.dart';
import '../models/status_effect.dart';
import '../models/status_effect_catalog.dart';
import '../models/trigger.dart';
import '../models/world_ability_effect.dart';
import '../util/dice.dart';

class _AbilityUseRecord {
  final String triggerId;
  final int baseCooldownTurns;
  _AbilityUseRecord(this.triggerId, this.baseCooldownTurns);
}

/// A temporary percentage reduction to a stat, e.g. the critical-miss
/// penalty ("Defense and Team Spirit reduced 20% for 1 turn"). Kept
/// separate from the named [StatusEffectDefinition] catalog since it's a
/// generic combat-rule side effect rather than one of the named status
/// effects.
class TempPercentPenalty {
  final ModifiableStat stat;
  final double percent;
  int remainingTurns;
  TempPercentPenalty(this.stat, this.percent, this.remainingTurns);
}

/// Mutable in-battle state for a single character: current health, active
/// status effects, ability cooldowns, and Full Arms Trigger bookkeeping.
/// The [Character] itself stays an immutable template so it can be reused
/// across battles/tests.
class CharacterBattleState {
  final Character character;
  int currentHealth;

  final List<StatusEffectInstance> statusEffects = [];

  /// Trigger id -> turns remaining before it can be used again.
  final Map<String, int> cooldowns = {};

  /// Turns remaining before this character can roll for FAT again. 0
  /// means ready.
  int fatCooldownRemaining = 0;

  /// Set when this character actually used FAT for 2+ abilities in a
  /// turn; halves their (post-modifier) Trion Affinity for the following
  /// turn only, then is cleared.
  bool trionAffinityHalvedNextTurn = false;

  bool fatTriggeredThisTurn = false;

  final List<_AbilityUseRecord> _abilitiesUsedThisTurn = [];

  final List<TempPercentPenalty> tempPercentPenalties = [];

  /// Passive effects currently equipped (from passive Triggers and any
  /// Black Trigger passive abilities), applied continuously for as long
  /// as this state exists - set once at battle start from the
  /// character's Loadout.
  final List<PassiveEffect> equippedPassiveEffects;

  /// Remaining charges of a World ability's damage-prevention pool, if
  /// the character has one equipped (null if not applicable). Each
  /// instance of damage fully negates and decrements this by 1.
  int? remainingDamagePreventionInstances;

  /// Whether this character still has an unused "survive lethal damage
  /// once" World ability charge.
  bool hasSurviveLethalDamageCharge;

  CharacterBattleState(
    this.character, {
    List<PassiveEffect> equippedPassiveEffects = const [],
    WorldAbilityEffect? worldAbility,
  })  : currentHealth = character.baseStats.maxHealth,
        equippedPassiveEffects = equippedPassiveEffects,
        remainingDamagePreventionInstances =
            worldAbility?.damagePreventionInstances,
        hasSurviveLethalDamageCharge =
            worldAbility?.surviveLethalDamageOnce ?? false;

  /// Applies a temporary percentage reduction to [stat] (e.g. the
  /// critical-miss penalty). Multiple active penalties on the same stat
  /// stack additively before being clamped to at most a 100% reduction.
  void applyPercentPenalty(ModifiableStat stat, double percent, int turns) {
    tempPercentPenalties.add(TempPercentPenalty(stat, percent, turns));
  }

  bool get isAlive => currentHealth > 0;

  bool get canTriggerFat => fatCooldownRemaining <= 0;

  int get abilitiesUsedThisTurnCount => _abilitiesUsedThisTurn.length;

  bool isActionPrevented([StatusEffectCatalog? catalog]) {
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    return statusEffects.any((i) => cat[i.definitionId].preventsActions);
  }

  bool isInvulnerableTo(String statusEffectId) =>
      character.statusInvulnerabilities.contains(statusEffectId) ||
      equippedPassiveEffects.any(
          (e) => e.statusInvulnerabilitiesGranted.contains(statusEffectId));

  /// Whether this character resists (halves) damage of [type], from
  /// either the character's permanent `damageResistances` or a currently
  /// equipped passive effect.
  bool hasDamageResistance(DamageType type) =>
      character.damageResistances.contains(type) ||
      equippedPassiveEffects
          .any((e) => e.damageResistancesGranted.contains(type));

  /// Records that [trigger] was used this turn; cooldown application
  /// (including any FAT doubling penalty) happens in `endTurn`.
  void recordAbilityUse(ActiveTrigger trigger) {
    _abilitiesUsedThisTurn
        .add(_AbilityUseRecord(trigger.id, trigger.cooldownTurns));
  }

  /// Finalizes cooldowns/penalties for abilities used this turn and
  /// resets per-turn bookkeeping. See `FatEngine.endTurn` for the FAT
  /// penalty rule this implements.
  void endTurn({FatConfig fatConfig = FatConfig.defaults}) {
    // Tick down cooldowns from abilities used on *previous* turns before
    // applying fresh cooldowns for abilities used this turn, so a newly
    // set cooldown isn't immediately decremented within the same call.
    cooldowns.updateAll((_, turns) => turns > 0 ? turns - 1 : 0);
    cooldowns.removeWhere((_, turns) => turns <= 0);

    final multiAbilityPenalty =
        _abilitiesUsedThisTurn.length >= fatConfig.multiAbilityPenaltyThreshold;

    for (final use in _abilitiesUsedThisTurn) {
      final cooldown = multiAbilityPenalty
          ? (use.baseCooldownTurns * fatConfig.cooldownDoubleMultiplier).round()
          : use.baseCooldownTurns;
      if (cooldown > 0) cooldowns[use.triggerId] = cooldown;
    }

    trionAffinityHalvedNextTurn = multiAbilityPenalty;

    _abilitiesUsedThisTurn.clear();
    fatTriggeredThisTurn = false;

    if (fatCooldownRemaining > 0) fatCooldownRemaining--;

    for (final penalty in tempPercentPenalties) {
      penalty.remainingTurns--;
    }
    tempPercentPenalties.removeWhere((p) => p.remainingTurns <= 0);
  }

  /// Effective stats after folding in active status effect modifiers and
  /// the FAT Trion Affinity halving penalty (if active this turn).
  Stats effectiveStats({
    StatusEffectCatalog? catalog,
    FatConfig fatConfig = FatConfig.defaults,
  }) {
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    final base = character.baseStats;

    final deltas = <ModifiableStat, double>{};
    final zeroed = <ModifiableStat>{};

    for (final instance in statusEffects) {
      final def = cat[instance.definitionId];
      def.flatStatModifiers.forEach((stat, delta) {
        deltas[stat] = (deltas[stat] ?? 0) + delta;
      });
      if (def.perRemainingTurnStatModifiers.isNotEmpty) {
        final remaining = instance.remainingTurns ?? 0;
        def.perRemainingTurnStatModifiers.forEach((stat, delta) {
          deltas[stat] = (deltas[stat] ?? 0) + delta * remaining;
        });
      }
      zeroed.addAll(def.zeroedStats);
    }

    for (final passive in equippedPassiveEffects) {
      passive.flatStatModifiers.forEach((stat, delta) {
        deltas[stat] = (deltas[stat] ?? 0) + delta;
      });
    }

    final percentPenalties = <ModifiableStat, double>{};
    for (final penalty in tempPercentPenalties) {
      percentPenalties[penalty.stat] =
          (percentPenalties[penalty.stat] ?? 0) + penalty.percent;
    }

    double resolve(ModifiableStat stat, num baseValue) {
      if (zeroed.contains(stat)) return 0;
      final value = baseValue + (deltas[stat] ?? 0);
      final penaltyPct = (percentPenalties[stat] ?? 0).clamp(0.0, 1.0);
      return value * (1 - penaltyPct);
    }

    var trionAffinity =
        resolve(ModifiableStat.trionAffinity, base.trionAffinity);
    if (trionAffinityHalvedNextTurn) {
      trionAffinity *= fatConfig.trionAffinityPenaltyMultiplier;
    }

    return base.copyWith(
      attack: resolve(ModifiableStat.attack, base.attack).round(),
      defense: resolve(ModifiableStat.defense, base.defense).round(),
      armor: resolve(ModifiableStat.armor, base.armor).round(),
      maxHealth: resolve(ModifiableStat.maxHealth, base.maxHealth).round(),
      trionAffinity: trionAffinity.round(),
      teamSpirit: resolve(ModifiableStat.teamSpirit, base.teamSpirit).round(),
      criticalChance:
          resolve(ModifiableStat.criticalChance, base.criticalChance),
      fatChance: resolve(ModifiableStat.fatChance, base.fatChance),
      statusEffectInfliction: resolve(ModifiableStat.statusEffectInfliction,
              base.statusEffectInfliction)
          .round(),
      statusEffectResistance: resolve(ModifiableStat.statusEffectResistance,
              base.statusEffectResistance)
          .round(),
    );
  }

  /// Builds a [RollContext] pre-populated with disadvantage sources from
  /// this character's active status effects for the given roll category -
  /// this is "this character's own roll" for that category, whether it's
  /// their own outgoing attack roll (Poisoned) or their own
  /// status-resistance roll rolled when someone attempts to inflict a new
  /// effect on them (Bleeding - see `StatusEffectEngine.resolveInfliction`).
  /// Callers may add further advantage/disadvantage sources (e.g. from an
  /// ability) before rolling.
  RollContext rollContextFor(StatusRollTag tag,
      {StatusEffectCatalog? catalog}) {
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    final context = RollContext();
    for (final instance in statusEffects) {
      final def = cat[instance.definitionId];
      if (def.disadvantageRollTags.contains(tag)) {
        context.addDisadvantage('status:${def.id}');
      }
    }
    return context;
  }

  /// Combined damage-type multiplier contributed by active status
  /// effects (Wet-style immune/vulnerable interactions, and Sickened's
  /// randomly-chosen vulnerable types). Does not include the character's
  /// static Damage Resistance, which is a separate, final-step halving
  /// applied by the combat engine.
  double statusDamageTypeMultiplier(DamageType type,
      {StatusEffectCatalog? catalog}) {
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    var multiplier = 1.0;
    for (final instance in statusEffects) {
      final def = cat[instance.definitionId];
      for (final rule in def.damageTypeInteractions) {
        if (rule.damageType != type) continue;
        if (rule.kind == DamageInteractionKind.immune) return 0.0;
        multiplier *= rule.vulnerableMultiplier;
      }
      if (def.vulnerableToRandomDamageTypesCount != null) {
        final chosen =
            instance.data['vulnerableDamageTypes'] as Set<DamageType>?;
        if (chosen != null && chosen.contains(type)) {
          multiplier *= 2.0;
        }
      }
    }
    return multiplier;
  }
}

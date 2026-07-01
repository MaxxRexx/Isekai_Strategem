import '../models/damage_type.dart';
import '../models/status_effect.dart';
import '../models/status_effect_catalog.dart';
import '../models/trigger.dart';
import '../util/dice.dart';
import 'character_battle_state.dart';

class TurnStartDamageEvent {
  final DamageType damageType;
  final int amount;
  const TurnStartDamageEvent(this.damageType, this.amount);
}

class TrionDrainEvent {
  final String causerCharacterId;
  final int amount;
  const TrionDrainEvent(this.causerCharacterId, this.amount);
}

class TurnStartHealEvent {
  final int amount;
  const TurnStartHealEvent(this.amount);
}

class StatusTickResult {
  final List<TurnStartDamageEvent> damageEvents;
  final List<TrionDrainEvent> trionDrainEvents;
  final List<TurnStartHealEvent> healEvents;
  const StatusTickResult(
      this.damageEvents, this.trionDrainEvents, this.healEvents);
}

/// Outcome of a single opposed status-infliction roll. Mirrors
/// `AttackRollOutcome` in combat_engine.dart, since the roll mechanic is
/// now structurally identical to attack resolution.
class InflictionRollOutcome {
  final D20RollResult causerRoll;
  final D20RollResult targetRoll;
  final bool applies;
  final bool isCriticalSuccess;
  final bool isCriticalFailure;

  const InflictionRollOutcome({
    required this.causerRoll,
    required this.targetRoll,
    required this.applies,
    required this.isCriticalSuccess,
    required this.isCriticalFailure,
  });
}

/// Resolves status effect infliction rolls, applies effects (including
/// any randomized instance data), and ticks them at the start of a
/// character's turn.
class StatusEffectEngine {
  final StatusEffectCatalog catalog;
  final DiceRoller diceRoller;

  StatusEffectEngine({
    StatusEffectCatalog? catalog,
    DiceRoller? diceRoller,
  })  : catalog = catalog ?? StatusEffectCatalog.defaultCatalog,
        diceRoller = diceRoller ?? DiceRoller();

  /// Resolves whether a status effect infliction attempt succeeds: an
  /// opposed roll where the causer rolls d20+Infliction, the target rolls
  /// d20+Resistance, and the effect applies if the causer's total is
  /// greater than or equal to the target's (ties favor the causer,
  /// matching `CombatEngine.resolveAttackRoll`'s tie-breaking). A natural
  /// 20 on the causer's kept die always applies the effect regardless of
  /// totals; a natural 1 always fails it - again mirroring
  /// `resolveAttackRoll`, since this is now the same opposed d20+mod
  /// contest shape.
  ///
  /// This also resolves what used to be a real tension with Bleeding
  /// ("disadvantage on status resistance rolls", intended as a debuff
  /// making the bleeding character more vulnerable to new effects): under
  /// the old single-roll subtractive formula, disadvantage on that one
  /// roll always *protected* whoever it was applied to. Under this
  /// two-roll opposed model, disadvantage on the *target's* own roll
  /// naturally weakens their side of the contest, correctly raising the
  /// apply rate against them - no special-casing required.
  InflictionRollOutcome resolveInfliction({
    required int causerInfliction,
    required int targetResistance,
    RollContext? causerRollContext,
    RollContext? targetRollContext,
  }) {
    final causerRoll = diceRoller.rollD20(
      mode: (causerRollContext ?? RollContext()).netMode,
      modifier: causerInfliction,
    );
    final targetRoll = diceRoller.rollD20(
      mode: (targetRollContext ?? RollContext()).netMode,
      modifier: targetResistance,
    );

    final isCriticalSuccess = causerRoll.isCriticalHit;
    final isCriticalFailure = causerRoll.isCriticalMiss;
    final applies = isCriticalSuccess ||
        (!isCriticalFailure && causerRoll.total >= targetRoll.total);

    return InflictionRollOutcome(
      causerRoll: causerRoll,
      targetRoll: targetRoll,
      applies: applies,
      isCriticalSuccess: isCriticalSuccess,
      isCriticalFailure: isCriticalFailure,
    );
  }

  /// Attempts to apply [statusEffectId] to [target]. Returns false without
  /// applying anything if the target is invulnerable to it. Does not
  /// perform the infliction roll itself - call [resolveInfliction] first
  /// if the effect is being inflicted rather than granted unconditionally
  /// (e.g. a self-buff like Prepared).
  bool apply(
    CharacterBattleState target,
    String statusEffectId, {
    String? sourceCharacterId,
    int? durationOverride,
  }) {
    if (target.isInvulnerableTo(statusEffectId)) return false;
    final def = catalog[statusEffectId];

    final instance = StatusEffectInstance(
      definitionId: statusEffectId,
      remainingTurns: durationOverride ?? def.defaultDurationTurns,
      sourceCharacterId: sourceCharacterId,
    );

    if (def.vulnerableToRandomDamageTypesCount != null) {
      final allTypes = DamageType.values.toList()..shuffle(diceRoller.random);
      instance.data['vulnerableDamageTypes'] =
          allTypes.take(def.vulnerableToRandomDamageTypesCount!).toSet();
    }

    target.statusEffects.add(instance);
    return true;
  }

  /// Re-picks the locked ability for any active Prone-like effect on
  /// [target] (locksRandomAbilityEachTurn), given their currently
  /// equipped active Triggers. No-op if there are no equipped triggers.
  void refreshAbilityLocks(
      CharacterBattleState target, List<ActiveTrigger> equippedTriggers) {
    if (equippedTriggers.isEmpty) return;
    for (final instance in target.statusEffects) {
      final def = catalog[instance.definitionId];
      if (!def.locksRandomAbilityEachTurn) continue;
      final pick =
          equippedTriggers[diceRoller.random.nextInt(equippedTriggers.length)];
      instance.data['lockedAbilityId'] = pick.id;
    }
  }

  /// Applies start-of-turn effects (damage ticks, Trion drain) for
  /// [target] and ticks down/removes expired instances. Health and Trion
  /// pool mutation is left to the caller via the returned events, keeping
  /// this engine decoupled from the rest of battle state.
  StatusTickResult tickStartOfTurn(CharacterBattleState target) {
    final damageEvents = <TurnStartDamageEvent>[];
    final drainEvents = <TrionDrainEvent>[];
    final healEvents = <TurnStartHealEvent>[];

    for (final instance in List.of(target.statusEffects)) {
      final def = catalog[instance.definitionId];

      if (def.turnStartDamage != null && def.turnStartDamageType != null) {
        final amount = def.turnStartDamage!.roll(diceRoller);
        damageEvents
            .add(TurnStartDamageEvent(def.turnStartDamageType!, amount));
      }

      if (def.turnStartHeal != null) {
        healEvents.add(TurnStartHealEvent(def.turnStartHeal!.roll(diceRoller)));
      }

      if (def.trionCapacityDrainPercentToCauser != null &&
          instance.sourceCharacterId != null) {
        final amount = (target.character.baseStats.trionCapacity *
                def.trionCapacityDrainPercentToCauser!)
            .round();
        drainEvents.add(TrionDrainEvent(instance.sourceCharacterId!, amount));
      }

      if (instance.remainingTurns != null) {
        instance.remainingTurns = instance.remainingTurns! - 1;
      }
    }

    target.statusEffects
        .removeWhere((i) => i.remainingTurns != null && i.remainingTurns! <= 0);

    return StatusTickResult(damageEvents, drainEvents, healEvents);
  }
}

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

class StatusTickResult {
  final List<TurnStartDamageEvent> damageEvents;
  final List<TrionDrainEvent> trionDrainEvents;
  const StatusTickResult(this.damageEvents, this.trionDrainEvents);
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

  /// Resolves whether a status effect infliction attempt succeeds.
  ///
  /// ## Design note (flagged ambiguity)
  /// The brief gives a concrete numeric example ("+1 resistance subtracts
  /// 1 from the result; if the modified result is less than the causer's
  /// Status Effect Infliction value, the effect fails") but doesn't say
  /// whose roll it is. This is implemented as a d20 roll modified by the
  /// target's Resistance: `modified = d20 - targetResistance`; the effect
  /// applies if `modified >= causerInfliction`. Higher Resistance lowers
  /// the modified result, making it harder to clear the Infliction bar,
  /// i.e. higher Resistance = effect fails more often, matching the
  /// worked example.
  ///
  /// Mathematically, *disadvantage* on this roll also lowers the apply
  /// rate (same direction as raising Resistance) - a lower roll is always
  /// harder to clear the bar with, whichever side "owns" the roll. That
  /// initially looked like a problem for Bleeding ("disadvantage on
  /// status resistance rolls", intended as a debuff making the bleeding
  /// character *more* vulnerable to new effects): naively granting
  /// disadvantage on the bleeding character's own roll would actually
  /// protect them, the opposite of the intent. Rather than change this
  /// formula (which would also invert Resistance's protective direction -
  /// see the worked example above), Bleeding instead grants *advantage*
  /// on this same roll to whoever is attempting to inflict a new effect
  /// on the bleeding character (`StatusEffectDefinition.advantageRollTags`
  /// on `StatusRollTag.statusResistanceRoll`, folded in via
  /// `CharacterBattleState.rollContextFor`). That raises the apply rate
  /// against a bleeding target - correctly a debuff - while leaving
  /// Resistance's math untouched.
  bool resolveInfliction({
    required int causerInfliction,
    required int targetResistance,
    RollContext? targetRollContext,
  }) {
    final mode = (targetRollContext ?? RollContext()).netMode;
    final roll = diceRoller.rollD20(mode: mode);
    final modified = roll.kept - targetResistance;
    return modified >= causerInfliction;
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
  /// equipped Triggers. No-op if there are no equipped triggers.
  void refreshAbilityLocks(
      CharacterBattleState target, List<Trigger> equippedTriggers) {
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

    for (final instance in List.of(target.statusEffects)) {
      final def = catalog[instance.definitionId];

      if (def.turnStartDamage != null && def.turnStartDamageType != null) {
        final amount = def.turnStartDamage!.roll(diceRoller);
        damageEvents
            .add(TurnStartDamageEvent(def.turnStartDamageType!, amount));
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

    return StatusTickResult(damageEvents, drainEvents);
  }
}

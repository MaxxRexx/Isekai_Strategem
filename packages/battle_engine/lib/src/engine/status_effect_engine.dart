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
    Map<String, Object?>? instanceData,
  }) {
    if (target.isInvulnerableTo(statusEffectId)) return false;
    final def = catalog[statusEffectId];

    // Item 3b's second axis: something the target already carries may react
    // to this status landing. No shipped row uses it yet (all twelve fire on
    // a damage type), and it is here because the table grows in wave 3 and
    // because it is the same two lines either way.
    _fireStatusReactions(target, statusEffectId);

    // Re-applying an effect never adds a second copy. It refreshes the one
    // that is there, and for the twelve that stack (item 5b) it also counts
    // another stack, up to the definition's maximum. Two instances ticking
    // separately and counting down out of step is unreadable on a character
    // strip and doubles a magnitude nobody priced.
    final existingIndex =
        target.statusEffects.indexWhere((i) => i.definitionId == statusEffectId);
    if (existingIndex >= 0) {
      final existing = target.statusEffects[existingIndex];
      final refreshed = durationOverride ?? def.defaultDurationTurns;
      // The longer of the two wins, so a short re-application never cuts a
      // long one short.
      if (refreshed == null || existing.remainingTurns == null) {
        existing.remainingTurns = null;
      } else if (refreshed > existing.remainingTurns!) {
        existing.remainingTurns = refreshed;
      }
      if (def.stacks && existing.stacks < def.maxStacks) {
        existing.stacks++;
      }
      // sourceCharacterId is final on the instance and the first applier
      // keeps the credit, which is what the "cannot target its source" rules
      // read.
      if (instanceData != null) existing.data.addAll(instanceData);
      // A refresh on the holder's own turn sits that turn out too, for the
      // same reason a fresh application does.
      if (target.isTakingTurn) existing.skipsNextCountdown = true;
      return true;
    }

    final instance = StatusEffectInstance(
      definitionId: statusEffectId,
      remainingTurns: durationOverride ?? def.defaultDurationTurns,
      sourceCharacterId: sourceCharacterId,
      skipsNextCountdown: target.isTakingTurn,
      data: instanceData,
    );

    if (def.vulnerableToRandomDamageTypesCount != null) {
      final allTypes = DamageType.values.toList()..shuffle(diceRoller.random);
      instance.data['vulnerableDamageTypes'] =
          allTypes.take(def.vulnerableToRandomDamageTypesCount!).toSet();
    }

    target.statusEffects.add(instance);
    return true;
  }

  /// Resolves any reaction that [incomingStatusId] landing sets off on a
  /// status [target] already carries (item 3b).
  ///
  /// Runs before the incoming status is applied, so a reaction that clears
  /// what is there leaves the new one to land on a clean slate. A reaction is
  /// never contested (decision #G), so the results are applied directly.
  void _fireStatusReactions(
    CharacterBattleState target,
    String incomingStatusId,
  ) {
    // A reaction applies a status, which can fire another reaction. No
    // shipped row can loop (all twelve fire on damage types), but the table
    // grows in wave 3 and a pair of statuses that each react to the other
    // would hang the battle rather than misbehave visibly. One level deep is
    // all any of the designed rows need.
    if (_firingStatusReactions) return;
    _firingStatusReactions = true;
    try {
      _fireStatusReactionsOnce(target, incomingStatusId);
    } finally {
      _firingStatusReactions = false;
    }
  }

  bool _firingStatusReactions = false;

  void _fireStatusReactionsOnce(
    CharacterBattleState target,
    String incomingStatusId,
  ) {
    for (final instance in List.of(target.statusEffects)) {
      if (!contains(instance.definitionId)) continue;
      final reaction =
          catalog[instance.definitionId].reactionToStatus(incomingStatusId);
      if (reaction == null) continue;

      if (reaction.consumesTrigger) {
        target.statusEffects.removeWhere((i) => identical(i, instance));
      }
      if (reaction.alsoRemoves != null) {
        target.statusEffects
            .removeWhere((i) => i.definitionId == reaction.alsoRemoves);
      }
      if (reaction.becomes != null && reaction.becomes != incomingStatusId) {
        apply(target, reaction.becomes!);
      }
    }
  }

  /// Whether [id] names a catalogued status.
  bool contains(String id) => catalog.contains(id);

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

  /// Applies start-of-turn effects (damage ticks, heals, Trion drain) for
  /// [target]. Health and Trion pool mutation is left to the caller via
  /// the returned events, keeping this engine decoupled from the rest of
  /// battle state.
  ///
  /// The duration countdown deliberately does **not** happen here: it runs
  /// at the end of the holder's turn instead, in [tickEndOfTurn]. See that
  /// method for why (item #D).
  StatusTickResult tickStartOfTurn(CharacterBattleState target) {
    final damageEvents = <TurnStartDamageEvent>[];
    final drainEvents = <TrionDrainEvent>[];
    final healEvents = <TurnStartHealEvent>[];

    for (final instance in List.of(target.statusEffects)) {
      final def = catalog[instance.definitionId];

      // Item 5b: every magnitude an effect carries is multiplied by how many
      // times it has stacked. One instance, one duration, three times the
      // bleed.
      final stacks = instance.stacks;

      if (def.turnStartDamage != null && def.turnStartDamageType != null) {
        final amount = def.turnStartDamage!.roll(diceRoller) * stacks;
        damageEvents
            .add(TurnStartDamageEvent(def.turnStartDamageType!, amount));
      }

      if (def.turnStartHeal != null) {
        healEvents.add(
            TurnStartHealEvent(def.turnStartHeal!.roll(diceRoller) * stacks));
      }

      if (def.trionCapacityDrainPercentToCauser != null &&
          instance.sourceCharacterId != null) {
        final amount = (target.character.baseStats.trionCapacity *
                def.trionCapacityDrainPercentToCauser! *
                stacks)
            .round();
        drainEvents.add(TrionDrainEvent(instance.sourceCharacterId!, amount));
      }

    }

    return StatusTickResult(damageEvents, drainEvents, healEvents);
  }

  /// Counts down [target]'s timed status effects and removes the ones that
  /// have run out, returning what expired (for the battle log).
  ///
  /// **Item #D.** This used to happen at the *start* of the holder's turn,
  /// alongside the ticks above, and that made one word mean three things.
  /// A 1-turn Stun put on an enemy was decremented to zero and removed at
  /// the start of their turn, before they acted, so it did nothing at all;
  /// a debuff of N turns delivered N damage ticks but only N-1 afflicted
  /// turns; and a self-buff of N covered N of the opponent's turns.
  ///
  /// Counting down at the end of the holder's turn, and skipping the turn
  /// the effect was applied on (see
  /// [StatusEffectInstance.skipsNextCountdown]), makes N mean the same
  /// thing everywhere: **the holder's next N turns**. A 1-turn Stun costs
  /// exactly one action, a 3-turn Bleeding still ticks three times, and a
  /// ward still covers the answers it always covered.
  ///
  /// Untimed effects (`remainingTurns == null`) are left alone; they end
  /// only when something removes them.
  List<StatusEffectInstance> tickEndOfTurn(CharacterBattleState target) {
    final expired = <StatusEffectInstance>[];

    for (final instance in target.statusEffects) {
      if (instance.remainingTurns == null) continue;
      if (instance.skipsNextCountdown) {
        instance.skipsNextCountdown = false;
        continue;
      }
      instance.remainingTurns = instance.remainingTurns! - 1;
      if (instance.remainingTurns! <= 0) expired.add(instance);
    }

    target.statusEffects
        .removeWhere((i) => i.remainingTurns != null && i.remainingTurns! <= 0);

    return expired;
  }
}

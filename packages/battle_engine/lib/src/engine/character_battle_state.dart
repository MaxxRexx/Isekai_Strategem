import '../constants.dart';
import '../models/battle_position.dart';
import '../models/character.dart';
import '../models/combatant_id.dart';
import '../models/damage_type.dart';
import '../models/passive_counter.dart';
import '../models/passive_effect.dart';
import '../models/reactive_effect.dart';
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

/// Where a character stands in the Bail Out sequence (work item #2).
///
/// Deliberately separate from health, and deliberately not a second reading
/// of "alive". Thirty-odd places already agree that zero health means gone,
/// and all of them should keep agreeing; only two questions get a different
/// answer while a body is [bailingOut], and both are listed on
/// [CharacterBattleState.isOnBoard].
enum BailOutState {
  /// Not bailing: still fighting, or destroyed outright with no window.
  none,

  /// The body is still on the board. It cannot act and cannot be healed,
  /// but it is a legal target for a damaging enemy ability and it still
  /// screens whoever is standing behind it.
  bailingOut,

  /// The window closed untouched: the operator was recalled and their squad
  /// banked the Trion Salvage.
  recalled,

  /// A landed hit destroyed the body before it could be recalled. The
  /// Salvage is gone.
  destroyed,
}

/// A temporary flat bonus to a stat (e.g. Ilona's Riposte Side Effect: a
/// stacking Attack buff after a melee miss against her). The additive
/// counterpart to [TempPercentPenalty].
class TempFlatBonus {
  final ModifiableStat stat;
  final double amount;
  int remainingTurns;
  TempFlatBonus(this.stat, this.amount, this.remainingTurns);
}

/// Mutable in-battle state for a single character: current health, active
/// status effects, ability cooldowns, and Full Arms Trigger bookkeeping.
/// The [Character] itself stays an immutable template so it can be reused
/// across battles/tests.
class CharacterBattleState {
  final Character character;

  /// This character's identity **within this battle** (see [CombatantIds]).
  ///
  /// Everything a battle keys by identity keys by this rather than by
  /// [Character.id], because both squads may field the same character and
  /// two Ilona Vances have to be two combatants rather than one shared one.
  ///
  /// Defaults to the character's own id, so a battle that never needed the
  /// distinction (an engine test, a tool harness, a squad drafted before
  /// mirror matches existed) behaves exactly as it always did: one Ilona
  /// Vance keyed by `ilona_vance`. The draft supplies the scoped id.
  final String combatantId;

  int currentHealth;

  /// Where this character is standing (see [BattlePosition]). Chosen at
  /// draft time and changed in battle by the Reposition action, which
  /// costs the character their ability use for that turn.
  ///
  /// Defaults to Middle so a battle built without positions (an older test,
  /// a standalone engine harness) behaves sensibly: at Middle against
  /// Middle the distance is 2, which Mid and Long both reach.
  BattlePosition position;

  /// Nullhymn: how many resonance grades this wielder's Black Trigger has been
  /// permanently dropped this battle (A->B->C->D). Applied in
  /// `TurnEngine.resonanceMultiplierFor`.
  int resonanceDowngradeSteps = 0;

  /// Monotonic stamp of the last time this character used a Black Trigger
  /// active (0 = never). Lets Nullhymn pick the "most-recently-active" enemy
  /// Black Trigger to downgrade.
  int lastBlackTriggerUseOrder = 0;

  /// Death Ledger: when this wielder's mark nullifies an enemy AoE, the engine
  /// parks that AoE trigger here as a signal for the app to swap it into the
  /// wielder's loadout for 2 turns. The app consumes and clears it.
  ActiveTrigger? deathLedgerSwapPending;

  final List<StatusEffectInstance> statusEffects = [];

  /// Reactive/counter effects (wards, traps, marks) standing on this
  /// character - the combat-v2 counter layer (see [ReactiveEffect]). Armed on
  /// the holder's turn; consulted and consumed when the opponent acts into
  /// them during resolution. Empty for all pre-combat-v2 content.
  final List<ReactiveEffect> reactiveEffects = [];

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

  /// True between the start and the end of this character's own team turn.
  ///
  /// Only one question reads it, and it is the one item #D turns on: a
  /// status effect landing on a character who is mid-turn must not count
  /// that turn against its own duration, because the holder never gets to
  /// spend it. `Battle` maintains the flag; a battle driven without
  /// `Battle` (an engine test wiring states by hand) simply leaves it
  /// false, which is the honest answer when nobody is taking a turn.
  bool isTakingTurn = false;

  final List<_AbilityUseRecord> _abilitiesUsedThisTurn = [];

  final List<TempPercentPenalty> tempPercentPenalties = [];
  final List<TempFlatBonus> tempFlatBonuses = [];

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

  /// The other living-or-dead members of this character's own team,
  /// populated by whoever sets up the battle (see `Battle`'s
  /// constructor) - needed for [SideEffect]s that read team state
  /// (Kaito's "last one standing" crit bonus, Marren's ally-health-aware
  /// Armor bonus). Empty until wired up; Side Effects that need it are simply
  /// inactive until then.
  List<CharacterBattleState> teammates = [];

  /// Whether this character's [SideEffect]'s once-per-battle charge
  /// (whichever mechanic it grants - reroll, dodge, redirect, first-hit
  /// mitigation, etc.) has already been spent. Each Side Effect uses at
  /// most one
  /// such charge, so a single flag is enough rather than per-mechanic
  /// bookkeeping.
  bool sideEffectChargeUsed = false;

  /// The category of the last [ActiveTrigger] this character used, for
  /// Tobias's "Versatile" Side Effect. Null until their first ability use.
  TriggerCategory? lastActiveTriggerCategory;

  /// Whether this character has used any ability yet this battle, for
  /// Ren's "First Strike" Side Effect (a first-turn-only Attack bonus).
  bool hasActedThisBattle = false;

  /// Running total of damage this character has personally dealt this
  /// battle, for `AiTargetPriority.highestThreat` (The Grudge Holder) - a
  /// "who has actually hurt my team the most" read, rather than a static
  /// Attack-stat proxy.
  int cumulativeDamageDealt = 0;

  /// Damage banked by Stored Retribution while Guarded/Braced. Discharged
  /// as bonus damage on this character's next offensive ability.
  int bankedDamage = 0;

  /// The id of the last ActiveTrigger this character used, for Root Snare's
  /// forced_repetition status. Null until the first ability use.
  String? lastUsedTriggerId;

  /// Trigger ids whose cooldown should be doubled this turn (Frozen
  /// Tempo). Cleared at the end of each turn.
  final Set<String> _cooldownSabotagedIds = {};

  /// Enemy character ids already marked by Death Ledger this battle (once
  /// per enemy per battle).
  final Set<String> deathLedgerMarkedIds = {};

  /// Active passive-counter states, keyed by kind. Populated at battle
  /// start from the character's equipped passive triggers that have a
  /// [PassiveCounterKind].
  final Map<PassiveCounterKind, PassiveCounterState> passiveCounters = {};

  /// Trigger ids used this turn, for Ironvow's Interdict repeat detection.
  final Set<String> triggersUsedThisTurn = {};

  /// Trigger ids used last turn, for Interdict repeat-ability check.
  final Set<String> triggersUsedLastTurn = {};

  /// The character id this character's last landed damaging hit was
  /// against, for `AiProfile.fixatesOnLastDamagedTarget` (The Berserker).
  /// Null until this character's first landed hit.
  String? lastDamagedTargetId;

  // --- Unique-subtype tracking (Phase C) ---

  /// Enemy character ids this character has landed a melee hit against
  /// this battle, for Shared Agony's auto-targeting.
  final Set<String> meleeHitEnemyIds = {};

  /// Charges for Illusory Double. Starts at 1, +1 each time an ally is
  /// defeated.
  int illusoryDoubleCharges = 0;

  /// The trigger id of a copied ability (Memory Theft). Null when no
  /// copy is active. Cleared after one use or at end of turn.
  String? copiedTriggerId;

  /// The enemy character id this character is bound to via Vow of the
  /// Duel. Null when not in a duel.
  String? duelTargetId;

  /// The enemy character id this character is linked to via Karmic Bind.
  /// Null when no link is active.
  String? karmicBindTargetId;

  /// Enemy character ids whose loadout has been revealed by Mind's Eye.
  final Set<String> revealedEnemyIds = {};

  /// Trigger ids that have been permanently destroyed this battle
  /// (Sunder Arms).
  final Set<String> destroyedTriggerIds = {};

  /// Ids of all active triggers this character has equipped for this
  /// battle. Populated at battle start; Sunder Arms picks from this list
  /// when destroying a random enemy trigger.
  final List<String> equippedTriggerIds;

  CharacterBattleState(
    this.character, {
    String? combatantId,
    List<PassiveEffect> equippedPassiveEffects = const [],
    List<String> equippedTriggerIds = const [],
    WorldAbilityEffect? worldAbility,
    this.position = BattlePosition.middle,
  })  : combatantId = combatantId ?? character.id,
        currentHealth = character.baseStats.maxHealth,
        equippedPassiveEffects = equippedPassiveEffects,
        equippedTriggerIds = equippedTriggerIds,
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

  /// Whether this character's body is still physically on the battlefield:
  /// alive, or [BailOutState.bailingOut] and not yet recalled or destroyed.
  ///
  /// Exactly two questions read this instead of [isAlive], and both are about
  /// the body rather than the fighter: **who screens** (a body in the way is
  /// still in the way), and **what a damaging enemy ability may be aimed at**.
  /// Everything else - Trion income, ally counts, whether a team is defeated,
  /// every Side Effect that reads the squad - keeps reading [isAlive] and keeps
  /// treating a bailing character as gone, because they are.
  bool get isOnBoard => isAlive || bailOutState == BailOutState.bailingOut;

  /// See [BailOutState]. Driven by `TurnEngine` (entering the window, being
  /// destroyed) and `Battle` (the recall at the turn boundary).
  BailOutState bailOutState = BailOutState.none;

  /// Set by `Battle` at the start of the enemy turn that is this body's
  /// contested window, and read at the end of it to recall the body.
  ///
  /// Armed at a turn boundary rather than counted from the drop, because the
  /// enemy committed the turn they killed you in before they knew they had:
  /// they get the *next* one to decide whether the body is worth an action.
  bool bailOutWindowArmed = false;

  /// Set once this character has spent a Refuse to Bail, so a second drop
  /// destroys them outright instead of opening a window they already refused.
  bool hasRefusedToBail = false;

  /// Set by `Battle` at the start of the turn that is the extra turn a
  /// Refuse to Bail bought, and read at the end of it to destroy the holder
  /// for good.
  ///
  /// Armed at a turn boundary rather than counted from the refusal, so the
  /// turn that was already underway when they refused never counts as the one
  /// they paid for. That is the same rule the Bail Out window uses.
  bool refuseToBailFinalTurn = false;

  bool get canTriggerFat => fatCooldownRemaining <= 0;

  int get abilitiesUsedThisTurnCount => _abilitiesUsedThisTurn.length;

  bool isActionPrevented([StatusEffectCatalog? catalog]) {
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    return statusEffects.any((i) => cat[i.definitionId].preventsActions);
  }

  /// Whether something is pinning this character in place (zone lock). Kept
  /// separate from [isActionPrevented] because a character can be free to
  /// act but unable to move, which is exactly what a snare should do.
  bool isRepositionPrevented([StatusEffectCatalog? catalog]) {
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    return statusEffects.any((i) => cat[i.definitionId].preventsReposition);
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

  /// Marks [triggerId]'s cooldown to be doubled this turn (Frozen Tempo).
  void sabotageAbilityCooldown(String triggerId) {
    _cooldownSabotagedIds.add(triggerId);
  }

  /// Records that [trigger] was used this turn; cooldown application
  /// (including any FAT doubling penalty) happens in `endTurn`.
  void recordAbilityUse(ActiveTrigger trigger) {
    _abilitiesUsedThisTurn
        .add(_AbilityUseRecord(trigger.id, trigger.cooldownTurns));
    lastActiveTriggerCategory = trigger.category;
    lastUsedTriggerId = trigger.id;
    triggersUsedThisTurn.add(trigger.id);
    hasActedThisBattle = true;
  }

  /// Spends this character's action for the turn on a Reposition.
  ///
  /// Deliberately does not touch `lastUsedTriggerId`, `triggersUsedThisTurn`
  /// or `lastActiveTriggerCategory`: moving is not using an ability, so it
  /// must not feed the combo ledger, satisfy Forced Repetition, or count as
  /// the "category of ability last used" that Tobias's Versatile Side
  /// Effect reads.
  /// It only occupies the action slot, and its sentinel record carries a
  /// zero cooldown so end-of-turn bookkeeping ignores it.
  void recordRepositionUse() {
    _abilitiesUsedThisTurn.add(_AbilityUseRecord(repositionActionId, 0));
    hasActedThisBattle = true;
  }

  /// Consumes this character's [SideEffect] once-per-battle charge if
  /// it hasn't been used yet, returning whether it was available. Callers
  /// check the specific Side Effect field that gates their mechanic first (e.g.
  /// `character.sideEffect?.canRerollOwnAttackRollOncePerBattle`) and only call
  /// this once they know the mechanic applies.
  bool consumeSideEffectChargeIfAvailable() {
    if (sideEffectChargeUsed) return false;
    sideEffectChargeUsed = true;
    return true;
  }

  /// Applies a temporary flat bonus to [stat] (e.g. Ilona's Riposte
  /// Side Effect). Multiple active bonuses on the same stat stack additively.
  void applyFlatBonus(ModifiableStat stat, double amount, int turns) {
    tempFlatBonuses.add(TempFlatBonus(stat, amount, turns));
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
      var cooldown = multiAbilityPenalty
          ? (use.baseCooldownTurns * fatConfig.cooldownDoubleMultiplier).round()
          : use.baseCooldownTurns;
      if (_cooldownSabotagedIds.contains(use.triggerId)) cooldown *= 2;
      if (cooldown > 0) cooldowns[use.triggerId] = cooldown;
    }

    trionAffinityHalvedNextTurn = multiAbilityPenalty;

    _abilitiesUsedThisTurn.clear();
    _cooldownSabotagedIds.clear();
    fatTriggeredThisTurn = false;

    triggersUsedLastTurn
      ..clear()
      ..addAll(triggersUsedThisTurn);
    triggersUsedThisTurn.clear();

    if (fatCooldownRemaining > 0) fatCooldownRemaining--;

    for (final penalty in tempPercentPenalties) {
      penalty.remainingTurns--;
    }
    tempPercentPenalties.removeWhere((p) => p.remainingTurns <= 0);

    for (final bonus in tempFlatBonuses) {
      bonus.remainingTurns--;
    }
    tempFlatBonuses.removeWhere((b) => b.remainingTurns <= 0);
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
      // Data-driven zeroing: an effect can name a single stat to zero via
      // its instance data rather than the definition's static zeroedStats
      // (Called Shot, which zeroes a caller-declared stat for its duration).
      final dataZeroed = instance.data['zeroedStat'];
      if (dataZeroed is ModifiableStat) zeroed.add(dataZeroed);
    }

    for (final passive in equippedPassiveEffects) {
      passive.flatStatModifiers.forEach((stat, delta) {
        deltas[stat] = (deltas[stat] ?? 0) + delta;
      });
    }

    for (final bonus in tempFlatBonuses) {
      deltas[bonus.stat] = (deltas[bonus.stat] ?? 0) + bonus.amount;
    }

    // Tobias-style "Versatile" Side Effect: a small bonus to whichever stat
    // matches the category of the last ability used. Attacker/Sniper/
    // Shooter categories are offense-flavored (Attack), Trapper is
    // affliction-flavored (Status Effect Infliction), Optional is
    // support/defense-flavored (Defense).
    final sideEffect = character.sideEffect;
    if (sideEffect != null &&
        sideEffect.grantsBonusForLastUsedAbilityCategory &&
        lastActiveTriggerCategory != null) {
      const bonusMagnitude = 2.0;
      final stat = switch (lastActiveTriggerCategory!) {
        TriggerCategory.attacker ||
        TriggerCategory.sniper ||
        TriggerCategory.shooter =>
          ModifiableStat.attack,
        TriggerCategory.trapper => ModifiableStat.statusEffectInfliction,
        TriggerCategory.optional => ModifiableStat.defense,
      };
      deltas[stat] = (deltas[stat] ?? 0) + bonusMagnitude;
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

    var criticalChance =
        resolve(ModifiableStat.criticalChance, base.criticalChance);
    if (sideEffect != null &&
        sideEffect.doublesCritChanceWhenLastAlive &&
        teammates.isNotEmpty &&
        teammates.every((t) => !t.isAlive)) {
      criticalChance *= 2;
    }

    var armor = resolve(ModifiableStat.armor, base.armor);
    if (sideEffect != null &&
        sideEffect.doublesArmorWhileAllyBelowQuarterHealth &&
        teammates.any((t) =>
            t.isAlive &&
            t.currentHealth < t.character.baseStats.maxHealth * 0.25)) {
      armor *= 2;
    }

    return base.copyWith(
      attack: resolve(ModifiableStat.attack, base.attack).round(),
      defense: resolve(ModifiableStat.defense, base.defense).round(),
      armor: armor.round(),
      maxHealth: resolve(ModifiableStat.maxHealth, base.maxHealth).round(),
      trionAffinity: trionAffinity.round(),
      teamSpirit: resolve(ModifiableStat.teamSpirit, base.teamSpirit).round(),
      criticalChance: criticalChance,
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
      if (def.advantageRollTags.contains(tag)) {
        context.addAdvantage('status:${def.id}');
      }
    }
    return context;
  }

  /// Returns the passive counter state for [kind], or null if this
  /// character doesn't have that counter equipped.
  PassiveCounterState? getPassiveCounter(PassiveCounterKind kind) =>
      passiveCounters[kind];

  /// Whether this character is currently untargetable (Illusory Double).
  bool isUntargetable([StatusEffectCatalog? catalog]) {
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    return statusEffects.any((i) => cat[i.definitionId].preventsTargeting);
  }

  /// Whether this character is currently isolated (cannot interact with
  /// allies).
  bool isIsolated([StatusEffectCatalog? catalog]) {
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    return statusEffects
        .any((i) => cat[i.definitionId].preventsAllyInteraction);
  }

  /// Whether this character's next attack will automatically miss
  /// (Echoing Doubt).
  bool isNextAttackForced([StatusEffectCatalog? catalog]) {
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    return statusEffects.any((i) => cat[i.definitionId].forcesNextAttackMiss);
  }

  /// Whether this character is currently blocked from being healed by any
  /// active status effect (Cursed, Necrotic Wound).
  bool isHealingPrevented([StatusEffectCatalog? catalog]) {
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    return statusEffects.any((i) => cat[i.definitionId].preventsHealing);
  }

  /// Combined Trion-cost multiplier from active status effects
  /// (Overcharged, Choked). 1.0 if none are active.
  double trionCostMultiplier([StatusEffectCatalog? catalog]) {
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    var multiplier = 1.0;
    for (final instance in statusEffects) {
      final m = cat[instance.definitionId].trionCostMultiplier;
      if (m != null) multiplier *= m;
    }
    return multiplier;
  }

  /// Combined outgoing-damage multiplier from active status effects
  /// (Empowered, Weakened). 1.0 if none are active.
  double outgoingDamageMultiplier([StatusEffectCatalog? catalog]) {
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    var multiplier = 1.0;
    for (final instance in statusEffects) {
      final m = cat[instance.definitionId].outgoingDamageMultiplier;
      if (m != null) multiplier *= m;
    }
    return multiplier;
  }

  /// Combined damage-type multiplier contributed by active status
  /// effects (Wet-style immune/vulnerable interactions, Sickened's
  /// randomly-chosen vulnerable types, and any type-agnostic
  /// [StatusEffectDefinition.allDamageTakenMultiplier] like Guarded/
  /// Exposed). Does not include the character's static Damage Resistance,
  /// which is a separate, final-step halving applied by the combat engine.
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
      if (def.allDamageTakenMultiplier != null) {
        multiplier *= def.allDamageTakenMultiplier!;
      }
    }
    return multiplier;
  }
}

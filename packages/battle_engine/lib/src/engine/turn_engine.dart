import 'dart:math';

import '../constants.dart';
import '../models/battle_position.dart';
import '../models/character_type.dart';
import '../models/damage_type.dart';
import '../models/passive_counter.dart';
import '../models/reactive_effect.dart';
import '../models/resonance.dart';
import '../models/combo.dart';
import '../models/status_effect.dart';
import '../models/status_effect_catalog.dart';
import '../models/status_reaction.dart';
import '../models/team.dart';
import '../models/teg_profile.dart';
import '../models/trigger.dart';
import 'combo_recognizer.dart';
import '../models/trion.dart';
import '../models/unique_behavior.dart';
import '../util/dice.dart';
import 'character_battle_state.dart';
import 'combat_engine.dart';
import 'fat_engine.dart';
import 'status_effect_engine.dart';
import 'team_spirit_curve.dart';
import 'trion_gain_engine.dart';

/// The full damage-formula trail behind one damaging hit: the trigger's own
/// dice roll, the combined pre-critical multiplier applied to it (Team Spirit's
/// damage bonus, any Side Effect/status outgoing multiplier), and the resulting
/// [DamageBreakdown] (crit doubling -> Armor -> damage-type multipliers). This
/// is what actually answers "how did this attack deal this much damage" - the
/// attack/defense roll shown alongside it only ever decided hit/miss/crit,
/// never the damage amount itself.
class HitDamageDetail {
  final DiceExpressionRollResult diceRoll;

  /// Combined multiplier applied to [diceRoll]'s total before critical
  /// doubling/Armor (1.0 if nothing applies) - `breakdown.baseDamage` is
  /// `(diceRoll.total * preCritMultiplier).round()`.
  final double preCritMultiplier;

  final DamageBreakdown breakdown;

  const HitDamageDetail({
    required this.diceRoll,
    required this.preCritMultiplier,
    required this.breakdown,
  });
}

/// Every roll made against one target during a single ability use, the
/// total damage it took, and which inflicted status effects actually
/// landed. Burst's multiple hits on the same target collapse into one
/// entry. Targets that received zero rolls (e.g. unreached Burst targets
/// when `hitsPerUse < targets.length`) are omitted from
/// `AbilityUseResult.targetResults`.
class TargetHitResult {
  final String targetCharacterId;
  final List<AttackRollOutcome> attackRolls;

  /// The damage dealt by each roll in [attackRolls], in the same order -
  /// exposed alongside the aggregated [totalDamageDealt] so a UI can show
  /// a full per-roll breakdown (which specific roll crit, which missed,
  /// how much each one actually dealt) rather than just the sum.
  final List<int> damagePerHit;

  /// The damage-formula trail behind each entry in [damagePerHit], in the
  /// same order - null for a roll that dealt no damage (a miss, a status-
  /// only Trigger, or a fully-prevented hit already reflected in its
  /// `DamageBreakdown.prevented`... except a miss never reaches damage
  /// resolution at all, hence null rather than a zeroed breakdown there).
  final List<HitDamageDetail?> damageDetails;

  final int totalDamageDealt;
  final List<String> statusEffectsApplied;

  /// How many stacks of each id in [statusEffectsApplied] the target is
  /// carrying once this ability has finished resolving against them.
  ///
  /// A playtest could not tell how many stacks of Chilled had gone on and
  /// when: "[Chilled]" in the log is the same line whether it is the first
  /// or the third. It says "[Chilled x2]" now, and this is where the 2 comes
  /// from. A burst that applies the same effect on every strike reports the
  /// pile it ended with, not one entry per strike.
  final Map<String, int> statusEffectStacks;

  const TargetHitResult({
    required this.targetCharacterId,
    required this.attackRolls,
    required this.damagePerHit,
    required this.damageDetails,
    required this.totalDamageDealt,
    required this.statusEffectsApplied,
    this.statusEffectStacks = const {},
  });
}

/// Outcome of a single ability use: one [TargetHitResult] per target
/// actually rolled against.
class AbilityUseResult {
  final String attackerCharacterId;
  final String triggerId;
  final List<TargetHitResult> targetResults;

  /// Item 3b's reactions that fired while this ability resolved, in the
  /// order they fired. Empty for the ordinary case where nothing on the
  /// target reacted to the damage type.
  final List<StatusReactionEvent> reactions;

  /// TEG Effect 3: Trion refunded to the acting team because this action was
  /// the payoff of a recognized setup->payoff combo. 0 when none applied. The
  /// engine computes it; the app credits the team's Trion pool.
  final int trionRefund;

  const AbilityUseResult({
    required this.attackerCharacterId,
    required this.triggerId,
    required this.targetResults,
    this.trionRefund = 0,
    this.reactions = const [],
  });
}

/// One firing of item 3b's reaction table, for the battle log.
///
/// A reaction is invisible unless the log says it happened: the player sees a
/// Frozen badge disappear and a bigger number, and has no way to connect the
/// two. This carries what fired, on whom, and what it turned into.
class StatusReactionEvent {
  /// Who was carrying the reacting status.
  final String characterId;

  /// The status that reacted (Wet, Frozen, Scorched...).
  final String reactingStatusId;

  /// The damage type that set it off, or null for a status-triggered one.
  final DamageType? damageType;

  /// The status that landed on them because of it, or null for a reaction
  /// whose whole effect was on the hit.
  final String? becameStatusId;

  /// Whether the reacting status was spent.
  final bool consumed;

  /// Damage multiplier the reaction put on the triggering hit. 1.0 for the
  /// rows that only change statuses.
  final double damageMultiplier;

  /// Who the reaction arced to, for the one row that arcs.
  final String? arcedToCharacterId;

  /// How many stacks of [becameStatusId] the target is carrying once the
  /// reaction has settled, or null when the reaction applied no status.
  ///
  /// The rows where a status builds into itself (Bleeding hit by Slashing,
  /// Scorched by Fire, Corroded by Acid) are only legible as a number: "it
  /// becomes Bleeding" says nothing when it was already Bleeding, and a
  /// playtest asked exactly that. The count is what happened.
  final int? becameStacks;

  /// True when the reaction fed the status it fired from, rather than
  /// turning it into a different one.
  bool get buildsOnItself => becameStatusId == reactingStatusId;

  const StatusReactionEvent({
    required this.characterId,
    required this.reactingStatusId,
    this.damageType,
    this.becameStatusId,
    this.consumed = false,
    this.damageMultiplier = 1.0,
    this.arcedToCharacterId,
    this.becameStacks,
  });
}

class _SingleHitResult {
  /// Null when nothing was rolled: an ability aimed at your own side is not
  /// an attack, so it has no attack roll to report and the log has no "hit"
  /// to count.
  final AttackRollOutcome? outcome;
  final int damage;
  final HitDamageDetail? damageDetail;
  final List<String> appliedStatusEffectIds;

  /// Stacks carried per applied id at the moment this hit finished, so a
  /// later hit's bigger pile overwrites an earlier one's.
  final Map<String, int> appliedStacks;
  _SingleHitResult(
    this.outcome,
    this.damage,
    this.damageDetail,
    this.appliedStatusEffectIds, {
    this.appliedStacks = const {},
  });
}

/// Orchestrates a single turn: team Trion gain, per-character status
/// ticking, Full Arms Trigger rolling, ability-use bookkeeping, ability
/// resolution, and end-of-turn cleanup. AI decision-making (which ability
/// to use, who to target) is deliberately left to the caller (e.g. a
/// future rule-based AI module or story-triggered scripted battle) - this
/// engine only answers "is this legal / what does this cost / what's the
/// result", not "what should happen".
/// Keys a trap uses to remember where it was laid and how far it reaches.
/// Private to the engine: a trap's band is engine bookkeeping, not part of
/// the [ReactiveEffect] contract callers write against.
const String _trapBandKey = '__trapBand';
const String _trapArmedStepKey = '__trapArmedStep';

class TurnEngine {
  final TrionGainEngine trionGainEngine;
  final FatEngine fatEngine;
  final CombatEngine combatEngine;
  final StatusEffectEngine statusEffectEngine;
  final TeamSpiritCurve teamSpiritCurve;
  final FatConfig fatConfig;
  final PassiveCounterConfig passiveCounterConfig;
  final UniqueConfig uniqueConfig;
  final BailOutConfig bailOutConfig;

  /// Per-character shared team Trion pool (character id -> the pool of the
  /// team they belong to), set by the Battle layer. Used to pay the attacking
  /// squad for destroying a Bailing Out body, the same way
  /// `StatusEffectEngine` credits a Sapped drain to its causer's pool. Empty
  /// when TurnEngine is used standalone, which simply skips the payment.
  Map<String, TrionPool> teamTrionPools = {};

  /// Battle-wide character registry (id -> state), set by the Battle layer
  /// so cross-team unique effects (Karmic Bind's live link) can look up a
  /// partner that isn't a teammate. Empty when TurnEngine is used
  /// standalone, which simply disables those cross-team effects.
  Map<String, CharacterBattleState> characterRegistry = {};

  /// Per-character TEG roll profiles (Combat-v2 section 5.2, Effects 1/2/5),
  /// injected by the Battle layer from the app-computed Team Efficiency
  /// Grade. Empty when unused (a standalone engine), which simply disables
  /// the TEG dice-advantage / crit-widen effects.
  Map<String, TegRollProfile> tegProfiles = {};

  /// Combat-v2 Phase I/J: the per-turn combo action ledger (populated as
  /// actions resolve, cleared at each turn boundary) and the recognizer that
  /// reads it. The recognizer is injected by the Battle/app layer (like
  /// [tegProfiles]); when null, TEG Effect 4 (combo advantage) and Effect 3
  /// (setup->payoff refund) are simply disabled - the ledger still records.
  final ComboLedger comboLedger = ComboLedger();
  ComboRecognizer? comboRecognizer;

  /// Advantage-chance granted per unit of recognized-combo strength (TEG
  /// Effect 4), before the universal 20% cap. Tunable (Phase H).
  static const int comboAdvantagePercentPerStrength = 7;

  /// Draegor's "raise TEG 2 tiers" effect: the app injects, per character, the
  /// profile their team WOULD have two tiers higher - but only for teams at
  /// tier <= S (SS/SSS teams get Draegor's fallback instead, so they have no
  /// entry here). While a character's boost is active ([_tegBoostRemaining])
  /// their boosted profile replaces the base one.
  Map<String, TegRollProfile> tegBoostedProfiles = {};
  final Map<String, int> _tegBoostRemaining = {};

  /// Monotonic counter stamping Black-Trigger-active uses (for Nullhymn's
  /// "most-recently-active enemy Black Trigger" downgrade target).
  int _btUseOrder = 0;

  TegRollProfile _tegFor(CharacterBattleState c) {
    if ((_tegBoostRemaining[c.combatantId] ?? 0) > 0) {
      final boosted = tegBoostedProfiles[c.combatantId];
      if (boosted != null) return boosted;
    }
    return tegProfiles[c.combatantId] ?? TegRollProfile.none;
  }

  /// Whether [holder]'s team is eligible for Draegor's 2-tier TEG boost (the
  /// app injected boosted profiles only for teams at tier <= S).
  bool _canTegBoost(CharacterBattleState holder) =>
      [holder, ...holder.teammates]
          .any((a) => tegBoostedProfiles.containsKey(a.combatantId));

  /// Activates Draegor's 2-tier TEG boost on [holder]'s living team for [turns].
  void _activateTegBoost(CharacterBattleState holder, int turns) {
    for (final a in [holder, ...holder.teammates]) {
      if (a.isAlive) _tegBoostRemaining[a.combatantId] = turns;
    }
  }

  /// Ticks the Draegor TEG boost down once per turn (call at each turn start).
  void tickTegBoost() {
    for (final id in _tegBoostRemaining.keys.toList()) {
      final next = (_tegBoostRemaining[id] ?? 0) - 1;
      if (next <= 0) {
        _tegBoostRemaining.remove(id);
      } else {
        _tegBoostRemaining[id] = next;
      }
    }
  }

  /// Read-only: turns remaining on [characterId]'s Draegor TEG boost (0 none).
  int tegBoostTurnsRemaining(String characterId) =>
      _tegBoostRemaining[characterId] ?? 0;

  /// A stable per-team key for the ledger: the sorted character ids of the
  /// actor plus its teammates. Same for every member of a team, unique per
  /// team in a battle, so the recognizer's same-team filter works without
  /// the engine needing an explicit team id.
  String _teamKeyFor(CharacterBattleState c) {
    final ids = <String>[
      c.combatantId,
      for (final t in c.teammates) t.combatantId,
    ]..sort();
    return ids.join('|');
  }

  /// A payoff "probe" entry for [attacker]'s [trigger] against [target],
  /// sequenced above every recorded entry so `contextFor` treats it purely as
  /// the payoff (never as one of its own priors).
  ComboLedgerEntry _comboProbe(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    CharacterBattleState target,
  ) =>
      ComboLedgerEntry(
        actorId: attacker.combatantId,
        teamId: _teamKeyFor(attacker),
        triggerId: trigger.id,
        originTag: trigger.originTag,
        attackType: trigger.attackType,
        attackSubtype: trigger.attackSubtype,
        targetAffiliation: trigger.targetAffiliation,
        targetIds: [target.combatantId],
        statusesApplied: const [],
        dealtDamage: false,
        sequence: 1 << 30, // above any recorded entry; excluded from priors
      );

  /// TEG Effect 4: if the current payoff against [target] completes a
  /// recognized combo, roll the strength-scaled advantage chance (capped at
  /// the universal 20%) and, on success, grant [ctx] advantage.
  void _applyComboAdvantage(
    RollContext ctx,
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    CharacterBattleState target,
  ) {
    final recognizer = comboRecognizer;
    if (recognizer == null) return;
    final combo = recognizer.best(comboLedger
        .contextFor(_comboProbe(attacker, trigger, target), targetState: target));
    if (combo == null) return;
    final chance =
        (combo.strength * comboAdvantagePercentPerStrength).clamp(0, 20);
    if (chance > 0 && combatEngine.diceRoller.rollPercent() <= chance) {
      ctx.addAdvantage('teg_combo');
    }
  }

  /// TEG Effect 3: the Trion refund for this action if it is the payoff of a
  /// recognized setup->payoff combo against any of its [targets], scaled by
  /// the attacker team's refund percent. 0 when disabled or unqualified.
  int _computeComboRefund(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets,
  ) {
    final recognizer = comboRecognizer;
    if (recognizer == null) return 0;
    final refundPercent = _tegFor(attacker).trionRefundPercent;
    if (refundPercent <= 0) return 0;
    final qualifies = targets.any((target) => recognizer
        .recognize(comboLedger
            .contextFor(_comboProbe(attacker, trigger, target), targetState: target))
        .any((c) => c.isSetupPayoff));
    if (!qualifies) return 0;
    return (trigger.trionCost * refundPercent / 100).round();
  }

  /// TEG Effect 1 (Coordination): with the actor's offense chance, grant
  /// [ctx] advantage on this offensive roll.
  void _applyTegOffenseAdvantage(RollContext ctx, CharacterBattleState actor) {
    final p = _tegFor(actor).offenseAdvantagePercent;
    if (p > 0 && combatEngine.diceRoller.rollPercent() <= p) {
      ctx.addAdvantage('teg_offense');
    }
  }

  /// TEG Effect 2 (Operator's Read): with the defender's (inverted) defense
  /// chance, grant [ctx] advantage on this defensive roll.
  void _applyTegDefenseAdvantage(
      RollContext ctx, CharacterBattleState defender) {
    final p = _tegFor(defender).defenseAdvantagePercent;
    if (p > 0 && combatEngine.diceRoller.rollPercent() <= p) {
      ctx.addAdvantage('teg_defense');
    }
  }

  /// Re-entrancy guard so Karmic Bind's propagated damage doesn't recurse.
  bool _resolvingKarmicBind = false;

  TurnEngine({
    TrionGainEngine? trionGainEngine,
    FatEngine? fatEngine,
    CombatEngine? combatEngine,
    StatusEffectEngine? statusEffectEngine,
    TeamSpiritCurve? teamSpiritCurve,
    this.fatConfig = FatConfig.defaults,
    this.passiveCounterConfig = PassiveCounterConfig.defaults,
    this.uniqueConfig = UniqueConfig.defaults,
    this.bailOutConfig = BailOutConfig.defaults,
  })  : trionGainEngine = trionGainEngine ?? TrionGainEngine(),
        fatEngine = fatEngine ?? FatEngine(),
        combatEngine = combatEngine ?? CombatEngine(),
        statusEffectEngine = statusEffectEngine ?? StatusEffectEngine(),
        teamSpiritCurve = teamSpiritCurve ?? const TeamSpiritCurve();

  /// Rolls this turn's Trion gain for [team] (using the sum of living
  /// members' effective Trion Affinity, so the FAT halving penalty is
  /// reflected) and adds it to the team's pool.
  ///
  /// [forceLowestTier] skips the roll entirely and grants only the Low
  /// tier - the first-move handicap (see `Battle.startTurn`): the team
  /// that acts first in the battle gets a reduced Trion gain on that
  /// single turn only, mirroring Naruto-Arena's "first player only draws
  /// 1 random Chakra instead of 3" offset for the tempo advantage of
  /// acting first.
  /// [teamStates] is [team]'s own states, which is all this needs: the map
  /// it used to take was only ever indexed to find them, and doing that here
  /// meant this had to know how the battle was keyed. `Battle.statesOf` is
  /// the one place that answers that now.
  TrionGainResult resolveTeamTrionGain(
    Team team,
    List<CharacterBattleState> teamStates, {
    double modifier = 0,
    bool forceLowestTier = false,
  }) {
    // Trion Backlash: a shot bent last turn, so this squad's income is capped
    // at Low however good their affinity is. Cleared as it is paid, so the
    // price lands once. Same switch as the first-move handicap, because it is
    // the same idea: this turn's income is not rolled for.
    if (team.trionBacklash) {
      team.trionBacklash = false;
      final result =
          TrionGainResult(TrionTier.low, trionGainEngine.config.lowAmount);
      team.trionPool.gain(result.amount);
      return result;
    }

    if (forceLowestTier) {
      final result =
          TrionGainResult(TrionTier.low, trionGainEngine.config.lowAmount);
      team.trionPool.gain(result.amount);
      return result;
    }

    final living = teamStates.where((s) => s.isAlive);

    final sum = living.fold<int>(
        0,
        (total, s) =>
            total + s.effectiveStats(fatConfig: fatConfig).trionAffinity);

    // Haru-style "Battery" Side Effect: a living character can grant their
    // whole team a positive modifier on this roll.
    final sideEffectModifier = living.fold<double>(
        0,
        (total, s) =>
            total +
            (s.character.sideEffect?.teamTrionGainModifierWhileAlive ?? 0));

    final result = trionGainEngine.rollTier(
        sumLivingTrionAffinity: sum, modifier: modifier + sideEffectModifier);
    team.trionPool.gain(result.amount);
    return result;
  }

  /// Applies start-of-turn status effect ticking (damage, heals, Trion
  /// drain) to [state]. Trion drained by an effect like Sapped is
  /// credited to the causer's pool via [causerTrionPools] (character id
  /// -> their team's pool), if supplied.
  StatusTickResult tickStatusEffects(
    CharacterBattleState state, {
    Map<String, TrionPool>? causerTrionPools,
  }) {
    final result = statusEffectEngine.tickStartOfTurn(state);
    final maxHealth = state.effectiveStats(fatConfig: fatConfig).maxHealth;

    for (final event in result.damageEvents) {
      _applyDamage(
        target: state,
        baseDamage: event.amount,
        damageType: event.damageType,
        isCriticalHit: false,
        // A status ticking its own damage is not somebody hitting you with
        // that damage type, and item 3b's table is about being hit. Without
        // this, Bleeding ticks Slashing, Slashing is what Bleeding reacts
        // to, and the bleed refreshes itself forever.
        firesReactions: false,
      );
    }

    if (!state.isHealingPrevented()) {
      for (final event in result.healEvents) {
        final healed = _scaledHealAmount(state, event.amount);
        final before = state.currentHealth;
        state.currentHealth =
            (state.currentHealth + healed).clamp(0, maxHealth);
        // Karmic Bind (Punish): healing received on a bound caster also
        // strikes the enemy they are bound to.
        _propagateKarmicBind(state, state.currentHealth - before);
      }
    }

    // A drain is a transfer, not a printing press. The causer's pool used to
    // be credited without the victim's ever being debited, so Sapped conjured
    // about 26 Trion a turn out of nothing against a team income of roughly
    // 15. It has never been felt in a played battle only because nothing
    // applies Sapped or Genjutsu Trapped yet. What is actually taken is what
    // the victim's squad has, so an empty pool pays nothing and the causer
    // gains nothing.
    for (final drain in result.trionDrainEvents) {
      final victimPool = causerTrionPools?[state.combatantId];
      final taken = victimPool == null
          ? drain.amount
          : drain.amount.clamp(0, victimPool.current);
      if (taken <= 0) continue;
      victimPool?.trySpend(taken);
      causerTrionPools?[drain.causerCharacterId]?.gain(taken);
    }

    return result;
  }

  /// Scales a heal amount by [recipient]'s own effective Team Spirit
  /// Health Regeneration bonus - Team Spirit's brief says higher values
  /// increase "Health Regeneration amount when healed", i.e. this is the
  /// receiving character's own bonus, not the healer's.
  int _scaledHealAmount(CharacterBattleState recipient, int baseAmount) {
    final stats = recipient.effectiveStats(fatConfig: fatConfig);
    final bonus = teamSpiritCurve.bonusesFor(stats.teamSpirit).healthRegenBonus;
    // Yuki-style "Devoted Aid" Side Effect: a bonus to all healing received,
    // regardless of source (including a drain-style Trigger that heals
    // its user off someone else's health).
    final sideEffectBonus =
        recipient.character.sideEffect?.incomingHealBonusPercent ?? 0;
    return (baseAmount * (1 + bonus + sideEffectBonus)).round();
  }

  /// Resolves damage against [target] and applies it to their health,
  /// honoring a World ability's "survive lethal damage once" charge: if
  /// this hit would reduce health to 0 while current health is above 1,
  /// and the charge is still available, health is clamped to 1 instead
  /// and the charge is consumed.
  ///
  /// Returns the step-by-step breakdown behind the pre-SE/pre-clamp
  /// damage number (see [DamageBreakdown]) - a UI showing "why was the
  /// damage this number" reads this rather than just the health delta,
  /// since Bastian's Absorb Side Effect and the survive-lethal clamp below can
  /// still adjust the actual health lost after this math runs.
  ///
  /// [criticalDiceComponent] is the dice-only half of [baseDamage], which
  /// is what a critical hit doubles (see
  /// `CombatEngine.resolveDamageBreakdown`). Damage with no dice behind it
  /// - status ticks, flat unique-behavior damage, trap damage - leaves it
  /// null; those sites never crit anyway.
  /// Item 3b's reactions that have fired since the buffer was last drained.
  /// [resolveAbilityUse] clears it before it resolves and hands what it
  /// collected to the caller on [AbilityUseResult.reactions].
  final List<StatusReactionEvent> _pendingReactions = [];

  /// Every reaction on [target] that [damageType] sets off, paired with the
  /// live instance carrying it.
  ///
  /// Read before the damage is resolved, because a reacting status is often
  /// what decides the damage: Wet is Fire-immune, Scorched is
  /// Fire-vulnerable, and both have to still be on the target while the
  /// breakdown runs. The reactions themselves are settled afterwards.
  List<(StatusEffectInstance, StatusReaction)> _damageReactionsOn(
    CharacterBattleState target,
    DamageType damageType,
  ) {
    final found = <(StatusEffectInstance, StatusReaction)>[];
    for (final instance in List.of(target.statusEffects)) {
      if (!statusEffectEngine.catalog.contains(instance.definitionId)) continue;
      final def = statusEffectEngine.catalog[instance.definitionId];
      final reaction = def.reactionToDamage(damageType);
      if (reaction != null) found.add((instance, reaction));
    }
    return found;
  }

  /// Settles the reactions [_damageReactionsOn] found, once the hit they fired
  /// on has landed: spends what they spend, applies what they apply, and
  /// records each one for the log.
  ///
  /// A reaction is never contested (decision #G), so this applies statuses
  /// directly rather than rolling infliction. A two-step play that had to win
  /// a roll at each step would come off about a fifth of the time.
  void _settleDamageReactions(
    CharacterBattleState target,
    List<(StatusEffectInstance, StatusReaction)> fired,
    DamageType damageType,
  ) {
    for (final (instance, reaction) in fired) {
      final reactingId = instance.definitionId;
      if (reaction.consumesTrigger) {
        target.statusEffects.removeWhere((i) => identical(i, instance));
      }
      if (reaction.alsoRemoves != null) {
        target.statusEffects
            .removeWhere((i) => i.definitionId == reaction.alsoRemoves);
      }
      if (reaction.becomes != null) {
        statusEffectEngine.apply(target, reaction.becomes!);
      }

      String? arcedTo;
      if (reaction.arcsToSameLine && reaction.becomes != null) {
        final neighbour = target.teammates
            .where((t) =>
                t.isAlive &&
                !identical(t, target) &&
                t.position == target.position)
            .firstOrNull;
        if (neighbour != null) {
          statusEffectEngine.apply(neighbour, reaction.becomes!);
          arcedTo = neighbour.combatantId;
        }
      }

      _pendingReactions.add(StatusReactionEvent(
        characterId: target.combatantId,
        reactingStatusId: reactingId,
        damageType: damageType,
        becameStatusId: reaction.becomes,
        consumed: reaction.consumesTrigger,
        damageMultiplier: reaction.damageMultiplier,
        arcedToCharacterId: arcedTo,
        // Read after the reaction has settled, so a row that builds reports
        // the pile it just added to rather than the one it started from.
        becameStacks: reaction.becomes == null
            ? null
            : target.statusEffects
                .where((i) => i.definitionId == reaction.becomes)
                .map((i) => i.stacks)
                .firstOrNull,
      ));
    }
  }

  DamageBreakdown _applyDamage({
    required CharacterBattleState target,
    required int baseDamage,
    required DamageType damageType,
    required bool isCriticalHit,
    CharacterBattleState? damageSource,
    int? criticalDiceComponent,
    bool firesReactions = true,
  }) {
    // A Bailing Out body has no health left to lose, so "destroyed" cannot be
    // defined by damage crossing zero. Any hit that reaches it ends it,
    // whatever the number and whoever threw it (a misfire from its own side
    // counts, and denies its own squad the Salvage). The mitigation math below
    // would be measuring a pool that is already empty, so this returns before
    // running it.
    if (target.bailOutState == BailOutState.bailingOut) {
      _destroyBailingBody(target, damageSource);
      return combatEngine.resolveDamageBreakdown(
        baseDamage: 0,
        damageType: damageType,
        isCriticalHit: false,
        target: target,
      );
    }

    // Item 3b: what the target already carries can change this hit (a Frozen
    // target shatters for double) and is changed by it. Read first, because
    // the reacting status is often what decides the damage; settled after,
    // because spending it before the breakdown would throw that away.
    final fired = firesReactions
        ? _damageReactionsOn(target, damageType)
        : const <(StatusEffectInstance, StatusReaction)>[];
    var reactionMultiplier = 1.0;
    for (final (_, reaction) in fired) {
      reactionMultiplier *= reaction.damageMultiplier;
    }

    final healthBeforeDamage = target.currentHealth;
    final breakdown = combatEngine.resolveDamageBreakdown(
      baseDamage: reactionMultiplier == 1.0
          ? baseDamage
          : (baseDamage * reactionMultiplier).round(),
      damageType: damageType,
      isCriticalHit: isCriticalHit,
      target: target,
      criticalDiceComponent: criticalDiceComponent,
    );
    var damage = breakdown.finalDamage;

    _settleDamageReactions(target, fired, damageType);

    // Bastian-style "Absorb" Side Effect: the first damage instance of the
    // battle is reduced further, on top of any other mitigation.
    final reduction =
        target.character.sideEffect?.firstDamageInstanceReductionPercent;
    if (reduction != null && !target.sideEffectChargeUsed) {
      damage = (damage * (1 - reduction)).round();
      target.consumeSideEffectChargeIfAvailable();
    }

    // Stored Retribution: bank damage while Guarded or Braced.
    if (damage > 0 &&
        target.reactiveEffects
            .any((r) => r.kind == ReactiveKind.bankDamage)) {
      final isGuarded = target.statusEffects
          .any((i) => i.definitionId == 'guarded' || i.definitionId == 'braced');
      if (isGuarded) {
        target.bankedDamage += damage;
      }
    }

    final maxHealth = target.effectiveStats(fatConfig: fatConfig).maxHealth;
    final wouldBeLethal =
        target.currentHealth > 1 && target.currentHealth - damage <= 0;

    if (wouldBeLethal && target.hasSurviveLethalDamageCharge) {
      target.hasSurviveLethalDamageCharge = false;
      target.currentHealth = 1;
      // One More Breath: on survive-lethal, double all status durations
      // and stun the attacker for 2 turns.
      final enrichIndex = target.reactiveEffects
          .indexWhere((r) => r.kind == ReactiveKind.enrichSurviveLethal);
      if (enrichIndex >= 0) {
        target.reactiveEffects.removeAt(enrichIndex);
        for (final status in target.statusEffects) {
          if (status.remainingTurns != null) {
            status.remainingTurns = status.remainingTurns! * 2;
          }
        }
        if (damageSource != null) {
          _applyStun(damageSource, 2);
        }
      }
    } else {
      target.currentHealth =
          (target.currentHealth - damage).clamp(0, maxHealth);
    }

    noteHealthChanged(target);

    // Karmic Bind (Punish): a fraction of any damage this character takes
    // is dealt to the enemy they are bound to.
    _propagateKarmicBind(target, healthBeforeDamage - target.currentHealth);
    return breakdown;
  }

  /// Call after anything writes [state]'s health, so a drop to zero opens the
  /// Bail Out window (or spends a Refuse to Bail) the instant it happens
  /// rather than at the next turn boundary.
  ///
  /// The timing matters: a body that is still on the board **screens**, so
  /// every distance computed later in the same resolution has to already know
  /// it is there. Deferring this to the end of the turn would mean an earlier
  /// kill briefly shortened the gap to whoever was standing behind them, which
  /// is exactly the case the bending shot exists to catch.
  void noteHealthChanged(CharacterBattleState state) {
    if (state.currentHealth > 0) return;
    if (state.bailOutState != BailOutState.none) return;

    // Refuse to Bail, pre-declared and armed like any other counter: the drop
    // does not happen. They stay standing at 1 health, buy one more turn of
    // their own, and are then gone for good with no window and no Salvage.
    final refusalIndex = state.reactiveEffects
        .indexWhere((r) => r.kind == ReactiveKind.refuseToBail);
    if (refusalIndex >= 0) {
      state.reactiveEffects.removeAt(refusalIndex);
      state.hasRefusedToBail = true;
      state.currentHealth = 1;
      return;
    }

    // Having already refused once, there is no window left to open: the
    // second drop is simply the end of them.
    if (state.hasRefusedToBail) return;

    // The last body of a squad does not bail. Its squad is defeated the
    // moment it falls (`Battle.isTeamDefeated` is unchanged), so a window
    // would only hold a finished battle open to settle a Trion transfer that
    // can no longer buy anything.
    if (!state.teammates.any((t) => t.isAlive)) return;

    state.bailOutState = BailOutState.bailingOut;
    // A wreck does not parry. Whatever was standing on this character - their
    // own ward, or an enemy trap that was waiting for them to act - goes with
    // them, so a corpse cannot reflect the hit that clears it.
    state.reactiveEffects.clear();
    // And a wreck does not bleed. Every status goes with the operator for the
    // same reason: what is left on the board is a screening obstacle with a
    // Trion value, not a fighter. They were being kept anyway, since a body
    // has no health left to lose and `Battle.startTurn` only ticks the
    // living, so a Bleeding on a bailing body was a badge that could never
    // fire. Clearing them says that outright rather than leaving the player
    // to work out which of the badges in front of them still mean anything.
    state.statusEffects.clear();
  }

  /// Ends a Bailing Out body: the Salvage is denied, and [destroyer]'s squad
  /// banks its share for having spent the action.
  void _destroyBailingBody(
    CharacterBattleState body,
    CharacterBattleState? destroyer,
  ) {
    body.bailOutState = BailOutState.destroyed;
    if (destroyer == null) return;
    teamTrionPools[destroyer.combatantId]
        ?.gain(bailOutConfig.attackerGainFor(body.character.baseStats.trionCapacity));
  }

  /// Karmic Bind, "Punish" (one-way): when a bound caster's own health
  /// changes by [magnitude] (damage taken or healing received), a
  /// Team-Spirit-scaled fraction of that magnitude is dealt to the enemy
  /// they are bound to, as unavoidable true damage. Requires the
  /// battle-wide [characterRegistry]; guarded against re-entrancy and a
  /// no-op once the karmic_bind status (which carries the fraction) has
  /// expired.
  void _propagateKarmicBind(CharacterBattleState caster, int magnitude) {
    if (_resolvingKarmicBind || magnitude <= 0) return;
    final targetId = caster.karmicBindTargetId;
    if (targetId == null) return;
    StatusEffectInstance? bind;
    for (final instance in caster.statusEffects) {
      if (!statusEffectEngine.catalog.contains(instance.definitionId)) continue;
      if (statusEffectEngine
          .catalog[instance.definitionId].sharesMagnitudeWithBoundEnemy) {
        bind = instance;
        break;
      }
    }
    final fraction = bind?.data['karmicBindFraction'] as double? ?? 0;
    if (fraction <= 0) return;
    final partner = characterRegistry[targetId];
    if (partner == null || !partner.isAlive) return;
    final dmg = (magnitude * fraction).round();
    if (dmg <= 0) return;
    _resolvingKarmicBind = true;
    partner.currentHealth = (partner.currentHealth - dmg).clamp(0, 1 << 30);
    noteHealthChanged(partner);
    _resolvingKarmicBind = false;
  }

  /// Rolls whether Full Arms Trigger activates for [state] this turn,
  /// using its effective FAT Chance (base stat + Team Spirit bonus).
  bool rollFatTrigger(CharacterBattleState state) {
    final stats = state.effectiveStats(fatConfig: fatConfig);
    final bonus = teamSpiritCurve.bonusesFor(stats.teamSpirit).fatChanceBonus;
    return fatEngine.rollTrigger(state, stats.fatChance + bonus);
  }

  /// Whether [state] may use [trigger] right now: not on cooldown, not
  /// action-prevented (Stunned/Frozen), not locked by Prone, and within
  /// this turn's ability-use limit (1, or up to 3 if FAT triggered).
  /// Passive Triggers are never "used" - this only applies to actives.
  bool canUseAbility(CharacterBattleState state, ActiveTrigger trigger) {
    if (state.isActionPrevented()) return false;
    if ((state.cooldowns[trigger.id] ?? 0) > 0) return false;
    if (!fatEngine.canUseAnotherAbility(state)) return false;
    final cat = StatusEffectCatalog.defaultCatalog;
    for (final instance in state.statusEffects) {
      if (instance.data['lockedAbilityId'] == trigger.id) return false;
      final def = cat[instance.definitionId];
      // Forced Choice: a status may whitelist exactly one usable ability
      // (the caller-declared cheapest/priciest); everything else is locked.
      // The definition declares the rule, the instance carries the choice.
      if (def.locksToSingleChosenAbility) {
        final onlyAllowed = instance.data['onlyAllowedTriggerId'];
        if (onlyAllowed is String && trigger.id != onlyAllowed) return false;
      }
      if (def.locksOriginFromData &&
          instance.data['lockedOrigin'] == trigger.originTag.name) {
        return false;
      }
      if (def.forcesRepetitionOfLastAbility &&
          state.lastUsedTriggerId != null &&
          trigger.id != state.lastUsedTriggerId) {
        return false;
      }
    }
    return true;
  }

  /// Spends [trigger]'s Trion cost (scaled by [state]'s active Trion-cost
  /// multiplier status effects, e.g. Overcharged/Choked) from [teamPool]
  /// and records the use against [state]'s per-turn ability count/pending
  /// cooldown. Returns false (no state change) if the team pool can't
  /// afford it.
  bool useAbility(
      CharacterBattleState state, ActiveTrigger trigger, TrionPool teamPool) {
    final cost = (trigger.trionCost * state.trionCostMultiplier()).round();
    if (!teamPool.trySpend(cost)) return false;
    state.recordAbilityUse(trigger);
    return true;
  }

  /// Max targets a ranged Trigger can hit for [attacker] right now:
  /// [ActiveTrigger.targetCount], reduced by 1 (minimum 1) if [attacker]
  /// is Blinded and [trigger] is ranged - melee/psychic Triggers are
  /// unaffected. Callers (AI/UI) should consult this before building a
  /// target list; [resolveAbilityUse] also defensively clamps to it.
  int maxRangedTargets(CharacterBattleState attacker, ActiveTrigger trigger,
      {StatusEffectCatalog? catalog}) {
    if (!trigger.rangeTag.isAtRange) return trigger.targetCount;
    if (attacker.character.sideEffect?.immuneToTargetCountReduction == true) {
      return trigger.targetCount;
    }
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    final blinded = attacker.statusEffects
        .any((i) => cat[i.definitionId].rangedTargetsReducedByOne);
    if (!blinded) return trigger.targetCount;
    return trigger.targetCount > 1 ? trigger.targetCount - 1 : 1;
  }

  /// Whether [state] may Reposition to [destination] right now.
  ///
  /// Reposition is one step along the line, and it costs the character
  /// their ability use for the turn, so it competes with attacking rather
  /// than being a free extra. That is the tempo price of closing the gap.
  ///
  /// Deliberately *not* blocked by the things that block abilities beyond
  /// action prevention: a character whose whole Loadout is out of range
  /// must still be able to move, or a bad position would leave them with no
  /// move at all, which is a punishment rather than a decision.
  bool canReposition(CharacterBattleState state, BattlePosition destination) {
    if (!canRepositionAtAll(state)) return false;
    if (!fatEngine.canUseAnotherAbility(state)) return false;
    return state.position.adjacent.contains(destination);
  }

  /// Whether nothing about [state] itself forbids moving: they are alive,
  /// not action-locked, and not pinned by a zone-lock effect.
  ///
  /// Split out of [canReposition] for the player's queue, which validates a
  /// move against a *projected* position and counts ability uses against what
  /// is already queued rather than against what has already resolved. Those
  /// two checks belong to the queue; these three belong to the character.
  bool canRepositionAtAll(CharacterBattleState state) =>
      state.isAlive &&
      !state.isActionPrevented() &&
      !state.isRepositionPrevented();

  /// Moves [state] one step to [destination], spending their action for the
  /// turn. Returns false and changes nothing if the move is not legal.
  bool reposition(CharacterBattleState state, BattlePosition destination) {
    if (!canReposition(state, destination)) return false;
    state.position = destination;
    state.recordRepositionUse();
    return true;
  }

  /// How many of [triggers] could reach at least one of [opponents] if
  /// [state] were standing at [from]. The measure of how useful a position
  /// is to this character right now.
  /// Counts only the triggers aimed at an enemy. A self-buff or an ally ward
  /// reaches from anywhere, so counting those would say a character standing
  /// four squares out of every attack's band is doing fine. That is exactly
  /// what happened: two squads out of range of each other, each holding a
  /// self-buff, stood still re-buffing for the rest of the battle because
  /// neither ever registered as stuck.
  int reachableAbilityCount(
    CharacterBattleState state,
    BattlePosition from,
    List<ActiveTrigger> triggers,
    List<CharacterBattleState> opponents,
  ) {
    final living = opponents.where((o) => o.isAlive).toList();
    if (living.isEmpty) return 0;
    // The opponents are each other's screens, so the lines they are standing
    // on are exactly what [BattleDistance.betweenEnemies] needs. Only the
    // living are worth aiming at, but every body still on the board screens,
    // so the two lists are drawn separately.
    final theirLines = [
      for (final o in opponents)
        if (o.isOnBoard) o.position,
    ];
    var count = 0;
    for (final trigger in triggers) {
      if (trigger.targetAffiliation != TargetAffiliation.opponent) continue;
      final reaches = living.any((o) => trigger.rangeTag.reaches(
          BattleDistance.betweenEnemies(from, o.position,
              targetSquad: theirLines)));
      if (reaches) count++;
    }
    return count;
  }

  /// The single step [state] should take to bring more of [triggers] into
  /// range, or null when staying put is at least as good.
  ///
  /// This is what stops a bad position becoming a skipped turn. A character
  /// whose whole Loadout is out of range would otherwise stand there doing
  /// nothing, and if both squads were in that state the battle would never
  /// end.
  ///
  /// [from] measures the step from somewhere other than where the character
  /// is standing, for a caller planning against a projected position (the
  /// player's queue). Such a caller counts ability uses against what it has
  /// queued, so the use check is skipped when [from] is given.
  BattlePosition? suggestReposition(
    CharacterBattleState state,
    List<ActiveTrigger> triggers,
    List<CharacterBattleState> opponents, {
    BattlePosition? from,
  }) {
    if (!canRepositionAtAll(state)) return null;
    if (from == null && !fatEngine.canUseAnotherAbility(state)) return null;
    final origin = from ?? state.position;
    final staying = reachableAbilityCount(state, origin, triggers, opponents);
    BattlePosition? best;
    var bestCount = staying;
    for (final destination in origin.adjacent) {
      final count =
          reachableAbilityCount(state, destination, triggers, opponents);
      if (count > bestCount) {
        bestCount = count;
        best = destination;
      }
    }
    if (best != null || staying > 0) return best;

    // Nothing reachable from here, and no single step fixes that either. A
    // strict-improvement test can never fire from that position, so a
    // character stranded two steps out would stand still forever. Walk
    // towards the band instead: whichever step shrinks the gap to the nearest
    // band edge, so the second step arrives.
    final here = _bandShortfall(origin, triggers, opponents);
    var bestShortfall = here;
    for (final destination in origin.adjacent) {
      final shortfall = _bandShortfall(destination, triggers, opponents);
      if (shortfall < bestShortfall) {
        bestShortfall = shortfall;
        best = destination;
      }
    }
    return best;
  }

  /// How far out of band this position is, summed over the opponent-targeted
  /// [triggers]: for each one, how many steps the nearest enemy is outside its
  /// window (0 when it already reaches). Lower is closer to being useful.
  ///
  /// Only meaningful as a comparison between neighbouring positions, which is
  /// the one thing [suggestReposition] uses it for.
  int _bandShortfall(
    BattlePosition from,
    List<ActiveTrigger> triggers,
    List<CharacterBattleState> opponents,
  ) {
    final living = opponents.where((o) => o.isAlive).toList();
    if (living.isEmpty) return 0;
    final theirLines = [
      for (final o in opponents)
        if (o.isOnBoard) o.position,
    ];
    var total = 0;
    for (final trigger in triggers) {
      if (trigger.targetAffiliation != TargetAffiliation.opponent) continue;
      // Bigger than any real shortfall can be: the widest gap is
      // maxEnemyDistance short of the tightest band's minimum of 0.
      var closest = BattleDistance.maxEnemyDistance + 1;
      for (final opponent in living) {
        final distance = BattleDistance.betweenEnemies(from, opponent.position,
            targetSquad: theirLines);
        final gap = distance < trigger.rangeTag.minDistance
            ? trigger.rangeTag.minDistance - distance
            : distance > trigger.rangeTag.maxDistance
                ? distance - trigger.rangeTag.maxDistance
                : 0;
        if (gap < closest) closest = gap;
      }
      total += closest;
    }
    return total;
  }

  /// Whether [trigger] is an attack: aimed at the enemy, and dealing damage.
  ///
  /// The one question that decides what may be pointed at a Bailing Out body.
  /// A body has no health left to take a debuff's word for, nothing to cleanse
  /// and nothing to heal, so only an attack may be aimed at one; every other
  /// ability passes it by and the interface never offers it. Shared with the
  /// app and the AI so there is exactly one definition of "damaging".
  static bool isAttackOnEnemy(ActiveTrigger trigger) =>
      trigger.targetAffiliation == TargetAffiliation.opponent &&
      trigger.damageType != null &&
      trigger.damage != null;

  /// Whether [a] and [b] are on the same side. Read off the `teammates`
  /// wiring the Battle constructor sets up; a character counts as their own
  /// ally so self-targeting takes the same path.
  bool areAllies(CharacterBattleState a, CharacterBattleState b) =>
      identical(a, b) || a.teammates.contains(b);

  /// The lines [target]'s own squadmates are standing on, which is what
  /// screens them (see [BattleDistance.screensFor]).
  ///
  /// Reads [CharacterBattleState.isOnBoard] rather than `isAlive`, because a
  /// Bailing Out body is still a body in the way. That is what makes clearing
  /// one a real choice rather than a formality: breaking a screen no longer
  /// shortens the gap on its own, since the screen is still standing there
  /// until somebody spends an action on it or it is recalled.
  ///
  /// Read off the `teammates` wiring the Battle constructor sets up. A
  /// standalone engine harness may leave that empty, in which case nobody
  /// screens anybody and the distance is the raw geometry, exactly as it was
  /// before screening existed. `battle_test` guards that a real Battle always
  /// wires it, so a live game never silently loses screening.
  List<BattlePosition> screeningLinesFor(CharacterBattleState target) => [
        for (final mate in target.teammates)
          if (mate.isOnBoard) mate.position,
      ];

  /// How far apart [a] and [b] are standing right now.
  ///
  /// Allies subtract and enemies add (see [BattleDistance]), because the two
  /// squads face each other across a gap: hanging back moves you away from
  /// the enemy but towards your own back line. Against an enemy the bodies
  /// screening them count too.
  int distanceBetween(CharacterBattleState a, CharacterBattleState b) =>
      areAllies(a, b)
          ? BattleDistance.betweenAllies(a.position, b.position)
          : BattleDistance.betweenEnemies(a.position, b.position,
              targetSquad: screeningLinesFor(b));

  /// Whether [trigger]'s range band reaches [target] from where [attacker]
  /// is standing.
  ///
  /// Self-targeted abilities always reach: you are always at your own
  /// position, whatever band the ability carries.
  ///
  /// Against an **enemy** the band is a window, minimum and maximum both: a
  /// sniper caught in a scrum has no shot, which is what stops standing at
  /// the back being free.
  ///
  /// Towards an **ally** only a maximum applies, and it is the band's own
  /// [RangeTagReachWindow.allyMaxDistance]. A band's minimum is about needing
  /// room to bring a weapon to bear on someone who is fighting you; none of
  /// that is true of handing a heal or a ward to the person next to you.
  /// Without this carve-out a Mid-band heal could not reach an ally standing
  /// in the same position, which is absurd on its face. Screening does not
  /// apply towards an ally either: your own squad is not in your way.
  ///
  /// [fromPosition] overrides where the attacker is measured from, and
  /// [targetPosition] where the target is. Both exist for planning against a
  /// position nobody is standing in yet: the player's queue resolves every
  /// Reposition before any ability, so the UI has to judge range against
  /// where the character *will* be, not where they are (see
  /// `PlaySession.projectedPositionOf`). Omit them for the live answer.
  ///
  /// [targetSquad] overrides which lines are counted as screening [target],
  /// for the same planning reason: a caller working from projected positions
  /// has to screen against the projected formation, not the live one. Omit it
  /// and the target's own living teammates are used.
  /// [bending] drops the band's **minimum** for this check, which is what a
  /// bent shot is: an attack committed at a legal distance whose target has
  /// since come too close. The maximum still applies, because bending buys
  /// you room, not reach. Callers set it only for a shot they have already
  /// decided is bending; see `PlaySession`, which owns that decision and
  /// charges Trion Backlash for it.
  bool canReach(
    CharacterBattleState attacker,
    CharacterBattleState target,
    ActiveTrigger trigger, {
    BattlePosition? fromPosition,
    BattlePosition? targetPosition,
    Iterable<BattlePosition>? targetSquad,
    bool bending = false,
  }) {
    if (identical(attacker, target)) return true;
    if (trigger.targetAffiliation == TargetAffiliation.self) return true;

    final from = fromPosition ?? attacker.position;
    final to = targetPosition ?? target.position;

    // Which side the target is on comes from what the ability is *for*,
    // not from the `teammates` wiring, which only the Battle constructor
    // sets up and which a standalone engine harness may leave empty. An
    // ally-targeted ability is aimed at an ally by definition.
    final towardsAlly = trigger.targetAffiliation != TargetAffiliation.opponent;
    if (towardsAlly) {
      return trigger.rangeTag
          .reachesAlly(BattleDistance.betweenAllies(from, to));
    }
    final distance = BattleDistance.betweenEnemies(from, to,
        targetSquad: targetSquad ?? screeningLinesFor(target));
    if (bending) return distance <= trigger.rangeTag.maxDistance;
    return trigger.rangeTag.reaches(distance);
  }

  /// Whether [attacker] may target [target] at all right now: false if
  /// [attacker] is Charmed by [target] (a charmed character cannot target
  /// their own charmer - the restriction lives on the charmed character,
  /// so this checks [attacker]'s own active effects, not [target]'s).
  ///
  /// Pass [trigger] to also apply the range band: an ability only reaches a
  /// target inside its window (see [canReach]). Callers that have no
  /// particular ability in mind may leave it null and get the old
  /// ability-agnostic answer. [fromPosition]/[targetPosition] are passed
  /// straight through to [canReach] for planning against projected positions.
  bool canTarget(CharacterBattleState attacker, CharacterBattleState target,
      {StatusEffectCatalog? catalog,
      ActiveTrigger? trigger,
      BattlePosition? fromPosition,
      BattlePosition? targetPosition,
      Iterable<BattlePosition>? targetSquad,
      bool bending = false}) {
    if (trigger != null &&
        !canReach(attacker, target, trigger,
            fromPosition: fromPosition,
            targetPosition: targetPosition,
            targetSquad: targetSquad,
            bending: bending)) {
      return false;
    }
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    for (final instance in attacker.statusEffects) {
      final def = cat[instance.definitionId];
      if (def.cannotTargetSource &&
          instance.sourceCharacterId == target.combatantId) {
        return false;
      }
    }
    // Vow of the Duel: can only target the bound enemy (opponents only).
    if (attacker.duelTargetId != null) {
      final isOpponent =
          !identical(attacker, target) && !attacker.teammates.contains(target);
      if (isOpponent && target.combatantId != attacker.duelTargetId) {
        return false;
      }
    }
    return true;
  }

  /// Advantage granted to [attacker] against [target], sourced from
  /// [target]'s own active status effects (e.g. Charmed: "the source has
  /// advantage on rolls against the affected character"). Applies to both
  /// the attack roll and any status-infliction roll [attacker] makes
  /// against [target] - a cross-character lookup that doesn't belong on
  /// `CharacterBattleState.rollContextFor`, which only reads a
  /// character's own effects.
  RollContext _advantageContextAgainst(
      CharacterBattleState attacker, CharacterBattleState target,
      {StatusEffectCatalog? catalog}) {
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    final context = RollContext();
    for (final instance in target.statusEffects) {
      final def = cat[instance.definitionId];
      if (def.sourceHasAdvantageAgainstTarget &&
          instance.sourceCharacterId == attacker.combatantId) {
        context.addAdvantage('status:${def.id}:source-advantage');
      }
    }
    return context;
  }

  /// [attacker]'s own roll-context contribution for using [trigger]:
  /// disadvantage from Poisoned (`StatusRollTag.attackRoll`, applies to
  /// every attack type) merged with Threatened/Blinded's
  /// `StatusRollTag.rangedAttackRoll` disadvantage if [trigger] is ranged.
  RollContext _attackRollContextFor(
      CharacterBattleState attacker, ActiveTrigger trigger) {
    final context = RollContext();
    for (final source in attacker
        .rollContextFor(StatusRollTag.attackRoll)
        .disadvantageSources) {
      context.addDisadvantage(source);
    }
    if (trigger.rangeTag.isAtRange) {
      for (final source in attacker
          .rollContextFor(StatusRollTag.rangedAttackRoll)
          .disadvantageSources) {
        context.addDisadvantage(source);
      }
    }
    return context;
  }

  /// A fresh [RollContext] combining every source from [base] and [extra],
  /// leaving both untouched.
  RollContext _mergedContext(RollContext base, RollContext extra) {
    final merged = RollContext();
    for (final s in base.advantageSources) merged.addAdvantage(s);
    for (final s in base.disadvantageSources) merged.addDisadvantage(s);
    for (final s in extra.advantageSources) merged.addAdvantage(s);
    for (final s in extra.disadvantageSources) merged.addDisadvantage(s);
    return merged;
  }

  /// Sable-style "Guardian's Instinct" Side Effect: if [target] has a living
  /// teammate with an unused redirect charge, the attack is rerouted onto
  /// that teammate instead, consuming their charge. Returns [target]
  /// unchanged if no redirect applies.
  CharacterBattleState _applyGuardianRedirect(CharacterBattleState target) {
    // Nobody steps in front of a Bailing Out body. There is nothing left to
    // save, and spending a once-per-battle charge on one would be the worst
    // trade in the game.
    if (target.bailOutState == BailOutState.bailingOut) return target;
    for (final teammate in target.teammates) {
      if (identical(teammate, target)) continue;
      if (!teammate.isAlive) continue;
      if (teammate.character.sideEffect?.canRedirectAllyAttackOncePerBattle !=
          true) {
        continue;
      }
      if (teammate.sideEffectChargeUsed) continue;
      // Protection needs proximity: you cannot step in front of someone you
      // are not standing near. A bodyguard has to actually be there.
      if (BattleDistance.betweenAllies(teammate.position, target.position) >
          1) {
        continue;
      }
      teammate.consumeSideEffectChargeIfAvailable();
      return teammate;
    }
    return target;
  }

  /// The Phase-4 reactive-stack remap: before a hit resolves against
  /// [target], the target's standing reactive effects (combat v2 counters)
  /// get a chance to reroute, negate, or modify it. Dispatches on
  /// [ReactiveKind] in priority order. Falls through to the SE-based
  /// Guardian redirect when no reactive effect applies. Returns the
  /// character the hit should actually resolve against, or null if the hit
  /// is negated entirely.
  CharacterBattleState? _applyReactiveTargetRemap(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    CharacterBattleState target,
  ) {
    // Foresight Counter: negate by origin tag (non-AoE only).
    if (trigger.attackSubtype != AttackSubtype.aoe) {
      final negateIndex = target.reactiveEffects.indexWhere((r) =>
          r.kind == ReactiveKind.negateByOrigin &&
          r.data['originTag'] == trigger.originTag.name);
      if (negateIndex >= 0) {
        target.reactiveEffects.removeAt(negateIndex);
        _applyStun(attacker, 2);
        return null;
      }
    }

    // Mirror Ward: reflect non-AoE.
    if (trigger.attackSubtype != AttackSubtype.aoe) {
      final wardIndex = target.reactiveEffects
          .indexWhere((r) => r.kind == ReactiveKind.reflectNonAoe);
      if (wardIndex >= 0) {
        target.reactiveEffects.removeAt(wardIndex);
        return attacker;
      }
    }

    // Puppet Strings: redirect non-AoE attacks to a random ally of the
    // attacker. Consumes the reactive and removes the caster's Exposed.
    if (trigger.attackSubtype != AttackSubtype.aoe) {
      final puppetIndex = target.reactiveEffects
          .indexWhere((r) => r.kind == ReactiveKind.redirectToOwnAlly);
      if (puppetIndex >= 0) {
        final effect = target.reactiveEffects.removeAt(puppetIndex);
        _removeExposedFromSource(effect.sourceCharacterId);
        final allyTargets =
            attacker.teammates.where((t) => t.isAlive).toList();
        if (allyTargets.isNotEmpty) {
          return allyTargets[
              combatEngine.diceRoller.random.nextInt(allyTargets.length)];
        }
        return null;
      }
    }

    // Predictive Parry: dodge melee single and counter-hit.
    if (trigger.attackType == AttackType.melee &&
        trigger.attackSubtype == AttackSubtype.single) {
      final parryIndex = target.reactiveEffects
          .indexWhere((r) => r.kind == ReactiveKind.dodgeMeleeSingle);
      if (parryIndex >= 0) {
        target.reactiveEffects.removeAt(parryIndex);
        _resolveCounterHit(target, attacker);
        return null;
      }
    }

    return _applyGuardianRedirect(target);
  }

  /// Applies a Stun (action prevention) to [target] for [turns] turns via
  /// the status effect engine.
  void _applyStun(CharacterBattleState target, int turns) {
    statusEffectEngine.apply(
      target,
      'stunned',
      durationOverride: turns,
    );
  }

  /// Resolves a free counter-hit from [attacker] against [target] using
  /// standard Twin Fang Strike damage (6d6+23 slashing) - kept in step
  /// with the catalog entry Predictive Parry hangs off.
  void _resolveCounterHit(
    CharacterBattleState attacker,
    CharacterBattleState target,
  ) {
    final counterDamageRoll =
        const DiceExpression(6, 6, flatBonus: 23).roll(combatEngine.diceRoller);
    _applyDamage(
      target: target,
      baseDamage: counterDamageRoll,
      damageType: DamageType.slashing,
      isCriticalHit: false,
    );
  }

  /// Checks whether [target] has burst mitigation armed; if so, records
  /// the index so subsequent hits on the same target in the same burst
  /// are suppressed. Returns true if this is NOT the first hit and burst
  /// mitigation is active (meaning the hit should be skipped).
  bool _isBurstMitigated(
    CharacterBattleState target,
    Map<String, bool> burstFirstHitLanded,
  ) {
    final key = target.combatantId;
    if (burstFirstHitLanded.containsKey(key)) return true;
    final mitigationIndex = target.reactiveEffects
        .indexWhere((r) => r.kind == ReactiveKind.burstMitigation);
    if (mitigationIndex < 0) return false;
    burstFirstHitLanded[key] = true;
    target.reactiveEffects.removeAt(mitigationIndex);
    return false;
  }

  /// Removes the Puppet Strings caster's Exposed status when the reactive
  /// fires or expires. No-op if the source can't be found or has no Exposed.
  void _removeExposedFromSource(String? sourceCharacterId) {
    if (sourceCharacterId == null) return;
    // The source may be on any team; search via the reactive's data.
    // Because we don't have a direct reference to all battle participants
    // here, the Exposed status is left to expire naturally if the source
    // can't be found in the target's teammates or the target itself.
    // The reactive's holder IS the protected ally, but the source (caster)
    // is tracked by sourceCharacterId. To find the caster we'd need
    // cross-team access, which _armReactiveEffect already has. Instead,
    // we rely on the Exposed status having the same duration as the
    // reactive, so it auto-expires in sync. If the reactive fires early,
    // the Exposed status remains until its natural 2-turn expiry.
  }

  /// Checks attacker-side reactive effects (Deadfall, Death Ledger) before
  /// ability resolution. Returns true if the ability is countered (should
  /// not resolve). Deadfall deals trap damage to the attacker.
  /// Whether [effect] can still reach [holder], the enemy it was set on,
  /// from where it was armed.
  ///
  /// **Screening deliberately does not apply here**, and this is the only
  /// distance in the game measured that way. A trap is a hazard already
  /// attached to its target, and squadmates shuffling about in front of them
  /// does not undo it. The two lines still count, so retreating out of the
  /// band you armed from does drop the trap.
  ///
  /// Every enemy-placed trap asks this question. Death Ledger used not to,
  /// which read as an oversight rather than as a rule.
  ///
  /// A trap armed before positions existed, or by a caller that did not
  /// record them, carries no band and always fires - so older content and
  /// test fixtures behave exactly as they did.
  bool _trapStillReaches(ReactiveEffect effect, CharacterBattleState holder) {
    final band = effect.data[_trapBandKey];
    final armedStep = effect.data[_trapArmedStepKey];
    if (band is! String || armedStep is! int) return true;
    final tag = RangeTag.values.firstWhere(
      (t) => t.name == band,
      orElse: () => RangeTag.mid,
    );
    return tag.reaches(armedStep + holder.position.step);
  }

  bool _checkAttackerReactives(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
  ) {
    // Deadfall: if the attacker has trapOnAction and uses a damaging ability.
    if (trigger.damageType != null) {
      final trapIndex = attacker.reactiveEffects.indexWhere((r) =>
          r.kind == ReactiveKind.trapOnAction && _trapStillReaches(r, attacker));
      if (trapIndex >= 0) {
        attacker.reactiveEffects.removeAt(trapIndex);
        final trapDamage = const DiceExpression(4, 8, flatBonus: 16)
            .roll(combatEngine.diceRoller);
        _applyDamage(
          target: attacker,
          baseDamage: trapDamage,
          damageType: DamageType.force,
          isCriticalHit: false,
        );
        return true;
      }
    }

    // Death Ledger: if the attacker has nullifyAoe and uses an AoE, nullify it
    // and signal the wielder to swap the AoE Trigger into their loadout.
    if (trigger.attackSubtype == AttackSubtype.aoe) {
      final ledgerIndex = attacker.reactiveEffects.indexWhere((r) =>
          r.kind == ReactiveKind.nullifyAoe && _trapStillReaches(r, attacker));
      if (ledgerIndex >= 0) {
        final reactive = attacker.reactiveEffects.removeAt(ledgerIndex);
        final wielderId = reactive.sourceCharacterId;
        if (wielderId != null) {
          characterRegistry[wielderId]?.deathLedgerSwapPending = trigger;
        }
        return true;
      }
    }

    return false;
  }

  /// Checks if the attacker has a misfire status, and if so, potentially
  /// redirects each target to a random living ally of the attacker.
  List<CharacterBattleState> _applyMisfireRedirect(
    CharacterBattleState attacker,
    List<CharacterBattleState> targets,
  ) {
    final cat = StatusEffectCatalog.defaultCatalog;
    double? chance;
    for (final instance in attacker.statusEffects) {
      final def = cat[instance.definitionId];
      if (def.misfireChance != null) {
        chance = def.misfireChance;
        break;
      }
    }
    if (chance == null) return targets;

    final allies = attacker.teammates.where((t) => t.isAlive).toList();
    if (allies.isEmpty) return targets;

    return targets.map((t) {
      if (combatEngine.diceRoller.random.nextInt(100) <
          (chance! * 100).round()) {
        return allies[combatEngine.diceRoller.random.nextInt(allies.length)];
      }
      return t;
    }).toList();
  }

  /// Item 3b's redesigned Enraged: while it is on, the holder does not choose
  /// who they hit.
  ///
  /// [pool] is every character the ability could legally have been aimed at.
  /// Each chosen target is replaced by a random one from it, so a squad that
  /// enrages an enemy blunts their aim, and a squad that enrages its own
  /// front-liner accepts that as the price of the damage and the psychic
  /// immunity. With no pool supplied there is nothing to choose between and
  /// the targets are returned unchanged.
  List<CharacterBattleState> _applyRandomTargeting(
    CharacterBattleState attacker,
    List<CharacterBattleState> targets,
    List<CharacterBattleState> pool,
  ) {
    final randomised = attacker.statusEffects.any((i) =>
        statusEffectEngine.catalog.contains(i.definitionId) &&
        statusEffectEngine.catalog[i.definitionId].randomizesOwnTargeting);
    if (!randomised) return targets;

    final candidates = pool.where((c) => c.isOnBoard).toList();
    if (candidates.length < 2) return targets;

    return [
      for (var i = 0; i < targets.length; i++)
        candidates[combatEngine.diceRoller.random.nextInt(candidates.length)],
    ];
  }

  /// Combined outgoing-damage multiplier from [attacker]'s Side Effect (Rurik's
  /// low-health scaling, Dross's AOE-vs-debuffed bonus, Nadia's
  /// stacking-per-extra-FAT-use bonus). 1.0 if [attacker] has no Side Effect or
  /// none of its fields apply to this hit.
  double _sideEffectOutgoingDamageMultiplier(
    CharacterBattleState attacker,
    CharacterBattleState target,
    ActiveTrigger trigger,
  ) {
    final sideEffect = attacker.character.sideEffect;
    if (sideEffect == null) return 1.0;
    var multiplier = 1.0;

    final lowHealthBonus = sideEffect.maxDamageBonusPercentAtZeroHealth;
    if (lowHealthBonus != null) {
      final maxHealth = attacker.effectiveStats(fatConfig: fatConfig).maxHealth;
      final missingFraction =
          maxHealth <= 0 ? 0.0 : 1 - (attacker.currentHealth / maxHealth);
      multiplier += lowHealthBonus * missingFraction.clamp(0.0, 1.0);
    }

    final aoeBonus = sideEffect.aoeDamageBonusPercentVsDebuffedTarget;
    if (aoeBonus != null &&
        trigger.attackSubtype == AttackSubtype.aoe &&
        target.statusEffects.isNotEmpty) {
      multiplier += aoeBonus;
    }

    final chainBonus = sideEffect.perExtraAbilityDamageBonusPercent;
    if (chainBonus != null) {
      final extraUses = attacker.abilitiesUsedThisTurnCount - 1;
      if (extraUses > 0) multiplier += chainBonus * extraUses;
    }

    return multiplier;
  }

  /// Resolves [attacker] using [trigger] against [targets]: rolls to hit
  /// (Single/Unique: one hit against the first target; AoE: one
  /// independent hit per target; Burst: `trigger.hitsPerUse` independent
  /// hits against *each* target - `targetCount` governs how many targets
  /// the ability can hit at all, `hitsPerUse` governs how many times it
  /// hits each one it does target), resolves damage/heal, and
  /// rolls/applies any status effects the Trigger inflicts on a landed
  /// hit. Folds in the attacker's effective Critical Chance and Team
  /// Spirit's damage/crit bonuses (mirroring `rollFatTrigger`'s pattern of
  /// folding a Team Spirit bonus into a base stat); the heal amount is
  /// scaled by the *target's* own Health Regeneration bonus instead (see
  /// `_scaledHealAmount`).
  ///
  /// [damageMultiplier]/[healMultiplier] additionally scale this use's
  /// damage/heal - used for Black Trigger abilities, whose particulars
  /// are scaled by the wielder's resonance grade (see
  /// `resonanceMultiplierFor`); regular Triggers leave these at 1.0.
  ///
  /// Does not check ability legality or spend Trion - call
  /// `canUseAbility`/`useAbility` first. [targets] is defensively clamped
  /// against `maxRangedTargets`/`canTarget`; callers (AI/UI) are expected
  /// to have already consulted those before choosing targets.
  ///
  /// [targetPool] is every character the ability could legally have been
  /// aimed at. It is only read when the attacker's targeting is out of their
  /// hands (Enraged, item 3b), and a caller that never inflicts such a status
  /// may leave it empty: with nothing to choose between, the chosen targets
  /// stand.
  AbilityUseResult resolveAbilityUse({
    required CharacterBattleState attacker,
    required ActiveTrigger trigger,
    required List<CharacterBattleState> targets,
    double damageMultiplier = 1.0,
    double healMultiplier = 1.0,
    Map<String, Object?>? reactiveData,
    Map<String, Object?>? statusEffectData,
    Map<String, Object?>? uniqueData,
    bool bending = false,
    List<CharacterBattleState> targetPool = const [],
  }) {
    // Item 3b: this resolution's reactions are collected as they fire and
    // handed back on the result, so the log can say why a Frozen badge
    // vanished and the number doubled.
    _pendingReactions.clear();

    // Nullhymn recency: stamp Black-Trigger-active uses so a later discharge
    // can downgrade the most-recently-active enemy Black Trigger.
    if (attacker.character.blackTrigger?.activeAbilities
            .any((t) => t.id == trigger.id) ??
        false) {
      attacker.lastBlackTriggerUseOrder = ++_btUseOrder;
    }

    // Attacker-side reactive check: Deadfall/Death Ledger can counter the
    // ability entirely before it resolves.
    if (_checkAttackerReactives(attacker, trigger)) {
      return AbilityUseResult(
        attackerCharacterId: attacker.combatantId,
        triggerId: trigger.id,
        targetResults: const [],
      );
    }

    // Echoing Doubt: the afflicted character's next offensive ability is
    // forced to whiff. They already paid Trion/cooldown (via useAbility);
    // the whiff then backlashes and Silences them. Deterministic, not RNG.
    if (trigger.targetAffiliation == TargetAffiliation.opponent &&
        attacker.isNextAttackForced()) {
      _consumeEchoingDoubt(attacker);
      return _emptyResult(attacker.combatantId, trigger.id);
    }

    final maxTargets = maxRangedTargets(attacker, trigger);
    var filteredTargets = targets
        .where((t) => canTarget(attacker, t, trigger: trigger, bending: bending))
        .toList();

    // An area attack catches one position, not any three bodies on the
    // field. The first surviving target is the one being aimed at, and
    // everyone standing with them is caught; anyone at another position is
    // not. This is what makes stacking a squad dangerous and spreading out
    // a real defence, and it is the half of the change that gives the
    // opponent a reason to want you clumped together.
    if (trigger.attackSubtype == AttackSubtype.aoe &&
        filteredTargets.isNotEmpty) {
      final aimedAt = filteredTargets.first.position;
      filteredTargets =
          filteredTargets.where((t) => t.position == aimedAt).toList();
    }

    filteredTargets = filteredTargets.take(maxTargets).toList();

    // Misfire redirect: if attacker has the misfire status, some targets
    // may be redirected to the attacker's own allies.
    if (trigger.targetAffiliation == TargetAffiliation.opponent) {
      filteredTargets = _applyMisfireRedirect(attacker, filteredTargets);
      // Enraged (item 3b): the holder is not choosing any more.
      filteredTargets = _applyRandomTargeting(
        attacker,
        filteredTargets,
        targetPool,
      );
    }

    // Unique subtype uses bespoke resolution and does NOT pass through the
    // standard reactive-remap (each unique defines its own reactive
    // handling - e.g. Curving Shot deliberately bends around the first
    // ward instead of being reflected by it). Dispatch here, before the
    // remap, on the canTarget/misfire-filtered targets.
    if (trigger.attackSubtype == AttackSubtype.unique &&
        trigger.uniqueBehavior != null) {
      return _resolveUniqueBehavior(
        attacker: attacker,
        trigger: trigger,
        targets: filteredTargets,
        damageMultiplier: damageMultiplier,
        healMultiplier: healMultiplier,
        uniqueData: uniqueData,
      );
    }

    final clampedTargets = <CharacterBattleState>[];
    for (final t in filteredTargets) {
      final remapped = _applyReactiveTargetRemap(attacker, trigger, t);
      if (remapped != null) clampedTargets.add(remapped);
    }

    final baseContext = _attackRollContextFor(attacker, trigger);
    final stats = attacker.effectiveStats(fatConfig: fatConfig);
    final bonuses = teamSpiritCurve.bonusesFor(stats.teamSpirit);
    final isBurst = trigger.attackSubtype == AttackSubtype.burst;

    // Ren-style "First Strike" Side Effect: a flat Attack bonus on this
    // character's first ability use of the battle. Gated on the Side Effect
    // charge (consumed here, once per ability use regardless of how many
    // targets/hits it resolves), not `hasActedThisBattle` - by the time
    // this method runs, `useAbility` has already flipped that flag.
    var effectiveAttack = stats.attack;
    final firstStrikeBonus =
        attacker.character.sideEffect?.firstTurnAttackBonus;
    if (firstStrikeBonus != null && !attacker.sideEffectChargeUsed) {
      effectiveAttack += firstStrikeBonus;
      attacker.consumeSideEffectChargeIfAvailable();
    }

    final hitsByTargetId = <String, List<_SingleHitResult>>{};

    void resolveHitAgainst(CharacterBattleState target) {
      final advantageContext = _advantageContextAgainst(attacker, target);
      var attackerContext = _mergedContext(baseContext, advantageContext);

      AttackRollOutcome? outcome;
      var forcedMiss = false;

      void record(
        int damage,
        HitDamageDetail? damageDetail,
        List<String> appliedIds, [
        Map<String, int> appliedStacks = const {},
      ]) {
        hitsByTargetId.putIfAbsent(target.combatantId, () => []).add(
              _SingleHitResult(
                outcome,
                damage,
                damageDetail,
                appliedIds,
                appliedStacks: appliedStacks,
              ),
            );
      }

      // A heal, a ward or a buff aimed at your own side is not an attack, and
      // it does not go through the attack pipeline at all.
      //
      // It used to. The roll was made against the recipient's own Defense and
      // then overridden to a hit, which fixed the answer and left everything
      // the pipeline does on the way to it still done: War Chant burned the
      // ally's once-per-battle Decoy charge, spent First Blood on a
      // full-health teammate, and consumed a Reckoning that should have
      // wrecked the caster's next real attack. It also read "Rurik Voss
      // (1 hit)" in the battle log, which is the part a playtest saw. A roll
      // that cannot fail and cannot be read is not a roll.
      //
      // Nothing on this path is contested: the status infliction below is
      // likewise uncontested on your own side. So there is nothing to roll,
      // and `outcome` stays null all the way into the log.
      if (trigger.targetAffiliation == TargetAffiliation.opponent) {
      // Airi-style "Feint" Side Effect: the first attack roll made against her
      // each battle is rolled with disadvantage.
      if (target.character.sideEffect?.firstIncomingAttackHasDisadvantage ==
              true &&
          !target.sideEffectChargeUsed) {
        final withFeint = RollContext();
        for (final s in attackerContext.advantageSources) {
          withFeint.addAdvantage(s);
        }
        for (final s in attackerContext.disadvantageSources) {
          withFeint.addDisadvantage(s);
        }
        withFeint.addDisadvantage('side_effect:feint');
        attackerContext = withFeint;
        target.consumeSideEffectChargeIfAvailable();
      }

      // Vela-style "First Blood" Side Effect: bonus Critical Chance on this
      // character's first attack of the battle, if that target is at
      // full health.
      var attackerCriticalChancePercent =
          stats.criticalChance + bonuses.criticalChanceBonus;
      final firstBloodBonus =
          attacker.character.sideEffect?.firstAttackCritBonusVsFullHealthTarget;
      if (firstBloodBonus != null && !attacker.sideEffectChargeUsed) {
        final targetMaxHealth =
            target.effectiveStats(fatConfig: fatConfig).maxHealth;
        if (target.currentHealth >= targetMaxHealth) {
          attackerCriticalChancePercent += firstBloodBonus;
        }
        attacker.consumeSideEffectChargeIfAvailable();
      }

      // Mireille-style "Decoy" Side Effect: once per battle, an incoming attack
      // has a flat chance to miss entirely, independent of the to-hit
      // roll. The roll is still made (for realistic telemetry); a
      // successful dodge just overrides the outcome.
      final dodgeChance = target.character.sideEffect?.dodgeChanceOncePerBattle;
      if (dodgeChance != null && !target.sideEffectChargeUsed) {
        if (combatEngine.diceRoller.rollPercent() <=
            (dodgeChance * 100).round()) {
          forcedMiss = true;
        }
        target.consumeSideEffectChargeIfAvailable();
      }

      // TEG Effects 1/2/5: coordination advantage on the attacker's roll,
      // Operator's Read advantage on the defender's contest, and (at SSS)
      // the widened crit threshold. No-ops when no TEG profile is injected.
      _applyTegOffenseAdvantage(attackerContext, attacker);
      _applyComboAdvantage(attackerContext, attacker, trigger, target);
      final tegDefenderContext = RollContext();
      _applyTegDefenseAdvantage(tegDefenderContext, target);
      final tegMaxCrit = _tegFor(attacker).maxCritThreshold;

      outcome = combatEngine.resolveAttackRoll(
        attackerAttack: effectiveAttack,
        defenderDefense: target.effectiveStats(fatConfig: fatConfig).defense,
        attackerCriticalChancePercent: attackerCriticalChancePercent,
        attackerContext: attackerContext,
        defenderContext: tegDefenderContext,
        maxCritThreshold: tegMaxCrit,
      );

      // Reckoning: forced critical miss overrides the roll. Read off the
      // definition's own field (item 13b) rather than by naming the status.
      final forcedCritMissIdx = attacker.statusEffects.indexWhere((i) =>
          statusEffectEngine.catalog.contains(i.definitionId) &&
          statusEffectEngine.catalog[i.definitionId]
              .forcesNextAttackCriticalMiss);
      if (forcedCritMissIdx >= 0) {
        attacker.statusEffects.removeAt(forcedCritMissIdx);
        outcome = AttackRollOutcome(
          attackerRoll: outcome.attackerRoll,
          defenderRoll: outcome.defenderRoll,
          isHit: false,
          isCriticalHit: false,
          isCriticalMiss: true,
          criticalHitThreshold: outcome.criticalHitThreshold,
        );
      }

      // Zheng-style "Foresight" Side Effect: once per battle, reroll a missed
      // attack roll.
      if (!outcome.isHit &&
          attacker.character.sideEffect?.canRerollOwnAttackRollOncePerBattle ==
              true &&
          !attacker.sideEffectChargeUsed) {
        outcome = combatEngine.resolveAttackRoll(
          attackerAttack: effectiveAttack,
          defenderDefense: target.effectiveStats(fatConfig: fatConfig).defense,
          attackerCriticalChancePercent: attackerCriticalChancePercent,
          attackerContext: attackerContext,
          defenderContext: tegDefenderContext,
          maxCritThreshold: tegMaxCrit,
        );
        attacker.consumeSideEffectChargeIfAvailable();
      }

      if (outcome.isCriticalMiss) {
        combatEngine.applyCriticalMissPenalty(attacker);
        record(0, null, const []);
        return;
      }
      if (forcedMiss || !outcome.isHit) {
        // A dodge that beat the roll has to be recorded as not landing. It
        // used to keep the rolled outcome, so a Decoy'd attack went into the
        // log as a hit that dealt no damage: "(1 hit) -> HP 100", with a
        // details panel that said "so it lands" and then showed no damage.
        // The dice are still what they were; what changed is whether it
        // landed, which is the thing everything downstream reads.
        if (forcedMiss && outcome.isHit) {
          outcome = AttackRollOutcome(
            attackerRoll: outcome.attackerRoll,
            defenderRoll: outcome.defenderRoll,
            isHit: false,
            isCriticalHit: false,
            isCriticalMiss: outcome.isCriticalMiss,
            criticalHitThreshold: outcome.criticalHitThreshold,
          );
        }
        // Ilona-style "Riposte" Side Effect: a melee attack that misses her
        // grants a stacking Attack buff for her next turn.
        final riposteBonus =
            target.character.sideEffect?.attackStackBonusOnMeleeMissAgainstSelf;
        if (riposteBonus != null && trigger.attackType == AttackType.melee) {
          target.applyFlatBonus(
              ModifiableStat.attack, riposteBonus.toDouble(), 2);
        }
        record(0, null, const []);
        return;
      }
      } // end of the hostile-only attack pipeline

      var damageDealt = 0;
      HitDamageDetail? damageDetail;
      if (trigger.damageType != null) {
        final diceRoll = trigger.damage?.rollDetailed(combatEngine.diceRoller);
        final baseDamage = diceRoll?.total ?? 0;
        final damageBonus = isBurst
            ? bonuses.burstDamageBonus
            : bonuses.singleTargetDamageBonus;
        final sideEffectMultiplier =
            _sideEffectOutgoingDamageMultiplier(attacker, target, trigger);
        final interdictMultiplier =
            _interdictDamageMultiplier(attacker, trigger);
        final preCritMultiplier = (1 + damageBonus) *
            damageMultiplier *
            attacker.outgoingDamageMultiplier() *
            sideEffectMultiplier *
            interdictMultiplier;
        final adjustedBaseDamage = (baseDamage * preCritMultiplier).round();
        // A crit doubles the dice, not the flat bonus, so the dice half of
        // the roll is scaled by the same pre-crit multiplier and handed
        // down as the amount a crit repeats.
        final diceOnly = diceRoll?.rawRolls.fold<int>(0, (a, b) => a + b) ?? 0;
        final adjustedDiceDamage = (diceOnly * preCritMultiplier).round();
        final healthBefore = target.currentHealth;
        final breakdown = _applyDamage(
          target: target,
          baseDamage: adjustedBaseDamage,
          damageType: trigger.damageType!,
          // Null on a friendly ability, which never rolled and so can never
          // have crit. No such ability deals damage today; this keeps the
          // answer right if one ever does.
          isCriticalHit: outcome?.isCriticalHit ?? false,
          damageSource: attacker,
          criticalDiceComponent: adjustedDiceDamage,
        );
        if (diceRoll != null) {
          damageDetail = HitDamageDetail(
            diceRoll: diceRoll,
            preCritMultiplier: preCritMultiplier,
            breakdown: breakdown,
          );
        }
        damageDealt = healthBefore - target.currentHealth;
        if (damageDealt > 0) {
          attacker.cumulativeDamageDealt += damageDealt;
          attacker.lastDamagedTargetId = target.combatantId;
          if (trigger.attackType == AttackType.melee) {
            attacker.meleeHitEnemyIds.add(target.combatantId);
          }
        }
      }

      if (trigger.healAmount != null) {
        final recipient = trigger.healsCasterInstead ? attacker : target;
        if (!recipient.isHealingPrevented()) {
          final baseHeal = trigger.healAmount!.roll(combatEngine.diceRoller);
          // Priya-style "Combat Medic" Side Effect: bonus heal when the
          // recipient is below 50% health.
          var priyaBonus = 1.0;
          final medicBonus = attacker
              .character.sideEffect?.healBonusPercentVsAllyBelowHalfHealth;
          if (medicBonus != null &&
              trigger.targetAffiliation == TargetAffiliation.ally) {
            final recipientMax =
                recipient.effectiveStats(fatConfig: fatConfig).maxHealth;
            if (recipient.currentHealth < recipientMax * 0.5) {
              priyaBonus += medicBonus;
            }
          }
          final healed = (_scaledHealAmount(recipient, baseHeal) *
                  healMultiplier *
                  priyaBonus)
              .round();
          final maxHealth =
              recipient.effectiveStats(fatConfig: fatConfig).maxHealth;
          final beforeHeal = recipient.currentHealth;
          recipient.currentHealth =
              (recipient.currentHealth + healed).clamp(0, maxHealth);
          // Karmic Bind (Punish): healing a bound caster also strikes the
          // enemy they are bound to.
          _propagateKarmicBind(
              recipient, recipient.currentHealth - beforeHeal);
        }
      }

      final appliedIds = <String>[];
      final appliedStacks = <String, int>{};
      // TEG Effect 1 (offense) on the causer's infliction rolls this use.
      _applyTegOffenseAdvantage(advantageContext, attacker);
      // A hit that destroyed a Bailing Out body leaves nothing to afflict.
      // The body is off the board; hanging a Bleeding on it would show a
      // status badge on a character who is gone.
      final skipRiders = target.bailOutState == BailOutState.destroyed;
      for (final application in skipRiders
          ? const <StatusEffectApplication>[]
          : trigger.inflictedStatusEffects) {
        // A buff or a ward granted to your own side is not inflicted, so it
        // is not contested. Rolling it against the recipient's own Status
        // Effect Resistance meant a character resisted their own War Chant
        // three times in four. (The engine's own note on
        // `StatusEffectEngine.apply` always said self-buffs are granted
        // unconditionally; the call sites did not honour it.)
        final contested =
            trigger.targetAffiliation == TargetAffiliation.opponent;
        // TEG Effect 2 (defense) on the target's resistance roll.
        final resistContext =
            target.rollContextFor(StatusRollTag.statusResistanceRoll);
        _applyTegDefenseAdvantage(resistContext, target);
        final inflictionOutcome = contested
            ? statusEffectEngine.resolveInfliction(
                causerInfliction: stats.statusEffectInfliction,
                targetResistance: target
                    .effectiveStats(fatConfig: fatConfig)
                    .statusEffectResistance,
                causerRollContext: advantageContext,
                targetRollContext: resistContext,
              )
            : null;
        if (!contested || inflictionOutcome!.applies) {
          // Soren-style "Weaken Resolve" Side Effect: bonus duration when the
          // target already carries an effect from this same attacker.
          var durationOverride = application.durationTurnsOverride;
          final resolveBonus = attacker
              .character.sideEffect?.bonusDurationVsAlreadyAffectedTarget;
          if (resolveBonus != null &&
              target.statusEffects
                  .any((i) => i.sourceCharacterId == attacker.combatantId)) {
            final base = durationOverride ??
                statusEffectEngine
                    .catalog[application.statusEffectId].defaultDurationTurns;
            durationOverride = base == null ? null : base + resolveBonus;
          }

          final applied = statusEffectEngine.apply(
            target,
            application.statusEffectId,
            sourceCharacterId: attacker.combatantId,
            durationOverride: durationOverride,
            instanceData: statusEffectData,
          );
          if (applied) {
            appliedIds.add(application.statusEffectId);
            // Read off the live instance rather than counted here: the
            // definition's own cap decides whether a re-application actually
            // added anything.
            final live = target.statusEffects
                .where((i) => i.definitionId == application.statusEffectId)
                .firstOrNull;
            if (live != null) {
              appliedStacks[application.statusEffectId] = live.stacks;
            }
            // Celestine-style "Warding Presence" Side Effect: an ally-targeted
            // buff also grants a Status Effect Resistance bonus.
            final wardBonus = attacker
                .character.sideEffect?.bonusStatusResistanceGrantedByAllyBuffs;
            if (wardBonus != null &&
                trigger.targetAffiliation == TargetAffiliation.ally) {
              target.applyFlatBonus(ModifiableStat.statusEffectResistance,
                  wardBonus.toDouble(), durationOverride ?? 2);
            }
          }
        }
      }

      record(damageDealt, damageDetail, appliedIds, appliedStacks);
    }

    switch (trigger.attackSubtype) {
      case AttackSubtype.single:
        if (clampedTargets.isNotEmpty) resolveHitAgainst(clampedTargets.first);
        break;
      case AttackSubtype.unique:
        // A unique trigger with a behavior is dispatched earlier (before
        // the reactive remap); only the no-behavior fallback reaches here,
        // resolving like a plain single-target hit.
        if (clampedTargets.isNotEmpty) resolveHitAgainst(clampedTargets.first);
        break;
      case AttackSubtype.aoe:
        for (final target in clampedTargets) {
          resolveHitAgainst(target);
        }
        break;
      case AttackSubtype.burst:
        final burstFirstHitLanded = <String, bool>{};
        for (final target in clampedTargets) {
          for (var hitIndex = 0; hitIndex < trigger.hitsPerUse; hitIndex++) {
            if (_isBurstMitigated(target, burstFirstHitLanded)) continue;
            resolveHitAgainst(target);
          }
        }
        break;
    }

    final targetResults = <TargetHitResult>[];
    for (final target in clampedTargets) {
      final hits = hitsByTargetId[target.combatantId];
      if (hits == null || hits.isEmpty) continue;
      targetResults.add(TargetHitResult(
        targetCharacterId: target.combatantId,
        // Empty for an ability aimed at your own side: nothing was rolled,
        // so the log counts no hits and shows no roll breakdown.
        attackRolls:
            hits.map((h) => h.outcome).whereType<AttackRollOutcome>().toList(),
        damagePerHit: hits.map((h) => h.damage).toList(),
        damageDetails: hits.map((h) => h.damageDetail).toList(),
        totalDamageDealt: hits.fold(0, (sum, h) => sum + h.damage),
        statusEffectsApplied:
            hits.expand((h) => h.appliedStatusEffectIds).toList(),
        // Later hits win: a burst that stacked an effect three times reports
        // three, not the one the first strike saw.
        statusEffectStacks: {
          for (final h in hits) ...h.appliedStacks,
        },
      ));
    }

    // Frozen Tempo: if any hit target had cooldownSabotage, double this
    // ability's cooldown for the attacker.
    for (final target in clampedTargets) {
      final saboIdx = target.reactiveEffects
          .indexWhere((r) => r.kind == ReactiveKind.cooldownSabotage);
      if (saboIdx >= 0 && trigger.rangeTag.isAtRange) {
        final hits = hitsByTargetId[target.combatantId];
        final anyHit =
            hits != null && hits.any((h) => h.outcome?.isHit ?? false);
        if (anyHit) {
          target.reactiveEffects.removeAt(saboIdx);
          attacker.sabotageAbilityCooldown(trigger.id);
          break;
        }
      }
    }

    // Stored Retribution: discharge banked damage as bonus on the
    // attacker's offensive ability. Applied as a flat addition to each
    // target's total damage.
    if (attacker.bankedDamage > 0 &&
        trigger.damageType != null &&
        trigger.targetAffiliation == TargetAffiliation.opponent) {
      final bankIdx = attacker.reactiveEffects
          .indexWhere((r) => r.kind == ReactiveKind.bankDamage);
      if (bankIdx >= 0) {
        for (final target in clampedTargets) {
          if (!target.isAlive) continue;
          _applyDamage(
            target: target,
            baseDamage: attacker.bankedDamage,
            damageType: trigger.damageType!,
            isCriticalHit: false,
            damageSource: attacker,
          );
        }
        attacker.bankedDamage = 0;
        attacker.reactiveEffects.removeAt(bankIdx);
      }
    }

    // Arm reactive effects declared by the trigger.
    if (trigger.armsReactive != null) {
      _armReactiveEffect(attacker, trigger, filteredTargets, reactiveData);
    }

    // TEG Effect 3: compute the setup->payoff refund against the ledger
    // BEFORE recording this action (so it sees only prior actions as setups).
    final trionRefund = _computeComboRefund(attacker, trigger, clampedTargets);

    // Combat-v2 Phase I/J: record this resolved action so a later same-team
    // payoff can recognize a setup->payoff / focus-fire combo (Effects 3/4).
    comboLedger.record(
      actorId: attacker.combatantId,
      teamId: _teamKeyFor(attacker),
      trigger: trigger,
      targetIds: [for (final r in targetResults) r.targetCharacterId],
      statusesApplied: [
        for (final r in targetResults) ...r.statusEffectsApplied,
      ],
      dealtDamage: targetResults.any((r) => r.totalDamageDealt > 0),
    );

    return AbilityUseResult(
      attackerCharacterId: attacker.combatantId,
      triggerId: trigger.id,
      targetResults: targetResults,
      trionRefund: trionRefund,
      reactions: List.of(_pendingReactions),
    );
  }

  /// Arms a [ReactiveEffect] on the appropriate character after an ability
  /// with [ActiveTrigger.armsReactive] resolves. Self/ally-targeted
  /// abilities arm on the target; opponent-targeted abilities arm on the
  /// caster.
  void _armReactiveEffect(
    CharacterBattleState caster,
    ActiveTrigger trigger,
    List<CharacterBattleState> originalTargets,
    Map<String, Object?>? reactiveData,
  ) {
    final kind = trigger.armsReactive!;

    // Deadfall and Death Ledger are opponent-targeted but arm on the
    // TARGET (the enemy), not on the caster; they fire when that enemy
    // acts. All other opponent-targeted reactives arm on the caster.
    final armsOnTarget =
        kind == ReactiveKind.trapOnAction || kind == ReactiveKind.nullifyAoe;

    CharacterBattleState holder;
    if (trigger.targetAffiliation == TargetAffiliation.opponent) {
      holder = armsOnTarget
          ? (originalTargets.isNotEmpty ? originalTargets.first : caster)
          : caster;
    } else {
      holder = originalTargets.isNotEmpty ? originalTargets.first : caster;
    }

    // A trap is laid at a place, in a band. It records where the wielder
    // was standing and how far that ability reaches, so it can later ask
    // whether the enemy walked into it or acted from safely outside. That
    // turns "will they still be in range when this fires" into a real
    // question rather than a formality.
    //
    // How long it stays armed is the ability's own armsReactiveDefaultTurns,
    // untouched here. Those are Phase B first-pass values chosen by eye and
    // are in scope for the SPTV pass (item #3), which prices duration
    // alongside magnitude and target count.
    holder.reactiveEffects.add(ReactiveEffect(
      kind: kind,
      sourceCharacterId: caster.combatantId,
      data: {
        ...?reactiveData,
        _trapBandKey: trigger.rangeTag.name,
        _trapArmedStepKey: caster.position.step,
      },
      remainingTurns: trigger.armsReactiveDefaultTurns,
    ));

    // Puppet Strings: the caster is Exposed while the reactive is armed.
    if (kind == ReactiveKind.redirectToOwnAlly) {
      statusEffectEngine.apply(
        caster,
        'exposed',
        durationOverride: trigger.armsReactiveDefaultTurns,
      );
    }
  }

  /// Ticks down reactive-effect expiry timers on [state]. Called once per
  /// opponent turn (at end of their turn). Expired effects are removed.
  void tickReactiveEffects(CharacterBattleState state) {
    state.reactiveEffects.removeWhere((effect) {
      if (effect.remainingTurns == null) return false;
      effect.remainingTurns = effect.remainingTurns! - 1;
      return effect.remainingTurns! <= 0;
    });
  }

  /// Finalizes [state] for the turn: counts down their status effects
  /// (item #D - see [StatusEffectEngine.tickEndOfTurn]), applies cooldowns
  /// (doubled if FAT was used for 2+ abilities), the resulting Trion
  /// Affinity halving penalty for next turn, and ticks down existing
  /// cooldowns/penalties.
  ///
  /// Returns the status effects that expired here, for the battle log.
  List<StatusEffectInstance> endCharacterTurn(CharacterBattleState state) {
    final expired = statusEffectEngine.tickEndOfTurn(state);
    state.endTurn(fatConfig: fatConfig);
    return expired;
  }

  /// The resonance multiplier applying to [wielder]'s own equipped Black
  /// Trigger, from [wielder]'s [CharacterType] x the Black Trigger's
  /// [BlackTriggerType] (see [ResonanceGrid]). 1.0 (no scaling) if
  /// [wielder] has no Black Trigger equipped. Callers pass this in as
  /// [resolveAbilityUse]'s `damageMultiplier`/`healMultiplier` when
  /// resolving one of the Black Trigger's own active abilities; regular
  /// Triggers are never resonance-scaled.
  double resonanceMultiplierFor(
    CharacterBattleState wielder, {
    ResonanceGrid grid = ResonanceGrid.defaultGrid,
    ResonanceMultipliers multipliers = ResonanceMultipliers.defaults,
  }) {
    final blackTrigger = wielder.character.blackTrigger;
    if (blackTrigger == null) return 1.0;
    final grade = grid.lookup(wielder.character.type, blackTrigger.type);
    // Nullhymn can permanently drop this wielder's grade for the battle
    // (A->B->C->D). Grades run d(0)..a(3), so a downgrade lowers the index,
    // floored at D. The const grid stays intact; the step count is per state.
    final downgraded = ResonanceGrade.values[
        (grade.index - wielder.resonanceDowngradeSteps)
            .clamp(0, ResonanceGrade.values.length - 1)];
    return multipliers.multiplierFor(downgraded);
  }

  /// Scales a Black Trigger active ability's [baseCooldownTurns] by its
  /// wielder's resonance [multiplier]: a stronger resonance (multiplier >
  /// 1) shortens the cooldown, a weaker one (multiplier < 1) lengthens it,
  /// matching the design brief's "could have less cooldowns on its
  /// ability" example. Never negative.
  int resonanceScaledCooldown(int baseCooldownTurns, double multiplier) {
    if (multiplier <= 0) return baseCooldownTurns;
    return (baseCooldownTurns / multiplier).round().clamp(0, 1 << 30);
  }

  /// This turn's timer duration for [team]: the configured base
  /// [TurnTimerConfig.secondsPerTurn] plus every living-or-not team
  /// member's equipped Black Trigger World ability's
  /// `turnTimerSecondsDelta` (the timer is per-team per-turn, so all 3
  /// members' deltas stack). Floored at 1 second. The actual countdown is
  /// a host-app/UI concern; this only computes the duration.
  int effectiveTurnTimerSeconds(
    Team team, {
    TurnTimerConfig config = TurnTimerConfig.defaults,
  }) {
    final delta = team.characters.fold<int>(
      0,
      (sum, c) =>
          sum + (c.blackTrigger?.worldAbility?.turnTimerSecondsDelta ?? 0),
    );
    return (config.secondsPerTurn + delta) < 1
        ? 1
        : config.secondsPerTurn + delta;
  }

  // ---------------------------------------------------------------------------
  // Passive-counter engine (Phase B4)
  // ---------------------------------------------------------------------------

  /// Interdict damage multiplier: if the attacker has an interdict status
  /// and is repeating an ability they used last turn, multiply damage.
  double _interdictDamageMultiplier(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
  ) {
    final cat = StatusEffectCatalog.defaultCatalog;
    var multiplier = 1.0;
    for (final instance in attacker.statusEffects) {
      final def = cat[instance.definitionId];
      if (def.repeatAbilityDamageMultiplier != null &&
          attacker.triggersUsedLastTurn.contains(trigger.id)) {
        multiplier *= def.repeatAbilityDamageMultiplier!;
      }
    }
    return multiplier;
  }

  /// Called after each ability resolves. Notifies passive counter state
  /// machines on both teams (attacker-side and defender-side).
  void notifyAbilityResolved({
    required CharacterBattleState attacker,
    required ActiveTrigger trigger,
    required AbilityUseResult result,
    required List<CharacterBattleState> defenderTeamStates,
    bool isBlackTriggerAbility = false,
  }) {
    final cfg = passiveCounterConfig;
    final anyDamage = result.targetResults.any((r) => r.totalDamageDealt > 0);
    final anyCrit =
        result.targetResults.any((r) => r.attackRolls.any((o) => o.isCriticalHit));

    // --- Attacker-side counters ---

    // Draegor: +1 Enmity when the holder uses an ability.
    final draegor =
        attacker.getPassiveCounter(PassiveCounterKind.draegor);
    if (draegor != null) {
      _draegorOnAbilityUsed(draegor, attacker, cfg);
    }

    // Ironvow: track attack type for sanctioned strike detection.
    final ironvow =
        attacker.getPassiveCounter(PassiveCounterKind.ironvow);
    if (ironvow != null && trigger.targetAffiliation == TargetAffiliation.opponent) {
      ironvow.lastTurnAttackType = trigger.attackType;
    }

    // --- Defender-side counters ---
    // Scan defender team for counter holders.
    if (trigger.targetAffiliation == TargetAffiliation.opponent &&
        defenderTeamStates.isNotEmpty) {
      final allDefenders = [defenderTeamStates.first] +
          defenderTeamStates.first.teammates;

      for (final defender in allDefenders) {
        if (!defender.isAlive) continue;

        // Reckoning: +1 Debt on crit against team OR 2+ cooldown ability.
        final reckoning =
            defender.getPassiveCounter(PassiveCounterKind.reckoning);
        if (reckoning != null && !reckoning.lockedOut) {
          if (anyCrit) {
            _reckoningIncrementDebt(
                reckoning, attacker.combatantId, cfg);
          }
          if (trigger.cooldownTurns >= 2) {
            _reckoningIncrementDebt(
                reckoning, attacker.combatantId, cfg);
          }
        }

        // Nullhymn: +1 Discord when enemy uses BT active against team.
        final nullhymn =
            defender.getPassiveCounter(PassiveCounterKind.nullhymn);
        if (nullhymn != null && isBlackTriggerAbility) {
          nullhymn.counter++;
        }

        // Coldread: track if marked enemy took a damaging action.
        final coldread =
            defender.getPassiveCounter(PassiveCounterKind.coldread);
        if (coldread != null &&
            coldread.pendingResolution &&
            coldread.markedEnemyId == attacker.combatantId &&
            anyDamage) {
          coldread.markedEnemyActedDamaging = true;
        }
      }
    }
  }

  /// Called when a status effect is successfully inflicted on [target].
  /// Increments Nullhymn discord for the holder (deduped per status/turn).
  void notifyStatusInflicted(
    CharacterBattleState target,
    String statusEffectId,
  ) {
    final nullhymn =
        target.getPassiveCounter(PassiveCounterKind.nullhymn);
    if (nullhymn != null &&
        !nullhymn.discordedStatusIdsThisTurn.contains(statusEffectId)) {
      nullhymn.discordedStatusIdsThisTurn.add(statusEffectId);
      nullhymn.counter++;
    }
  }

  /// Start-of-turn passive counter hooks for [activeTeamStates].
  void tickStartOfTurnPassiveCounters(
    List<CharacterBattleState> activeTeamStates,
    List<CharacterBattleState> enemyTeamStates,
  ) {
    for (final state in activeTeamStates) {
      if (!state.isAlive) continue;

      // Draegor: tick Regret remaining turns.
      final draegor =
          state.getPassiveCounter(PassiveCounterKind.draegor);
      if (draegor != null && draegor.regretRemainingTurns > 0) {
        draegor.regretRemainingTurns--;
      }

      // Coldread: mark one enemy if not on cooldown and not pending.
      final coldread =
          state.getPassiveCounter(PassiveCounterKind.coldread);
      if (coldread != null &&
          coldread.cooldownTurns <= 0 &&
          !coldread.pendingResolution) {
        final livingEnemies =
            enemyTeamStates.where((e) => e.isAlive).toList();
        if (livingEnemies.isNotEmpty) {
          final target = livingEnemies[
              combatEngine.diceRoller.random.nextInt(livingEnemies.length)];
          coldread.markedEnemyId = target.combatantId;
          coldread.pendingResolution = true;
          coldread.markedEnemyActedDamaging = false;
        }
      }

      // Ironvow: sanction one attack type at random (not last turn's).
      final ironvow =
          state.getPassiveCounter(PassiveCounterKind.ironvow);
      if (ironvow != null) {
        if (ironvow.sanctionedStrikeCooldown > 0) {
          ironvow.sanctionedStrikeCooldown--;
        }
        final eligible = AttackType.values
            .where((t) => t != ironvow.lastTurnAttackType)
            .toList();
        ironvow.sanctionedType = eligible[
            combatEngine.diceRoller.random.nextInt(eligible.length)];
      }

      // Tick down cooldowns for counters with per-turn cooldowns.
      for (final pc in state.passiveCounters.values) {
        if (pc.cooldownTurns > 0) pc.cooldownTurns--;
      }
    }
  }

  /// End-of-turn passive counter hooks. Called at the end of [activeTeam]'s
  /// turn; [inactiveTeamStates] hold the counters that fire "at end of
  /// opponent turn." [activeTeamDealtDamage] tracks whether the active team
  /// dealt any damage this turn (for Gravehour stall detection).
  void tickEndOfTurnPassiveCounters({
    required List<CharacterBattleState> activeTeamStates,
    required List<CharacterBattleState> inactiveTeamStates,
    required TrionPool activeTeamPool,
    required TrionPool inactiveTeamPool,
    required bool activeTeamDealtDamage,
  }) {
    final cfg = passiveCounterConfig;

    for (final state in inactiveTeamStates) {
      if (!state.isAlive) continue;

      // Draegor: if opponent chained 2+ abilities (FAT) and holder has
      // active Regret, consume Regret for a boost.
      final draegor =
          state.getPassiveCounter(PassiveCounterKind.draegor);
      if (draegor != null && draegor.regretRemainingTurns > 0) {
        final opponentChained = activeTeamStates.any(
            (s) => s.abilitiesUsedThisTurnCount >= cfg.draegorFatChainThreshold);
        if (opponentChained) {
          draegor.regretRemainingTurns = 0;
          if (_canTegBoost(state)) {
            // Real effect: raise the team's TEG by 2 tiers for the duration
            // (the app injected the 2-tier-higher profiles), shifting the
            // roll-advantage tables.
            _activateTegBoost(state, cfg.draegorBoostDurationTurns);
          } else {
            // Exception (team already SS/SSS): double the highest-TA ally's
            // Trion Affinity instead.
            final allies = [state] + state.teammates;
            final livingAllies = allies.where((a) => a.isAlive).toList();
            if (livingAllies.isNotEmpty) {
              livingAllies.sort((a, b) => b
                  .effectiveStats(fatConfig: fatConfig)
                  .trionAffinity
                  .compareTo(
                      a.effectiveStats(fatConfig: fatConfig).trionAffinity));
              livingAllies.first.applyFlatBonus(
                ModifiableStat.trionAffinity,
                livingAllies.first
                    .effectiveStats(fatConfig: fatConfig)
                    .trionAffinity
                    .toDouble(),
                cfg.draegorBoostDurationTurns,
              );
            }
          }
        }
      }

      // Gravehour: if opponent stalled or left any enemy at <=30% HP.
      final gravehour =
          state.getPassiveCounter(PassiveCounterKind.gravehour);
      if (gravehour != null && gravehour.cooldownTurns <= 0) {
        final stalled = !activeTeamDealtDamage;
        final lowHpEnemy = activeTeamStates.any((e) =>
            e.isAlive &&
            e.currentHealth <=
                e.effectiveStats(fatConfig: fatConfig).maxHealth *
                    cfg.gravehourLowHpThreshold);

        if (stalled || lowHpEnemy) {
          _gravehourFinisher(state, activeTeamStates, cfg);
        }
      }

      // Coldread: resolve prediction.
      final coldread =
          state.getPassiveCounter(PassiveCounterKind.coldread);
      if (coldread != null && coldread.pendingResolution) {
        if (coldread.markedEnemyActedDamaging) {
          // Correct read: the reward alternates, Levy first then Seize.
          if (coldread.coldreadNextRewardIsSeize) {
            _coldreadSeize(state, cfg);
          } else {
            final levyAmount = _findCostliestTrionCost(activeTeamStates);
            _applyLevy(activeTeamPool, inactiveTeamPool, levyAmount);
          }
          coldread.coldreadNextRewardIsSeize =
              !coldread.coldreadNextRewardIsSeize;
        } else {
          // Wrong read: dock holder's team Trion gain next turn.
          coldread.trionGainDockedNextTurn = true;
        }
        coldread.pendingResolution = false;
        coldread.markedEnemyId = null;
        coldread.markedEnemyActedDamaging = false;
        coldread.cooldownTurns = cfg.coldreadCooldownTurns;
      }

      // Nullhymn: check discord threshold.
      final nullhymn =
          state.getPassiveCounter(PassiveCounterKind.nullhymn);
      if (nullhymn != null &&
          nullhymn.counter >= cfg.nullhymnDiscordThreshold &&
          nullhymn.chargesUsed < cfg.nullhymnMaxDischarges) {
        _nullhymnDischarge(state, activeTeamStates);
        nullhymn.counter = 0;
        nullhymn.chargesUsed++;
      }

      // Reckoning: check debt threshold.
      final reckoning =
          state.getPassiveCounter(PassiveCounterKind.reckoning);
      if (reckoning != null &&
          !reckoning.lockedOut &&
          reckoning.counter >= cfg.reckoningDebtThreshold) {
        _reckoningDischarge(
            reckoning, activeTeamStates, activeTeamPool, inactiveTeamPool, cfg);
      }

      // Clear per-turn Nullhymn dedup.
      nullhymn?.discordedStatusIdsThisTurn.clear();
    }
  }

  // --- Passive counter helpers ---

  void _draegorOnAbilityUsed(
    PassiveCounterState draegor,
    CharacterBattleState holder,
    PassiveCounterConfig cfg,
  ) {
    // Check team-wide Regret cap.
    final teamRegretTotal = _teamRegretTotal(holder);
    if (teamRegretTotal >= cfg.draegorMaxRegretPerBattle) return;

    draegor.counter++;
    if (draegor.counter >= cfg.draegorEnmityThreshold) {
      draegor.counter = 0;
      draegor.regretRemainingTurns = cfg.draegorRegretDurationTurns;
      draegor.totalRegretGenerated++;
    }
  }

  int _teamRegretTotal(CharacterBattleState holder) {
    var total = 0;
    final all = [holder] + holder.teammates;
    for (final s in all) {
      final d = s.getPassiveCounter(PassiveCounterKind.draegor);
      if (d != null) total += d.totalRegretGenerated;
    }
    return total;
  }

  /// Coldread Seize (the alternate reward to the Levy on a correct read):
  /// grant the whole living squad a flat +N to every roll for a turn. The
  /// roll modifier for each opposed d20 contest is the acting stat itself
  /// (attack vs defense, infliction vs resistance), so a temporary flat
  /// bonus to those four stats is exactly "+N to all their rolls."
  void _coldreadSeize(CharacterBattleState holder, PassiveCounterConfig cfg) {
    final squad = [holder, ...holder.teammates].where((s) => s.isAlive);
    const rollStats = [
      ModifiableStat.attack,
      ModifiableStat.defense,
      ModifiableStat.statusEffectInfliction,
      ModifiableStat.statusEffectResistance,
    ];
    for (final member in squad) {
      for (final stat in rollStats) {
        member.applyFlatBonus(stat, cfg.coldreadSeizeRollBonus.toDouble(),
            cfg.coldreadSeizeDurationTurns);
      }
    }
  }

  void _reckoningIncrementDebt(
    PassiveCounterState reckoning,
    String enemyId,
    PassiveCounterConfig cfg,
  ) {
    reckoning.counter++;
    reckoning.counterByEnemyId[enemyId] =
        (reckoning.counterByEnemyId[enemyId] ?? 0) + 1;
  }

  void _reckoningDischarge(
    PassiveCounterState reckoning,
    List<CharacterBattleState> enemyTeamStates,
    TrionPool enemyPool,
    TrionPool holderPool,
    PassiveCounterConfig cfg,
  ) {
    // Find the enemy who ran up the most Debt.
    String? topEnemyId;
    var topDebt = 0;
    for (final entry in reckoning.counterByEnemyId.entries) {
      if (entry.value > topDebt) {
        topDebt = entry.value;
        topEnemyId = entry.key;
      }
    }

    if (topEnemyId != null) {
      final topEnemy = enemyTeamStates
          .where((s) => s.combatantId == topEnemyId)
          .firstOrNull;
      if (topEnemy != null) {
        // Extend all current cooldowns +1.
        for (final key in topEnemy.cooldowns.keys.toList()) {
          topEnemy.cooldowns[key] =
              (topEnemy.cooldowns[key] ?? 0) + cfg.reckoningCooldownExtension;
        }
        // Force next attack to critical miss.
        statusEffectEngine.apply(topEnemy, 'forced_critical_miss');
      }
    }

    // Levy: steal Trion from enemy pool.
    final levyAmount = _findCostliestTrionCost(enemyTeamStates);
    _applyLevy(enemyPool, holderPool, levyAmount);

    reckoning.counter = 0;
    reckoning.counterByEnemyId.clear();
    reckoning.lockedOut = true;
  }

  void _nullhymnDischarge(
    CharacterBattleState holder,
    List<CharacterBattleState> enemyTeamStates,
  ) {
    // Primary effect: if any living enemy runs a Black Trigger, the
    // most-recently-active one permanently loses a resonance grade
    // (A->B->C->D) for the rest of the battle.
    final btEnemies = enemyTeamStates
        .where((e) => e.isAlive && e.character.blackTrigger != null)
        .toList();
    if (btEnemies.isNotEmpty) {
      btEnemies.sort((a, b) =>
          b.lastBlackTriggerUseOrder.compareTo(a.lastBlackTriggerUseOrder));
      btEnemies.first.resonanceDowngradeSteps++;
      return;
    }

    // Fallback (no enemy Black Trigger): purge all debuffs on the holder's
    // team and reflect the most prolific enemy's debuffs.
    final allies = [holder] + holder.teammates;
    final cat = StatusEffectCatalog.defaultCatalog;

    // Count debuffs by source.
    final debuffCountBySource = <String, int>{};
    final debuffsToReflect = <StatusEffectInstance>[];

    for (final ally in allies) {
      final toRemove = <StatusEffectInstance>[];
      for (final instance in ally.statusEffects) {
        final def = cat[instance.definitionId];
        // Consider anything with negative flat modifiers, DoT, action
        // prevention, or disadvantage as a "debuff."
        final isDebuff = def.preventsActions ||
            def.turnStartDamage != null ||
            def.disadvantageRollTags.isNotEmpty ||
            def.flatStatModifiers.values.any((v) => v < 0) ||
            (def.allDamageTakenMultiplier != null &&
                def.allDamageTakenMultiplier! > 1) ||
            (def.outgoingDamageMultiplier != null &&
                def.outgoingDamageMultiplier! < 1);
        if (isDebuff) {
          toRemove.add(instance);
          if (instance.sourceCharacterId != null) {
            debuffCountBySource[instance.sourceCharacterId!] =
                (debuffCountBySource[instance.sourceCharacterId!] ?? 0) + 1;
            debuffsToReflect.add(instance);
          }
        }
      }
      for (final r in toRemove) {
        ally.statusEffects.remove(r);
      }
    }

    // Reflect onto the enemy who applied the most debuffs.
    if (debuffCountBySource.isNotEmpty) {
      String? topSourceId;
      var topCount = 0;
      for (final entry in debuffCountBySource.entries) {
        if (entry.value > topCount) {
          topCount = entry.value;
          topSourceId = entry.key;
        }
      }
      if (topSourceId != null) {
        final target = enemyTeamStates
            .where((s) => s.combatantId == topSourceId && s.isAlive)
            .firstOrNull;
        if (target != null) {
          for (final debuff in debuffsToReflect) {
            if (debuff.sourceCharacterId == topSourceId) {
              statusEffectEngine.apply(
                target,
                debuff.definitionId,
                sourceCharacterId: holder.combatantId,
                durationOverride: debuff.remainingTurns,
              );
            }
          }
        }
      }
    }
  }

  void _gravehourFinisher(
    CharacterBattleState holder,
    List<CharacterBattleState> enemyTeamStates,
    PassiveCounterConfig cfg,
  ) {
    // Find lowest-HP living enemy.
    final livingEnemies = enemyTeamStates.where((e) => e.isAlive).toList();
    if (livingEnemies.isEmpty) return;
    livingEnemies.sort((a, b) => a.currentHealth.compareTo(b.currentHealth));
    final target = livingEnemies.first;

    // Free, uncounterable finisher.
    _applyDamage(
      target: target,
      baseDamage: cfg.gravehourFinisherFlatDamage,
      damageType: DamageType.force,
      isCriticalHit: false,
      damageSource: holder,
    );

    // Heal prevention on the target (using Cursed status, 2 turns to
    // cover through the opponent's next full turn).
    statusEffectEngine.apply(
      target,
      'cursed',
      sourceCharacterId: holder.combatantId,
      durationOverride: cfg.gravehourHealPreventionDurationTurns,
    );

    // Set Gravehour on cooldown.
    final gravehour =
        holder.getPassiveCounter(PassiveCounterKind.gravehour)!;
    gravehour.cooldownTurns = cfg.gravehourCooldownTurns;

    // Put one of the holder's own abilities on cooldown at random.
    final holderCooldowns = holder.cooldowns;
    final allTriggerIds = holderCooldowns.keys.toList();
    // Pick from abilities NOT on cooldown (or extend one already on cooldown).
    final random = combatEngine.diceRoller.random;
    if (allTriggerIds.isNotEmpty) {
      final pick = allTriggerIds[random.nextInt(allTriggerIds.length)];
      holderCooldowns[pick] = (holderCooldowns[pick] ?? 0) + 1;
    }
  }

  /// The Levy: steal Trion from [fromPool] and add to [toPool], capped
  /// at what [fromPool] actually has.
  void _applyLevy(TrionPool fromPool, TrionPool toPool, int amount) {
    final actual = min(amount, fromPool.current);
    if (actual <= 0) return;
    fromPool.trySpend(actual);
    toPool.gain(actual);
  }

  /// The costliest Trion cost among the abilities [teamStates] used this
  /// turn, which is what a Levy steals.
  ///
  /// Whether the user survived the turn is not asked: the Levy takes what was
  /// spent, and it was spent either way.
  ///
  /// This used to return a flat 20 for any ability at all, and 0 for none,
  /// because the id was the only thing kept about a use and nothing here
  /// could resolve it back to a Trigger. The design document has always said
  /// "steal the Trion from their costliest action", so that was a bug rather
  /// than a first-pass value: `CharacterBattleState` now records the cost as
  /// the ability is used.
  int _findCostliestTrionCost(List<CharacterBattleState> teamStates) {
    var maxCost = 0;
    for (final state in teamStates) {
      maxCost = max(maxCost, state.costliestTrionCostThisTurn);
    }
    return maxCost;
  }

  /// Ironvow Sanctioned Strike check: returns true if [attacker] has an
  /// Ironvow counter and [trigger]'s attack type matches the sanctioned
  /// type, the strike is available, and the cost is affordable. If true,
  /// the strike is consumed and effects applied.
  bool checkSanctionedStrike(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    CharacterBattleState target,
  ) {
    final ironvow =
        attacker.getPassiveCounter(PassiveCounterKind.ironvow);
    if (ironvow == null) return false;
    if (ironvow.sanctionedType != trigger.attackType) return false;
    if (ironvow.sanctionedStrikeCooldown > 0) return false;
    if (ironvow.chargesUsed >= passiveCounterConfig.ironvowMaxSanctionedStrikes) {
      return false;
    }

    // Consume the strike.
    ironvow.chargesUsed++;
    ironvow.sanctionedStrikeCooldown =
        passiveCounterConfig.ironvowStrikeCooldownTurns;

    // Strip one active buff from the target.
    _stripOneBuff(target);

    // Brand target with Interdict.
    statusEffectEngine.apply(
      target,
      'interdict',
      sourceCharacterId: attacker.combatantId,
    );

    // Cost: allies Vulnerable (Exposed) until next turn.
    for (final ally in attacker.teammates) {
      if (!ally.isAlive) continue;
      statusEffectEngine.apply(
        ally,
        'exposed',
        durationOverride: 1,
        sourceCharacterId: attacker.combatantId,
      );
    }

    return true;
  }

  // --- Unique-subtype dispatch (Phase C) ---

  AbilityUseResult _resolveUniqueBehavior({
    required CharacterBattleState attacker,
    required ActiveTrigger trigger,
    required List<CharacterBattleState> targets,
    double damageMultiplier = 1.0,
    double healMultiplier = 1.0,
    Map<String, Object?>? uniqueData,
  }) {
    switch (trigger.uniqueBehavior!) {
      case UniqueBehavior.sharedAgony:
        return _resolveSharedAgony(attacker, trigger, targets);
      case UniqueBehavior.graveBargain:
        return _resolveGraveBargain(attacker, trigger, targets);
      case UniqueBehavior.martyrsEnd:
        return _resolveMartyrsEnd(attacker, trigger, targets);
      case UniqueBehavior.vowOfTheDuel:
        return _resolveVowOfTheDuel(attacker, trigger, targets);
      case UniqueBehavior.sunderArms:
        return _resolveSunderArms(attacker, trigger, targets, uniqueData);
      case UniqueBehavior.curvingShot:
        return _resolveCurvingShot(attacker, trigger, targets);
      case UniqueBehavior.calledShot:
        return _resolveCalledShot(attacker, trigger, targets, uniqueData);
      case UniqueBehavior.mindsEye:
        return _resolveMindsEye(attacker, trigger, targets);
      case UniqueBehavior.forcedChoice:
        return _resolveForcedChoice(attacker, trigger, targets, uniqueData);
      case UniqueBehavior.memoryTheft:
        return _resolveMemoryTheft(attacker, trigger, targets);
      case UniqueBehavior.sensorySwap:
        return _resolveSensorySwap(attacker, trigger, targets, uniqueData);
      case UniqueBehavior.dreadResonance:
        return _resolveDreadResonance(attacker, trigger, targets);
      case UniqueBehavior.isolation:
        return _resolveIsolation(attacker, trigger, targets);
      case UniqueBehavior.illusoryDouble:
        return _resolveIllusoryDouble(attacker, trigger, targets);
      case UniqueBehavior.echoingDoubt:
        return _resolveEchoingDoubt(attacker, trigger, targets);
      case UniqueBehavior.karmicBind:
        return _resolveKarmicBind(attacker, trigger, targets);
      case UniqueBehavior.unmaking:
        return _resolveUnmaking(attacker, trigger, targets);
    }
  }

  AbilityUseResult _emptyResult(String attackerId, String triggerId) {
    return AbilityUseResult(
      attackerCharacterId: attackerId,
      triggerId: triggerId,
      targetResults: const [],
    );
  }

  AbilityUseResult _resolveSharedAgony(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets,
  ) {
    // Auto-target: pick a random living enemy the caster has melee-hit.
    final eligibleTargets = targets
        .where((t) =>
            t.isAlive && attacker.meleeHitEnemyIds.contains(t.combatantId))
        .toList();
    if (eligibleTargets.isEmpty) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    final enemy = eligibleTargets[
        combatEngine.diceRoller.random.nextInt(eligibleTargets.length)];

    final damageRoll = trigger.damage?.roll(combatEngine.diceRoller) ?? 0;

    // Self-damage: full rolled amount, no mitigation (the caster
    // deliberately channels the pain; can kill them).
    final selfDamage = damageRoll;
    final maxHp = attacker.effectiveStats(fatConfig: fatConfig).maxHealth;
    attacker.currentHealth =
        (attacker.currentHealth - selfDamage).clamp(0, maxHp);
    noteHealthChanged(attacker);

    // Enemy damage: rolled amount * linked multiplier (1.2x default),
    // through normal damage pipeline.
    final enemyBaseDamage =
        (damageRoll * uniqueConfig.sharedAgonyLinkedDamageMultiplier).round();
    final healthBefore = enemy.currentHealth;
    _applyDamage(
      target: enemy,
      baseDamage: enemyBaseDamage,
      damageType: trigger.damageType ?? DamageType.slashing,
      isCriticalHit: false,
      damageSource: attacker,
    );
    final enemyDamageDealt = healthBefore - enemy.currentHealth;
    if (enemyDamageDealt > 0) {
      attacker.cumulativeDamageDealt += enemyDamageDealt;
      attacker.lastDamagedTargetId = enemy.combatantId;
    }

    return AbilityUseResult(
      attackerCharacterId: attacker.combatantId,
      triggerId: trigger.id,
      targetResults: [
        TargetHitResult(
          targetCharacterId: enemy.combatantId,
          attackRolls: const [],
          damagePerHit: [enemyDamageDealt],
          damageDetails: const [null],
          totalDamageDealt: enemyDamageDealt,
          statusEffectsApplied: const [],
        ),
      ],
    );
  }

  AbilityUseResult _resolveGraveBargain(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets,
  ) {
    if (targets.isEmpty) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    final target = targets.first;

    // Spend a fraction of current HP (floors at 1 so the caster survives).
    final hpCost =
        (attacker.currentHealth * uniqueConfig.graveBargainHpSpendFraction)
            .round();
    attacker.currentHealth = max(1, attacker.currentHealth - hpCost);

    // Deal the spent HP as unavoidable true damage: no roll, no armor,
    // no defense, no type interactions, no damage prevention.
    final healthBefore = target.currentHealth;
    target.currentHealth = max(0, target.currentHealth - hpCost);
    noteHealthChanged(target);
    final damageDealt = healthBefore - target.currentHealth;

    if (damageDealt > 0) {
      attacker.cumulativeDamageDealt += damageDealt;
      attacker.lastDamagedTargetId = target.combatantId;
    }

    return AbilityUseResult(
      attackerCharacterId: attacker.combatantId,
      triggerId: trigger.id,
      targetResults: [
        TargetHitResult(
          targetCharacterId: target.combatantId,
          attackRolls: const [],
          damagePerHit: [damageDealt],
          damageDetails: const [null],
          totalDamageDealt: damageDealt,
          statusEffectsApplied: const [],
        ),
      ],
    );
  }

  AbilityUseResult _resolveMartyrsEnd(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets,
  ) {
    // Only usable below the HP threshold.
    final maxHp = attacker.effectiveStats(fatConfig: fatConfig).maxHealth;
    if (attacker.currentHealth > maxHp * uniqueConfig.martyrsEndHpThreshold) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }

    // The caster is removed from battle. Uniformly with every other way to
    // reach zero, that opens a Bail Out window: the operator leaving the
    // engagement is what Bail Out is, however they came to leave it.
    attacker.currentHealth = 0;
    noteHealthChanged(attacker);

    // Every living enemy takes massive damage.
    final targetResults = <TargetHitResult>[];
    for (final enemy in targets) {
      if (!enemy.isAlive) continue;
      final healthBefore = enemy.currentHealth;
      _applyDamage(
        target: enemy,
        baseDamage: uniqueConfig.martyrsEndDamage,
        damageType: DamageType.force,
        isCriticalHit: false,
        damageSource: attacker,
      );
      final damageDealt = healthBefore - enemy.currentHealth;
      targetResults.add(TargetHitResult(
        targetCharacterId: enemy.combatantId,
        attackRolls: const [],
        damagePerHit: [damageDealt],
        damageDetails: const [null],
        totalDamageDealt: damageDealt,
        statusEffectsApplied: const [],
      ));
    }

    return AbilityUseResult(
      attackerCharacterId: attacker.combatantId,
      triggerId: trigger.id,
      targetResults: targetResults,
    );
  }

  AbilityUseResult _resolveVowOfTheDuel(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets,
  ) {
    if (targets.isEmpty) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    final target = targets.first;

    // Bind to the target: 2x outgoing damage + healing prevention come
    // from the vow_of_the_duel status effect; targeting restriction is
    // enforced by canTarget via duelTargetId.
    attacker.duelTargetId = target.combatantId;
    statusEffectEngine.apply(
      attacker,
      'vow_of_the_duel',
      sourceCharacterId: attacker.combatantId,
    );

    return AbilityUseResult(
      attackerCharacterId: attacker.combatantId,
      triggerId: trigger.id,
      targetResults: [
        TargetHitResult(
          targetCharacterId: target.combatantId,
          attackRolls: const [],
          damagePerHit: const [0],
          damageDetails: const [null],
          totalDamageDealt: 0,
          statusEffectsApplied: const ['vow_of_the_duel'],
        ),
      ],
    );
  }

  /// Checks whether the Vow of the Duel status has expired on [caster]
  /// and, if the bound enemy is still alive, stuns the caster. Call this
  /// after status-effect ticking each turn.
  void checkVowOfTheDuelExpiry(
    CharacterBattleState caster,
    List<CharacterBattleState> enemyStates,
  ) {
    if (caster.duelTargetId == null) return;
    final hasVow =
        caster.statusEffects.any((i) => i.definitionId == 'vow_of_the_duel');
    if (hasVow) return;

    // The vow has expired. Check if the duel target is still alive.
    final duelTarget = enemyStates
        .where((s) => s.combatantId == caster.duelTargetId)
        .firstOrNull;
    if (duelTarget != null && duelTarget.isAlive) {
      _applyStun(caster, StatusEffectMagnitudes.defaults.vowOfTheDuelStunDurationTurns);
    }
    caster.duelTargetId = null;
  }

  AbilityUseResult _resolveSunderArms(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets, [
    Map<String, Object?>? uniqueData,
  ]) {
    if (targets.isEmpty) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    final target = targets.first;

    // Standard attack roll.
    final stats = attacker.effectiveStats(fatConfig: fatConfig);
    final bonuses = teamSpiritCurve.bonusesFor(stats.teamSpirit);
    final baseContext = _attackRollContextFor(attacker, trigger);
    final advantageContext = _advantageContextAgainst(attacker, target);
    final attackerContext = _mergedContext(baseContext, advantageContext);

    // TEG Effects 1/2/5 on the unique attack roll (same as the main path).
    _applyTegOffenseAdvantage(attackerContext, attacker);
    final tegDefenderContext = RollContext();
    _applyTegDefenseAdvantage(tegDefenderContext, target);

    final outcome = combatEngine.resolveAttackRoll(
      attackerAttack: stats.attack,
      defenderDefense: target.effectiveStats(fatConfig: fatConfig).defense,
      attackerCriticalChancePercent:
          stats.criticalChance + bonuses.criticalChanceBonus,
      attackerContext: attackerContext,
      defenderContext: tegDefenderContext,
      maxCritThreshold: _tegFor(attacker).maxCritThreshold,
    );

    var damageDealt = 0;
    if (outcome.isCriticalMiss) {
      combatEngine.applyCriticalMissPenalty(attacker);
    } else if (outcome.isHit) {
      // Deal damage.
      if (trigger.damageType != null) {
        final damageRoll = trigger.damage?.rollDetailed(combatEngine.diceRoller);
        final preCritMultiplier =
            (1 + bonuses.singleTargetDamageBonus) *
            attacker.outgoingDamageMultiplier();
        final adjustedBase = ((damageRoll?.total ?? 0) * preCritMultiplier)
            .round();
        final diceOnly = damageRoll?.rawRolls.fold<int>(0, (a, b) => a + b) ?? 0;
        final healthBefore = target.currentHealth;
        _applyDamage(
          target: target,
          baseDamage: adjustedBase,
          damageType: trigger.damageType!,
          isCriticalHit: outcome.isCriticalHit,
          damageSource: attacker,
          criticalDiceComponent: (diceOnly * preCritMultiplier).round(),
        );
        damageDealt = healthBefore - target.currentHealth;
        if (damageDealt > 0) {
          attacker.cumulativeDamageDealt += damageDealt;
          attacker.lastDamagedTargetId = target.combatantId;
          attacker.meleeHitEnemyIds.add(target.combatantId);
        }
      }

      // Destroy a random equipped trigger on the target.
      final targetEligible = target.equippedTriggerIds
          .where((id) => !target.destroyedTriggerIds.contains(id))
          .toList();
      if (targetEligible.isNotEmpty) {
        final pick = targetEligible[
            combatEngine.diceRoller.random.nextInt(targetEligible.length)];
        target.destroyedTriggerIds.add(pick);
      }

      // Caster sacrifices one of their own (caller specifies via uniqueData).
      final casterSacrificeId =
          uniqueData?['casterSacrificeTriggerId'] as String?;
      if (casterSacrificeId != null) {
        attacker.destroyedTriggerIds.add(casterSacrificeId);
      } else {
        // Fallback: random from caster's own equipped triggers.
        final casterEligible = attacker.equippedTriggerIds
            .where((id) => !attacker.destroyedTriggerIds.contains(id))
            .toList();
        if (casterEligible.isNotEmpty) {
          final pick = casterEligible[
              combatEngine.diceRoller.random.nextInt(casterEligible.length)];
          attacker.destroyedTriggerIds.add(pick);
        }
      }
    }

    return AbilityUseResult(
      attackerCharacterId: attacker.combatantId,
      triggerId: trigger.id,
      targetResults: [
        TargetHitResult(
          targetCharacterId: target.combatantId,
          attackRolls: [outcome],
          damagePerHit: [damageDealt],
          damageDetails: const [null],
          totalDamageDealt: damageDealt,
          statusEffectsApplied: const [],
        ),
      ],
    );
  }

  AbilityUseResult _resolveCurvingShot(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets,
  ) {
    if (targets.isEmpty) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    final target = targets.first;

    // Ignore the first ward/dodge/counter the target has standing: consume
    // it without letting it fire, so the shot bends around it.
    if (target.reactiveEffects.isNotEmpty) {
      target.reactiveEffects.removeAt(0);
    }

    // Always resolves: a guaranteed hit that skips the reactive-remap and
    // the to-hit contest entirely (no dodge, no reflect, no negate).
    var damageDealt = 0;
    if (trigger.damageType != null) {
      final stats = attacker.effectiveStats(fatConfig: fatConfig);
      final bonuses = teamSpiritCurve.bonusesFor(stats.teamSpirit);
      final roll = trigger.damage?.roll(combatEngine.diceRoller) ?? 0;
      final preCritMultiplier = (1 + bonuses.singleTargetDamageBonus) *
          attacker.outgoingDamageMultiplier();
      final base = (roll * preCritMultiplier).round();
      final healthBefore = target.currentHealth;
      _applyDamage(
        target: target,
        baseDamage: base,
        damageType: trigger.damageType!,
        isCriticalHit: false,
        damageSource: attacker,
      );
      damageDealt = healthBefore - target.currentHealth;
      if (damageDealt > 0) {
        attacker.cumulativeDamageDealt += damageDealt;
        attacker.lastDamagedTargetId = target.combatantId;
      }
    }

    // Riders resolve unconditionally too, since the shot always lands.
    final appliedIds = <String>[];
    final stats = attacker.effectiveStats(fatConfig: fatConfig);
    // TEG Effect 1 (offense) on the causer's infliction rolls. Fresh context
    // so non-TEG behavior is unchanged (this site passed none before).
    final tegCauserContext = RollContext();
    _applyTegOffenseAdvantage(tegCauserContext, attacker);
    for (final application in trigger.inflictedStatusEffects) {
      // Granted, not inflicted, when it lands on your own side: no contest.
      final contested = trigger.targetAffiliation == TargetAffiliation.opponent;
      final tegResistContext = RollContext();
      _applyTegDefenseAdvantage(tegResistContext, target); // Effect 2
      final inflictionOutcome = contested
          ? statusEffectEngine.resolveInfliction(
              causerInfliction: stats.statusEffectInfliction,
              targetResistance: target
                  .effectiveStats(fatConfig: fatConfig)
                  .statusEffectResistance,
              causerRollContext: tegCauserContext,
              targetRollContext: tegResistContext,
            )
          : null;
      if (!contested || inflictionOutcome!.applies) {
        final applied = statusEffectEngine.apply(
          target,
          application.statusEffectId,
          sourceCharacterId: attacker.combatantId,
          durationOverride: application.durationTurnsOverride,
        );
        if (applied) appliedIds.add(application.statusEffectId);
      }
    }

    return AbilityUseResult(
      attackerCharacterId: attacker.combatantId,
      triggerId: trigger.id,
      targetResults: [
        TargetHitResult(
          targetCharacterId: target.combatantId,
          attackRolls: const [],
          damagePerHit: [damageDealt],
          damageDetails: const [null],
          totalDamageDealt: damageDealt,
          statusEffectsApplied: appliedIds,
        ),
      ],
    );
  }

  AbilityUseResult _resolveCalledShot(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets, [
    Map<String, Object?>? uniqueData,
  ]) {
    if (targets.isEmpty) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    final target = targets.first;

    // The declared stat to zero (caller picks it); defaults to Attack when
    // the caller doesn't declare one.
    final declared = uniqueData?['calledShotStat'];
    final zeroedStat =
        declared is ModifiableStat ? declared : ModifiableStat.attack;

    // No damage: zero the named stat for the effect's duration via
    // data-driven zeroing (see CharacterBattleState.effectiveStats).
    statusEffectEngine.apply(
      target,
      'called_shot_stat_zero',
      sourceCharacterId: attacker.combatantId,
      instanceData: {'zeroedStat': zeroedStat},
    );

    return AbilityUseResult(
      attackerCharacterId: attacker.combatantId,
      triggerId: trigger.id,
      targetResults: [
        TargetHitResult(
          targetCharacterId: target.combatantId,
          attackRolls: const [],
          damagePerHit: const [0],
          damageDetails: const [null],
          totalDamageDealt: 0,
          statusEffectsApplied: const ['called_shot_stat_zero'],
        ),
      ],
    );
  }

  /// A no-damage, single-target unique result carrying the status ids that
  /// were applied to [target].
  AbilityUseResult _singleStatusResult(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    CharacterBattleState target,
    List<String> appliedStatusIds,
  ) {
    return AbilityUseResult(
      attackerCharacterId: attacker.combatantId,
      triggerId: trigger.id,
      targetResults: [
        TargetHitResult(
          targetCharacterId: target.combatantId,
          attackRolls: const [],
          damagePerHit: const [0],
          damageDetails: const [null],
          totalDamageDealt: 0,
          statusEffectsApplied: appliedStatusIds,
        ),
      ],
    );
  }

  AbilityUseResult _resolveMindsEye(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets,
  ) {
    if (targets.isEmpty) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    final target = targets.first;
    // Cannot be used on the caster.
    if (target.combatantId == attacker.combatantId) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    attacker.revealedEnemyIds.add(target.combatantId);
    statusEffectEngine.apply(
      target,
      'minds_eye_reveal',
      sourceCharacterId: attacker.combatantId,
    );
    return _singleStatusResult(
        attacker, trigger, target, const ['minds_eye_reveal']);
  }

  AbilityUseResult _resolveForcedChoice(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets, [
    Map<String, Object?>? uniqueData,
  ]) {
    if (targets.isEmpty) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    final target = targets.first;
    final mode = uniqueData?['forcedChoiceMode'] as String? ?? 'cheapest';
    final data = <String, Object?>{'forcedChoiceMode': mode};

    // If the caller supplies the target's equipped active Triggers, resolve
    // the one allowed ability now (cheapest or priciest by Trion cost) and
    // whitelist it so canUseAbility enforces the restriction next turn.
    final equipped = uniqueData?['targetEquippedTriggers'];
    if (equipped is List<ActiveTrigger> && equipped.isNotEmpty) {
      final sorted = [...equipped]
        ..sort((a, b) => a.trionCost.compareTo(b.trionCost));
      final allowed = mode == 'priciest' ? sorted.last : sorted.first;
      data['onlyAllowedTriggerId'] = allowed.id;
    }

    statusEffectEngine.apply(
      target,
      'forced_choice',
      sourceCharacterId: attacker.combatantId,
      instanceData: data,
    );
    return _singleStatusResult(
        attacker, trigger, target, const ['forced_choice']);
  }

  AbilityUseResult _resolveMemoryTheft(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets,
  ) {
    if (targets.isEmpty) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    final target = targets.first;
    // Copy the target's last-used ability; the caller offers it to the
    // caster for one cast next turn (occupying Memory Theft's own slot).
    attacker.copiedTriggerId = target.lastUsedTriggerId;
    return _singleStatusResult(attacker, trigger, target, const []);
  }

  AbilityUseResult _resolveSensorySwap(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets, [
    Map<String, Object?>? uniqueData,
  ]) {
    // Needs two characters: move one active status from the first to the
    // second (enemy to enemy, or self to enemy).
    if (targets.length < 2) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    final source = targets[0];
    final dest = targets[1];
    final statusId = uniqueData?['sensorySwapStatusId'] as String?;
    final idx = statusId != null
        ? source.statusEffects
            .indexWhere((i) => i.definitionId == statusId)
        : (source.statusEffects.isNotEmpty ? 0 : -1);
    if (idx < 0) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    // Move the live instance so remaining turns / source are preserved.
    final moved = source.statusEffects.removeAt(idx);
    dest.statusEffects.add(moved);
    return _singleStatusResult(
        attacker, trigger, dest, [moved.definitionId]);
  }

  AbilityUseResult _resolveDreadResonance(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets,
  ) {
    if (targets.isEmpty) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    final target = targets.first;
    // Damage scales with the total damage the target has dealt this battle.
    final scaled = (target.cumulativeDamageDealt *
            uniqueConfig.dreadResonanceDamagePerCumulativeDamage)
        .round();
    final base = scaled < uniqueConfig.dreadResonanceMinDamage
        ? uniqueConfig.dreadResonanceMinDamage
        : scaled;
    final healthBefore = target.currentHealth;
    _applyDamage(
      target: target,
      baseDamage: base,
      damageType: trigger.damageType ?? DamageType.force,
      isCriticalHit: false,
      damageSource: attacker,
    );
    final dealt = healthBefore - target.currentHealth;
    if (dealt > 0) {
      attacker.cumulativeDamageDealt += dealt;
      attacker.lastDamagedTargetId = target.combatantId;
    }
    return AbilityUseResult(
      attackerCharacterId: attacker.combatantId,
      triggerId: trigger.id,
      targetResults: [
        TargetHitResult(
          targetCharacterId: target.combatantId,
          attackRolls: const [],
          damagePerHit: [dealt],
          damageDetails: const [null],
          totalDamageDealt: dealt,
          statusEffectsApplied: const [],
        ),
      ],
    );
  }

  AbilityUseResult _resolveIsolation(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets,
  ) {
    if (targets.isEmpty) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    final target = targets.first;
    statusEffectEngine.apply(
      target,
      'isolation',
      sourceCharacterId: attacker.combatantId,
    );
    return _singleStatusResult(attacker, trigger, target, const ['isolation']);
  }

  AbilityUseResult _resolveIllusoryDouble(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets,
  ) {
    if (targets.isEmpty) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    // Needs an available charge (starts at 1, +1 per ally defeated).
    if (attacker.illusoryDoubleCharges <= 0) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    attacker.illusoryDoubleCharges -= 1;
    // Target self or an ally: make them untargetable for the opponent's
    // next turn.
    final target = targets.first;
    statusEffectEngine.apply(
      target,
      'untargetable',
      sourceCharacterId: attacker.combatantId,
    );
    return _singleStatusResult(
        attacker, trigger, target, const ['untargetable']);
  }

  AbilityUseResult _resolveEchoingDoubt(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets,
  ) {
    if (targets.isEmpty) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    final target = targets.first;
    // Force the target's next attack to whiff; the backlash + Silence fire
    // when that whiff is consumed (see _consumeEchoingDoubt).
    statusEffectEngine.apply(
      target,
      'echoing_doubt',
      sourceCharacterId: attacker.combatantId,
    );
    return _singleStatusResult(
        attacker, trigger, target, const ['echoing_doubt']);
  }

  /// Consumes an active Echoing Doubt on [attacker] when they use an
  /// offensive ability: removes the forced-miss status, deals flat backlash
  /// damage, and Silences them.
  void _consumeEchoingDoubt(CharacterBattleState attacker) {
    attacker.statusEffects.removeWhere((i) => i.definitionId == 'echoing_doubt');
    _applyDamage(
      target: attacker,
      baseDamage: uniqueConfig.echoingDoubtBacklashDamage,
      damageType: DamageType.force,
      isCriticalHit: false,
    );
    statusEffectEngine.apply(
      attacker,
      'silenced',
      sourceCharacterId: attacker.combatantId,
    );
  }

  AbilityUseResult _resolveKarmicBind(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets,
  ) {
    if (targets.isEmpty) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    final target = targets.first;
    // Both link fractions scale with the caster's Team Spirit: about 25% at
    // TS 0 up to about 60% at TS 100.
    final ts = attacker.effectiveStats(fatConfig: fatConfig).teamSpirit;
    final t = (ts / 100).clamp(0.0, 1.0);
    final fraction = uniqueConfig.karmicBindLowTsFraction +
        t *
            (uniqueConfig.karmicBindHighTsFraction -
                uniqueConfig.karmicBindLowTsFraction);

    attacker.karmicBindTargetId = target.combatantId;
    // The live damage/heal propagation across the 3-turn link needs a
    // battle-wide character registry (TurnEngine has no cross-team lookup);
    // it is a Battle-layer hook, so here we record the link and fraction on
    // both partners for that layer to read (consistent with the passive
    // counters' deferred cross-team effects).
    statusEffectEngine.apply(
      target,
      'karmic_bind',
      sourceCharacterId: attacker.combatantId,
      instanceData: {
        'karmicBindFraction': fraction,
        'partnerId': attacker.combatantId,
      },
    );
    statusEffectEngine.apply(
      attacker,
      'karmic_bind',
      sourceCharacterId: attacker.combatantId,
      instanceData: {
        'karmicBindFraction': fraction,
        'partnerId': target.combatantId,
      },
    );
    return _singleStatusResult(
        attacker, trigger, target, const ['karmic_bind']);
  }

  /// Buff status id -> its debuff equivalent, for Unmaking's inversion.
  static const Map<String, String> _buffToDebuffInversion = {
    'empowered': 'weakened',
    'guarded': 'exposed',
    'inspired': 'fatigued',
    'hastened': 'chilled',
    'prepared': 'reeling',
    'braced': 'slowed',
    'overcharged': 'choked',
    'warded': 'hexed',
    'focused': 'poisoned',
    'regenerating': 'bleeding',
  };

  AbilityUseResult _resolveUnmaking(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets,
  ) {
    if (targets.isEmpty) {
      return _emptyResult(attacker.combatantId, trigger.id);
    }
    final target = targets.first;

    // Collect the invertible buffs first (avoid mutating while iterating).
    final toInvert = <StatusEffectInstance>[];
    for (final inst in target.statusEffects) {
      if (_buffToDebuffInversion.containsKey(inst.definitionId)) {
        toInvert.add(inst);
      }
    }

    final inverted = <String>[];
    for (final inst in toInvert) {
      final debuffId = _buffToDebuffInversion[inst.definitionId]!;
      final turns = inst.remainingTurns;
      target.statusEffects.remove(inst);
      final applied = statusEffectEngine.apply(
        target,
        debuffId,
        sourceCharacterId: attacker.combatantId,
        durationOverride: turns,
      );
      if (applied) inverted.add(debuffId);
    }

    return _singleStatusResult(attacker, trigger, target, inverted);
  }

  void _stripOneBuff(CharacterBattleState target) {
    final cat = StatusEffectCatalog.defaultCatalog;
    for (var i = 0; i < target.statusEffects.length; i++) {
      final def = cat[target.statusEffects[i].definitionId];
      final isBuff = def.flatStatModifiers.values.any((v) => v > 0) ||
          def.advantageRollTags.isNotEmpty ||
          (def.allDamageTakenMultiplier != null &&
              def.allDamageTakenMultiplier! < 1) ||
          (def.outgoingDamageMultiplier != null &&
              def.outgoingDamageMultiplier! > 1);
      if (isBuff) {
        target.statusEffects.removeAt(i);
        return;
      }
    }
  }
}

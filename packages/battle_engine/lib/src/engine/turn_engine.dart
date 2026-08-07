import 'dart:math';

import '../constants.dart';
import '../models/character_type.dart';
import '../models/damage_type.dart';
import '../models/passive_counter.dart';
import '../models/reactive_effect.dart';
import '../models/resonance.dart';
import '../models/combo.dart';
import '../models/status_effect.dart';
import '../models/status_effect_catalog.dart';
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

/// The full damage-formula trail behind one damaging hit: the trigger's
/// own dice roll, the combined pre-critical multiplier applied to it
/// (Team Spirit's damage bonus, any perk/status outgoing multiplier), and
/// the resulting [DamageBreakdown] (crit doubling -> Armor -> damage-type
/// multipliers). This is what actually answers "how did this attack deal
/// this much damage" - the attack/defense roll shown alongside it only
/// ever decided hit/miss/crit, never the damage amount itself.
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

  const TargetHitResult({
    required this.targetCharacterId,
    required this.attackRolls,
    required this.damagePerHit,
    required this.damageDetails,
    required this.totalDamageDealt,
    required this.statusEffectsApplied,
  });
}

/// Outcome of a single ability use: one [TargetHitResult] per target
/// actually rolled against.
class AbilityUseResult {
  final String attackerCharacterId;
  final String triggerId;
  final List<TargetHitResult> targetResults;

  const AbilityUseResult({
    required this.attackerCharacterId,
    required this.triggerId,
    required this.targetResults,
  });
}

class _SingleHitResult {
  final AttackRollOutcome outcome;
  final int damage;
  final HitDamageDetail? damageDetail;
  final List<String> appliedStatusEffectIds;
  _SingleHitResult(
    this.outcome,
    this.damage,
    this.damageDetail,
    this.appliedStatusEffectIds,
  );
}

/// Orchestrates a single turn: team Trion gain, per-character status
/// ticking, Full Arms Trigger rolling, ability-use bookkeeping, ability
/// resolution, and end-of-turn cleanup. AI decision-making (which ability
/// to use, who to target) is deliberately left to the caller (e.g. a
/// future rule-based AI module or story-triggered scripted battle) - this
/// engine only answers "is this legal / what does this cost / what's the
/// result", not "what should happen".
class TurnEngine {
  final TrionGainEngine trionGainEngine;
  final FatEngine fatEngine;
  final CombatEngine combatEngine;
  final StatusEffectEngine statusEffectEngine;
  final TeamSpiritCurve teamSpiritCurve;
  final FatConfig fatConfig;
  final PassiveCounterConfig passiveCounterConfig;
  final UniqueConfig uniqueConfig;

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

  TegRollProfile _tegFor(CharacterBattleState c) =>
      tegProfiles[c.character.id] ?? TegRollProfile.none;

  /// A stable per-team key for the ledger: the sorted character ids of the
  /// actor plus its teammates. Same for every member of a team, unique per
  /// team in a battle, so the recognizer's same-team filter works without
  /// the engine needing an explicit team id.
  String _teamKeyFor(CharacterBattleState c) {
    final ids = <String>[
      c.character.id,
      for (final t in c.teammates) t.character.id,
    ]..sort();
    return ids.join('|');
  }

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
    final probe = ComboLedgerEntry(
      actorId: attacker.character.id,
      teamId: _teamKeyFor(attacker),
      triggerId: trigger.id,
      originTag: trigger.originTag,
      attackType: trigger.attackType,
      attackSubtype: trigger.attackSubtype,
      targetAffiliation: trigger.targetAffiliation,
      targetIds: [target.character.id],
      statusesApplied: const [],
      dealtDamage: false,
      sequence: 1 << 30, // above any recorded entry; excluded from priors
    );
    final combo = recognizer
        .best(comboLedger.contextFor(probe, targetState: target));
    if (combo == null) return;
    final chance =
        (combo.strength * comboAdvantagePercentPerStrength).clamp(0, 20);
    if (chance > 0 && combatEngine.diceRoller.rollPercent() <= chance) {
      ctx.addAdvantage('teg_combo');
    }
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
  TrionGainResult resolveTeamTrionGain(
    Team team,
    Map<String, CharacterBattleState> states, {
    double modifier = 0,
    bool forceLowestTier = false,
  }) {
    if (forceLowestTier) {
      final result =
          TrionGainResult(TrionTier.low, trionGainEngine.config.lowAmount);
      team.trionPool.gain(result.amount);
      return result;
    }

    final living =
        team.characters.map((c) => states[c.id]!).where((s) => s.isAlive);

    final sum = living.fold<int>(
        0,
        (total, s) =>
            total + s.effectiveStats(fatConfig: fatConfig).trionAffinity);

    // Haru-style "Battery" perk: a living character can grant their whole
    // team a positive modifier on this roll.
    final perkModifier = living.fold<double>(
        0,
        (total, s) =>
            total + (s.character.perk?.teamTrionGainModifierWhileAlive ?? 0));

    final result = trionGainEngine.rollTier(
        sumLivingTrionAffinity: sum, modifier: modifier + perkModifier);
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

    for (final drain in result.trionDrainEvents) {
      causerTrionPools?[drain.causerCharacterId]?.gain(drain.amount);
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
    // Yuki-style "Devoted Aid" perk: a bonus to all healing received,
    // regardless of source (including a drain-style Trigger that heals
    // its user off someone else's health).
    final perkBonus = recipient.character.perk?.incomingHealBonusPercent ?? 0;
    return (baseAmount * (1 + bonus + perkBonus)).round();
  }

  /// Resolves damage against [target] and applies it to their health,
  /// honoring a World ability's "survive lethal damage once" charge: if
  /// this hit would reduce health to 0 while current health is above 1,
  /// and the charge is still available, health is clamped to 1 instead
  /// and the charge is consumed.
  ///
  /// Returns the step-by-step breakdown behind the pre-perk/pre-clamp
  /// damage number (see [DamageBreakdown]) - a UI showing "why was the
  /// damage this number" reads this rather than just the health delta,
  /// since Bastian's Absorb perk and the survive-lethal clamp below can
  /// still adjust the actual health lost after this math runs.
  DamageBreakdown _applyDamage({
    required CharacterBattleState target,
    required int baseDamage,
    required DamageType damageType,
    required bool isCriticalHit,
    CharacterBattleState? damageSource,
  }) {
    final healthBeforeDamage = target.currentHealth;
    final breakdown = combatEngine.resolveDamageBreakdown(
      baseDamage: baseDamage,
      damageType: damageType,
      isCriticalHit: isCriticalHit,
      target: target,
    );
    var damage = breakdown.finalDamage;

    // Bastian-style "Absorb" perk: the first damage instance of the
    // battle is reduced further, on top of any other mitigation.
    final reduction =
        target.character.perk?.firstDamageInstanceReductionPercent;
    if (reduction != null && !target.perkChargeUsed) {
      damage = (damage * (1 - reduction)).round();
      target.consumePerkChargeIfAvailable();
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

    // Karmic Bind (Punish): a fraction of any damage this character takes
    // is dealt to the enemy they are bound to.
    _propagateKarmicBind(target, healthBeforeDamage - target.currentHealth);
    return breakdown;
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
      if (instance.definitionId == 'karmic_bind') {
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
      // Forced Choice: a status may whitelist exactly one usable ability
      // (the caller-declared cheapest/priciest); everything else is locked.
      final onlyAllowed = instance.data['onlyAllowedTriggerId'];
      if (onlyAllowed is String && trigger.id != onlyAllowed) return false;
      final def = cat[instance.definitionId];
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
    if (trigger.rangeTag != RangeTag.ranged) return trigger.targetCount;
    if (attacker.character.perk?.immuneToTargetCountReduction == true) {
      return trigger.targetCount;
    }
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    final blinded = attacker.statusEffects
        .any((i) => cat[i.definitionId].rangedTargetsReducedByOne);
    if (!blinded) return trigger.targetCount;
    return trigger.targetCount > 1 ? trigger.targetCount - 1 : 1;
  }

  /// Whether [attacker] may target [target] at all right now: false if
  /// [attacker] is Charmed by [target] (a charmed character cannot target
  /// their own charmer - the restriction lives on the charmed character,
  /// so this checks [attacker]'s own active effects, not [target]'s).
  /// Callers (AI/UI) should consult this before building a target list;
  /// [resolveAbilityUse] also defensively filters against it.
  bool canTarget(CharacterBattleState attacker, CharacterBattleState target,
      {StatusEffectCatalog? catalog}) {
    final cat = catalog ?? StatusEffectCatalog.defaultCatalog;
    for (final instance in attacker.statusEffects) {
      final def = cat[instance.definitionId];
      if (def.cannotTargetSource &&
          instance.sourceCharacterId == target.character.id) {
        return false;
      }
    }
    // Vow of the Duel: can only target the bound enemy (opponents only).
    if (attacker.duelTargetId != null) {
      final isOpponent =
          !identical(attacker, target) && !attacker.teammates.contains(target);
      if (isOpponent && target.character.id != attacker.duelTargetId) {
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
          instance.sourceCharacterId == attacker.character.id) {
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
    if (trigger.rangeTag == RangeTag.ranged) {
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

  /// Sable-style "Guardian's Instinct" perk: if [target] has a living
  /// teammate with an unused redirect charge, the attack is rerouted onto
  /// that teammate instead, consuming their charge. Returns [target]
  /// unchanged if no redirect applies.
  CharacterBattleState _applyGuardianRedirect(CharacterBattleState target) {
    for (final teammate in target.teammates) {
      if (identical(teammate, target)) continue;
      if (!teammate.isAlive) continue;
      if (teammate.character.perk?.canRedirectAllyAttackOncePerBattle != true) {
        continue;
      }
      if (teammate.perkChargeUsed) continue;
      teammate.consumePerkChargeIfAvailable();
      return teammate;
    }
    return target;
  }

  /// The Phase-4 reactive-stack remap: before a hit resolves against
  /// [target], the target's standing reactive effects (combat v2 counters)
  /// get a chance to reroute, negate, or modify it. Dispatches on
  /// [ReactiveKind] in priority order. Falls through to the perk-based
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
  /// standard Twin Fang Strike damage (2d6+37 slashing).
  void _resolveCounterHit(
    CharacterBattleState attacker,
    CharacterBattleState target,
  ) {
    final counterDamageRoll =
        const DiceExpression(2, 6, flatBonus: 37).roll(combatEngine.diceRoller);
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
    final key = target.character.id;
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
  bool _checkAttackerReactives(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
  ) {
    // Deadfall: if the attacker has trapOnAction and uses a damaging ability.
    if (trigger.damageType != null) {
      final trapIndex = attacker.reactiveEffects
          .indexWhere((r) => r.kind == ReactiveKind.trapOnAction);
      if (trapIndex >= 0) {
        attacker.reactiveEffects.removeAt(trapIndex);
        final trapDamage = const DiceExpression(2, 8, flatBonus: 25)
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

    // Death Ledger: if the attacker has nullifyAoe and uses an AoE.
    if (trigger.attackSubtype == AttackSubtype.aoe) {
      final ledgerIndex = attacker.reactiveEffects
          .indexWhere((r) => r.kind == ReactiveKind.nullifyAoe);
      if (ledgerIndex >= 0) {
        attacker.reactiveEffects.removeAt(ledgerIndex);
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

  /// Combined outgoing-damage multiplier from [attacker]'s perk (Rurik's
  /// low-health scaling, Dross's AOE-vs-debuffed bonus, Nadia's
  /// stacking-per-extra-FAT-use bonus). 1.0 if [attacker] has no perk or
  /// none of its fields apply to this hit.
  double _perkOutgoingDamageMultiplier(
    CharacterBattleState attacker,
    CharacterBattleState target,
    ActiveTrigger trigger,
  ) {
    final perk = attacker.character.perk;
    if (perk == null) return 1.0;
    var multiplier = 1.0;

    final lowHealthBonus = perk.maxDamageBonusPercentAtZeroHealth;
    if (lowHealthBonus != null) {
      final maxHealth = attacker.effectiveStats(fatConfig: fatConfig).maxHealth;
      final missingFraction =
          maxHealth <= 0 ? 0.0 : 1 - (attacker.currentHealth / maxHealth);
      multiplier += lowHealthBonus * missingFraction.clamp(0.0, 1.0);
    }

    final aoeBonus = perk.aoeDamageBonusPercentVsDebuffedTarget;
    if (aoeBonus != null &&
        trigger.attackSubtype == AttackSubtype.aoe &&
        target.statusEffects.isNotEmpty) {
      multiplier += aoeBonus;
    }

    final chainBonus = perk.perExtraAbilityDamageBonusPercent;
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
  AbilityUseResult resolveAbilityUse({
    required CharacterBattleState attacker,
    required ActiveTrigger trigger,
    required List<CharacterBattleState> targets,
    double damageMultiplier = 1.0,
    double healMultiplier = 1.0,
    Map<String, Object?>? reactiveData,
    Map<String, Object?>? statusEffectData,
    Map<String, Object?>? uniqueData,
  }) {
    // Attacker-side reactive check: Deadfall/Death Ledger can counter the
    // ability entirely before it resolves.
    if (_checkAttackerReactives(attacker, trigger)) {
      return AbilityUseResult(
        attackerCharacterId: attacker.character.id,
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
      return _emptyResult(attacker.character.id, trigger.id);
    }

    final maxTargets = maxRangedTargets(attacker, trigger);
    var filteredTargets = targets
        .where((t) => canTarget(attacker, t))
        .take(maxTargets)
        .toList();

    // Misfire redirect: if attacker has the misfire status, some targets
    // may be redirected to the attacker's own allies.
    if (trigger.targetAffiliation == TargetAffiliation.opponent) {
      filteredTargets = _applyMisfireRedirect(attacker, filteredTargets);
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

    // Ren-style "First Strike" perk: a flat Attack bonus on this
    // character's first ability use of the battle. Gated on the perk
    // charge (consumed here, once per ability use regardless of how many
    // targets/hits it resolves), not `hasActedThisBattle` - by the time
    // this method runs, `useAbility` has already flipped that flag.
    var effectiveAttack = stats.attack;
    final firstStrikeBonus = attacker.character.perk?.firstTurnAttackBonus;
    if (firstStrikeBonus != null && !attacker.perkChargeUsed) {
      effectiveAttack += firstStrikeBonus;
      attacker.consumePerkChargeIfAvailable();
    }

    final hitsByTargetId = <String, List<_SingleHitResult>>{};

    void resolveHitAgainst(CharacterBattleState target) {
      final advantageContext = _advantageContextAgainst(attacker, target);
      var attackerContext = _mergedContext(baseContext, advantageContext);

      // Airi-style "Feint" perk: the first attack roll made against her
      // each battle is rolled with disadvantage.
      if (target.character.perk?.firstIncomingAttackHasDisadvantage == true &&
          !target.perkChargeUsed) {
        final withFeint = RollContext();
        for (final s in attackerContext.advantageSources) {
          withFeint.addAdvantage(s);
        }
        for (final s in attackerContext.disadvantageSources) {
          withFeint.addDisadvantage(s);
        }
        withFeint.addDisadvantage('perk:feint');
        attackerContext = withFeint;
        target.consumePerkChargeIfAvailable();
      }

      // Vela-style "First Blood" perk: bonus Critical Chance on this
      // character's first attack of the battle, if that target is at
      // full health.
      var attackerCriticalChancePercent =
          stats.criticalChance + bonuses.criticalChanceBonus;
      final firstBloodBonus =
          attacker.character.perk?.firstAttackCritBonusVsFullHealthTarget;
      if (firstBloodBonus != null && !attacker.perkChargeUsed) {
        final targetMaxHealth =
            target.effectiveStats(fatConfig: fatConfig).maxHealth;
        if (target.currentHealth >= targetMaxHealth) {
          attackerCriticalChancePercent += firstBloodBonus;
        }
        attacker.consumePerkChargeIfAvailable();
      }

      // Mireille-style "Decoy" perk: once per battle, an incoming attack
      // has a flat chance to miss entirely, independent of the to-hit
      // roll. The roll is still made (for realistic telemetry); a
      // successful dodge just overrides the outcome.
      var forcedMiss = false;
      final dodgeChance = target.character.perk?.dodgeChanceOncePerBattle;
      if (dodgeChance != null && !target.perkChargeUsed) {
        if (combatEngine.diceRoller.rollPercent() <=
            (dodgeChance * 100).round()) {
          forcedMiss = true;
        }
        target.consumePerkChargeIfAvailable();
      }

      // TEG Effects 1/2/5: coordination advantage on the attacker's roll,
      // Operator's Read advantage on the defender's contest, and (at SSS)
      // the widened crit threshold. No-ops when no TEG profile is injected.
      _applyTegOffenseAdvantage(attackerContext, attacker);
      _applyComboAdvantage(attackerContext, attacker, trigger, target);
      final tegDefenderContext = RollContext();
      _applyTegDefenseAdvantage(tegDefenderContext, target);
      final tegMaxCrit = _tegFor(attacker).maxCritThreshold;

      var outcome = combatEngine.resolveAttackRoll(
        attackerAttack: effectiveAttack,
        defenderDefense: target.effectiveStats(fatConfig: fatConfig).defense,
        attackerCriticalChancePercent: attackerCriticalChancePercent,
        attackerContext: attackerContext,
        defenderContext: tegDefenderContext,
        maxCritThreshold: tegMaxCrit,
      );

      // Reckoning: forced critical miss overrides the roll.
      final forcedCritMissIdx = attacker.statusEffects
          .indexWhere((i) => i.definitionId == 'forced_critical_miss');
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

      // Zheng-style "Foresight" perk: once per battle, reroll a missed
      // attack roll.
      if (!outcome.isHit &&
          attacker.character.perk?.canRerollOwnAttackRollOncePerBattle ==
              true &&
          !attacker.perkChargeUsed) {
        outcome = combatEngine.resolveAttackRoll(
          attackerAttack: effectiveAttack,
          defenderDefense: target.effectiveStats(fatConfig: fatConfig).defense,
          attackerCriticalChancePercent: attackerCriticalChancePercent,
          attackerContext: attackerContext,
          defenderContext: tegDefenderContext,
          maxCritThreshold: tegMaxCrit,
        );
        attacker.consumePerkChargeIfAvailable();
      }

      void record(
        int damage,
        HitDamageDetail? damageDetail,
        List<String> appliedIds,
      ) {
        hitsByTargetId
            .putIfAbsent(target.character.id, () => [])
            .add(_SingleHitResult(outcome, damage, damageDetail, appliedIds));
      }

      if (outcome.isCriticalMiss) {
        combatEngine.applyCriticalMissPenalty(attacker);
        record(0, null, const []);
        return;
      }
      if (forcedMiss || !outcome.isHit) {
        // Ilona-style "Riposte" perk: a melee attack that misses her
        // grants a stacking Attack buff for her next turn.
        final riposteBonus =
            target.character.perk?.attackStackBonusOnMeleeMissAgainstSelf;
        if (riposteBonus != null && trigger.attackType == AttackType.melee) {
          target.applyFlatBonus(
              ModifiableStat.attack, riposteBonus.toDouble(), 2);
        }
        record(0, null, const []);
        return;
      }

      var damageDealt = 0;
      HitDamageDetail? damageDetail;
      if (trigger.damageType != null) {
        final diceRoll = trigger.damage?.rollDetailed(combatEngine.diceRoller);
        final baseDamage = diceRoll?.total ?? 0;
        final damageBonus = isBurst
            ? bonuses.burstDamageBonus
            : bonuses.singleTargetDamageBonus;
        final perkMultiplier =
            _perkOutgoingDamageMultiplier(attacker, target, trigger);
        final interdictMultiplier =
            _interdictDamageMultiplier(attacker, trigger);
        final preCritMultiplier = (1 + damageBonus) *
            damageMultiplier *
            attacker.outgoingDamageMultiplier() *
            perkMultiplier *
            interdictMultiplier;
        final adjustedBaseDamage = (baseDamage * preCritMultiplier).round();
        final healthBefore = target.currentHealth;
        final breakdown = _applyDamage(
          target: target,
          baseDamage: adjustedBaseDamage,
          damageType: trigger.damageType!,
          isCriticalHit: outcome.isCriticalHit,
          damageSource: attacker,
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
          attacker.lastDamagedTargetId = target.character.id;
          if (trigger.attackType == AttackType.melee) {
            attacker.meleeHitEnemyIds.add(target.character.id);
          }
        }
      }

      if (trigger.healAmount != null) {
        final recipient = trigger.healsCasterInstead ? attacker : target;
        if (!recipient.isHealingPrevented()) {
          final baseHeal = trigger.healAmount!.roll(combatEngine.diceRoller);
          // Priya-style "Combat Medic" perk: bonus heal when the
          // recipient is below 50% health.
          var priyaBonus = 1.0;
          final medicBonus =
              attacker.character.perk?.healBonusPercentVsAllyBelowHalfHealth;
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
      // TEG Effect 1 (offense) on the causer's infliction rolls this use.
      _applyTegOffenseAdvantage(advantageContext, attacker);
      for (final application in trigger.inflictedStatusEffects) {
        // TEG Effect 2 (defense) on the target's resistance roll.
        final resistContext =
            target.rollContextFor(StatusRollTag.statusResistanceRoll);
        _applyTegDefenseAdvantage(resistContext, target);
        final inflictionOutcome = statusEffectEngine.resolveInfliction(
          causerInfliction: stats.statusEffectInfliction,
          targetResistance: target
              .effectiveStats(fatConfig: fatConfig)
              .statusEffectResistance,
          causerRollContext: advantageContext,
          targetRollContext: resistContext,
        );
        if (inflictionOutcome.applies) {
          // Soren-style "Weaken Resolve" perk: bonus duration when the
          // target already carries an effect from this same attacker.
          var durationOverride = application.durationTurnsOverride;
          final resolveBonus =
              attacker.character.perk?.bonusDurationVsAlreadyAffectedTarget;
          if (resolveBonus != null &&
              target.statusEffects
                  .any((i) => i.sourceCharacterId == attacker.character.id)) {
            final base = durationOverride ??
                statusEffectEngine
                    .catalog[application.statusEffectId].defaultDurationTurns;
            durationOverride = base == null ? null : base + resolveBonus;
          }

          final applied = statusEffectEngine.apply(
            target,
            application.statusEffectId,
            sourceCharacterId: attacker.character.id,
            durationOverride: durationOverride,
            instanceData: statusEffectData,
          );
          if (applied) {
            appliedIds.add(application.statusEffectId);
            // Celestine-style "Warding Presence" perk: an ally-targeted
            // buff also grants a Status Effect Resistance bonus.
            final wardBonus = attacker
                .character.perk?.bonusStatusResistanceGrantedByAllyBuffs;
            if (wardBonus != null &&
                trigger.targetAffiliation == TargetAffiliation.ally) {
              target.applyFlatBonus(ModifiableStat.statusEffectResistance,
                  wardBonus.toDouble(), durationOverride ?? 2);
            }
          }
        }
      }

      record(damageDealt, damageDetail, appliedIds);
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
      final hits = hitsByTargetId[target.character.id];
      if (hits == null || hits.isEmpty) continue;
      targetResults.add(TargetHitResult(
        targetCharacterId: target.character.id,
        attackRolls: hits.map((h) => h.outcome).toList(),
        damagePerHit: hits.map((h) => h.damage).toList(),
        damageDetails: hits.map((h) => h.damageDetail).toList(),
        totalDamageDealt: hits.fold(0, (sum, h) => sum + h.damage),
        statusEffectsApplied:
            hits.expand((h) => h.appliedStatusEffectIds).toList(),
      ));
    }

    // Frozen Tempo: if any hit target had cooldownSabotage, double this
    // ability's cooldown for the attacker.
    for (final target in clampedTargets) {
      final saboIdx = target.reactiveEffects
          .indexWhere((r) => r.kind == ReactiveKind.cooldownSabotage);
      if (saboIdx >= 0 && trigger.rangeTag == RangeTag.ranged) {
        final hits = hitsByTargetId[target.character.id];
        final anyHit = hits != null && hits.any((h) => h.outcome.isHit);
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

    // Combat-v2 Phase I/J: record this resolved action so a later same-team
    // payoff can recognize a setup->payoff / focus-fire combo (Effects 3/4).
    comboLedger.record(
      actorId: attacker.character.id,
      teamId: _teamKeyFor(attacker),
      trigger: trigger,
      targetIds: [for (final r in targetResults) r.targetCharacterId],
      statusesApplied: [
        for (final r in targetResults) ...r.statusEffectsApplied,
      ],
      dealtDamage: targetResults.any((r) => r.totalDamageDealt > 0),
    );

    return AbilityUseResult(
      attackerCharacterId: attacker.character.id,
      triggerId: trigger.id,
      targetResults: targetResults,
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

    holder.reactiveEffects.add(ReactiveEffect(
      kind: kind,
      sourceCharacterId: caster.character.id,
      data: reactiveData,
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

  /// Finalizes [state] for the turn: applies cooldowns (doubled if FAT
  /// was used for 2+ abilities), the resulting Trion Affinity halving
  /// penalty for next turn, and ticks down existing cooldowns/penalties.
  void endCharacterTurn(CharacterBattleState state) =>
      state.endTurn(fatConfig: fatConfig);

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
    return multipliers.multiplierFor(grade);
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
                reckoning, attacker.character.id, cfg);
          }
          if (trigger.cooldownTurns >= 2) {
            _reckoningIncrementDebt(
                reckoning, attacker.character.id, cfg);
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
            coldread.markedEnemyId == attacker.character.id &&
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
          coldread.markedEnemyId = target.character.id;
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
          // TEG boost deferred to Phase E (needs TEG engine).
          // Fallback: double the highest-TA ally's Trion Affinity.
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
          .where((s) => s.character.id == topEnemyId)
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
    // Resonance downgrade deferred to Phase E (ResonanceGrid is immutable).
    // Fallback: purge all debuffs on holder's team and reflect the most
    // prolific enemy's debuffs.
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
            .where((s) => s.character.id == topSourceId && s.isAlive)
            .firstOrNull;
        if (target != null) {
          for (final debuff in debuffsToReflect) {
            if (debuff.sourceCharacterId == topSourceId) {
              statusEffectEngine.apply(
                target,
                debuff.definitionId,
                sourceCharacterId: holder.character.id,
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
      sourceCharacterId: holder.character.id,
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

  /// Finds the costliest Trion cost among abilities used this turn by any
  /// living member of [teamStates] (for Levy calculation).
  int _findCostliestTrionCost(List<CharacterBattleState> teamStates) {
    var maxCost = 0;
    for (final state in teamStates) {
      for (final triggerId in state.triggersUsedThisTurn) {
        // Look up trigger cost via cooldown records as a proxy - we don't
        // have direct trigger references here, so use a reasonable default.
        maxCost = max(maxCost, 20);
      }
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
      sourceCharacterId: attacker.character.id,
    );

    // Cost: allies Vulnerable (Exposed) until next turn.
    for (final ally in attacker.teammates) {
      if (!ally.isAlive) continue;
      statusEffectEngine.apply(
        ally,
        'exposed',
        durationOverride: 1,
        sourceCharacterId: attacker.character.id,
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
            t.isAlive && attacker.meleeHitEnemyIds.contains(t.character.id))
        .toList();
    if (eligibleTargets.isEmpty) {
      return _emptyResult(attacker.character.id, trigger.id);
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
      attacker.lastDamagedTargetId = enemy.character.id;
    }

    return AbilityUseResult(
      attackerCharacterId: attacker.character.id,
      triggerId: trigger.id,
      targetResults: [
        TargetHitResult(
          targetCharacterId: enemy.character.id,
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
      return _emptyResult(attacker.character.id, trigger.id);
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
    final damageDealt = healthBefore - target.currentHealth;

    if (damageDealt > 0) {
      attacker.cumulativeDamageDealt += damageDealt;
      attacker.lastDamagedTargetId = target.character.id;
    }

    return AbilityUseResult(
      attackerCharacterId: attacker.character.id,
      triggerId: trigger.id,
      targetResults: [
        TargetHitResult(
          targetCharacterId: target.character.id,
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
      return _emptyResult(attacker.character.id, trigger.id);
    }

    // The caster is removed from battle.
    attacker.currentHealth = 0;

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
        targetCharacterId: enemy.character.id,
        attackRolls: const [],
        damagePerHit: [damageDealt],
        damageDetails: const [null],
        totalDamageDealt: damageDealt,
        statusEffectsApplied: const [],
      ));
    }

    return AbilityUseResult(
      attackerCharacterId: attacker.character.id,
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
      return _emptyResult(attacker.character.id, trigger.id);
    }
    final target = targets.first;

    // Bind to the target: 2x outgoing damage + healing prevention come
    // from the vow_of_the_duel status effect; targeting restriction is
    // enforced by canTarget via duelTargetId.
    attacker.duelTargetId = target.character.id;
    statusEffectEngine.apply(
      attacker,
      'vow_of_the_duel',
      sourceCharacterId: attacker.character.id,
    );

    return AbilityUseResult(
      attackerCharacterId: attacker.character.id,
      triggerId: trigger.id,
      targetResults: [
        TargetHitResult(
          targetCharacterId: target.character.id,
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
        .where((s) => s.character.id == caster.duelTargetId)
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
      return _emptyResult(attacker.character.id, trigger.id);
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
        final damageRoll = trigger.damage?.roll(combatEngine.diceRoller) ?? 0;
        final preCritMultiplier =
            (1 + bonuses.singleTargetDamageBonus) *
            attacker.outgoingDamageMultiplier();
        final adjustedBase = (damageRoll * preCritMultiplier).round();
        final healthBefore = target.currentHealth;
        _applyDamage(
          target: target,
          baseDamage: adjustedBase,
          damageType: trigger.damageType!,
          isCriticalHit: outcome.isCriticalHit,
          damageSource: attacker,
        );
        damageDealt = healthBefore - target.currentHealth;
        if (damageDealt > 0) {
          attacker.cumulativeDamageDealt += damageDealt;
          attacker.lastDamagedTargetId = target.character.id;
          attacker.meleeHitEnemyIds.add(target.character.id);
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
      attackerCharacterId: attacker.character.id,
      triggerId: trigger.id,
      targetResults: [
        TargetHitResult(
          targetCharacterId: target.character.id,
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
      return _emptyResult(attacker.character.id, trigger.id);
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
        attacker.lastDamagedTargetId = target.character.id;
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
      final tegResistContext = RollContext();
      _applyTegDefenseAdvantage(tegResistContext, target); // Effect 2
      final inflictionOutcome = statusEffectEngine.resolveInfliction(
        causerInfliction: stats.statusEffectInfliction,
        targetResistance:
            target.effectiveStats(fatConfig: fatConfig).statusEffectResistance,
        causerRollContext: tegCauserContext,
        targetRollContext: tegResistContext,
      );
      if (inflictionOutcome.applies) {
        final applied = statusEffectEngine.apply(
          target,
          application.statusEffectId,
          sourceCharacterId: attacker.character.id,
          durationOverride: application.durationTurnsOverride,
        );
        if (applied) appliedIds.add(application.statusEffectId);
      }
    }

    return AbilityUseResult(
      attackerCharacterId: attacker.character.id,
      triggerId: trigger.id,
      targetResults: [
        TargetHitResult(
          targetCharacterId: target.character.id,
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
      return _emptyResult(attacker.character.id, trigger.id);
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
      sourceCharacterId: attacker.character.id,
      instanceData: {'zeroedStat': zeroedStat},
    );

    return AbilityUseResult(
      attackerCharacterId: attacker.character.id,
      triggerId: trigger.id,
      targetResults: [
        TargetHitResult(
          targetCharacterId: target.character.id,
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
      attackerCharacterId: attacker.character.id,
      triggerId: trigger.id,
      targetResults: [
        TargetHitResult(
          targetCharacterId: target.character.id,
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
      return _emptyResult(attacker.character.id, trigger.id);
    }
    final target = targets.first;
    // Cannot be used on the caster.
    if (target.character.id == attacker.character.id) {
      return _emptyResult(attacker.character.id, trigger.id);
    }
    attacker.revealedEnemyIds.add(target.character.id);
    statusEffectEngine.apply(
      target,
      'minds_eye_reveal',
      sourceCharacterId: attacker.character.id,
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
      return _emptyResult(attacker.character.id, trigger.id);
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
      sourceCharacterId: attacker.character.id,
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
      return _emptyResult(attacker.character.id, trigger.id);
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
      return _emptyResult(attacker.character.id, trigger.id);
    }
    final source = targets[0];
    final dest = targets[1];
    final statusId = uniqueData?['sensorySwapStatusId'] as String?;
    final idx = statusId != null
        ? source.statusEffects
            .indexWhere((i) => i.definitionId == statusId)
        : (source.statusEffects.isNotEmpty ? 0 : -1);
    if (idx < 0) {
      return _emptyResult(attacker.character.id, trigger.id);
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
      return _emptyResult(attacker.character.id, trigger.id);
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
      attacker.lastDamagedTargetId = target.character.id;
    }
    return AbilityUseResult(
      attackerCharacterId: attacker.character.id,
      triggerId: trigger.id,
      targetResults: [
        TargetHitResult(
          targetCharacterId: target.character.id,
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
      return _emptyResult(attacker.character.id, trigger.id);
    }
    final target = targets.first;
    statusEffectEngine.apply(
      target,
      'isolation',
      sourceCharacterId: attacker.character.id,
    );
    return _singleStatusResult(attacker, trigger, target, const ['isolation']);
  }

  AbilityUseResult _resolveIllusoryDouble(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets,
  ) {
    if (targets.isEmpty) {
      return _emptyResult(attacker.character.id, trigger.id);
    }
    // Needs an available charge (starts at 1, +1 per ally defeated).
    if (attacker.illusoryDoubleCharges <= 0) {
      return _emptyResult(attacker.character.id, trigger.id);
    }
    attacker.illusoryDoubleCharges -= 1;
    // Target self or an ally: make them untargetable for the opponent's
    // next turn.
    final target = targets.first;
    statusEffectEngine.apply(
      target,
      'untargetable',
      sourceCharacterId: attacker.character.id,
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
      return _emptyResult(attacker.character.id, trigger.id);
    }
    final target = targets.first;
    // Force the target's next attack to whiff; the backlash + Silence fire
    // when that whiff is consumed (see _consumeEchoingDoubt).
    statusEffectEngine.apply(
      target,
      'echoing_doubt',
      sourceCharacterId: attacker.character.id,
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
      sourceCharacterId: attacker.character.id,
    );
  }

  AbilityUseResult _resolveKarmicBind(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> targets,
  ) {
    if (targets.isEmpty) {
      return _emptyResult(attacker.character.id, trigger.id);
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

    attacker.karmicBindTargetId = target.character.id;
    // The live damage/heal propagation across the 3-turn link needs a
    // battle-wide character registry (TurnEngine has no cross-team lookup);
    // it is a Battle-layer hook, so here we record the link and fraction on
    // both partners for that layer to read (consistent with the passive
    // counters' deferred cross-team effects).
    statusEffectEngine.apply(
      target,
      'karmic_bind',
      sourceCharacterId: attacker.character.id,
      instanceData: {
        'karmicBindFraction': fraction,
        'partnerId': attacker.character.id,
      },
    );
    statusEffectEngine.apply(
      attacker,
      'karmic_bind',
      sourceCharacterId: attacker.character.id,
      instanceData: {
        'karmicBindFraction': fraction,
        'partnerId': target.character.id,
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
      return _emptyResult(attacker.character.id, trigger.id);
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
        sourceCharacterId: attacker.character.id,
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

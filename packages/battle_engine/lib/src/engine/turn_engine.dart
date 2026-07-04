import '../constants.dart';
import '../models/character_type.dart';
import '../models/damage_type.dart';
import '../models/resonance.dart';
import '../models/status_effect.dart';
import '../models/status_effect_catalog.dart';
import '../models/team.dart';
import '../models/trigger.dart';
import '../models/trion.dart';
import '../util/dice.dart';
import 'character_battle_state.dart';
import 'combat_engine.dart';
import 'fat_engine.dart';
import 'status_effect_engine.dart';
import 'team_spirit_curve.dart';
import 'trion_gain_engine.dart';

/// Every roll made against one target during a single ability use, the
/// total damage it took, and which inflicted status effects actually
/// landed. Burst's multiple hits on the same target collapse into one
/// entry. Targets that received zero rolls (e.g. unreached Burst targets
/// when `hitsPerUse < targets.length`) are omitted from
/// `AbilityUseResult.targetResults`.
class TargetHitResult {
  final String targetCharacterId;
  final List<AttackRollOutcome> attackRolls;
  final int totalDamageDealt;
  final List<String> statusEffectsApplied;

  const TargetHitResult({
    required this.targetCharacterId,
    required this.attackRolls,
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
  final List<String> appliedStatusEffectIds;
  _SingleHitResult(this.outcome, this.damage, this.appliedStatusEffectIds);
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

  TurnEngine({
    TrionGainEngine? trionGainEngine,
    FatEngine? fatEngine,
    CombatEngine? combatEngine,
    StatusEffectEngine? statusEffectEngine,
    TeamSpiritCurve? teamSpiritCurve,
    this.fatConfig = FatConfig.defaults,
  })  : trionGainEngine = trionGainEngine ?? TrionGainEngine(),
        fatEngine = fatEngine ?? FatEngine(),
        combatEngine = combatEngine ?? CombatEngine(),
        statusEffectEngine = statusEffectEngine ?? StatusEffectEngine(),
        teamSpiritCurve = teamSpiritCurve ?? const TeamSpiritCurve();

  /// Rolls this turn's Trion gain for [team] (using the sum of living
  /// members' effective Trion Affinity, so the FAT halving penalty is
  /// reflected) and adds it to the team's pool.
  TrionGainResult resolveTeamTrionGain(
    Team team,
    Map<String, CharacterBattleState> states, {
    double modifier = 0,
  }) {
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
        state.currentHealth =
            (state.currentHealth + healed).clamp(0, maxHealth);
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
  void _applyDamage({
    required CharacterBattleState target,
    required int baseDamage,
    required DamageType damageType,
    required bool isCriticalHit,
  }) {
    var damage = combatEngine.resolveDamage(
      baseDamage: baseDamage,
      damageType: damageType,
      isCriticalHit: isCriticalHit,
      target: target,
    );

    // Bastian-style "Absorb" perk: the first damage instance of the
    // battle is reduced further, on top of any other mitigation.
    final reduction =
        target.character.perk?.firstDamageInstanceReductionPercent;
    if (reduction != null && !target.perkChargeUsed) {
      damage = (damage * (1 - reduction)).round();
      target.consumePerkChargeIfAvailable();
    }

    final maxHealth = target.effectiveStats(fatConfig: fatConfig).maxHealth;
    final wouldBeLethal =
        target.currentHealth > 1 && target.currentHealth - damage <= 0;

    if (wouldBeLethal && target.hasSurviveLethalDamageCharge) {
      target.hasSurviveLethalDamageCharge = false;
      target.currentHealth = 1;
    } else {
      target.currentHealth =
          (target.currentHealth - damage).clamp(0, maxHealth);
    }
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
    for (final instance in state.statusEffects) {
      if (instance.data['lockedAbilityId'] == trigger.id) return false;
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
  }) {
    final maxTargets = maxRangedTargets(attacker, trigger);
    final clampedTargets = targets
        .where((t) => canTarget(attacker, t))
        .take(maxTargets)
        .map((t) => _applyGuardianRedirect(t))
        .toList();

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

      var outcome = combatEngine.resolveAttackRoll(
        attackerAttack: effectiveAttack,
        defenderDefense: target.effectiveStats(fatConfig: fatConfig).defense,
        attackerCriticalChancePercent: attackerCriticalChancePercent,
        attackerContext: attackerContext,
      );

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
        );
        attacker.consumePerkChargeIfAvailable();
      }

      void record(int damage, List<String> appliedIds) {
        hitsByTargetId
            .putIfAbsent(target.character.id, () => [])
            .add(_SingleHitResult(outcome, damage, appliedIds));
      }

      if (outcome.isCriticalMiss) {
        combatEngine.applyCriticalMissPenalty(attacker);
        record(0, const []);
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
        record(0, const []);
        return;
      }

      var damageDealt = 0;
      if (trigger.damageType != null) {
        final baseDamage = trigger.damage?.roll(combatEngine.diceRoller) ?? 0;
        final damageBonus = isBurst
            ? bonuses.burstDamageBonus
            : bonuses.singleTargetDamageBonus;
        final perkMultiplier =
            _perkOutgoingDamageMultiplier(attacker, target, trigger);
        final adjustedBaseDamage = (baseDamage *
                (1 + damageBonus) *
                damageMultiplier *
                attacker.outgoingDamageMultiplier() *
                perkMultiplier)
            .round();
        final healthBefore = target.currentHealth;
        _applyDamage(
          target: target,
          baseDamage: adjustedBaseDamage,
          damageType: trigger.damageType!,
          isCriticalHit: outcome.isCriticalHit,
        );
        damageDealt = healthBefore - target.currentHealth;
        if (damageDealt > 0) {
          attacker.cumulativeDamageDealt += damageDealt;
          attacker.lastDamagedTargetId = target.character.id;
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
          recipient.currentHealth =
              (recipient.currentHealth + healed).clamp(0, maxHealth);
        }
      }

      final appliedIds = <String>[];
      for (final application in trigger.inflictedStatusEffects) {
        final inflictionOutcome = statusEffectEngine.resolveInfliction(
          causerInfliction: stats.statusEffectInfliction,
          targetResistance: target
              .effectiveStats(fatConfig: fatConfig)
              .statusEffectResistance,
          causerRollContext: advantageContext,
          targetRollContext:
              target.rollContextFor(StatusRollTag.statusResistanceRoll),
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

      record(damageDealt, appliedIds);
    }

    switch (trigger.attackSubtype) {
      case AttackSubtype.single:
      case AttackSubtype.unique:
        if (clampedTargets.isNotEmpty) resolveHitAgainst(clampedTargets.first);
        break;
      case AttackSubtype.aoe:
        for (final target in clampedTargets) {
          resolveHitAgainst(target);
        }
        break;
      case AttackSubtype.burst:
        for (final target in clampedTargets) {
          for (var hitIndex = 0; hitIndex < trigger.hitsPerUse; hitIndex++) {
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
        totalDamageDealt: hits.fold(0, (sum, h) => sum + h.damage),
        statusEffectsApplied:
            hits.expand((h) => h.appliedStatusEffectIds).toList(),
      ));
    }

    return AbilityUseResult(
      attackerCharacterId: attacker.character.id,
      triggerId: trigger.id,
      targetResults: targetResults,
    );
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
}

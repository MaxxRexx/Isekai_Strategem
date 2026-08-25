import 'dart:math';

import '../engine/battle.dart';
import '../engine/character_battle_state.dart';
import '../engine/turn_engine.dart';
import '../models/battle_position.dart';
import '../models/team.dart';
import '../models/trigger.dart';
import 'ai_profile.dart';
import 'ai_skill_class.dart';
import 'loadout_builder.dart';
import 'rule_based_ai.dart';

/// One ability use the AI has committed to for this turn, chosen up front
/// against a predicted overlay (a blind queue) and resolved later through
/// the shared phase-priority resolver - the same path the player's queue
/// uses (see [ProfileDrivenAi.planTurn]).
class AiPlannedAction {
  final String characterId;
  final String triggerId;
  final List<String> targetIds;

  /// Set only on a planned Reposition ([triggerId] is [repositionActionId]):
  /// the line this step moves to. Null for every ability.
  final BattlePosition? destination;

  const AiPlannedAction({
    required this.characterId,
    required this.triggerId,
    required this.targetIds,
    this.destination,
  });

  /// Whether this entry is a move rather than an ability use. Moves carry no
  /// Trion cost and resolve ahead of every ability, so the caller has to be
  /// able to tell them apart.
  bool get isReposition => triggerId == repositionActionId;
}

/// Plays one [AiProfile]'s strategy for a [Battle]'s active team: which
/// ability, which target, and whether to keep chaining FAT-triggered
/// extra actions, all read from the profile's data rather than
/// hardcoded per-type logic (mirrors `CharacterPerk`'s "bag of
/// parameters, one generic engine" shape).
///
/// [AiSkillClassConfig.mistakeChance] makes lower classes occasionally
/// fall back to a random legal choice instead of the profile's intended
/// pick - a shared, honest way to feel human/fallible without needing a
/// bespoke special-cased "habit" implementation per low-tier type.
class ProfileDrivenAi {
  final AiProfile profile;
  final Random random;

  static const _tagLookup = LoadoutBuilder();

  ProfileDrivenAi(this.profile, {Random? random}) : random = random ?? Random();

  List<AiActionResult> takeTurn(
    Battle battle, {
    required Map<String, List<ActiveTrigger>> equippedActiveTriggers,
  }) {
    final engine = battle.turnEngine;
    final config = profile.skillConfig;
    final results = <AiActionResult>[];

    for (final state in battle.statesOf(battle.activeTeam)) {
      if (!state.isAlive) continue;

      final triggers = equippedActiveTriggers[state.combatantId] ?? const [];
      if (triggers.isEmpty) continue;

      // Decide the step before swinging, so a character who closes the gap
      // can still act this turn (see [_planStep]).
      final step = _planStep(
        engine,
        state,
        triggers,
        battle.inactiveTeamStates,
        engine.fatEngine.maxAbilitiesThisTurn(state) -
            state.abilitiesUsedThisTurnCount,
      );
      if (step != null) engine.reposition(state, step);

      final unusableThisTurn = <String>{};
      while (true) {
        final usable = triggers
            .where((t) =>
                !unusableThisTurn.contains(t.id) &&
                engine.canUseAbility(state, t))
            .toList();
        if (usable.isEmpty) break;

        final trigger = _chooseAbility(state, usable, config, battle);
        final targets = _chooseTargets(engine, state, trigger, battle, config);
        if (targets.isEmpty) {
          unusableThisTurn.add(trigger.id);
          continue;
        }

        if (!engine.useAbility(state, trigger, battle.activeTeamPool)) {
          unusableThisTurn.add(trigger.id);
          continue;
        }

        final healthBefore = {
          for (final t in targets) t.combatantId: t.currentHealth
        };
        final useResult = engine.resolveAbilityUse(
          attacker: state,
          trigger: trigger,
          targets: targets,
        );
        results.add(AiActionResult(
          characterId: state.combatantId,
          triggerId: trigger.id,
          useResult: useResult,
        ));

        if (battle.isOver) return results;

        if (!_shouldKeepChaining(battle, healthBefore, useResult)) break;
      }

      // Nothing this character could reach from where they are standing.
      // Move rather than skip the turn: a Loadout that is briefly out of
      // range should cost tempo, not the whole turn, and two squads both
      // stranded would otherwise never finish the battle.
      if (state.abilitiesUsedThisTurnCount == 0) {
        final destination = engine.suggestReposition(
          state,
          triggers,
          battle.inactiveTeamStates,
        );
        if (destination != null) engine.reposition(state, destination);
      }
    }

    return results;
  }

  /// Chooses the active team's entire turn up front, without resolving any
  /// of it, so it can be committed as a blind queue and resolved later
  /// through the shared phase-priority resolver (the same path the player's
  /// queue uses). Reuses the same ability/target selection as [takeTurn] but
  /// evaluates it against a predicted overlay - remaining health per
  /// character, the Trion budget, and per-character use counts - rather than
  /// mutating the battle. Does not spend Trion or record uses; the caller
  /// resolves the returned plan.
  List<AiPlannedAction> planTurn(
    Battle battle, {
    required Map<String, List<ActiveTrigger>> equippedActiveTriggers,
  }) {
    final engine = battle.turnEngine;
    final config = profile.skillConfig;
    final plan = <AiPlannedAction>[];

    final predictedHealth = <String, int>{
      for (final team in [battle.activeTeam, battle.inactiveTeam])
        for (final s in battle.statesOf(team)) s.combatantId: s.currentHealth,
    };
    var trionBudget = battle.activeTeamPool.current;
    final usesPerChar = <String, int>{};
    // Where each character will be standing once the plan's moves resolve.
    // Everything after a planned move is chosen against this, not against the
    // live position, so the AI can close the gap and swing in one turn just
    // like the player can.
    final plannedPositions = <String, BattlePosition>{};

    for (final state in battle.statesOf(battle.activeTeam)) {
      if (!state.isAlive) continue;

      final triggers = equippedActiveTriggers[state.combatantId] ?? const [];
      if (triggers.isEmpty) continue;

      final step = _planStep(
        engine,
        state,
        triggers,
        battle.inactiveTeamStates,
        engine.fatEngine.maxAbilitiesThisTurn(state) -
            state.abilitiesUsedThisTurnCount,
      );
      if (step != null) {
        plannedPositions[state.combatantId] = step;
        usesPerChar[state.combatantId] = (usesPerChar[state.combatantId] ?? 0) + 1;
        plan.add(AiPlannedAction(
          characterId: state.combatantId,
          triggerId: repositionActionId,
          targetIds: const [],
          destination: step,
        ));
      }

      final unusableThisTurn = <String>{};
      while (true) {
        if ((usesPerChar[state.combatantId] ?? 0) >=
            engine.fatEngine.maxAbilitiesThisTurn(state)) {
          break;
        }
        final usable = triggers.where((t) {
          if (unusableThisTurn.contains(t.id)) return false;
          if (!engine.canUseAbility(state, t)) return false;
          final cost = (t.trionCost * state.trionCostMultiplier()).round();
          return cost <= trionBudget;
        }).toList();
        if (usable.isEmpty) break;

        final trigger = _chooseAbility(state, usable, config, battle);
        final targets = _chooseTargets(
          engine,
          state,
          trigger,
          battle,
          config,
          predictedHealth: predictedHealth,
          fromPosition: plannedPositions[state.combatantId],
        );
        if (targets.isEmpty) {
          unusableThisTurn.add(trigger.id);
          continue;
        }

        final cost = (trigger.trionCost * state.trionCostMultiplier()).round();
        trionBudget -= cost;
        usesPerChar[state.combatantId] = (usesPerChar[state.combatantId] ?? 0) + 1;
        plan.add(AiPlannedAction(
          characterId: state.combatantId,
          triggerId: trigger.id,
          targetIds: [for (final t in targets) t.combatantId],
        ));

        // Update the overlay with predicted damage so later choices avoid
        // predicted-dead targets and the chaining check can see kills.
        for (final t in targets) {
          final id = t.combatantId;
          final dmg = _predictedDamage(engine, state, t, trigger).round();
          predictedHealth[id] = (predictedHealth[id]! - dmg).clamp(0, 1 << 30);
        }

        if (!_shouldKeepChainingPlanned(battle, targets, predictedHealth)) {
          break;
        }
      }
    }

    return plan;
  }

  /// The step this character should take before acting, or null to stand pat.
  ///
  /// Two cases, and only two:
  ///
  /// A character who can reach **nothing** moves. Standing still forfeits the
  /// turn outright, so any move is better, and two stranded squads would
  /// otherwise never finish the battle.
  ///
  /// A character with a **spare** ability use moves when a step brings more of
  /// their Loadout to bear. There the move costs tempo rather than the whole
  /// turn, which is a trade worth making.
  ///
  /// A character with one action and something to do keeps the action. Paying
  /// an entire turn to improve the next one is a bad trade, and an AI that
  /// made it would read as indecisive rather than clever.
  BattlePosition? _planStep(
    TurnEngine engine,
    CharacterBattleState state,
    List<ActiveTrigger> triggers,
    List<CharacterBattleState> opponents,
    int usesAvailable,
  ) {
    if (usesAvailable <= 0) return null;
    final destination = engine.suggestReposition(
      state,
      triggers,
      opponents,
      from: state.position,
    );
    if (destination == null) return null;
    final reachNow = engine.reachableAbilityCount(
      state,
      state.position,
      triggers,
      opponents,
    );
    return reachNow == 0 || usesAvailable > 1 ? destination : null;
  }

  bool _isMistake(AiSkillClassConfig config) =>
      random.nextDouble() < config.mistakeChance;

  bool _isBlackTriggerAbility(CharacterBattleState state, ActiveTrigger t) =>
      state.character.blackTrigger?.activeAbilities.any((a) => a.id == t.id) ??
      false;

  ActiveTrigger _chooseAbility(
    CharacterBattleState state,
    List<ActiveTrigger> usable,
    AiSkillClassConfig config,
    Battle battle,
  ) {
    if (_isMistake(config)) {
      return usable[random.nextInt(usable.length)];
    }

    List<ActiveTrigger> byPower(List<ActiveTrigger> pool) {
      final sorted = List.of(pool)
        ..sort((a, b) => _abilityPower(b).compareTo(_abilityPower(a)));
      return sorted;
    }

    // The Copycat: before applying its own priority, try to just repeat
    // whatever TriggerCategory the opponent team most recently acted
    // with - copying, not reading the board independently.
    if (profile.mirrorsOpponentLastCategory) {
      final opponentCategories = battle
          .statesOf(battle.inactiveTeam)
          .map((s) => s.lastActiveTriggerCategory)
          .whereType<TriggerCategory>()
          .toSet();
      final mirrored =
          usable.where((t) => opponentCategories.contains(t.category)).toList();
      if (mirrored.isNotEmpty) return byPower(mirrored).first;
    }

    switch (profile.abilityPriority) {
      case AiAbilityPriority.fixedOrder:
        return usable.first;

      case AiAbilityPriority.supportFirst:
        // Only "useful" support counts - a heal with nobody hurt, or a
        // buff everyone eligible already has, doesn't count, so the AI
        // doesn't loop forever re-applying a no-op instead of attacking
        // (this is exactly what let two support-heavy teams stalemate at
        // full health indefinitely before this check existed). The
        // Turtle opts out of this gate entirely (see
        // `AiProfile.ignoresSupportUsefulnessGate`) - it leans on
        // support to a fault, need or not.
        final supportCandidates = usable
            .where((t) =>
                t.targetAffiliation != TargetAffiliation.opponent &&
                (t.healAmount != null || t.inflictedStatusEffects.isNotEmpty))
            .toList();
        final usefulSupport = profile.ignoresSupportUsefulnessGate
            ? supportCandidates
            : supportCandidates
                .where((t) => _isSupportActionUseful(state, t, battle))
                .toList();
        return usefulSupport.isNotEmpty
            ? byPower(usefulSupport).first
            : byPower(usable).first;

      case AiAbilityPriority.debuffFocused:
        final debuffs =
            usable.where((t) => t.inflictedStatusEffects.isNotEmpty).toList();
        return debuffs.isNotEmpty
            ? byPower(debuffs).first
            : byPower(usable).first;

      case AiAbilityPriority.aoeFavoring:
        final aoe =
            usable.where((t) => t.attackSubtype == AttackSubtype.aoe).toList();
        if (aoe.isEmpty) return byPower(usable).first;
        if (!profile.aoeOnlyWhenMultipleInKillRange) return byPower(aoe).first;

        // The Sweeper: only actually reach for AOE once it's worth it -
        // at least two legal enemies predicted lethal from this hit -
        // otherwise focus fire like normal.
        final engine = battle.turnEngine;
        final livingEnemies = battle
            .statesOf(battle.inactiveTeam)
            .where((s) => s.isAlive)
            .toList();
        for (final candidate in byPower(aoe)) {
          final inKillRange = livingEnemies
              .where((t) =>
                  _predictedDamage(engine, state, t, candidate) >=
                  t.currentHealth)
              .length;
          if (inKillRange >= 2) return candidate;
        }
        return byPower(usable).first;

      case AiAbilityPriority.blackTriggerFavoring:
        final blackTriggerAbilities =
            usable.where((t) => _isBlackTriggerAbility(state, t)).toList();
        return blackTriggerAbilities.isNotEmpty
            ? byPower(blackTriggerAbilities).first
            : byPower(usable).first;

      case AiAbilityPriority.highestDamage:
        return byPower(usable).first;

      case AiAbilityPriority.adaptive:
        // The Prodigy: re-reads the board every ability choice instead
        // of committing to one fixed strategy - AOE once it'd hit
        // multiple enemies, debuff setup on an undebuffed enemy, else
        // whatever hits hardest.
        final aliveEnemyStates = battle
            .statesOf(battle.inactiveTeam)
            .where((s) => s.isAlive)
            .toList();
        if (aliveEnemyStates.length >= 2) {
          final aoe = usable
              .where((t) => t.attackSubtype == AttackSubtype.aoe)
              .toList();
          if (aoe.isNotEmpty) return byPower(aoe).first;
        }
        if (aliveEnemyStates.any((s) => s.statusEffects.isEmpty)) {
          final debuffs =
              usable.where((t) => t.inflictedStatusEffects.isNotEmpty).toList();
          if (debuffs.isNotEmpty) return byPower(debuffs).first;
        }
        return byPower(usable).first;
    }
  }

  /// Whether using [trigger] (a heal and/or buff, ally/self-targeted)
  /// would actually accomplish something worth skipping an attack for:
  /// a heal only counts once a recipient has taken meaningful damage
  /// (below 80% health, not merely "not literally full"), and a buff
  /// only counts if the recipient currently has *no* active status
  /// effects of its own at all - several short buffs with staggered
  /// expiries would otherwise always have exactly one due for a refresh,
  /// so "any single buff missing" would mean this character never
  /// attacks. Requiring a clean slate makes buff-chasing a periodic
  /// top-up between attacks instead of a permanent substitute for them.
  bool _isSupportActionUseful(
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    Battle battle,
  ) {
    final pool = trigger.targetAffiliation == TargetAffiliation.self
        ? [attacker]
        : battle.statesOf(battle.activeTeam);

    for (final candidate in pool) {
      if (!candidate.isAlive) continue;
      if (trigger.healAmount != null &&
          candidate.currentHealth <
              candidate.effectiveStats().maxHealth * 0.8) {
        return true;
      }
      if (trigger.inflictedStatusEffects.isNotEmpty &&
          candidate.statusEffects.isEmpty) {
        return true;
      }
    }
    return false;
  }

  /// Raw damage power plus a bonus for matching [AiProfile.
  /// preferredTriggerTags] - the same tags Loadout-building already
  /// favors also bias which usable ability this profile actually reaches
  /// for in battle (e.g. The Sharpshooter overvaluing Ranged/Burst
  /// options even when a weaker choice this turn).
  double _abilityPower(ActiveTrigger trigger) {
    final damage = trigger.damage;
    final hits =
        trigger.attackSubtype == AttackSubtype.burst ? trigger.hitsPerUse : 1;
    final damagePower = damage == null ? 0.0 : damage.average * hits;
    final matchedTags = _tagLookup
        .triggerTags(trigger)
        .intersection(profile.preferredTriggerTags)
        .length;
    return damagePower + matchedTags * 50;
  }

  /// Reads [t]'s health, or its predicted health during planning (see
  /// [planTurn]); with no overlay it is exactly the live value, so
  /// [takeTurn]'s behavior is unchanged.
  int _healthOf(CharacterBattleState t, Map<String, int>? predicted) =>
      predicted == null
          ? t.currentHealth
          : (predicted[t.combatantId] ?? t.currentHealth);

  bool _aliveOf(CharacterBattleState t, Map<String, int>? predicted) =>
      predicted == null
          ? t.isAlive
          : (predicted[t.combatantId] ?? t.currentHealth) > 0;

  List<CharacterBattleState> _chooseTargets(
    TurnEngine engine,
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    Battle battle,
    AiSkillClassConfig config, {
    Map<String, int>? predictedHealth,
    BattlePosition? fromPosition,
  }) {
    if (trigger.targetAffiliation == TargetAffiliation.self) {
      return [attacker];
    }

    final pool = trigger.targetAffiliation == TargetAffiliation.opponent
        ? battle.statesOf(battle.inactiveTeam)
        : battle.statesOf(battle.activeTeam);

    // The range band is part of legality, on ally-targeted abilities as much
    // as opponent-targeted ones. Without it the AI picks targets the engine
    // then silently drops at resolution, which spends Trion on nothing.
    final legal = pool
        .where((t) =>
            _aliveOf(t, predictedHealth) &&
            engine.canTarget(attacker, t,
                trigger: trigger, fromPosition: fromPosition))
        .toList();

    // Bail Out (#2): a body left on the board is worth destroying, because it
    // denies the enemy squad their Trion Salvage and pays for the action. But
    // it is never worth *trading* a live shot for, so this only looks once
    // nothing that can still fight back is in band. Item #7 owns weighing the
    // two properly; this is the floor that stops the opponent ignoring the
    // mechanic altogether.
    if (legal.isEmpty) {
      if (!TurnEngine.isAttackOnEnemy(trigger)) return const [];
      final bodies = pool
          .where((t) =>
              t.bailOutState == BailOutState.bailingOut &&
              engine.canTarget(attacker, t,
                  trigger: trigger, fromPosition: fromPosition))
          .toList();
      if (bodies.isEmpty) return const [];
      return bodies.take(trigger.targetCount).toList();
    }

    final isMistake = _isMistake(config);
    if (isMistake) {
      legal.shuffle(random);
    } else {
      switch (profile.targetPriority) {
        case AiTargetPriority.lowestHealth:
          legal.sort((a, b) => _healthOf(a, predictedHealth)
              .compareTo(_healthOf(b, predictedHealth)));
          break;
        case AiTargetPriority.matchupAware:
          if (config.matchupAwareEvaluation) {
            legal.sort((a, b) => _matchupScore(a, predictedHealth)
                .compareTo(_matchupScore(b, predictedHealth)));
          } else {
            legal.sort((a, b) => _healthOf(a, predictedHealth)
                .compareTo(_healthOf(b, predictedHealth)));
          }
          break;
        case AiTargetPriority.highestThreat:
          legal.sort((a, b) =>
              b.cumulativeDamageDealt.compareTo(a.cumulativeDamageDealt));
          break;
        case AiTargetPriority.firstAvailable:
          break;
        case AiTargetPriority.random:
          legal.shuffle(random);
          break;
      }
    }

    // The Berserker: once it's drawn blood from someone, it keeps
    // hitting that same target ahead of its normal priority - a no-op
    // for ally/self-targeted triggers, since `lastDamagedTargetId` is
    // always an opponent's id.
    if (profile.fixatesOnLastDamagedTarget && !isMistake) {
      final fixation =
          legal.where((t) => t.combatantId == attacker.lastDamagedTargetId);
      if (fixation.isNotEmpty) {
        final target = fixation.first;
        legal.remove(target);
        legal.insert(0, target);
      }
    }

    if (config.usesLookahead &&
        !isMistake &&
        trigger.damageType != null &&
        legal.length > 1) {
      _preferALethalTargetIfAvailable(
          engine, attacker, trigger, legal, predictedHealth);
    }

    final maxTargets = trigger.rangeTag.isAtRange
        ? engine.maxRangedTargets(attacker, trigger)
        : trigger.targetCount;
    return legal.take(maxTargets).toList();
  }

  /// Lower is a more attractive kill target: current health, softened by
  /// Armor/Defense (a high-Armor target with the same health is a worse
  /// use of this hit than a low-Armor one).
  double _matchupScore(CharacterBattleState t, Map<String, int>? predicted) {
    final stats = t.effectiveStats();
    return _healthOf(t, predicted) + stats.armor * 2 + stats.defense * 0.5;
  }

  /// Expert-only lookahead: if [trigger]'s predicted damage wouldn't
  /// finish off [legal]'s current top pick, but it would finish off some
  /// other legal target, move that target to the front instead - don't
  /// waste this hit on a target that survives it when a kill was
  /// available. Mutates [legal] in place; a no-op if the top pick is
  /// already predicted lethal or no other candidate is.
  void _preferALethalTargetIfAvailable(
    TurnEngine engine,
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    List<CharacterBattleState> legal,
    Map<String, int>? predictedHealth,
  ) {
    final topPick = legal.first;
    if (_predictedDamage(engine, attacker, topPick, trigger) >=
        _healthOf(topPick, predictedHealth)) {
      return;
    }
    for (final candidate in legal.skip(1)) {
      if (_predictedDamage(engine, attacker, candidate, trigger) >=
          _healthOf(candidate, predictedHealth)) {
        legal.remove(candidate);
        legal.insert(0, candidate);
        return;
      }
    }
  }

  /// A rough expected-damage estimate for [trigger] used by [attacker]
  /// against [target] - the dice expression's average, scaled by Team
  /// Spirit's damage bonus and any outgoing-damage perk/status
  /// multiplier, then mitigated by [target]'s Armor and damage-type
  /// multiplier/resistance. Assumes the hit lands (no miss-chance
  /// modeling) - a lookahead heuristic, not a full simulation.
  double _predictedDamage(
    TurnEngine engine,
    CharacterBattleState attacker,
    CharacterBattleState target,
    ActiveTrigger trigger,
  ) {
    final damage = trigger.damage;
    if (damage == null || trigger.damageType == null) return 0;

    final stats = attacker.effectiveStats();
    final bonuses = engine.teamSpiritCurve.bonusesFor(stats.teamSpirit);
    final isBurst = trigger.attackSubtype == AttackSubtype.burst;
    final damageBonus =
        isBurst ? bonuses.burstDamageBonus : bonuses.singleTargetDamageBonus;
    final hits = isBurst ? trigger.hitsPerUse : 1;

    final raw = damage.average *
        hits *
        (1 + damageBonus) *
        attacker.outgoingDamageMultiplier();
    final armor = target.effectiveStats().armor;
    final afterArmor = (raw - armor).clamp(0, double.infinity);
    final typeMultiplier =
        target.statusDamageTypeMultiplier(trigger.damageType!) *
            (target.hasDamageResistance(trigger.damageType!) ? 0.5 : 1.0);
    return afterArmor * typeMultiplier;
  }

  bool _shouldKeepChaining(
    Battle battle,
    Map<String, int> healthBefore,
    AbilityUseResult useResult,
  ) {
    switch (profile.fatPolicy) {
      case AiFatPolicy.alwaysChain:
        return true;
      case AiFatPolicy.neverVoluntary:
        return false;
      case AiFatPolicy.killOrTempoOnly:
        final securedKill = useResult.targetResults.any((r) {
          final before = healthBefore[r.targetCharacterId] ?? 0;
          return before > 0 && before - r.totalDamageDealt <= 0;
        });
        if (securedKill) return true;
        return _teamHealthFraction(battle, battle.activeTeam) >
            _teamHealthFraction(battle, battle.inactiveTeam);
    }
  }

  double _teamHealthFraction(Battle battle, Team team) {
    var current = 0;
    var max = 0;
    for (final s in battle.statesOf(team)) {
      current += s.currentHealth;
      max += s.effectiveStats().maxHealth;
    }
    return max == 0 ? 0 : current / max;
  }

  /// [_shouldKeepChaining]'s planning counterpart: evaluated against the
  /// predicted overlay ([planTurn]) rather than resolved results.
  bool _shouldKeepChainingPlanned(
    Battle battle,
    List<CharacterBattleState> targets,
    Map<String, int> predicted,
  ) {
    switch (profile.fatPolicy) {
      case AiFatPolicy.alwaysChain:
        return true;
      case AiFatPolicy.neverVoluntary:
        return false;
      case AiFatPolicy.killOrTempoOnly:
        final securedKill =
            targets.any((t) => (predicted[t.combatantId] ?? 1) <= 0);
        if (securedKill) return true;
        return _predictedTeamHealthFraction(
                battle, battle.activeTeam, predicted) >
            _predictedTeamHealthFraction(
                battle, battle.inactiveTeam, predicted);
    }
  }

  double _predictedTeamHealthFraction(
    Battle battle,
    Team team,
    Map<String, int> predicted,
  ) {
    var current = 0;
    var max = 0;
    for (final s in battle.statesOf(team)) {
      current += predicted[s.combatantId] ?? s.currentHealth;
      max += s.effectiveStats().maxHealth;
    }
    return max == 0 ? 0 : current / max;
  }
}

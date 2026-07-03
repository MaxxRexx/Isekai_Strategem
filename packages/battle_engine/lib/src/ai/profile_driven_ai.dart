import 'dart:math';

import '../engine/battle.dart';
import '../engine/character_battle_state.dart';
import '../engine/turn_engine.dart';
import '../models/team.dart';
import '../models/trigger.dart';
import 'ai_profile.dart';
import 'ai_skill_class.dart';
import 'rule_based_ai.dart';

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

  ProfileDrivenAi(this.profile, {Random? random}) : random = random ?? Random();

  List<AiActionResult> takeTurn(
    Battle battle, {
    required Map<String, List<ActiveTrigger>> equippedActiveTriggers,
  }) {
    final engine = battle.turnEngine;
    final config = profile.skillConfig;
    final results = <AiActionResult>[];

    for (final character in battle.activeTeam.characters) {
      final state = battle.states[character.id]!;
      if (!state.isAlive) continue;

      final triggers = equippedActiveTriggers[character.id] ?? const [];
      if (triggers.isEmpty) continue;

      final unusableThisTurn = <String>{};
      while (true) {
        final usable = triggers
            .where((t) =>
                !unusableThisTurn.contains(t.id) &&
                engine.canUseAbility(state, t))
            .toList();
        if (usable.isEmpty) break;

        final trigger = _chooseAbility(state, usable, config);
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
          for (final t in targets) t.character.id: t.currentHealth
        };
        final useResult = engine.resolveAbilityUse(
          attacker: state,
          trigger: trigger,
          targets: targets,
        );
        results.add(AiActionResult(
          characterId: character.id,
          triggerId: trigger.id,
          useResult: useResult,
        ));

        if (battle.isOver) return results;

        if (!_shouldKeepChaining(battle, healthBefore, useResult)) break;
      }
    }

    return results;
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
  ) {
    if (_isMistake(config)) {
      return usable[random.nextInt(usable.length)];
    }

    List<ActiveTrigger> byPower(List<ActiveTrigger> pool) {
      final sorted = List.of(pool)
        ..sort((a, b) => _abilityPower(b).compareTo(_abilityPower(a)));
      return sorted;
    }

    switch (profile.abilityPriority) {
      case AiAbilityPriority.fixedOrder:
        return usable.first;

      case AiAbilityPriority.supportFirst:
        final support = usable
            .where((t) =>
                t.targetAffiliation != TargetAffiliation.opponent &&
                (t.healAmount != null || t.inflictedStatusEffects.isNotEmpty))
            .toList();
        return support.isNotEmpty
            ? byPower(support).first
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
        return aoe.isNotEmpty ? byPower(aoe).first : byPower(usable).first;

      case AiAbilityPriority.blackTriggerFavoring:
        final blackTriggerAbilities =
            usable.where((t) => _isBlackTriggerAbility(state, t)).toList();
        return blackTriggerAbilities.isNotEmpty
            ? byPower(blackTriggerAbilities).first
            : byPower(usable).first;

      case AiAbilityPriority.highestDamage:
        return byPower(usable).first;
    }
  }

  double _abilityPower(ActiveTrigger trigger) {
    final damage = trigger.damage;
    if (damage == null) return 0;
    final hits =
        trigger.attackSubtype == AttackSubtype.burst ? trigger.hitsPerUse : 1;
    return damage.average * hits;
  }

  List<CharacterBattleState> _chooseTargets(
    TurnEngine engine,
    CharacterBattleState attacker,
    ActiveTrigger trigger,
    Battle battle,
    AiSkillClassConfig config,
  ) {
    if (trigger.targetAffiliation == TargetAffiliation.self) {
      return [attacker];
    }

    final pool = trigger.targetAffiliation == TargetAffiliation.opponent
        ? battle.inactiveTeam.characters.map((c) => battle.states[c.id]!)
        : battle.activeTeam.characters.map((c) => battle.states[c.id]!);

    final legal = pool
        .where((t) =>
            t.isAlive &&
            (trigger.targetAffiliation != TargetAffiliation.opponent ||
                engine.canTarget(attacker, t)))
        .toList();
    if (legal.isEmpty) return const [];

    if (_isMistake(config)) {
      legal.shuffle(random);
    } else {
      switch (profile.targetPriority) {
        case AiTargetPriority.lowestHealth:
          legal.sort((a, b) => a.currentHealth.compareTo(b.currentHealth));
          break;
        case AiTargetPriority.matchupAware:
          if (config.matchupAwareEvaluation) {
            legal.sort((a, b) => _matchupScore(a).compareTo(_matchupScore(b)));
          } else {
            legal.sort((a, b) => a.currentHealth.compareTo(b.currentHealth));
          }
          break;
        case AiTargetPriority.highestThreat:
          legal.sort((a, b) =>
              b.effectiveStats().attack.compareTo(a.effectiveStats().attack));
          break;
        case AiTargetPriority.firstAvailable:
          break;
        case AiTargetPriority.random:
          legal.shuffle(random);
          break;
      }
    }

    final maxTargets = trigger.rangeTag == RangeTag.ranged
        ? engine.maxRangedTargets(attacker, trigger)
        : trigger.targetCount;
    return legal.take(maxTargets).toList();
  }

  /// Lower is a more attractive kill target: current health, softened by
  /// Armor/Defense (a high-Armor target with the same health is a worse
  /// use of this hit than a low-Armor one).
  double _matchupScore(CharacterBattleState t) {
    final stats = t.effectiveStats();
    return t.currentHealth + stats.armor * 2 + stats.defense * 0.5;
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
    for (final c in team.characters) {
      final s = battle.states[c.id]!;
      current += s.currentHealth;
      max += s.effectiveStats().maxHealth;
    }
    return max == 0 ? 0 : current / max;
  }
}

import '../engine/battle.dart';
import '../engine/character_battle_state.dart';
import '../engine/turn_engine.dart';
import '../models/trigger.dart';

/// One ability use the AI decided to make, and its resolution.
class AiActionResult {
  final String characterId;
  final String triggerId;
  final AbilityUseResult useResult;

  const AiActionResult({
    required this.characterId,
    required this.triggerId,
    required this.useResult,
  });
}

/// A simple rule-based opponent: no learning, no lookahead, just a fixed
/// priority order applied fresh each ability use.
///
/// Decisions baked in here (flagged as defaults, not confirmed against a
/// specific design brief - tune/replace freely):
/// - **Ability choice**: among currently-usable equipped active abilities,
///   prefer the highest-scoring damaging one (roughly "expected damage per
///   use", so Burst's multiple hits count for more than a single-hit
///   ability with the same per-hit average); if none of the character's
///   usable abilities deal damage, fall back to the first usable one (a
///   status/support ability).
/// - **Targeting**: opponent-targeting abilities focus-fire the lowest
///   current-health legal target(s) (`TurnEngine.canTarget`-filtered, e.g.
///   respecting Charmed); ally-targeting abilities (heals/buffs) are
///   pointed at the lowest-health living ally, self-targeting abilities
///   always target the user.
/// - **Full Arms Trigger**: not a separate choice - `TurnEngine`'s own
///   FAT roll already decided whether extra abilities are available this
///   turn (`FatEngine.canUseAnotherAbility`); this AI simply keeps acting
///   with the same priority order until the character runs out of usable
///   abilities or affordable Trion, rather than voluntarily stopping
///   early to avoid the multi-ability cooldown/Trion Affinity penalty.
/// - **Loadout**: out of scope - each character's currently equipped
///   active abilities must be supplied by the caller via
///   [equippedActiveTriggers] (e.g. from a pre-authored enemy roster);
///   this class never builds a Loadout itself.
class RuleBasedAi {
  const RuleBasedAi();

  /// Acts for every living member of [battle]'s currently active team,
  /// in team order, each character using as many of its usable equipped
  /// abilities as the turn allows (1, or up to 3 if FAT triggers for
  /// them). Stops immediately if the battle ends mid-turn. Does not call
  /// [Battle.startTurn]/[Battle.endTurn] - the caller drives the overall
  /// turn lifecycle; this only fills in the "which ability, which target"
  /// decisions in between.
  List<AiActionResult> takeTurn(
    Battle battle, {
    required Map<String, List<ActiveTrigger>> equippedActiveTriggers,
  }) {
    final engine = battle.turnEngine;
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

        final trigger = _chooseAbility(usable);
        final targets = _chooseTargets(engine, state, trigger, battle);
        if (targets.isEmpty) {
          unusableThisTurn.add(trigger.id);
          continue;
        }

        if (!engine.useAbility(state, trigger, battle.activeTeamPool)) {
          unusableThisTurn.add(trigger.id);
          continue;
        }

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
      }
    }

    return results;
  }

  ActiveTrigger _chooseAbility(List<ActiveTrigger> usable) {
    final damaging = usable.where((t) => t.damageType != null).toList()
      ..sort((a, b) => _abilityPower(b).compareTo(_abilityPower(a)));
    if (damaging.isNotEmpty) return damaging.first;
    return usable.first;
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
        .toList()
      ..sort((a, b) => a.currentHealth.compareTo(b.currentHealth));

    if (legal.isEmpty) return const [];

    final maxTargets = trigger.rangeTag == RangeTag.ranged
        ? engine.maxRangedTargets(attacker, trigger)
        : trigger.targetCount;

    return legal.take(maxTargets).toList();
  }
}

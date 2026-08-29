// Counts what actually happens to Bail Out windows over a batch of real
// AI-vs-AI battles, so item #2's central question is answered from play rather
// than from argument.
//
//   dart run tool/bail_out_sim.dart [--seed N] [--battles N]
//
// The question: **is the Trion Salvage ever collected?** The rule is that any
// landed hit destroys a body, so an area attack aimed at a living enemy on the
// same line clears the body for free. That is intended (where you fall
// matters), but if it means the Salvage is denied nearly every time then the
// reward is decoration and the contested half of the item never happens.
//
// Every source of chance is drawn from the seed, so a number printed here can
// be reproduced.
import 'dart:math';

import 'package:battle_engine/battle_engine.dart';

class _Draft {
  final Team team;
  final Map<String, CharacterBattleState> states;
  final Map<String, List<ActiveTrigger>> equipped;
  const _Draft(this.team, this.states, this.equipped);
}

_Draft draft(String teamId, List<String> ids, AiProfile profile) {
  const builder = LoadoutBuilder();
  final characters = ids.map((id) => CharacterRoster.defaultRoster[id]).toList();
  final states = <String, CharacterBattleState>{};
  final equipped = <String, List<ActiveTrigger>>{};
  for (final character in characters) {
    final loadout = builder.build(
      character,
      activeTriggerPool: TriggerCatalog.defaultCatalog.activeTriggers,
      passiveTriggerPool: TriggerCatalog.defaultCatalog.passiveTriggers,
      blackTriggerPool: BlackTriggerCatalog.defaultCatalog.all,
      profile: profile,
    );
    // The Black Trigger's own actives count toward the Loadout rule and are
    // usable in battle, so they belong in the equipped list (the app's draft
    // says the same). Item 4b found four tools dropping them, which under-arms
    // every squad they simulate.
    final actives = [
      ...loadout.triggers.whereType<ActiveTrigger>(),
      ...?loadout.blackTrigger?.activeAbilities,
    ];
    states[character.id] = CharacterBattleState(
      character,
      equippedPassiveEffects: loadout.triggers
          .whereType<PassiveTrigger>()
          .map((t) => t.effect)
          .toList(),
      equippedTriggerIds: actives.map((t) => t.id).toList(),
      position: startingPositionFor(actives.map((t) => t.rangeTag)),
    );
    equipped[character.id] = actives;
  }
  return _Draft(Team(id: teamId, characters: characters), states, equipped);
}

String pct(num part, num whole) =>
    whole == 0 ? '  n/a' : '${(part / whole * 100).round()}%';

void main(List<String> args) {
  int intArg(String name, int fallback) {
    final i = args.indexOf('--$name');
    if (i < 0 || i + 1 >= args.length) return fallback;
    return int.tryParse(args[i + 1]) ?? fallback;
  }

  final battles = intArg('battles', 200);
  final seed = intArg('seed', 20260814);
  final roster = CharacterRoster.defaultRoster.all.map((c) => c.id).toList();
  final profiles = AiProfile.all;
  final random = Random(seed);

  var opened = 0;
  var recalled = 0;
  var destroyed = 0;
  var openAtEnd = 0;
  var defeatedOutright = 0;
  var salvageBanked = 0;
  var salvageDenied = 0;
  var paidToAttackers = 0;

  print('== Bail Out over $battles AI vs AI battles (seed $seed) ==');

  for (var i = 0; i < battles; i++) {
    final pool = [...roster]..shuffle(random);
    final aProfile = profiles[random.nextInt(profiles.length)];
    final bProfile = profiles[random.nextInt(profiles.length)];
    final a = draft('team-a', pool.take(3).toList(), aProfile);
    final b = draft('team-b', pool.skip(3).take(3).toList(), bProfile);
    final dice = Random(seed * 1000003 + i);
    final battle = Battle(
      teamA: a.team,
      teamB: b.team,
      states: {...a.states, ...b.states},
      turnEngine: TurnEngine(
        combatEngine: CombatEngine(diceRoller: DiceRoller(dice)),
        statusEffectEngine: StatusEffectEngine(diceRoller: DiceRoller(dice)),
        trionGainEngine: TrionGainEngine(diceRoller: DiceRoller(dice)),
        fatEngine: FatEngine(diceRoller: DiceRoller(dice)),
      ),
    );
    final aiA = ProfileDrivenAi(aProfile, random: dice);
    final aiB = ProfileDrivenAi(bProfile, random: dice);

    final everBailed = <String>{};

    for (var turn = 0; turn < 400; turn++) {
      if (battle.isOver) break;
      final active = battle.isTeamATurn ? a : b;
      final ai = battle.isTeamATurn ? aiA : aiB;
      battle.startTurn(equippedActiveTriggers: active.equipped);
      if (battle.isOver) break;
      ai.takeTurn(battle, equippedActiveTriggers: active.equipped);
      for (final state in battle.states.values) {
        if (state.bailOutState != BailOutState.none) {
          everBailed.add(state.character.id);
        }
      }
      if (battle.isOver) break;
      final settled = battle.endTurn();
      for (final r in settled.bailOuts) {
        if (!r.refused) salvageBanked += r.trionSalvaged;
      }
    }

    for (final state in battle.states.values) {
      final config = battle.turnEngine.bailOutConfig;
      final capacity = state.character.baseStats.trionCapacity;
      switch (state.bailOutState) {
        case BailOutState.recalled:
          opened++;
          recalled++;
        case BailOutState.destroyed:
          opened++;
          destroyed++;
          salvageDenied += config.salvageFor(capacity);
          paidToAttackers += config.attackerGainFor(capacity);
        case BailOutState.bailingOut:
          opened++;
          openAtEnd++;
        case BailOutState.none:
          if (!state.isAlive) defeatedOutright++;
      }
    }
    everBailed.clear();
  }

  void line(String label, Object value) =>
      print('  ${label.padRight(38)}$value');

  print('');
  line('windows opened', opened);
  line('  recalled, Salvage banked',
      '$recalled (${pct(recalled, opened)} of windows)');
  line('  body destroyed, Salvage denied',
      '$destroyed (${pct(destroyed, opened)} of windows)');
  line('  still open when the battle ended', openAtEnd);
  line('defeated with no window at all', defeatedOutright);
  print('');
  line('Trion banked as Salvage', salvageBanked);
  line('Trion denied by destroyed bodies', salvageDenied);
  line('Trion paid to attackers for bodies', paidToAttackers);
  print('');
  print('  A window that is neither recalled nor destroyed was still open');
  print('  when the battle ended, which is the ordinary way a losing squad');
  print('  runs out of members. Only the first two lines are a contest.');
}

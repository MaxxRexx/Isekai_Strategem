// Prints a balance report over the live catalogs and roster: the numbers a
// tuning pass actually needs to look at, computed from the content itself
// rather than transcribed by hand.
//
//   dart run tool/balance_report.dart
//
// The three things it reports on:
//
//  - Accuracy band. Every Attack and Defense modifier in the roster, and the
//    hit rate the best and worst matchups produce. Bounded accuracy wants the
//    typical gap to sit inside the d20's range, so the die decides a real
//    share of the outcome.
//  - Dice share. For each damaging Trigger, how much of its average damage
//    comes from its dice rather than its flat bonus. Target is 40-50%.
//  - Value. Average damage across all targets and hits per point of Trion,
//    scaled by a cooldown factor, so outliers stand out against the median.
//
// It then plays a batch of real AI-vs-AI battles and reports how long they
// run and how often attacks land, because the catalog numbers on their own
// do not tell you whether the fight is any good.
import 'dart:math';

import 'package:battle_engine/battle_engine.dart';

/// Cooldown factor from the design-director synthesis: a short cooldown is
/// worth more than the same damage on a long one, because you get it more
/// often.
double cooldownFactor(int cooldownTurns) => switch (cooldownTurns) {
      <= 1 => 1.5,
      2 => 1.0,
      3 => 0.8,
      _ => 0.7,
    };

/// Probability that an attacker with modifier advantage [gap] beats a
/// defender in the opposed d20 contest (ties go to the attacker).
double hitChance(int gap) {
  var wins = 0;
  for (var a = 1; a <= 20; a++) {
    for (var d = 1; d <= 20; d++) {
      if (a + gap >= d) wins++;
    }
  }
  return wins / 400;
}

double diceAverage(DiceExpression d) => d.count * (d.sides + 1) / 2;

String pct(double fraction) => '${(fraction * 100).round()}%';

String pad(String s, int width) =>
    s.length >= width ? s : s + ' ' * (width - s.length);

String padLeft(String s, int width) =>
    s.length >= width ? s : ' ' * (width - s.length) + s;

void reportAccuracyBand() {
  print('== Accuracy band ==');
  final attacks = <int>[];
  final defenses = <int>[];
  for (final c in CharacterRoster.defaultRoster.all) {
    attacks.add(c.baseStats.attack);
    defenses.add(c.baseStats.defense);
  }
  attacks.sort();
  defenses.sort();
  final minGap = attacks.first - defenses.last;
  final maxGap = attacks.last - defenses.first;
  print('Attack  ${attacks.first}..${attacks.last} '
      '(median ${attacks[attacks.length ~/ 2]})');
  print('Defense ${defenses.first}..${defenses.last} '
      '(median ${defenses[defenses.length ~/ 2]})');
  print('Worst matchup: gap $minGap -> ${pct(hitChance(minGap))} to hit');
  print('Best  matchup: gap $maxGap -> ${pct(hitChance(maxGap))} to hit');
  print('Even matchup:  gap 0 -> ${pct(hitChance(0))} to hit');
  print('');

  print('Per character (attack / defense):');
  final sorted = CharacterRoster.defaultRoster.all.toList()
    ..sort((a, b) => b.baseStats.attack.compareTo(a.baseStats.attack));
  for (final c in sorted) {
    print('  ${pad(c.name, 20)} ${pad(c.type.name, 8)} '
        'atk ${padLeft('${c.baseStats.attack}', 3)}   '
        'def ${padLeft('${c.baseStats.defense}', 3)}');
  }
  print('');
}

void reportTrigger(ActiveTrigger t, {String prefix = ''}) {
  final damage = t.damage;
  if (damage == null) return;
  final average = damage.average;
  final share = diceAverage(damage) / average;
  final payload = average * t.targetCount * t.hitsPerUse;
  final value = t.trionCost == 0
      ? double.infinity
      : payload / t.trionCost * cooldownFactor(t.cooldownTurns);
  final spread = '${damage.count * damage.sides + damage.flatBonus}';
  print('  ${pad('$prefix${t.id}', 24)} '
      '${pad(damage.toString(), 10)} '
      'avg ${padLeft(average.toStringAsFixed(1), 5)}  '
      'max ${padLeft(spread, 4)}  '
      'dice ${padLeft(pct(share), 4)}  '
      'tc ${t.targetCount} x${t.hitsPerUse}  '
      'payload ${padLeft(payload.toStringAsFixed(0), 4)}  '
      'trion ${padLeft('${t.trionCost}', 3)}  '
      'cd ${t.cooldownTurns}  '
      'value ${value.toStringAsFixed(2)}');
}

void reportDamageCatalog() {
  print('== Trigger damage (dice share target 40-50%) ==');
  final damaging = TriggerCatalog.defaultCatalog.activeTriggers
      .where((t) => t.damage != null)
      .toList()
    ..sort((a, b) => b.damage!.average.compareTo(a.damage!.average));
  for (final t in damaging) {
    reportTrigger(t);
  }
  print('');

  print('== Black Trigger damage ==');
  for (final bt in BlackTriggerCatalog.defaultCatalog.all) {
    for (final t in bt.activeAbilities) {
      reportTrigger(t);
    }
  }
  print('');

  final shares = damaging
      .map((t) => diceAverage(t.damage!) / t.damage!.average)
      .toList()
    ..sort();
  final values = damaging
      .where((t) => t.trionCost > 0)
      .map((t) =>
          t.damage!.average *
          t.targetCount *
          t.hitsPerUse /
          t.trionCost *
          cooldownFactor(t.cooldownTurns))
      .toList()
    ..sort();
  print('Dice share: min ${pct(shares.first)}, '
      'median ${pct(shares[shares.length ~/ 2])}, max ${pct(shares.last)}');
  print('Value: min ${values.first.toStringAsFixed(2)}, '
      'median ${values[values.length ~/ 2].toStringAsFixed(2)}, '
      'max ${values.last.toStringAsFixed(2)}');
}

/// Wires a drafted [Loadout] into a battle-ready state the way a host app
/// does: passives folded in, the Black Trigger's World ability attached, and
/// the Black Trigger baked onto the Character so resonance applies. Mirrors
/// the same setup in test/integration/full_battle_simulation_test.dart.
CharacterBattleState buildBattleState(Character character, Loadout loadout) {
  final passiveEffects = <PassiveEffect>[
    for (final t in loadout.triggers.whereType<PassiveTrigger>()) t.effect,
    if (loadout.blackTrigger != null)
      for (final p in loadout.blackTrigger!.passiveAbilities) p.effect,
  ];
  return CharacterBattleState(
    Character(
      id: character.id,
      name: character.name,
      type: character.type,
      baseStats: character.baseStats,
      damageResistances: character.damageResistances,
      statusInvulnerabilities: character.statusInvulnerabilities,
      blackTrigger: loadout.blackTrigger,
      sideEffect: character.sideEffect,
    ),
    equippedPassiveEffects: passiveEffects,
    worldAbility: loadout.blackTrigger?.worldAbility,
    // Start where this Loadout can actually operate: a Close Range kit at
    // the Front, a sniper's kit at the Back. Without this everyone would
    // open at Middle, two squads would stand 2 apart, and every Close Range
    // ability in the game would be unusable on turn one.
    position: startingPositionFor(
      loadout.triggers.whereType<ActiveTrigger>().map((t) => t.rangeTag),
    ),
  );
}

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
    states[character.id] = buildBattleState(character, loadout);
    equipped[character.id] = loadout.triggers.whereType<ActiveTrigger>().toList();
  }
  return _Draft(Team(id: teamId, characters: characters), states, equipped);
}

void reportSimulation({int battles = 200, int seed = 20260814}) {
  print('== Simulated battles ($battles AI vs AI, seed $seed) ==');
  final roster = CharacterRoster.defaultRoster.all.map((c) => c.id).toList();
  final profiles = AiProfile.all;
  final random = Random(seed);

  final rounds = <int>[];
  var attackRolls = 0;
  var attackHits = 0;
  var crits = 0;
  var unresolved = 0;

  for (var i = 0; i < battles; i++) {
    final pool = [...roster]..shuffle(random);
    final aProfile = profiles[random.nextInt(profiles.length)];
    final bProfile = profiles[random.nextInt(profiles.length)];
    final a = draft('team-a', pool.take(3).toList(), aProfile);
    final b = draft('team-b', pool.skip(3).take(3).toList(), bProfile);
    // Every source of chance in the battle is drawn from the one seed, so a
    // pacing number printed here can be reproduced later. Without this only
    // the matchups were seeded and the dice were not, which made two runs of
    // the same seed disagree about the tail.
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

    var concluded = false;
    for (var turn = 0; turn < 400; turn++) {
      if (battle.isOver) {
        concluded = true;
        break;
      }
      final active = battle.isTeamATurn ? a : b;
      final ai = battle.isTeamATurn ? aiA : aiB;
      battle.startTurn(equippedActiveTriggers: active.equipped);
      if (battle.isOver) {
        concluded = true;
        break;
      }
      final results = ai.takeTurn(battle,
          equippedActiveTriggers: active.equipped);
      for (final result in results) {
        for (final target in result.useResult.targetResults) {
          for (final roll in target.attackRolls) {
            attackRolls++;
            if (roll.isHit) attackHits++;
            if (roll.isCriticalHit) crits++;
          }
        }
      }
      if (battle.isOver) {
        concluded = true;
        break;
      }
      battle.endTurn();
    }
    if (concluded) {
      rounds.add(battle.roundNumber);
    } else {
      unresolved++;
    }
  }

  rounds.sort();
  if (rounds.isEmpty) {
    print('No battle concluded - something is badly wrong.');
    return;
  }
  final mean = rounds.reduce((a, b) => a + b) / rounds.length;
  int percentile(double p) => rounds[(rounds.length * p).floor().clamp(
        0,
        rounds.length - 1,
      )];
  print('Rounds: min ${rounds.first}, p25 ${percentile(0.25)}, '
      'median ${percentile(0.5)}, p75 ${percentile(0.75)}, '
      'p90 ${percentile(0.90)}, max ${rounds.last} '
      '(mean ${mean.toStringAsFixed(1)})');
  // The design target is a band, 8 to 20 rounds (design section 11): under it
  // somebody was deleted before they got to play, over it nobody's damage is
  // keeping up. Judge it on the middle of the distribution, since the tails
  // are matchups rather than pacing.
  const targetLow = 8;
  const targetHigh = 20;
  final inBand = rounds.where((r) => r >= targetLow && r <= targetHigh).length;
  final median = percentile(0.5);
  print('Pacing target $targetLow-$targetHigh rounds: '
      'median $median (${median < targetLow ? 'FAST' : median > targetHigh ? 'SLOW' : 'in band'}), '
      '${pct(inBand / rounds.length)} of battles inside the band');
  print('Unresolved after 400 turns: $unresolved');
  print('Attack rolls: $attackRolls, '
      'hit rate ${pct(attackHits / attackRolls)}, '
      'crit rate ${pct(crits / attackRolls)}');
}

/// `dart run tool/balance_report.dart [--seed N] [--battles N] [--sim-only]`
///
/// The seed is an argument rather than a constant because a pacing claim made
/// from one batch of 200 is one sample, and the questions this tool gets asked
/// (does a change move the median, does it move the tail) need several. Four
/// runs on four seeds is what items 1b and #2 were both measured with.
void main(List<String> args) {
  int intArg(String name, int fallback) {
    final i = args.indexOf('--$name');
    if (i < 0 || i + 1 >= args.length) return fallback;
    return int.tryParse(args[i + 1]) ?? fallback;
  }

  if (!args.contains('--sim-only')) {
    reportAccuracyBand();
    reportDamageCatalog();
  }
  reportSimulation(
    battles: intArg('battles', 200),
    seed: intArg('seed', 20260814),
  );
}

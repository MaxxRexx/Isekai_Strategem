// Item 4b: why a minority of battles run past the 8-20 round pacing band.
//
//   dart run tool/long_battle_diagnosis.dart [--battles N] [--seeds a,b,c,d]
//
// `balance_report.dart` reports the shape of the distribution; it does not say
// what the long battles are made of. This plays the same batch, with the same drafts
// and the same dice, and records what each battle spent its rounds doing, so
// the long ones can be compared against the ordinary ones rather than
// guessed at.
//
// The spec named two suspects: two sustain-heavy squads out-healing each
// other, or a Trion-starved pair trading single cheap abilities. Both are
// measured here, along with a third the range bands made possible: a turn
// where nobody on the acting side can reach anybody at all.
//
// Every turn is classified into exactly one of four kinds:
//
//  - **acted**: the AI used at least one ability.
//  - **repositioned**: no ability, but somebody moved a line. Reposition
//    costs the action, so this is a spent turn that deals no damage.
//  - **idle**: no ability and nobody moved, split by what was missing -
//    Trion, reach, both, or neither (the AI simply passed).
//
// Health is measured by watching every character's health across the whole
// turn (start, actions, end), so status ticks and regeneration count as the
// damage and healing they are, rather than only what an ability's result
// happened to report.
import 'dart:math';

import 'package:battle_engine/battle_engine.dart';

import 'balance_report.dart'
    show Draft, draft, hitChance, pct, pad, padLeft;

/// Everything one battle spent its rounds doing.
class BattleTrace {
  final int seed;
  final int index;
  BattleTrace(this.seed, this.index);

  int rounds = 0;
  int turns = 0;
  bool resolved = false;
  String profileA = '';
  String profileB = '';
  List<String> squadA = const [];
  List<String> squadB = const [];

  int startHealth = 0;
  int damage = 0;
  int healing = 0;

  int actions = 0;
  int actedTurns = 0;
  int repositionTurns = 0;
  int idleCooldown = 0;
  int idleNoTrion = 0;
  int idleNoReach = 0;
  int idlePassed = 0;

  int trionIncome = 0;
  int trionSpent = 0;
  int poolSum = 0;
  int poolSamples = 0;

  int attackRolls = 0;
  int attackHits = 0;
  int attackingActions = 0;

  int healTriggers = 0;
  int equippedTriggers = 0;

  /// How many of the two squads went into this battle with no equipped
  /// active Trigger that deals damage at all: 0, 1 or 2.
  int squadsThatCannotDealDamage = 0;

  /// Item #4 proposes cutting a battle off at 30 rounds and awarding it to
  /// whoever is ahead on health. For a battle that ran past 30, this is who
  /// that tiebreak would have handed it to, against who actually won.
  BattleOutcome? tiebreakAtThirty;
  BattleOutcome outcome = BattleOutcome.ongoing;

  int unreachableTurns = 0;
  int zeroDamageTurns = 0;
  int longestZeroDamageRun = 0;

  /// Mean accuracy gap of the matchup: each squad's mean Attack against the
  /// other's mean Defense, averaged. Negative means the defenders are ahead.
  double accuracyGap = 0;

  int get idleTurns => idleCooldown + idleNoTrion + idleNoReach + idlePassed;
  double get attackRollsPerTurn => turns == 0 ? 0 : attackRolls / turns;
  double get damagePerRound => rounds == 0 ? 0 : damage / rounds;
  double get healingPerRound => rounds == 0 ? 0 : healing / rounds;
  double get healingShare => damage == 0 ? 0 : healing / damage;
  double get actionsPerTurn => turns == 0 ? 0 : actions / turns;
  double get meanPool => poolSamples == 0 ? 0 : poolSum / poolSamples;
  double get hitRate => attackRolls == 0 ? 0 : attackHits / attackRolls;
  String get matchup => '$profileA vs $profileB';
}

/// The distance from [state] to the nearest enemy it could reach with
/// anything it has equipped, or null when nothing it carries reaches anyone.
///
/// Screening is included, because a target two bodies deep is genuinely out
/// of reach even when the raw geometry says otherwise.
bool canReachAnyEnemy(
  CharacterBattleState state,
  List<CharacterBattleState> enemies,
  List<ActiveTrigger> equipped,
) {
  final onBoard = enemies.where((e) => e.isAlive).toList();
  if (onBoard.isEmpty) return false;
  final squad = onBoard.map((e) => e.position).toList();
  for (final enemy in onBoard) {
    final distance = BattleDistance.betweenEnemies(
      state.position,
      enemy.position,
      targetSquad: squad,
    );
    for (final trigger in equipped) {
      if (trigger.rangeTag.reaches(distance)) return true;
    }
  }
  return false;
}

BattleTrace playOne(
  int seed,
  int index,
  Random matchupRandom, {
  required bool blackTriggerActives,
}) {
  final trace = BattleTrace(seed, index);
  final roster = CharacterRoster.defaultRoster.all.map((c) => c.id).toList();
  final profiles = AiProfile.all;

  final pool = [...roster]..shuffle(matchupRandom);
  final aProfile = profiles[matchupRandom.nextInt(profiles.length)];
  final bProfile = profiles[matchupRandom.nextInt(profiles.length)];
  final a = draft('team-a', pool.take(3).toList(), aProfile,
      includeBlackTriggerActives: blackTriggerActives);
  final b = draft('team-b', pool.skip(3).take(3).toList(), bProfile,
      includeBlackTriggerActives: blackTriggerActives);
  trace.profileA = aProfile.name;
  trace.profileB = bProfile.name;
  trace.squadA = a.team.characters.map((c) => c.name).toList();
  trace.squadB = b.team.characters.map((c) => c.name).toList();

  double meanAttack(Draft d) =>
      meanOf(d.team.characters.map((c) => c.baseStats.attack));
  double meanDefense(Draft d) =>
      meanOf(d.team.characters.map((c) => c.baseStats.defense));
  trace.accuracyGap =
      ((meanAttack(a) - meanDefense(b)) + (meanAttack(b) - meanDefense(a))) / 2;

  for (final side in [a, b]) {
    var damaging = 0;
    for (final entry in side.equipped.entries) {
      trace.equippedTriggers += entry.value.length;
      trace.healTriggers +=
          entry.value.where((t) => t.healAmount != null).length;
      damaging += entry.value.where((t) => t.damage != null).length;
    }
    if (damaging == 0) trace.squadsThatCannotDealDamage++;
  }

  // The same dice derivation as balance_report, so battle N of a seed here is
  // battle N of the same seed there.
  final dice = Random(seed * 1000003 + index);
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

  final everyone = [...battle.statesOf(a.team), ...battle.statesOf(b.team)];
  trace.startHealth =
      everyone.fold(0, (sum, s) => sum + s.character.baseStats.maxHealth);

  var zeroRun = 0;
  for (var turn = 0; turn < 400; turn++) {
    if (battle.isOver) {
      trace.resolved = true;
      break;
    }
    final active = battle.isTeamATurn ? a : b;
    final enemyStates = battle.statesOf(
      battle.isTeamATurn ? b.team : a.team,
    );
    final activeStates = battle.statesOf(active.team);

    if (trace.tiebreakAtThirty == null && battle.roundNumber > 30) {
      final healthA = battle
          .statesOf(a.team)
          .fold<int>(0, (sum, s) => sum + max(0, s.currentHealth));
      final healthB = battle
          .statesOf(b.team)
          .fold<int>(0, (sum, s) => sum + max(0, s.currentHealth));
      trace.tiebreakAtThirty = healthA > healthB
          ? BattleOutcome.teamAWins
          : healthB > healthA
              ? BattleOutcome.teamBWins
              : BattleOutcome.draw;
    }

    final healthBefore = {for (final s in everyone) s: s.currentHealth};
    final poolBefore = active.team.trionPool.current;

    battle.startTurn(equippedActiveTriggers: active.equipped);
    if (battle.isOver) {
      trace.resolved = true;
      break;
    }
    trace.turns++;
    final poolAtDecision = active.team.trionPool.current;
    trace.trionIncome += poolAtDecision - poolBefore;
    trace.poolSum += poolAtDecision;
    trace.poolSamples++;

    final positionsBefore = {for (final s in activeStates) s: s.position};
    final reachable = activeStates
        .where((s) => s.isAlive)
        .any((s) => canReachAnyEnemy(
              s,
              enemyStates,
              active.equipped[s.character.id] ?? const [],
            ));
    if (!reachable) trace.unreachableTurns++;

    final ai = battle.isTeamATurn ? aiA : aiB;
    final results = ai.takeTurn(
      battle,
      equippedActiveTriggers: active.equipped,
    );
    trace.actions += results.length;
    for (final result in results) {
      if (result.useResult.targetResults
          .any((t) => t.attackRolls.isNotEmpty)) {
        trace.attackingActions++;
      }
      for (final target in result.useResult.targetResults) {
        for (final roll in target.attackRolls) {
          trace.attackRolls++;
          if (roll.isHit) trace.attackHits++;
        }
      }
    }
    trace.trionSpent += poolAtDecision - active.team.trionPool.current;

    if (results.isNotEmpty) {
      trace.actedTurns++;
    } else if (activeStates.any((s) => s.position != positionsBefore[s])) {
      trace.repositionTurns++;
    } else {
      // Nothing happened. Say what was missing, using the pool as it stood
      // when the AI had to choose. Cooldown and Trion are asked separately:
      // "nothing affordable" reads as poverty when the real answer is often
      // that every ability the squad owns is still cooling down.
      var anyOffCooldown = false;
      var anyAffordable = false;
      for (final s in activeStates.where((s) => s.isAlive)) {
        for (final t in active.equipped[s.character.id] ?? const []) {
          if (!battle.turnEngine.canUseAbility(s, t)) continue;
          anyOffCooldown = true;
          final cost = (t.trionCost * s.trionCostMultiplier()).round();
          if (cost <= poolAtDecision) anyAffordable = true;
        }
      }
      if (!anyOffCooldown) {
        trace.idleCooldown++;
      } else if (!anyAffordable) {
        trace.idleNoTrion++;
      } else if (!reachable) {
        trace.idleNoReach++;
      } else {
        trace.idlePassed++;
      }
    }

    if (battle.isOver) {
      trace.resolved = true;
      break;
    }
    battle.endTurn();

    var turnDamage = 0;
    for (final s in everyone) {
      final delta = s.currentHealth - healthBefore[s]!;
      if (delta < 0) {
        trace.damage += -delta;
        turnDamage += -delta;
      } else {
        trace.healing += delta;
      }
    }
    if (turnDamage == 0) {
      trace.zeroDamageTurns++;
      zeroRun++;
      if (zeroRun > trace.longestZeroDamageRun) {
        trace.longestZeroDamageRun = zeroRun;
      }
    } else {
      zeroRun = 0;
    }
  }
  trace.rounds = battle.roundNumber;
  trace.outcome = battle.outcome;
  return trace;
}

String bucketOf(BattleTrace t) {
  if (!t.resolved) return 'unresolved';
  if (t.rounds < 8) return 'under 8';
  if (t.rounds <= 20) return '8-20 (band)';
  if (t.rounds <= 30) return '21-30';
  return 'over 30';
}

const bucketOrder = ['under 8', '8-20 (band)', '21-30', 'over 30', 'unresolved'];

double meanOf(Iterable<num> xs) {
  final list = xs.toList();
  if (list.isEmpty) return 0;
  return list.fold<num>(0, (a, b) => a + b) / list.length;
}

void reportBuckets(List<BattleTrace> traces) {
  print('== What the rounds were spent on, by battle length ==');
  print('');
  print('${pad('Bucket', 14)}${padLeft('n', 4)}  '
      '${padLeft('rounds', 7)}  ${padLeft('dmg/rd', 7)}  '
      '${padLeft('heal/rd', 8)}  ${padLeft('heal%', 6)}  '
      '${padLeft('act/turn', 9)}  ${padLeft('idle%', 6)}  '
      '${padLeft('repos%', 7)}  ${padLeft('pool', 6)}  ${padLeft('hit%', 5)}');
  for (final bucket in bucketOrder) {
    final group = traces.where((t) => bucketOf(t) == bucket).toList();
    if (group.isEmpty) continue;
    final turns = group.fold<int>(0, (s, t) => s + t.turns);
    final idle = group.fold<int>(0, (s, t) => s + t.idleTurns);
    final repos = group.fold<int>(0, (s, t) => s + t.repositionTurns);
    print('${pad(bucket, 14)}${padLeft('${group.length}', 4)}  '
        '${padLeft(meanOf(group.map((t) => t.rounds)).toStringAsFixed(1), 7)}  '
        '${padLeft(meanOf(group.map((t) => t.damagePerRound)).toStringAsFixed(1), 7)}  '
        '${padLeft(meanOf(group.map((t) => t.healingPerRound)).toStringAsFixed(1), 8)}  '
        '${padLeft(pct(meanOf(group.map((t) => t.healingShare)).toDouble()), 6)}  '
        '${padLeft(meanOf(group.map((t) => t.actionsPerTurn)).toStringAsFixed(2), 9)}  '
        '${padLeft(pct(turns == 0 ? 0 : idle / turns), 6)}  '
        '${padLeft(pct(turns == 0 ? 0 : repos / turns), 7)}  '
        '${padLeft(meanOf(group.map((t) => t.meanPool)).toStringAsFixed(1), 6)}  '
        '${padLeft(pct(meanOf(group.map((t) => t.hitRate)).toDouble()), 5)}');
  }
  print('');
  print('dmg/rd and heal/rd are health lost and health regained per round, '
      'across both squads.');
  print('heal% is healing as a share of damage. act/turn counts abilities '
      'used per turn.');
  print('idle% is turns that used no ability and moved nobody; repos% is '
      'turns spent moving.');
  print('');
}

void reportIdleBreakdown(List<BattleTrace> traces) {
  print('== Why an idle turn was idle ==');
  print('');
  print('${pad('Bucket', 14)}${padLeft('turns', 7)}  ${padLeft('idle', 6)}  '
      '${padLeft('cooldown', 9)}  ${padLeft('no Trion', 9)}  '
      '${padLeft('no reach', 9)}  ${padLeft('passed', 7)}  '
      '${padLeft('unreachable', 12)}');
  for (final bucket in bucketOrder) {
    final group = traces.where((t) => bucketOf(t) == bucket).toList();
    if (group.isEmpty) continue;
    int sum(int Function(BattleTrace) f) => group.fold(0, (s, t) => s + f(t));
    final turns = sum((t) => t.turns);
    print('${pad(bucket, 14)}${padLeft('$turns', 7)}  '
        '${padLeft('${sum((t) => t.idleTurns)}', 6)}  '
        '${padLeft('${sum((t) => t.idleCooldown)}', 9)}  '
        '${padLeft('${sum((t) => t.idleNoTrion)}', 9)}  '
        '${padLeft('${sum((t) => t.idleNoReach)}', 9)}  '
        '${padLeft('${sum((t) => t.idlePassed)}', 7)}  '
        '${padLeft(pct(turns == 0 ? 0 : sum((t) => t.unreachableTurns) / turns), 12)}');
  }
  print('');
  print('"unreachable" is the share of all turns on which nobody on the '
      'acting side could reach any enemy');
  print('with anything they had equipped, whether or not they ended up '
      'acting.');
  print('');
}

void reportDraftDefect(List<BattleTrace> traces) {
  print('== Squads drafted with nothing that deals damage ==');
  print('');
  final affected =
      traces.where((t) => t.squadsThatCannotDealDamage > 0).toList();
  final both = traces.where((t) => t.squadsThatCannotDealDamage == 2).toList();
  final clean = traces.where((t) => t.squadsThatCannotDealDamage == 0).toList();
  print('Battles with at least one such squad: ${affected.length} of '
      '${traces.length} (${pct(affected.length / traces.length)}).');
  print('Battles where both squads are like that: ${both.length}.');
  if (affected.isEmpty || clean.isEmpty) {
    print('');
    return;
  }
  print('Mean rounds: ${meanOf(clean.map((t) => t.rounds)).toStringAsFixed(1)} '
      'when both squads can deal damage, against '
      '${meanOf(affected.map((t) => t.rounds)).toStringAsFixed(1)} when at '
      'least one cannot.');
  if (both.isNotEmpty) {
    print('When neither can: '
        '${meanOf(both.map((t) => t.rounds)).toStringAsFixed(1)} rounds.');
  }
  final longCount = affected.where((t) => !t.resolved || t.rounds > 20).length;
  final cleanLong = clean.where((t) => !t.resolved || t.rounds > 20).length;
  print('${pct(longCount / affected.length)} of them run past 20 rounds, against '
      '${pct(cleanLong / clean.length)} of the rest.');
  final profiles = <String, int>{};
  for (final t in affected) {
    for (final p in [t.profileA, t.profileB]) {
      profiles[p] = (profiles[p] ?? 0) + 1;
    }
  }
  final names = profiles.keys.toList()
    ..sort((a, b) => profiles[b]!.compareTo(profiles[a]!));
  print('AI profiles in those battles, most common first: '
      '${names.take(6).map((n) => '$n (${profiles[n]})').join(', ')}.');
  print('');
}

void reportRoundLimit(List<BattleTrace> traces) {
  print('== What a 30-round limit with a health tiebreak would decide ==');
  print('');
  final past = traces.where((t) => t.tiebreakAtThirty != null).toList();
  print('Battles still running at round 30: ${past.length} of '
      '${traces.length} (${pct(past.length / traces.length)}).');
  if (past.isEmpty) {
    print('');
    return;
  }
  final decided = past.where((t) => t.outcome != BattleOutcome.ongoing).toList();
  final agree =
      decided.where((t) => t.tiebreakAtThirty == t.outcome).length;
  final draws =
      past.where((t) => t.tiebreakAtThirty == BattleOutcome.draw).length;
  print('Of the ${decided.length} that went on to finish on their own, the '
      'health leader at round 30');
  print('went on to win $agree of them '
      '(${pct(agree / decided.length)}), so the limit would have '
      'reversed ${decided.length - agree}.');
  print('Level on health at round 30, so the tiebreak decides nothing: '
      '$draws.');
  print('');
}

void reportByGap(List<BattleTrace> traces) {
  print('== Battle length against the matchup\'s accuracy gap ==');
  print('');
  print('${pad('Gap', 8)}${padLeft('n', 5)}  ${padLeft('rounds', 7)}  '
      '${padLeft('over 20', 8)}  ${padLeft('hit%', 6)}  '
      '${padLeft('expected', 9)}  ${padLeft('dmg/rd', 7)}');
  final byGap = <int, List<BattleTrace>>{};
  for (final t in traces) {
    byGap.putIfAbsent(t.accuracyGap.round(), () => []).add(t);
  }
  final gaps = byGap.keys.toList()..sort();
  for (final gap in gaps) {
    final group = byGap[gap]!;
    final long = group.where((t) => !t.resolved || t.rounds > 20).length;
    print('${pad(gap > 0 ? '+$gap' : '$gap', 8)}${padLeft('${group.length}', 5)}  '
        '${padLeft(meanOf(group.map((t) => t.rounds)).toStringAsFixed(1), 7)}  '
        '${padLeft(pct(long / group.length), 8)}  '
        '${padLeft(pct(meanOf(group.map((t) => t.hitRate)).toDouble()), 6)}  '
        '${padLeft(pct(hitChance(gap)), 9)}  '
        '${padLeft(meanOf(group.map((t) => t.damagePerRound)).toStringAsFixed(1), 7)}');
  }
  print('');
  print('"expected" is the opposed-d20 hit chance for that gap, as '
      'balance_report computes it.');
  print('');
}

void reportCharacters(List<BattleTrace> traces) {
  print('== Who is in the long battles ==');
  print('');
  final appearances = <String, int>{};
  final longAppearances = <String, int>{};
  for (final t in traces) {
    final isLong = !t.resolved || t.rounds > 20;
    for (final name in [...t.squadA, ...t.squadB]) {
      appearances[name] = (appearances[name] ?? 0) + 1;
      if (isLong) longAppearances[name] = (longAppearances[name] ?? 0) + 1;
    }
  }
  final baseline = traces.where((t) => !t.resolved || t.rounds > 20).length /
      traces.length;
  final stats = {
    for (final c in CharacterRoster.defaultRoster.all) c.name: c.baseStats,
  };
  final names = appearances.keys.toList()
    ..sort((a, b) {
      final ra = (longAppearances[a] ?? 0) / appearances[a]!;
      final rb = (longAppearances[b] ?? 0) / appearances[b]!;
      return rb.compareTo(ra);
    });
  print('${pad('Character', 20)}${padLeft('atk', 4)}  ${padLeft('def', 4)}  '
      '${padLeft('battles', 8)}  ${padLeft('long', 8)}  '
      '${padLeft('rate', 6)}  ${padLeft('vs base', 8)}');
  for (final name in names) {
    final rate = (longAppearances[name] ?? 0) / appearances[name]!;
    print('${pad(name, 20)}'
        '${padLeft('${stats[name]?.attack ?? 0}', 4)}  '
        '${padLeft('${stats[name]?.defense ?? 0}', 4)}  '
        '${padLeft('${appearances[name]}', 8)}  '
        '${padLeft('${longAppearances[name] ?? 0}', 8)}  '
        '${padLeft(pct(rate), 6)}  '
        '${padLeft('${(rate / baseline).toStringAsFixed(2)}x', 8)}');
  }
  print('');
  print('Baseline: ${pct(baseline)} of battles run past 20 rounds. '
      '"vs base" is how much more often');
  print('a battle containing that character does.');
  print('');
}

void reportLongest(List<BattleTrace> traces, {int count = 12}) {
  final sorted = [...traces]..sort((a, b) {
      if (a.resolved != b.resolved) return a.resolved ? 1 : -1;
      return b.rounds.compareTo(a.rounds);
    });
  print('== The ${min(count, sorted.length)} longest battles ==');
  print('');
  for (final t in sorted.take(count)) {
    print('seed ${t.seed} #${t.index}: '
        '${t.resolved ? '${t.rounds} rounds' : 'UNRESOLVED (${t.rounds} rounds)'}, '
        '${t.matchup}');
    print('    damage ${t.damage} (${t.damagePerRound.toStringAsFixed(1)}/rd), '
        'healing ${t.healing} (${t.healingPerRound.toStringAsFixed(1)}/rd, '
        '${pct(t.healingShare)} of damage), '
        'start HP ${t.startHealth}');
    print('    turns ${t.turns}: acted ${t.actedTurns}, '
        'repositioned ${t.repositionTurns}, '
        'idle ${t.idleTurns} '
        '(cooldown ${t.idleCooldown}, no Trion ${t.idleNoTrion}, '
        'no reach ${t.idleNoReach}, passed ${t.idlePassed})');
    print('    Trion: income ${t.trionIncome}, spent ${t.trionSpent}, '
        'mean pool at decision ${t.meanPool.toStringAsFixed(1)}; '
        'heal triggers equipped ${t.healTriggers}/${t.equippedTriggers}');
    print('    attack rolls ${t.attackRolls} '
        '(${t.attackRollsPerTurn.toStringAsFixed(1)}/turn, '
        '${t.attackingActions}/${t.actions} actions were attacks), '
        'hit rate ${pct(t.hitRate)}');
    print('    zero-damage turns ${t.zeroDamageTurns}/${t.turns}, '
        'longest run ${t.longestZeroDamageRun}; '
        'accuracy gap ${t.accuracyGap.toStringAsFixed(1)} '
        '-> ${pct(hitChance(t.accuracyGap.round()))} expected to hit');
    print('    ${t.squadA.join(', ')}  vs  ${t.squadB.join(', ')}');
  }
  print('');
}

void reportDrivers(List<BattleTrace> traces) {
  print('== What separates a long battle from an ordinary one ==');
  print('');
  final band = traces
      .where((t) => t.resolved && t.rounds >= 8 && t.rounds <= 20)
      .toList();
  final long = traces.where((t) => !t.resolved || t.rounds > 20).toList();
  if (band.isEmpty || long.isEmpty) {
    print('Not enough of one group to compare.');
    return;
  }
  void row(String label, double Function(BattleTrace) f, {bool asPct = false}) {
    final inBand = meanOf(band.map(f));
    final inLong = meanOf(long.map(f));
    final ratio = inBand == 0 ? double.nan : inLong / inBand;
    String fmt(double v) => asPct ? pct(v) : v.toStringAsFixed(2);
    print('${pad(label, 34)}${padLeft(fmt(inBand), 10)}  '
        '${padLeft(fmt(inLong), 10)}  '
        '${padLeft(ratio.isNaN ? '-' : '${ratio.toStringAsFixed(2)}x', 8)}');
  }

  print('${pad('', 34)}${padLeft('8-20', 10)}  ${padLeft('over 20', 10)}  '
      '${padLeft('ratio', 8)}');
  row('rounds', (t) => t.rounds.toDouble());
  row('damage per round', (t) => t.damagePerRound);
  row('healing per round', (t) => t.healingPerRound);
  row('healing as share of damage', (t) => t.healingShare, asPct: true);
  row('abilities used per turn', (t) => t.actionsPerTurn);
  row('mean Trion pool at decision', (t) => t.meanPool);
  row('Trion income per turn',
      (t) => t.turns == 0 ? 0 : t.trionIncome / t.turns);
  row('Trion spent per turn',
      (t) => t.turns == 0 ? 0 : t.trionSpent / t.turns);
  row('idle turns', (t) => t.turns == 0 ? 0 : t.idleTurns / t.turns,
      asPct: true);
  row('reposition turns',
      (t) => t.turns == 0 ? 0 : t.repositionTurns / t.turns, asPct: true);
  row('turns with nobody in reach',
      (t) => t.turns == 0 ? 0 : t.unreachableTurns / t.turns, asPct: true);
  row('turns dealing no damage',
      (t) => t.turns == 0 ? 0 : t.zeroDamageTurns / t.turns, asPct: true);
  row('longest no-damage run (turns)',
      (t) => t.longestZeroDamageRun.toDouble());
  row('hit rate', (t) => t.hitRate, asPct: true);
  row('attack rolls per turn', (t) => t.attackRollsPerTurn);
  row('attacks as share of actions',
      (t) => t.actions == 0 ? 0 : t.attackingActions / t.actions, asPct: true);
  row('matchup accuracy gap', (t) => t.accuracyGap);
  row('healing triggers equipped', (t) => t.healTriggers.toDouble());
  row('starting health, both squads', (t) => t.startHealth.toDouble());
  print('');
}

void main(List<String> args) {
  int intArg(String name, int fallback) {
    final i = args.indexOf('--$name');
    if (i < 0 || i + 1 >= args.length) return fallback;
    return int.tryParse(args[i + 1]) ?? fallback;
  }

  final battles = intArg('battles', 200);
  final seedsIndex = args.indexOf('--seeds');
  final seeds = seedsIndex >= 0 && seedsIndex + 1 < args.length
      ? args[seedsIndex + 1].split(',').map(int.parse).toList()
      : const [20260814, 20260815, 20260816, 20260817];

  final blackTriggerActives =
      !args.contains('--drop-black-trigger-actives');

  final traces = <BattleTrace>[];
  for (final seed in seeds) {
    final matchupRandom = Random(seed);
    for (var i = 0; i < battles; i++) {
      traces.add(playOne(seed, i, matchupRandom,
          blackTriggerActives: blackTriggerActives));
    }
  }

  print('== Item 4b: why some battles run long ==');
  print('${traces.length} battles, $battles per seed, '
      'seeds ${seeds.join(', ')}');
  print(blackTriggerActives
      ? "Equipped list: the Loadout's actives plus the Black Trigger's own "
          'actives (what the app hands the AI).'
      : "Equipped list: the Loadout's actives only (what the simulator "
          'handed the AI before 4b).');
  print('');

  final resolved = traces.where((t) => t.resolved).toList();
  final rounds = resolved.map((t) => t.rounds).toList()..sort();
  int percentile(double p) =>
      rounds[(rounds.length * p).floor().clamp(0, rounds.length - 1)];
  final inBand = rounds.where((r) => r >= 8 && r <= 20).length;
  print('Rounds: min ${rounds.first}, p25 ${percentile(0.25)}, '
      'median ${percentile(0.5)}, p75 ${percentile(0.75)}, '
      'p90 ${percentile(0.90)}, p99 ${percentile(0.99)}, max ${rounds.last} '
      '(mean ${meanOf(rounds).toStringAsFixed(1)})');
  print('Inside the 8-20 band: ${pct(inBand / rounds.length)}. '
      'Over 20: ${rounds.where((r) => r > 20).length}. '
      'Over 30: ${rounds.where((r) => r > 30).length}. '
      'Unresolved after 400 turns: ${traces.length - resolved.length}.');
  print('');

  reportDraftDefect(traces);
  reportBuckets(traces);
  reportIdleBreakdown(traces);
  reportDrivers(traces);
  reportRoundLimit(traces);
  reportByGap(traces);
  reportCharacters(traces);
  reportLongest(traces);
}

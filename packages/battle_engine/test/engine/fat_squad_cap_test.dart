import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// A [Random] whose percent rolls always come up, so every character's Full
/// Arms Trigger roll succeeds and the draw between them is the only thing
/// left to observe. [nextInt] returns a scripted sequence, which is what the
/// draw uses.
class _AlwaysTriggers implements Random {
  final List<int> picks;
  int _i = 0;
  _AlwaysTriggers([this.picks = const [0]]);

  @override
  int nextInt(int max) => picks[_i++ % picks.length] % max;

  @override
  double nextDouble() => 0.0;

  @override
  bool nextBool() => true;
}

/// Item #4's Full Arms Trigger cap: **one character per squad may have FAT on
/// a turn**.
///
/// Everybody still rolls for it, and several of them may come up. One of
/// those winners is then drawn at random, and is the only one who gets it.
/// The others have an ordinary turn: one action, cooldowns untouched, no
/// lockout, because as far as they are concerned it never triggered.
void main() {
  Battle battleWith(Random random) {
    final engine = TurnEngine(
      fatEngine: FatEngine(diceRoller: DiceRoller(random)),
    );
    return Battle(
      turnEngine: engine,
      teamA: Team(id: 'a', characters: [
        testCharacter(id: 'a-1', stats: testStats(fatChance: 100)),
        testCharacter(id: 'a-2', stats: testStats(fatChance: 100)),
        testCharacter(id: 'a-3', stats: testStats(fatChance: 100)),
      ]),
      teamB: Team(id: 'b', characters: [
        testCharacter(id: 'b-1'),
        testCharacter(id: 'b-2'),
        testCharacter(id: 'b-3'),
      ]),
    );
  }

  test('when the whole squad rolls it, exactly one of them gets it', () {
    final battle = battleWith(_AlwaysTriggers());
    final result = battle.startTurn();

    final winners =
        result.fatTriggered.entries.where((e) => e.value).map((e) => e.key);
    expect(winners, hasLength(1));

    final withFat = battle
        .statesOf(battle.teamA)
        .where((s) => s.fatTriggeredThisTurn);
    expect(withFat, hasLength(1),
        reason: 'the states must agree with what the log reported');
  });

  test('the one who gets it may use up to three abilities', () {
    final battle = battleWith(_AlwaysTriggers());
    battle.startTurn();
    final holder =
        battle.statesOf(battle.teamA).firstWhere((s) => s.fatTriggeredThisTurn);

    expect(battle.turnEngine.fatEngine.maxAbilitiesThisTurn(holder), 3);
  });

  test('everybody else has an ordinary turn, with one action', () {
    final battle = battleWith(_AlwaysTriggers());
    battle.startTurn();

    final others = battle
        .statesOf(battle.teamA)
        .where((s) => !s.fatTriggeredThisTurn)
        .toList();
    expect(others, hasLength(2));
    for (final state in others) {
      expect(battle.turnEngine.fatEngine.maxAbilitiesThisTurn(state), 1);
    }
  });

  test('a character who loses the draw keeps their cooldowns', () {
    final battle = battleWith(_AlwaysTriggers());
    for (final state in battle.statesOf(battle.teamA)) {
      state.cooldowns['some_ability'] = 2;
    }

    battle.startTurn();

    for (final state in battle.statesOf(battle.teamA)) {
      if (state.fatTriggeredThisTurn) {
        expect(state.cooldowns, isEmpty,
            reason: 'the one who got it has theirs cleared, as FAT always did');
      } else {
        expect(state.cooldowns['some_ability'], 2,
            reason: 'losing the draw must not cost them their cooldowns, '
                'which is the whole reason the draw happens before the grant');
      }
    }
  });

  test('a character who loses the draw is not locked out of FAT either', () {
    final battle = battleWith(_AlwaysTriggers());
    battle.startTurn();

    for (final state in battle.statesOf(battle.teamA)) {
      if (state.fatTriggeredThisTurn) {
        expect(state.fatCooldownRemaining, greaterThan(0));
      } else {
        expect(state.fatCooldownRemaining, 0,
            reason: 'they never triggered it, so nothing should lock out');
      }
    }
  });

  test('the draw is random, not the first in turn order', () {
    // Three members, so a draw of index 2 must land on the third of them.
    final battle = battleWith(_AlwaysTriggers([2]));
    battle.startTurn();

    final holder =
        battle.statesOf(battle.teamA).firstWhere((s) => s.fatTriggeredThisTurn);
    expect(holder.combatantId, contains('a-3'));
  });

  test('one winner needs no draw', () {
    // Only the second character can trigger at all, so there is nothing to
    // draw between and the roll must not consume one.
    final battle = battleWith(_AlwaysTriggers());
    final states = battle.statesOf(battle.teamA);
    states[0].fatCooldownRemaining = 2;
    states[2].fatCooldownRemaining = 2;

    battle.startTurn();

    expect(states[1].fatTriggeredThisTurn, isTrue);
    expect(states[0].fatTriggeredThisTurn, isFalse);
    expect(states[2].fatTriggeredThisTurn, isFalse);
  });

  test('next turn it is up for grabs again, on the same rules as ever', () {
    // The whole change is "one per turn instead of two or three". Nothing
    // carries across turns beyond the per-character lockout FAT always had,
    // so a character who lost the draw is a candidate again immediately.
    final battle = battleWith(_AlwaysTriggers([0]));
    final states = battle.statesOf(battle.teamA);

    battle.startTurn();
    final firstHolder = states.firstWhere((s) => s.fatTriggeredThisTurn);
    final losers = states.where((s) => !s.fatTriggeredThisTurn).toList();
    for (final loser in losers) {
      expect(loser.canTriggerFat, isTrue,
          reason: 'losing the draw must not cost them anything');
    }
    battle.endTurn(); // team A ends
    battle.startTurn(); // team B
    battle.endTurn();

    battle.startTurn(); // team A again
    final secondHolder = states.firstWhere((s) => s.fatTriggeredThisTurn);

    expect(states.where((s) => s.fatTriggeredThisTurn), hasLength(1),
        reason: 'still exactly one, turn after turn');
    expect(secondHolder.combatantId, isNot(firstHolder.combatantId),
        reason: 'the one who took it is locked out, as FAT always locked out, '
            'so it goes to somebody who qualified this turn');
  });

  test('nobody rolling it means nobody gets it', () {
    final battle = Battle(
      turnEngine: TurnEngine(
        fatEngine: FatEngine(diceRoller: DiceRoller(const FixedRandom(99))),
      ),
      teamA: Team(id: 'a', characters: [
        testCharacter(id: 'a-1', stats: testStats(fatChance: 0)),
        testCharacter(id: 'a-2', stats: testStats(fatChance: 0)),
        testCharacter(id: 'a-3', stats: testStats(fatChance: 0)),
      ]),
      teamB: Team(id: 'b', characters: [
        testCharacter(id: 'b-1'),
        testCharacter(id: 'b-2'),
        testCharacter(id: 'b-3'),
      ]),
    );

    final result = battle.startTurn();
    expect(result.fatTriggered.values, everyElement(isFalse));
  });
}

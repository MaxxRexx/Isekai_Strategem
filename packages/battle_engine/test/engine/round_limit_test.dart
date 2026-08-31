import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Item #4's round limit: a battle nobody has won by the end of round 30 is
/// awarded to whoever is ahead on total remaining health.
///
/// Measured rather than picked. `tool/long_battle_diagnosis.dart` found 21 of
/// 800 battles still running at round 30, of which the health leader went on
/// to win 17, so the limit reverses 4 results in 800 and none of them level
/// on health. What it is not for is shortening battles: 4b showed the long
/// ones are an accuracy problem, and this cuts off 3% of them.
void main() {
  Battle freshBattle({int maxRounds = 30}) => Battle(
        teamA: Team(id: 'a', characters: [
          testCharacter(id: 'a-1'),
          testCharacter(id: 'a-2'),
          testCharacter(id: 'a-3'),
        ]),
        teamB: Team(id: 'b', characters: [
          testCharacter(id: 'b-1'),
          testCharacter(id: 'b-2'),
          testCharacter(id: 'b-3'),
        ]),
        roundLimitConfig: RoundLimitConfig(maxRounds: maxRounds),
      );

  test('a battle inside the limit is still ongoing, level or not', () {
    final battle = freshBattle();
    battle.roundNumber = 30;

    expect(battle.roundLimitReached, isFalse,
        reason: 'round 30 is being played, not finished');
    expect(battle.outcome, BattleOutcome.ongoing);
  });

  test('past the limit it goes to the squad ahead on health', () {
    final battle = freshBattle();
    battle.roundNumber = 31;
    battle.statesOf(battle.teamB).first.currentHealth -= 1;

    expect(battle.roundLimitReached, isTrue);
    expect(battle.outcome, BattleOutcome.teamAWins);
    expect(battle.isOver, isTrue);
    expect(battle.endedOnRoundLimit, isTrue);
  });

  test('level on health past the limit is a draw', () {
    final battle = freshBattle();
    battle.roundNumber = 31;

    expect(battle.outcome, BattleOutcome.draw);
    expect(battle.endedOnRoundLimit, isTrue);
  });

  test('a defeat still outranks the limit, so a wipe reads as a wipe', () {
    final battle = freshBattle();
    battle.roundNumber = 31;
    // Team A is ahead on health and would win the tiebreak, but team A is
    // the side that got wiped out, so the tiebreak must not be consulted.
    for (final s in battle.statesOf(battle.teamA)) {
      s.currentHealth = 0;
    }

    expect(battle.outcome, BattleOutcome.teamBWins);
    expect(battle.endedOnRoundLimit, isFalse,
        reason: 'this was won, not timed out');
  });

  test('health below zero counts as none, not as a negative', () {
    final battle = freshBattle();
    battle.roundNumber = 31;
    // One of A's is well past dead; without clamping, A would lose a battle
    // its living member is winning.
    final a = battle.statesOf(battle.teamA);
    for (final s in a) {
      s.currentHealth = 0;
    }
    a.first.currentHealth = -500;
    a.last.currentHealth = 10;
    for (final s in battle.statesOf(battle.teamB)) {
      s.currentHealth = 1;
    }

    expect(battle.remainingHealthOf(battle.teamA), 10);
    expect(battle.outcome, BattleOutcome.teamAWins);
  });

  test('the limit is configurable, and the default is the game rule', () {
    expect(RoundLimitConfig.defaults.maxRounds, 30);

    final short = freshBattle(maxRounds: 5);
    short.roundNumber = 6;
    expect(short.roundLimitReached, isTrue);
  });
}

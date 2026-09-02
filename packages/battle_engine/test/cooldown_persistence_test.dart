import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// A [Random] that always returns the maximum value, so [DiceRoller.rollPercent]
/// yields 100 and [FatEngine] never triggers FAT. Without this the test flakes:
/// a randomly-triggered FAT clears the caster's cooldowns (the very thing under
/// test), turning an expected `1` into `null`.
class _NoFatRandom implements Random {
  const _NoFatRandom();
  @override
  int nextInt(int max) => max - 1;
  @override
  double nextDouble() => 0.9999999;
  @override
  bool nextBool() => true;
}

/// Locks in the cooldown timing that Play mode relies on: a used ability's
/// cooldown is applied at the caster's *end of turn* and only ticks down on
/// that same team's own subsequent turns, so a 1-turn cooldown blocks the
/// ability through the opponent's turn AND the caster's own next turn.
void main() {
  final roster = CharacterRoster.defaultRoster;
  final catalog = TriggerCatalog.defaultCatalog;
  // Item #4 moved the cooldowns by range band: Mid pays in tempo, so nothing
  // there sits at 1 any more. Close is the fast band, and this test needs an
  // ability with a 1-turn cooldown, not a particular ability.
  final slash = // cooldownTurns: 1
      catalog['shatterpoint'] as ActiveTrigger;
  final volley = // cooldownTurns: 2
      catalog['twin_fang_strike'] as ActiveTrigger;

  Battle freshBattle() => Battle(
    // Deterministic FAT (never triggers) so a stray FAT proc can't clear the
    // cooldown this test is asserting on.
    turnEngine: TurnEngine(
      fatEngine: FatEngine(diceRoller: DiceRoller(_NoFatRandom())),
    ),
    teamA: Team(
      id: 'a',
      characters: [
        roster['vela_ashworth'],
        roster['kaito_reyes'],
        roster['dross'],
      ],
    ),
    teamB: Team(
      id: 'b',
      characters: [
        roster['nadia_kessler'],
        roster['sable_whitlock'],
        roster['rurik_voss'],
      ],
    ),
  );

  /// The battle these tests want: nothing standing between the caster and the
  /// ability except its cooldown, which is what they are about. Item #15 put
  /// Trion Types in the way as well, and those arrive on a roll.
  Battle stockedBattle() {
    final battle = freshBattle();
    stockEveryTrionType(battle.teamA);
    stockEveryTrionType(battle.teamB);
    return battle;
  }

  // Advances a full round: the opponent's turn (no action) then team A's turn
  // (no action), so team A's cooldowns tick exactly once per round.
  void advanceFullRound(Battle b) {
    b.startTurn(); // team B
    b.endTurn();
    b.startTurn(); // team A
    b.endTurn();
  }

  test('a 1-turn cooldown blocks the ability through the next own turn', () {
    final battle = stockedBattle();
    final vela = battle.states['vela_ashworth']!;
    final engine = battle.turnEngine;

    battle.startTurn();
    vela.recordAbilityUse(slash);
    // The cooldown is not set until end of turn (Play mode spends Trion at
    // queue time but defers cooldowns to resolution/end of turn).
    expect(vela.cooldowns['shatterpoint'] ?? 0, 0);

    battle.endTurn(); // team A ends -> cooldown now applies.
    expect(vela.cooldowns['shatterpoint'], 1);
    expect(engine.canUseAbility(vela, slash), isFalse);

    // Opponent's turn passes; the caster is still on cooldown on its own
    // next turn.
    battle.startTurn(); // team B
    battle.endTurn();
    battle.startTurn(); // team A, the caster's next turn
    expect(vela.cooldowns['shatterpoint'], 1);
    expect(engine.canUseAbility(vela, slash), isFalse);

    // Only after ending that own turn does it clear.
    battle.endTurn();
    expect(vela.cooldowns['shatterpoint'] ?? 0, 0);
    battle.startTurn();
    expect(engine.canUseAbility(vela, slash), isTrue);
  });

  test('a 2-turn cooldown blocks two of the caster\'s own turns', () {
    final battle = stockedBattle();
    final vela = battle.states['vela_ashworth']!;
    final engine = battle.turnEngine;

    battle.startTurn();
    vela.recordAbilityUse(volley);
    battle.endTurn();
    expect(vela.cooldowns['twin_fang_strike'], 2);

    advanceFullRound(battle); // caster's own turn ticks it once
    expect(vela.cooldowns['twin_fang_strike'], 1);
    expect(engine.canUseAbility(vela, volley), isFalse);

    advanceFullRound(battle);
    expect(vela.cooldowns['twin_fang_strike'] ?? 0, 0);
    battle.startTurn();
    expect(engine.canUseAbility(vela, volley), isTrue);
  });
}

import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group('FatEngine.rollTrigger', () {
    test('cannot roll while on FAT cooldown', () {
      final engine = FatEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      state.fatCooldownRemaining = 2;

      final triggered = engine.rollTrigger(state, 100);
      expect(triggered, isFalse);
      expect(state.fatTriggeredThisTurn, isFalse);
    });

    test('100% chance always triggers when off cooldown', () {
      final engine = FatEngine(diceRoller: DiceRoller(Random(2)));
      final state = CharacterBattleState(testCharacter());
      expect(engine.rollTrigger(state, 100), isTrue);
      expect(state.fatTriggeredThisTurn, isTrue);
    });

    test('0% chance never triggers', () {
      final engine = FatEngine(diceRoller: DiceRoller(Random(2)));
      final state = CharacterBattleState(testCharacter());
      for (var i = 0; i < 50; i++) {
        expect(engine.rollTrigger(state, 0), isFalse);
      }
    });

    test('triggering clears all existing cooldowns', () {
      final engine = FatEngine(diceRoller: DiceRoller(Random(2)));
      final state = CharacterBattleState(testCharacter());
      state.cooldowns['ability-a'] = 3;
      state.cooldowns['ability-b'] = 1;

      engine.rollTrigger(state, 100);

      expect(state.cooldowns, isEmpty);
    });

    test('triggering sets fatCooldownRemaining to the configured base', () {
      const config = FatConfig(baseFatCooldownTurns: 4);
      final engine =
          FatEngine(config: config, diceRoller: DiceRoller(Random(2)));
      final state = CharacterBattleState(testCharacter());

      engine.rollTrigger(state, 100);

      expect(state.fatCooldownRemaining, 4);
    });
  });

  group('FatEngine ability count', () {
    test('without FAT, only 1 ability is allowed per turn', () {
      final engine = FatEngine();
      final state = CharacterBattleState(testCharacter());
      expect(engine.maxAbilitiesThisTurn(state), 1);
      expect(engine.canUseAnotherAbility(state), isTrue);

      state.recordAbilityUse(testTrigger());
      expect(engine.canUseAnotherAbility(state), isFalse);
    });

    test(
        'after FAT triggers, up to 3 abilities are allowed (optional, not forced)',
        () {
      final engine = FatEngine(diceRoller: DiceRoller(Random(2)));
      final state = CharacterBattleState(testCharacter());
      engine.rollTrigger(state, 100);

      expect(engine.maxAbilitiesThisTurn(state), 3);

      state.recordAbilityUse(testTrigger(id: 't1'));
      expect(engine.canUseAnotherAbility(state), isTrue);
      state.recordAbilityUse(testTrigger(id: 't2'));
      expect(engine.canUseAnotherAbility(state), isTrue);
      state.recordAbilityUse(testTrigger(id: 't3'));
      expect(engine.canUseAnotherAbility(state), isFalse);

      // Using only 1 of the 3 available abilities is legal (optional).
      final soloState = CharacterBattleState(testCharacter());
      engine.rollTrigger(soloState, 100);
      soloState.recordAbilityUse(testTrigger(id: 'only-one'));
      soloState.endTurn();
      expect(soloState.trionAffinityHalvedNextTurn, isFalse);
    });
  });

  group('FAT usage penalty (2+ abilities in one turn)', () {
    test('using only 1 ability via FAT applies no penalty', () {
      final engine = FatEngine(diceRoller: DiceRoller(Random(2)));
      final state = CharacterBattleState(testCharacter());
      engine.rollTrigger(state, 100);

      final trigger = testTrigger(cooldownTurns: 2);
      state.recordAbilityUse(trigger);
      state.endTurn();

      expect(state.cooldowns[trigger.id], 2);
      expect(state.trionAffinityHalvedNextTurn, isFalse);
    });

    test('using 2+ abilities via FAT doubles all cooldowns used that turn', () {
      final engine = FatEngine(diceRoller: DiceRoller(Random(2)));
      final state = CharacterBattleState(testCharacter());
      engine.rollTrigger(state, 100);

      final a = testTrigger(id: 'a', cooldownTurns: 2);
      final b = testTrigger(id: 'b', cooldownTurns: 3);
      state.recordAbilityUse(a);
      state.recordAbilityUse(b);
      state.endTurn();

      expect(state.cooldowns['a'], 4);
      expect(state.cooldowns['b'], 6);
    });

    test(
        'using 2+ abilities via FAT halves Trion Affinity for the next turn only',
        () {
      final engine = FatEngine(diceRoller: DiceRoller(Random(2)));
      final character = testCharacter(stats: testStats(trionAffinity: 20));
      final state = CharacterBattleState(character);
      engine.rollTrigger(state, 100);

      state.recordAbilityUse(testTrigger(id: 'a'));
      state.recordAbilityUse(testTrigger(id: 'b'));
      state.endTurn();

      expect(state.effectiveStats().trionAffinity, 10);

      // The penalty only lasts for the following turn.
      state.endTurn();
      expect(state.effectiveStats().trionAffinity, 20);
    });

    test(
        'FAT penalty applies only to the character who used FAT, not teammates',
        () {
      final engine = FatEngine(diceRoller: DiceRoller(Random(2)));
      final userState = CharacterBattleState(
          testCharacter(id: 'user', stats: testStats(trionAffinity: 20)));
      final teammateState = CharacterBattleState(
          testCharacter(id: 'teammate', stats: testStats(trionAffinity: 20)));

      engine.rollTrigger(userState, 100);
      userState.recordAbilityUse(testTrigger(id: 'a'));
      userState.recordAbilityUse(testTrigger(id: 'b'));
      userState.endTurn();
      teammateState.endTurn();

      expect(userState.effectiveStats().trionAffinity, 10);
      expect(teammateState.effectiveStats().trionAffinity, 20);
    });

    test('cannot re-trigger FAT again until the cooldown elapses', () {
      const config = FatConfig(baseFatCooldownTurns: 2);
      final engine =
          FatEngine(config: config, diceRoller: DiceRoller(Random(2)));
      final state = CharacterBattleState(testCharacter());

      expect(engine.rollTrigger(state, 100), isTrue);
      state.endTurn(); // fatCooldownRemaining: 2 -> 1
      expect(engine.rollTrigger(state, 100), isFalse);
      state.endTurn(); // fatCooldownRemaining: 1 -> 0
      expect(engine.rollTrigger(state, 100), isTrue);
    });
  });
}

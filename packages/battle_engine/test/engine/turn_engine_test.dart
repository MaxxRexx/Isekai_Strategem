import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group('TurnEngine integration', () {
    test(
        'team Trion gain uses the sum of living members effective Trion Affinity',
        () {
      final team = Team(
        id: 'team-1',
        characters: [
          testCharacter(id: 'a', stats: testStats(trionAffinity: 10)),
          testCharacter(id: 'b', stats: testStats(trionAffinity: 10)),
          testCharacter(id: 'c', stats: testStats(trionAffinity: 10)),
        ],
      );
      final states = {
        for (final c in team.characters) c.id: CharacterBattleState(c)
      };

      // Kill one member; only living members' affinity should count.
      states['c']!.currentHealth = 0;

      const config = TrionTierConfig(
          baseChanceLowToMedium: 1.0, baseChanceMediumToHigh: 0.0);
      final engine = TurnEngine(
        trionGainEngine:
            TrionGainEngine(config: config, diceRoller: DiceRoller(Random(1))),
      );

      final result = engine.resolveTeamTrionGain(team, states);
      expect(result.tier,
          TrionTier.medium); // always upgrades from low, never to high
      expect(team.trionPool.current, config.mediumAmount);
    });

    test(
        'full ability-use flow: cooldown, Trion spend, and end-of-turn bookkeeping',
        () {
      final character = testCharacter(stats: testStats(fatChance: 0));
      final state = CharacterBattleState(character);
      final teamPool = TrionPool(current: 20);
      final trigger = testTrigger(trionCost: 5, cooldownTurns: 2);

      final engine = TurnEngine();

      expect(engine.canUseAbility(state, trigger), isTrue);
      expect(engine.useAbility(state, trigger, teamPool), isTrue);
      expect(teamPool.current, 15);

      // Only 1 ability per turn without FAT.
      expect(engine.canUseAbility(state, testTrigger(id: 'other')), isFalse);

      engine.endCharacterTurn(state);
      expect(state.cooldowns[trigger.id], 2);
    });

    test(
        'useAbility fails and makes no state change if the team pool cannot afford it',
        () {
      final state = CharacterBattleState(testCharacter());
      final teamPool = TrionPool(current: 2);
      final trigger = testTrigger(trionCost: 5);

      final engine = TurnEngine();
      final result = engine.useAbility(state, trigger, teamPool);

      expect(result, isFalse);
      expect(teamPool.current, 2);
      expect(state.cooldowns, isEmpty);
    });

    test('status effect ticking applies turn-start damage to current health',
        () {
      final engine = TurnEngine();
      final state = CharacterBattleState(
          testCharacter(stats: testStats(armor: 0, maxHealth: 100)));
      engine.statusEffectEngine.apply(state, 'bleeding');

      final healthBefore = state.currentHealth;
      engine.tickStatusEffects(state);
      expect(state.currentHealth, lessThan(healthBefore));
    });

    test('Sapped drain credits the causer team pool via tickStatusEffects', () {
      final engine = TurnEngine();
      final target = CharacterBattleState(
          testCharacter(stats: testStats(trionCapacity: 100)));
      engine.statusEffectEngine
          .apply(target, 'sapped', sourceCharacterId: 'causer');

      final causerPool = TrionPool();
      engine
          .tickStatusEffects(target, causerTrionPools: {'causer': causerPool});

      expect(causerPool.current, 25);
    });

    test('FAT roll integrates Team Spirit bonus into effective FAT Chance', () {
      final character =
          testCharacter(stats: testStats(fatChance: 0, teamSpirit: 100));
      final state = CharacterBattleState(character);
      final engine =
          TurnEngine(fatEngine: FatEngine(diceRoller: DiceRoller(Random(2))));

      // Base FAT Chance is 0, but Team Spirit is maxed (100), which should
      // grant the full high-side FAT Chance bonus, making a trigger roll
      // possible even though the base stat alone would never trigger.
      var triggeredAtLeastOnce = false;
      for (var i = 0; i < 20; i++) {
        state.fatCooldownRemaining = 0;
        if (engine.rollFatTrigger(state)) {
          triggeredAtLeastOnce = true;
          break;
        }
      }
      expect(triggeredAtLeastOnce, isTrue);
    });
  });
}

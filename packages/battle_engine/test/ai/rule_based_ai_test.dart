import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

Team _team(String prefix, {Stats? stats}) => Team(
      id: '$prefix-team',
      characters: [
        testCharacter(id: '$prefix-1', stats: stats),
        testCharacter(id: '$prefix-2', stats: stats),
        testCharacter(id: '$prefix-3', stats: stats),
      ],
    );

void main() {
  group('RuleBasedAi.takeTurn', () {
    test('a character with no equipped active triggers takes no action', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);

      final results =
          const RuleBasedAi().takeTurn(battle, equippedActiveTriggers: {});

      expect(results, isEmpty);
    });

    test('focuses the lowest-health legal opponent target', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);
      battle.states['b-1']!.currentHealth = 80;
      battle.states['b-2']!.currentHealth = 10; // lowest
      battle.states['b-3']!.currentHealth = 50;

      final trigger = testTrigger(
        id: 'a-1-attack',
        trionCost: 0,
        cooldownTurns: 0,
        damage: const DiceExpression(0, 1, flatBonus: 5),
      );

      final results = const RuleBasedAi().takeTurn(
        battle,
        equippedActiveTriggers: {
          'a-1': [trigger],
          'a-2': [],
          'a-3': [],
        },
      );

      expect(results, hasLength(1));
      expect(results.single.characterId, 'a-1');
      expect(
        results.single.useResult.targetResults.single.targetCharacterId,
        'b-2',
      );
    });

    test('prefers the highest-damage usable ability over a weaker one', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);

      final weak = testTrigger(
        id: 'weak',
        trionCost: 0,
        cooldownTurns: 0,
        damage: const DiceExpression(0, 1, flatBonus: 1),
      );
      final strong = testTrigger(
        id: 'strong',
        trionCost: 0,
        cooldownTurns: 0,
        damage: const DiceExpression(0, 1, flatBonus: 50),
      );

      final results = const RuleBasedAi().takeTurn(
        battle,
        equippedActiveTriggers: {
          'a-1': [weak, strong],
          'a-2': [],
          'a-3': [],
        },
      );

      expect(results.single.triggerId, 'strong');
    });

    test(
        'falls back to a status/support ability when nothing usable deals '
        'damage', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);

      final support = testTrigger(
        id: 'support',
        trionCost: 0,
        cooldownTurns: 0,
        includeDamage: false,
        inflictedStatusEffects: const [StatusEffectApplication('poisoned')],
      );

      final results = const RuleBasedAi().takeTurn(
        battle,
        equippedActiveTriggers: {
          'a-1': [support],
          'a-2': [],
          'a-3': [],
        },
      );

      expect(results.single.triggerId, 'support');
    });

    test('chains additional abilities across a full FAT-triggered turn', () {
      final character = testCharacter(
          id: 'a-1', stats: testStats(fatChance: 100, teamSpirit: 50));
      final teamA = Team(id: 'a-team', characters: [
        character,
        testCharacter(id: 'a-2'),
        testCharacter(id: 'a-3')
      ]);
      final battle = Battle(
        teamA: teamA,
        teamB: _team('b'),
        turnEngine:
            TurnEngine(fatEngine: FatEngine(diceRoller: DiceRoller(Random(2)))),
      );
      battle.teamA.trionPool.gain(1000);

      // Roll FAT so this character can use up to 3 abilities this turn.
      var fatTriggered = false;
      for (var i = 0; i < 20 && !fatTriggered; i++) {
        battle.states['a-1']!.fatCooldownRemaining = 0;
        fatTriggered = battle.turnEngine.rollFatTrigger(battle.states['a-1']!);
      }
      expect(fatTriggered, isTrue);

      final trigger = testTrigger(
        id: 'a-1-attack',
        trionCost: 0,
        cooldownTurns: 0,
        damage: const DiceExpression(0, 1, flatBonus: 5),
      );

      final results = const RuleBasedAi().takeTurn(
        battle,
        equippedActiveTriggers: {
          'a-1': [trigger],
          'a-2': [],
          'a-3': [],
        },
      );

      expect(results, hasLength(3));
      expect(results.every((r) => r.characterId == 'a-1'), isTrue);
    });

    test('stops immediately once the battle is won mid-turn', () {
      // Force every attack roll to a natural 20 (guaranteed crit hit) so
      // the AoE reliably kills all 3 opposing members in one use, rather
      // than depending on unseeded rolls landing on a low-health target.
      final battle = Battle(
        teamA: _team('a'),
        teamB: _team('b'),
        turnEngine: TurnEngine(
          combatEngine:
              CombatEngine(diceRoller: DiceRoller(const FixedRandom(19))),
        ),
      );
      battle.teamA.trionPool.gain(1000);
      // Make every opposing character one hit from death.
      for (final id in ['b-1', 'b-2', 'b-3']) {
        battle.states[id]!.currentHealth = 1;
      }

      final lethalTrigger = testTrigger(
        id: 'lethal',
        trionCost: 0,
        cooldownTurns: 0,
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.aoe,
        targetCount: 3,
        damage: const DiceExpression(0, 1, flatBonus: 999),
      );

      final results = const RuleBasedAi().takeTurn(
        battle,
        equippedActiveTriggers: {
          'a-1': [lethalTrigger],
          'a-2': [lethalTrigger],
          'a-3': [lethalTrigger],
        },
      );

      expect(battle.isOver, isTrue);
      expect(battle.outcome, BattleOutcome.teamAWins);
      // Only team A's first character should have needed to act.
      expect(results, hasLength(1));
    });

    test(
        'targets the lowest-health living ally for a self/ally-affiliated '
        'ability', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);
      battle.states['a-2']!.currentHealth = 20; // lowest ally health
      battle.states['a-3']!.currentHealth = 90;

      final healTrigger = testTrigger(
        id: 'heal',
        trionCost: 0,
        cooldownTurns: 0,
        includeDamage: false,
        targetAffiliation: TargetAffiliation.ally,
        healAmount: const DiceExpression(0, 1, flatBonus: 10),
      );

      final results = const RuleBasedAi().takeTurn(
        battle,
        equippedActiveTriggers: {
          'a-1': [healTrigger],
          'a-2': [],
          'a-3': [],
        },
      );

      expect(
        results.single.useResult.targetResults.single.targetCharacterId,
        'a-2',
      );
    });
  });
}

import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

Team _team(String prefix) => Team(
      id: '$prefix-team',
      characters: [
        testCharacter(id: '$prefix-1'),
        testCharacter(id: '$prefix-2'),
        testCharacter(id: '$prefix-3'),
      ],
    );

void main() {
  group('Battle turn structure', () {
    test('teamA goes first by default; turns alternate whole-team', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      expect(battle.isTeamATurn, isTrue);
      expect(battle.activeTeam, battle.teamA);

      battle.endTurn();
      expect(battle.isTeamATurn, isFalse);
      expect(battle.activeTeam, battle.teamB);

      battle.endTurn();
      expect(battle.isTeamATurn, isTrue);
    });

    test('teamAGoesFirst: false starts with team B active', () {
      final battle =
          Battle(teamA: _team('a'), teamB: _team('b'), teamAGoesFirst: false);
      expect(battle.isTeamATurn, isFalse);
      expect(battle.activeTeam, battle.teamB);
    });

    test('roundNumber increments once both teams have taken a turn', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      expect(battle.roundNumber, 1);

      battle.endTurn(); // team A's turn ends, team B's begins
      expect(battle.roundNumber, 1);

      battle.endTurn(); // team B's turn ends, round completes
      expect(battle.roundNumber, 2);
    });

    test(
        'states holds a CharacterBattleState for every character on both '
        'teams', () {
      final teamA = _team('a');
      final teamB = _team('b');
      final battle = Battle(teamA: teamA, teamB: teamB);

      for (final c in [...teamA.characters, ...teamB.characters]) {
        expect(battle.states[c.id], isNotNull);
        expect(battle.states[c.id]!.character, c);
      }
    });
  });

  group('Battle.startTurn', () {
    test('rolls Trion gain for the active team only', () {
      const config = TrionTierConfig(
          baseChanceLowToMedium: 1.0, baseChanceMediumToHigh: 0.0);
      Team zeroAffinityTeam(String prefix) => Team(
            id: '$prefix-team',
            characters: List.generate(
              3,
              (i) => testCharacter(
                  id: '$prefix-${i + 1}', stats: testStats(trionAffinity: 0)),
            ),
          );
      final battle = Battle(
        teamA: zeroAffinityTeam('a'),
        teamB: zeroAffinityTeam('b'),
        turnEngine: TurnEngine(
          trionGainEngine: TrionGainEngine(
              config: config, diceRoller: DiceRoller(Random(1))),
        ),
      );

      // Team A's turn here is the very first turn of the whole battle, so
      // the first-move handicap (tested in detail below) forces the Low
      // tier regardless of the config - advance past it to team B's first
      // turn to observe this config's normal (unhandicapped) odds.
      battle.startTurn();
      battle.endTurn();
      final result = battle.startTurn();
      expect(result.trionGain.tier, TrionTier.medium);
      expect(battle.teamB.trionPool.current, config.mediumAmount);
      expect(battle.teamA.trionPool.current, config.lowAmount);
    });

    test(
        "forces the Low tier on the battle's very first turn regardless of "
        "the roll, then rolls normally from the second turn onward "
        '(first-move handicap, Naruto-Arena-style)', () {
      const config = TrionTierConfig(
          baseChanceLowToMedium: 1.0, baseChanceMediumToHigh: 1.0);
      final battle = Battle(
        teamA: _team('a'),
        teamB: _team('b'),
        turnEngine: TurnEngine(
          trionGainEngine: TrionGainEngine(config: config),
        ),
      );

      final firstResult = battle.startTurn();
      expect(firstResult.trionGain.tier, TrionTier.low);
      expect(battle.teamA.trionPool.current, config.lowAmount);

      battle.endTurn();
      final secondResult = battle.startTurn();
      expect(secondResult.trionGain.tier, TrionTier.high);
    });

    test(
        'the handicap still applies when team B goes first, and does not '
        "reapply to team A's own first turn afterward", () {
      const config = TrionTierConfig(
          baseChanceLowToMedium: 1.0, baseChanceMediumToHigh: 1.0);
      final battle = Battle(
        teamA: _team('a'),
        teamB: _team('b'),
        teamAGoesFirst: false,
        turnEngine: TurnEngine(
          trionGainEngine: TrionGainEngine(config: config),
        ),
      );

      final firstResult = battle.startTurn();
      expect(firstResult.trionGain.tier, TrionTier.low);
      expect(battle.activeTeam, battle.teamB);

      battle.endTurn();
      final secondResult = battle.startTurn();
      expect(battle.activeTeam, battle.teamA);
      expect(secondResult.trionGain.tier, TrionTier.high);
    });

    test('ticks status effects for every living member of the active team', () {
      final teamA = Team(
        id: 'a-team',
        characters: List.generate(
          3,
          (i) => testCharacter(id: 'a-${i + 1}', stats: testStats(armor: 0)),
        ),
      );
      final battle = Battle(teamA: teamA, teamB: _team('b'));
      final bleedingState = battle.states['a-1']!;
      battle.turnEngine.statusEffectEngine.apply(bleedingState, 'bleeding');
      final healthBefore = bleedingState.currentHealth;

      final result = battle.startTurn();

      expect(result.statusTicks['a-1'], isNotNull);
      expect(bleedingState.currentHealth, lessThan(healthBefore));
      // Team B hasn't had a turn yet, so it's untouched.
      expect(result.statusTicks.containsKey('b-1'), isFalse);
    });

    test('skips a member who died to their own status tick this turn', () {
      final teamA = Team(
        id: 'a-team',
        characters: List.generate(
          3,
          (i) => testCharacter(id: 'a-${i + 1}', stats: testStats(armor: 0)),
        ),
      );
      final battle = Battle(teamA: teamA, teamB: _team('b'));
      final dyingState = battle.states['a-1']!;
      dyingState.currentHealth = 1;
      battle.turnEngine.statusEffectEngine.apply(dyingState, 'bleeding');

      expect(() => battle.startTurn(), returnsNormally);
      expect(dyingState.currentHealth, 0);
    });

    test('rolls FAT for every living member of the active team', () {
      final team = Team(
        id: 'team-a',
        characters: [
          testCharacter(
              id: 'a-1', stats: testStats(fatChance: 100, teamSpirit: 50)),
          testCharacter(id: 'a-2'),
          testCharacter(id: 'a-3'),
        ],
      );
      final battle = Battle(teamA: team, teamB: _team('b'));

      final result = battle.startTurn();
      expect(result.fatTriggered['a-1'], isTrue);
    });

    test('refreshes a Prone lock when equipped active triggers are supplied',
        () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      final state = battle.states['a-1']!;
      // Override the duration so the lock survives this turn's status tick
      // (which ticks it down before the refresh runs) - Prone's own default
      // duration is 1 turn, which would otherwise expire immediately.
      battle.turnEngine.statusEffectEngine
          .apply(state, 'prone', durationOverride: 3);
      final triggers = [testTrigger(id: 'x'), testTrigger(id: 'y')];

      battle.startTurn(equippedActiveTriggers: {'a-1': triggers});

      final locked = state.statusEffects.single.data['lockedAbilityId'];
      expect(['x', 'y'], contains(locked));
    });
  });

  group('Battle.endTurn', () {
    test(
        'finalizes cooldowns for abilities used by the active team this '
        'turn', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      final state = battle.states['a-1']!;
      final trigger = testTrigger(trionCost: 5, cooldownTurns: 2);
      battle.teamA.trionPool.gain(50);

      battle.turnEngine.useAbility(state, trigger, battle.activeTeamPool);
      battle.endTurn();

      expect(state.cooldowns[trigger.id], 2);
    });

    test('does not finalize cooldowns for the inactive team', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      final teamBState = battle.states['b-1']!;
      final trigger = testTrigger(trionCost: 5, cooldownTurns: 2);
      battle.teamB.trionPool.gain(50);

      battle.turnEngine.useAbility(teamBState, trigger, battle.teamB.trionPool);
      battle.endTurn(); // ends team A's turn, not team B's

      expect(teamBState.cooldowns, isEmpty);
    });
  });

  group('Battle win/loss detection', () {
    test('outcome is ongoing while both teams have a living member', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      expect(battle.outcome, BattleOutcome.ongoing);
      expect(battle.isOver, isFalse);
    });

    test('team A wins once every team B member reaches 0 health', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      for (final c in battle.teamB.characters) {
        battle.states[c.id]!.currentHealth = 0;
      }
      expect(battle.isTeamDefeated(battle.teamB), isTrue);
      expect(battle.outcome, BattleOutcome.teamAWins);
      expect(battle.isOver, isTrue);
    });

    test('team B wins once every team A member reaches 0 health', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      for (final c in battle.teamA.characters) {
        battle.states[c.id]!.currentHealth = 0;
      }
      expect(battle.outcome, BattleOutcome.teamBWins);
    });

    test('a simultaneous wipe is a draw', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      for (final c in [
        ...battle.teamA.characters,
        ...battle.teamB.characters
      ]) {
        battle.states[c.id]!.currentHealth = 0;
      }
      expect(battle.outcome, BattleOutcome.draw);
    });

    test('a team with at least one member above 0 health is not defeated', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.states['b-1']!.currentHealth = 0;
      battle.states['b-2']!.currentHealth = 0;
      // b-3 still alive.
      expect(battle.isTeamDefeated(battle.teamB), isFalse);
      expect(battle.outcome, BattleOutcome.ongoing);
    });
  });
}

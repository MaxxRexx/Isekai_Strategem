import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group('StatusEffectEngine.resolveInfliction', () {
    test('fails when modified roll is less than causer infliction', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      // Even a natural 20 (20 - resistance) must clear the infliction bar.
      final succeeded =
          engine.resolveInfliction(causerInfliction: 25, targetResistance: 0);
      // 20 - 0 = 20 < 25 -> always fails regardless of roll.
      expect(succeeded, isFalse);
    });

    test('succeeds when modified roll meets or exceeds causer infliction', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      // 1 - 0 = 1 >= 1 -> always succeeds regardless of roll (min roll is 1).
      final succeeded =
          engine.resolveInfliction(causerInfliction: 1, targetResistance: 0);
      expect(succeeded, isTrue);
    });

    test('higher target resistance lowers the success rate', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(42)));
      const samples = 5000;

      int successes(int resistance) {
        var count = 0;
        for (var i = 0; i < samples; i++) {
          if (engine.resolveInfliction(
              causerInfliction: 10, targetResistance: resistance)) {
            count++;
          }
        }
        return count;
      }

      final lowResistance = successes(0);
      final highResistance = successes(8);
      expect(highResistance, lessThan(lowResistance));
    });

    test('matches the worked example: +1 resistance subtracts 1 from the roll',
        () {
      // Roll a bunch of times with resistance 0 and resistance 1 using
      // separately-seeded rollers that produce the same die sequence, and
      // verify the pass/fail boundary shifted by exactly 1 point of
      // infliction threshold.
      final rollerA = DiceRoller(Random(7));
      final engineA = StatusEffectEngine(diceRoller: rollerA);
      final rollerB = DiceRoller(Random(7));
      final engineB = StatusEffectEngine(diceRoller: rollerB);

      // Same underlying roll sequence (same seed) - resistance 1 against
      // infliction N behaves exactly like resistance 0 against infliction
      // N+1.
      for (var i = 0; i < 100; i++) {
        final a =
            engineA.resolveInfliction(causerInfliction: 9, targetResistance: 1);
        final b = engineB.resolveInfliction(
            causerInfliction: 10, targetResistance: 0);
        expect(a, b);
      }
    });

    test('disadvantage on the roll lowers the apply rate; advantage raises it',
        () {
      // Under the worked-example formula (modified = roll - resistance;
      // applies if modified >= infliction), disadvantage on the roll
      // always lowers the apply rate and advantage always raises it -
      // same direction as Resistance/lowering Resistance, respectively.
      // This is exactly why Bleeding grants *advantage* (not disadvantage
      // on the bleeding character's own roll) to whoever attempts to
      // inflict a new effect on them: that's the only way to make
      // Bleeding a debuff (raises the apply rate against them) without
      // touching this formula. See StatusEffectEngine.resolveInfliction's
      // doc comment and the 'Bleeding' group below.
      const samples = 5000;

      int successesWithMode(RollMode mode) {
        final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(3)));
        var count = 0;
        for (var i = 0; i < samples; i++) {
          final context = RollContext();
          if (mode == RollMode.disadvantage) context.addDisadvantage('x');
          if (mode == RollMode.advantage) context.addAdvantage('x');
          if (engine.resolveInfliction(
            causerInfliction: 10,
            targetResistance: 0,
            targetRollContext: context,
          )) {
            count++;
          }
        }
        return count;
      }

      final normalSuccesses = successesWithMode(RollMode.normal);
      final disadvantageSuccesses = successesWithMode(RollMode.disadvantage);
      final advantageSuccesses = successesWithMode(RollMode.advantage);
      expect(disadvantageSuccesses, lessThan(normalSuccesses));
      expect(advantageSuccesses, greaterThan(normalSuccesses));
    });
  });

  group('Invulnerabilities', () {
    test('a character invulnerable to an effect never has it applied', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(
        testCharacter(statusInvulnerabilities: {'stunned'}),
      );

      final applied = engine.apply(state, 'stunned');

      expect(applied, isFalse);
      expect(state.statusEffects, isEmpty);
    });

    test('invulnerability bypasses the roll entirely (no roll needed)', () {
      final state = CharacterBattleState(
          testCharacter(statusInvulnerabilities: {'poisoned'}));
      expect(state.isInvulnerableTo('poisoned'), isTrue);
      expect(state.isInvulnerableTo('bleeding'), isFalse);
    });
  });

  group('StatusEffectEngine.apply', () {
    test('Sickened grants vulnerability to exactly 4 random damage types', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(9)));
      final state = CharacterBattleState(testCharacter());
      engine.apply(state, 'sickened');

      final instance = state.statusEffects.single;
      final vulnerableTypes =
          instance.data['vulnerableDamageTypes'] as Set<DamageType>;
      expect(vulnerableTypes, hasLength(4));

      var vulnerableCount = 0;
      for (final type in vulnerableTypes) {
        expect(state.statusDamageTypeMultiplier(type), 2.0);
      }
      for (final type in DamageType.values) {
        if (vulnerableTypes.contains(type)) vulnerableCount++;
      }
      expect(vulnerableCount, 4);
    });

    test('sets remaining turns from the definition default', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      engine.apply(state, 'bleeding');
      expect(state.statusEffects.single.remainingTurns,
          StatusEffectMagnitudes.defaults.bleedingDurationTurns);
    });
  });

  group('StatusEffectEngine.tickStartOfTurn', () {
    test('Bleeding deals its configured flat damage at the start of turn', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      engine.apply(state, 'bleeding');

      final result = engine.tickStartOfTurn(state);

      expect(result.damageEvents, hasLength(1));
      expect(result.damageEvents.single.damageType, DamageType.slashing);
      expect(result.damageEvents.single.amount,
          StatusEffectMagnitudes.defaults.bleedingDamagePerTurn);
    });

    test('Electrocuted deals 1d4 lightning damage at the start of turn', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      engine.apply(state, 'electrocuted');

      for (var i = 0; i < 20; i++) {
        final result = engine.tickStartOfTurn(state);
        if (result.damageEvents.isEmpty) break; // effect expired
        expect(result.damageEvents.single.damageType, DamageType.lightning);
        expect(result.damageEvents.single.amount, inInclusiveRange(1, 4));
      }
    });

    test('Sapped drains a percentage of Trion Capacity to the causer each turn',
        () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final character = testCharacter(stats: testStats(trionCapacity: 100));
      final state = CharacterBattleState(character);
      engine.apply(state, 'sapped', sourceCharacterId: 'causer-1');

      final result = engine.tickStartOfTurn(state);

      expect(result.trionDrainEvents, hasLength(1));
      expect(result.trionDrainEvents.single.causerCharacterId, 'causer-1');
      expect(result.trionDrainEvents.single.amount, 25); // 25% of 100
    });

    test('effects expire and are removed once remainingTurns reaches 0', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      engine.apply(state, 'stunned', durationOverride: 2);

      expect(state.statusEffects, hasLength(1));
      engine.tickStartOfTurn(state); // 2 -> 1
      expect(state.statusEffects, hasLength(1));
      engine.tickStartOfTurn(state); // 1 -> 0, removed
      expect(state.statusEffects, isEmpty);
    });
  });

  group('Stunned / Frozen', () {
    test('Stunned prevents actions and zeroes Team Spirit while active', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state =
          CharacterBattleState(testCharacter(stats: testStats(teamSpirit: 60)));
      engine.apply(state, 'stunned');

      expect(state.isActionPrevented(), isTrue);
      expect(state.effectiveStats().teamSpirit, 0);
    });

    test('Frozen prevents actions and zeroes Trion Affinity while active', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(
          testCharacter(stats: testStats(trionAffinity: 30)));
      engine.apply(state, 'frozen');

      expect(state.isActionPrevented(), isTrue);
      expect(state.effectiveStats().trionAffinity, 0);
    });
  });

  group('Reeling / Prepared / Braced (per-remaining-turn modifiers)', () {
    test('Reeling applies -1 Attack per remaining turn', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state =
          CharacterBattleState(testCharacter(stats: testStats(attack: 20)));
      engine.apply(state, 'reeling', durationOverride: 3);

      expect(state.effectiveStats().attack, 17); // 20 - 1*3
      engine.tickStartOfTurn(state); // remaining -> 2
      expect(state.effectiveStats().attack, 18); // 20 - 1*2
    });

    test('Prepared applies +1 Attack per remaining turn', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state =
          CharacterBattleState(testCharacter(stats: testStats(attack: 20)));
      engine.apply(state, 'prepared', durationOverride: 2);
      expect(state.effectiveStats().attack, 22); // 20 + 1*2
    });

    test('Braced applies +Defense per remaining turn', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state =
          CharacterBattleState(testCharacter(stats: testStats(defense: 5)));
      engine.apply(state, 'braced', durationOverride: 4);
      expect(state.effectiveStats().defense, 9); // 5 + 1*4
    });
  });

  group('Roll-affecting status effects', () {
    test('Poisoned grants disadvantage on attack rolls', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      engine.apply(state, 'poisoned');
      expect(state.rollContextFor(StatusRollTag.attackRoll).hasDisadvantage,
          isTrue);
      expect(
          state.rollContextFor(StatusRollTag.rangedAttackRoll).hasDisadvantage,
          isFalse);
    });

    test('Threatened grants disadvantage on ranged attacks only', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      engine.apply(state, 'threatened');
      expect(
          state.rollContextFor(StatusRollTag.rangedAttackRoll).hasDisadvantage,
          isTrue);
      expect(state.rollContextFor(StatusRollTag.attackRoll).hasDisadvantage,
          isFalse);
    });

    test(
        'Bleeding grants advantage on status resistance rolls made against the bleeding character '
        '(so it is actually a debuff - see resolveInfliction doc comment)', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      engine.apply(state, 'bleeding');

      final context = state.rollContextFor(StatusRollTag.statusResistanceRoll);
      expect(context.hasAdvantage, isTrue);
      expect(context.hasDisadvantage, isFalse);
    });

    test(
        'Bleeding + StatusEffectEngine.resolveInfliction: raises the apply rate against a bleeding target',
        () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final bleedingTarget =
          CharacterBattleState(testCharacter(id: 'bleeding'));
      engine.apply(bleedingTarget, 'bleeding');
      final healthyTarget = CharacterBattleState(testCharacter(id: 'healthy'));

      const samples = 5000;
      int applyCount(CharacterBattleState target) {
        var count = 0;
        for (var i = 0; i < samples; i++) {
          final context =
              target.rollContextFor(StatusRollTag.statusResistanceRoll);
          if (engine.resolveInfliction(
            causerInfliction: 10,
            targetResistance: 0,
            targetRollContext: context,
          )) {
            count++;
          }
        }
        return count;
      }

      expect(
          applyCount(bleedingTarget), greaterThan(applyCount(healthyTarget)));
    });

    test(
        'Blinded reduces ranged targets and grants disadvantage on ranged attacks',
        () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      engine.apply(state, 'blinded');
      expect(
          state.rollContextFor(StatusRollTag.rangedAttackRoll).hasDisadvantage,
          isTrue);
      expect(
          StatusEffectCatalog
              .defaultCatalog['blinded'].rangedTargetsReducedByOne,
          isTrue);
    });
  });

  group('Acid', () {
    test('reduces Armor by the configured flat value', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state =
          CharacterBattleState(testCharacter(stats: testStats(armor: 10)));
      engine.apply(state, 'acid');
      expect(
        state.effectiveStats().armor,
        10 - StatusEffectMagnitudes.defaults.acidArmorReduction,
      );
    });
  });

  group('Rallied', () {
    test('increases max Health by the configured flat value', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state =
          CharacterBattleState(testCharacter(stats: testStats(maxHealth: 100)));
      engine.apply(state, 'rallied');
      expect(
        state.effectiveStats().maxHealth,
        100 + StatusEffectMagnitudes.defaults.ralliedMaxHealthBonus,
      );
    });
  });

  group('Charmed', () {
    test('is flagged as cannot-target-source with source advantage', () {
      final def = StatusEffectCatalog.defaultCatalog['charmed'];
      expect(def.cannotTargetSource, isTrue);
      expect(def.sourceHasAdvantageAgainstTarget, isTrue);
    });
  });

  group('Prone (locks one random ability each turn)', () {
    test('refreshAbilityLocks picks one of the equipped triggers', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      engine.apply(state, 'prone');

      final triggers = [
        testTrigger(id: 'a'),
        testTrigger(id: 'b'),
        testTrigger(id: 'c')
      ];
      engine.refreshAbilityLocks(state, triggers);

      final locked = state.statusEffects.single.data['lockedAbilityId'];
      expect(['a', 'b', 'c'], contains(locked));
    });
  });
}

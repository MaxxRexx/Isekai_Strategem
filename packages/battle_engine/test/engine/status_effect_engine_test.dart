import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group('StatusEffectEngine.resolveInfliction', () {
    test('higher causer Infliction raises the apply rate', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(42)));
      const samples = 5000;

      int successes(int infliction) {
        var count = 0;
        for (var i = 0; i < samples; i++) {
          final outcome = engine.resolveInfliction(
              causerInfliction: infliction, targetResistance: 10);
          if (outcome.applies) count++;
        }
        return count;
      }

      final lowInfliction = successes(0);
      final highInfliction = successes(8);
      expect(highInfliction, greaterThan(lowInfliction));
    });

    test('higher target Resistance lowers the apply rate', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(42)));
      const samples = 5000;

      int successes(int resistance) {
        var count = 0;
        for (var i = 0; i < samples; i++) {
          final outcome = engine.resolveInfliction(
              causerInfliction: 10, targetResistance: resistance);
          if (outcome.applies) count++;
        }
        return count;
      }

      final lowResistance = successes(0);
      final highResistance = successes(8);
      expect(highResistance, lessThan(lowResistance));
    });

    test('a tie between causer total and target total favors the causer', () {
      // Force both d20 rolls to come up 10 (causer rolls first, then
      // target), with equal modifiers, so the totals tie exactly.
      final engine =
          StatusEffectEngine(diceRoller: DiceRoller(SequenceRandom([9, 9])));
      final outcome =
          engine.resolveInfliction(causerInfliction: 5, targetResistance: 5);

      expect(outcome.causerRoll.total, outcome.targetRoll.total);
      expect(outcome.applies, isTrue);
    });

    test('a natural 20 for the causer always applies, regardless of totals',
        () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(3)));
      var sawCrit = false;
      for (var i = 0; i < 2000 && !sawCrit; i++) {
        // Force a huge disadvantage for the causer's total so only a
        // natural 20 could possibly win, then check the crit flag correlates.
        final outcome = engine.resolveInfliction(
            causerInfliction: -1000, targetResistance: 0);
        if (outcome.causerRoll.kept == 20) {
          expect(outcome.isCriticalSuccess, isTrue);
          expect(outcome.applies, isTrue);
          sawCrit = true;
        }
      }
      expect(sawCrit, isTrue);
    });

    test('a natural 1 for the causer always fails, regardless of totals', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(4)));
      var sawCritFailure = false;
      for (var i = 0; i < 2000 && !sawCritFailure; i++) {
        // Force a huge causer Infliction bonus so only a natural 1 could
        // possibly lose.
        final outcome = engine.resolveInfliction(
            causerInfliction: 1000, targetResistance: 0);
        if (outcome.causerRoll.kept == 1) {
          expect(outcome.isCriticalFailure, isTrue);
          expect(outcome.applies, isFalse);
          sawCritFailure = true;
        }
      }
      expect(sawCritFailure, isTrue);
    });

    test(
        "disadvantage on the target's roll raises the apply rate; advantage lowers it",
        () {
      // Under the two-roll opposed formula (applies if causerTotal >=
      // targetTotal), weakening the target's own roll makes their side of
      // the contest easier to beat - the natural, expected direction for
      // an opposed roll (same as a defender's disadvantage helping an
      // attacker land a hit in CombatEngine.resolveAttackRoll). This is
      // exactly why Bleeding grants disadvantage on the bleeding
      // character's own status-resistance roll (see the 'Bleeding' group
      // below) rather than needing a special-cased workaround.
      const samples = 5000;

      int successesWithMode(RollMode mode) {
        final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(3)));
        var count = 0;
        for (var i = 0; i < samples; i++) {
          final context = RollContext();
          if (mode == RollMode.disadvantage) context.addDisadvantage('x');
          if (mode == RollMode.advantage) context.addAdvantage('x');
          final outcome = engine.resolveInfliction(
            causerInfliction: 10,
            targetResistance: 0,
            targetRollContext: context,
          );
          if (outcome.applies) count++;
        }
        return count;
      }

      final normalSuccesses = successesWithMode(RollMode.normal);
      final disadvantageSuccesses = successesWithMode(RollMode.disadvantage);
      final advantageSuccesses = successesWithMode(RollMode.advantage);
      expect(disadvantageSuccesses, greaterThan(normalSuccesses));
      expect(advantageSuccesses, lessThan(normalSuccesses));
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
        'Bleeding grants disadvantage on the bleeding character\'s own status resistance roll '
        '(so it is actually a debuff - see resolveInfliction doc comment)', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      engine.apply(state, 'bleeding');

      final context = state.rollContextFor(StatusRollTag.statusResistanceRoll);
      expect(context.hasDisadvantage, isTrue);
      expect(context.hasAdvantage, isFalse);
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
          final outcome = engine.resolveInfliction(
            causerInfliction: 10,
            targetResistance: 0,
            targetRollContext: context,
          );
          if (outcome.applies) count++;
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

  group('StatusEffectCatalog.defaultCatalog completeness', () {
    test('has exactly 63 built-in effects', () {
      expect(StatusEffectCatalog.defaultCatalog.all, hasLength(63));
    });

    test('every effect has a unique id', () {
      final ids = StatusEffectCatalog.defaultCatalog.all.map((d) => d.id);
      expect(ids.toSet(), hasLength(ids.length));
    });
  });

  group('Focused / Hastened (advantageRollTags)', () {
    test('Focused grants advantage on attack rolls only', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      engine.apply(state, 'focused');
      expect(
          state.rollContextFor(StatusRollTag.attackRoll).hasAdvantage, isTrue);
      expect(state.rollContextFor(StatusRollTag.rangedAttackRoll).hasAdvantage,
          isFalse);
    });

    test('Hastened grants advantage plus +Attack per remaining turn', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state =
          CharacterBattleState(testCharacter(stats: testStats(attack: 10)));
      engine.apply(state, 'hastened', durationOverride: 2);
      expect(
          state.rollContextFor(StatusRollTag.attackRoll).hasAdvantage, isTrue);
      expect(state.effectiveStats().attack, 12); // 10 + 1*2
    });
  });

  group('Guarded / Exposed / Marked (allDamageTakenMultiplier)', () {
    test('Guarded reduces all incoming damage regardless of type', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      engine.apply(state, 'guarded');
      expect(state.statusDamageTypeMultiplier(DamageType.fire),
          StatusEffectMagnitudes.defaults.guardedAllDamageTakenMultiplier);
      expect(state.statusDamageTypeMultiplier(DamageType.psychic),
          StatusEffectMagnitudes.defaults.guardedAllDamageTakenMultiplier);
    });

    test('Exposed raises all incoming damage regardless of type', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      engine.apply(state, 'exposed');
      expect(state.statusDamageTypeMultiplier(DamageType.bludgeoning),
          StatusEffectMagnitudes.defaults.exposedAllDamageTakenMultiplier);
    });

    test('Marked grants the source advantage against the marked target', () {
      final def = StatusEffectCatalog.defaultCatalog['marked'];
      expect(def.sourceHasAdvantageAgainstTarget, isTrue);
      expect(def.allDamageTakenMultiplier, greaterThan(1.0));
    });
  });

  group('Empowered / Weakened (outgoingDamageMultiplier)', () {
    test(
        'outgoingDamageMultiplier combines multiplicatively from all active '
        'effects', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      expect(state.outgoingDamageMultiplier(), 1.0);

      engine.apply(state, 'empowered');
      expect(state.outgoingDamageMultiplier(),
          StatusEffectMagnitudes.defaults.empoweredOutgoingDamageMultiplier);

      engine.apply(state, 'weakened');
      expect(
        state.outgoingDamageMultiplier(),
        closeTo(
          StatusEffectMagnitudes.defaults.empoweredOutgoingDamageMultiplier *
              StatusEffectMagnitudes.defaults.weakenedOutgoingDamageMultiplier,
          1e-9,
        ),
      );
    });
  });

  group('Cursed / Necrotic Wound (preventsHealing)', () {
    test('a cursed character is flagged as healing-prevented', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      expect(state.isHealingPrevented(), isFalse);
      engine.apply(state, 'cursed');
      expect(state.isHealingPrevented(), isTrue);
    });
  });

  group('Overcharged / Choked (trionCostMultiplier)', () {
    test(
        'trionCostMultiplier combines multiplicatively from all active '
        'effects', () {
      final engine = StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final state = CharacterBattleState(testCharacter());
      expect(state.trionCostMultiplier(), 1.0);

      engine.apply(state, 'overcharged');
      expect(state.trionCostMultiplier(),
          StatusEffectMagnitudes.defaults.overchargedTrionCostMultiplier);
    });
  });
}

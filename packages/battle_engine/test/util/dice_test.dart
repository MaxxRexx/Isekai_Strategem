import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

void main() {
  group('DiceRoller.rollD20', () {
    test('normal roll only rolls one die', () {
      final roller = DiceRoller(Random(1));
      final result = roller.rollD20();
      expect(result.rawRolls, hasLength(1));
      expect(result.kept, result.rawRolls.single);
    });

    test('advantage keeps the higher of two dice', () {
      final roller = DiceRoller(Random(42));
      for (var i = 0; i < 200; i++) {
        final result = roller.rollD20(mode: RollMode.advantage);
        expect(result.rawRolls, hasLength(2));
        expect(result.kept, max(result.rawRolls[0], result.rawRolls[1]));
      }
    });

    test('disadvantage keeps the lower of two dice', () {
      final roller = DiceRoller(Random(42));
      for (var i = 0; i < 200; i++) {
        final result = roller.rollD20(mode: RollMode.disadvantage);
        expect(result.rawRolls, hasLength(2));
        expect(result.kept, min(result.rawRolls[0], result.rawRolls[1]));
      }
    });

    test('advantage distribution skews higher than normal on average', () {
      final normalRoller = DiceRoller(Random(7));
      final advantageRoller = DiceRoller(Random(7));
      const samples = 20000;

      var normalTotal = 0;
      var advantageTotal = 0;
      for (var i = 0; i < samples; i++) {
        normalTotal += normalRoller.rollD20().kept;
        advantageTotal +=
            advantageRoller.rollD20(mode: RollMode.advantage).kept;
      }

      final normalAvg = normalTotal / samples;
      final advantageAvg = advantageTotal / samples;

      // Expected value: normal d20 ~10.5, advantage ~13.825.
      expect(normalAvg, closeTo(10.5, 0.3));
      expect(advantageAvg, closeTo(13.825, 0.3));
      expect(advantageAvg, greaterThan(normalAvg));
    });

    test('disadvantage distribution skews lower than normal on average', () {
      final normalRoller = DiceRoller(Random(9));
      final disadvantageRoller = DiceRoller(Random(9));
      const samples = 20000;

      var normalTotal = 0;
      var disadvantageTotal = 0;
      for (var i = 0; i < samples; i++) {
        normalTotal += normalRoller.rollD20().kept;
        disadvantageTotal +=
            disadvantageRoller.rollD20(mode: RollMode.disadvantage).kept;
      }

      final normalAvg = normalTotal / samples;
      final disadvantageAvg = disadvantageTotal / samples;

      // Expected value: normal d20 ~10.5, disadvantage ~7.175.
      expect(normalAvg, closeTo(10.5, 0.3));
      expect(disadvantageAvg, closeTo(7.175, 0.3));
      expect(disadvantageAvg, lessThan(normalAvg));
    });

    test('natural 20/1 are evaluated against the kept die', () {
      final roller = DiceRoller(Random(5));
      var sawCrit = false;
      var sawCritMiss = false;
      for (var i = 0; i < 5000 && !(sawCrit && sawCritMiss); i++) {
        final result = roller.rollD20(mode: RollMode.advantage);
        if (result.kept == 20) {
          expect(result.isCriticalHit, isTrue);
          sawCrit = true;
        }
        if (result.kept == 1) {
          expect(result.isCriticalMiss, isTrue);
          sawCritMiss = true;
        }
      }
      expect(sawCrit, isTrue);
      expect(sawCritMiss, isTrue);
    });

    test('modifier is added to total but not to the kept die', () {
      final roller = DiceRoller(Random(3));
      final result = roller.rollD20(modifier: 5);
      expect(result.total, result.kept + 5);
    });
  });

  group('RollContext', () {
    test('multiple advantage sources still net to plain advantage', () {
      final context = RollContext()
        ..addAdvantage('a')
        ..addAdvantage('b');
      expect(context.netMode, RollMode.advantage);
    });

    test('multiple disadvantage sources still net to plain disadvantage', () {
      final context = RollContext()
        ..addDisadvantage('a')
        ..addDisadvantage('b');
      expect(context.netMode, RollMode.disadvantage);
    });

    test('advantage and disadvantage cancel out to normal', () {
      final context = RollContext()
        ..addAdvantage('a')
        ..addDisadvantage('b');
      expect(context.netMode, RollMode.normal);
    });

    test('no sources is normal', () {
      expect(RollContext().netMode, RollMode.normal);
    });
  });

  group('DiceExpression', () {
    test('rolls within the expected range', () {
      final roller = DiceRoller(Random(11));
      const expr = DiceExpression(1, 4);
      for (var i = 0; i < 500; i++) {
        final value = expr.roll(roller);
        expect(value, inInclusiveRange(1, 4));
      }
    });

    test('flat bonus is added after the dice roll', () {
      final roller = DiceRoller(Random(11));
      const expr = DiceExpression(0, 1, flatBonus: 2);
      expect(expr.roll(roller), 2);
    });
  });
}

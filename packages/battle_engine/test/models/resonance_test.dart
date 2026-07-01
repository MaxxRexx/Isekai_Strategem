import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ResonanceGrid.defaultGrid', () {
    test('matches the specified grid exactly', () {
      const grid = ResonanceGrid.defaultGrid;

      final expected = {
        CharacterType.attack: {
          BlackTriggerType.attack: ResonanceGrade.a,
          BlackTriggerType.defense: ResonanceGrade.b,
          BlackTriggerType.support: ResonanceGrade.c,
          BlackTriggerType.unique: ResonanceGrade.a,
        },
        CharacterType.defense: {
          BlackTriggerType.attack: ResonanceGrade.c,
          BlackTriggerType.defense: ResonanceGrade.a,
          BlackTriggerType.support: ResonanceGrade.s,
          BlackTriggerType.unique: ResonanceGrade.b,
        },
        CharacterType.support: {
          BlackTriggerType.attack: ResonanceGrade.d,
          BlackTriggerType.defense: ResonanceGrade.a,
          BlackTriggerType.support: ResonanceGrade.a,
          BlackTriggerType.unique: ResonanceGrade.b,
        },
        CharacterType.unique: {
          BlackTriggerType.attack: ResonanceGrade.b,
          BlackTriggerType.defense: ResonanceGrade.b,
          BlackTriggerType.support: ResonanceGrade.b,
          BlackTriggerType.unique: ResonanceGrade.b,
        },
      };

      for (final characterType in CharacterType.values) {
        for (final blackTriggerType in BlackTriggerType.values) {
          expect(
            grid.lookup(characterType, blackTriggerType),
            expected[characterType]![blackTriggerType],
            reason: '$characterType x $blackTriggerType',
          );
        }
      }
    });

    test('Defense char x Support Black Trigger is the sole S grade', () {
      const grid = ResonanceGrid.defaultGrid;
      var sCount = 0;
      for (final characterType in CharacterType.values) {
        for (final blackTriggerType in BlackTriggerType.values) {
          if (grid.lookup(characterType, blackTriggerType) ==
              ResonanceGrade.s) {
            sCount++;
            expect(characterType, CharacterType.defense);
            expect(blackTriggerType, BlackTriggerType.support);
          }
        }
      }
      expect(sCount, 1);
    });
  });

  group('ResonanceMultipliers', () {
    test('defaults are strictly ordered S > A > B > C > D', () {
      const multipliers = ResonanceMultipliers.defaults;
      expect(
        multipliers.multiplierFor(ResonanceGrade.s),
        greaterThan(multipliers.multiplierFor(ResonanceGrade.a)),
      );
      expect(
        multipliers.multiplierFor(ResonanceGrade.a),
        greaterThan(multipliers.multiplierFor(ResonanceGrade.b)),
      );
      expect(
        multipliers.multiplierFor(ResonanceGrade.b),
        greaterThan(multipliers.multiplierFor(ResonanceGrade.c)),
      );
      expect(
        multipliers.multiplierFor(ResonanceGrade.c),
        greaterThan(multipliers.multiplierFor(ResonanceGrade.d)),
      );
    });

    test(
        'an extended custom scale is a drop-in replacement (no interface change)',
        () {
      final extended = ResonanceMultipliers({
        ...const {
          ResonanceGrade.s: 1.5,
          ResonanceGrade.a: 1.25,
          ResonanceGrade.b: 1.1,
          ResonanceGrade.c: 1.0,
          ResonanceGrade.d: 0.85,
        },
      });
      expect(extended.multiplierFor(ResonanceGrade.s), 1.5);
    });

    test('throws for an unconfigured grade rather than silently defaulting',
        () {
      const multipliers = ResonanceMultipliers({ResonanceGrade.a: 1.0});
      expect(() => multipliers.multiplierFor(ResonanceGrade.d),
          throwsArgumentError);
    });
  });
}

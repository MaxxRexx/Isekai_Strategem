import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/battle_models.dart';
import 'package:isekai_strategem/src/widgets/log_view.dart';

/// Raised in the #2 playtest, against a log line reading
/// `1+6+2+3+2+6+23 = 43`: the owner asked what it meant and whether the game
/// was rolling several dice. It is (Twin Fang Strike is 6d6+23), but the flat
/// bonus was printed in the same additive chain as the dice, so it read as a
/// seventh die that had somehow rolled 23 on a d6.
///
/// The two are separate steps now. These pin that, because the fix is copy
/// and copy is the first thing to drift back.
void main() {
  LogDamageDetail detail({
    List<int> rolls = const [1, 6, 2, 3, 2, 6],
    int sides = 6,
    int flat = 23,
  }) {
    final diceTotal = rolls.fold<int>(0, (sum, d) => sum + d) + flat;
    return LogDamageDetail(
      diceRawRolls: rolls,
      diceFlatBonus: flat,
      diceTotal: diceTotal,
      diceSides: sides,
      preCritMultiplier: 1.0,
      prevented: false,
      criticalHitApplied: false,
      criticalHitMultiplier: 2.0,
      criticalBonusDamage: 0,
      afterCriticalHit: diceTotal,
      armor: 1,
      afterArmor: diceTotal - 1,
      statusDamageTypeMultiplier: 1.0,
      damageResistanceApplied: false,
      finalDamage: diceTotal - 1,
    );
  }

  group('the model separates the dice from the flat bonus', () {
    test('Twin Fang Strike reads as 6d6 plus 23, not seven numbers', () {
      final d = detail();
      expect(d.diceNotation, '6d6');
      expect(d.diceRollsDescribe, '1+6+2+3+2+6');
      expect(d.diceRollsTotal, 20);
      expect(d.flatBonusDescribe, '+23');
      expect(d.diceTotal, 43);
      // The old rendering, which is what confused the reader.
      expect(d.diceRollsDescribe, isNot(contains('23')));
    });

    test('Frag Grenade reads as 3d6 plus 9', () {
      final d = detail(rolls: const [1, 3, 6], flat: 9);
      expect(d.diceNotation, '3d6');
      expect(d.diceRollsTotal, 10);
      expect(d.diceTotal, 19);
    });

    test('an ability with no flat bonus says so by omission', () {
      final d = detail(rolls: const [4, 4], flat: 0);
      expect(d.flatBonusDescribe, isEmpty);
      expect(d.diceTotal, 8);
    });

    test('a negative flat bonus keeps its sign', () {
      final d = detail(rolls: const [5], flat: -2);
      expect(d.flatBonusDescribe, '-2');
    });
  });

  group('the engine carries the die size so the log can name it', () {
    test('a rolled expression knows how many faces it had', () {
      final roll = const DiceExpression(3, 8, flatBonus: 4)
          .rollDetailed(DiceRoller(Random(1)));
      expect(roll.sides, 8);
      expect(roll.rawRolls, hasLength(3));
      expect(roll.notation, '3d8');
      expect(roll.flatBonus, 4);
      expect(
        roll.total,
        roll.rawRolls.fold<int>(0, (sum, d) => sum + d) + 4,
      );
    });
  });

  group('the log renders the two steps apart', () {
    const roll = LogDiceRoll(
      rawRolls: [16],
      kept: 16,
      mode: RollMode.normal,
      modifier: 10,
      total: 26,
    );

    testWidgets('the dice and the bonus are separate clauses', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RollBreakdownView(
              actorName: 'Vela Ashworth',
              abilityName: 'Twin Fang Strike',
              targetName: 'Kaito Reyes',
              rolls: [
                LogRollBreakdown(
                  attackerRoll: roll,
                  defenderRoll: roll,
                  isHit: true,
                  isCriticalHit: false,
                  isCriticalMiss: false,
                  damage: 42,
                  damageDetail: detail(),
                ),
              ],
              statusEffectsApplied: const [],
              healthAfter: 58,
              died: false,
            ),
          ),
        ),
      );

      // Every line of the panel, as the player reads it. The breakdown is a
      // bullet per step now rather than one run-on sentence, so the dice and
      // the bonus are separate lines and not merely separate clauses.
      final lines = [
        for (final w in tester.widgetList<Text>(find.byType(Text)))
          w.textSpan?.toPlainText() ?? w.data ?? '',
      ];
      final text = lines.join(' ');

      expect(lines.any((l) => l.contains('Rolls 6d6: 1+6+2+3+2+6 = 20')), isTrue,
          reason: 'the dice are one step: notation, the rolls, the total');
      expect(lines.any((l) => l.contains('flat +23') && l.contains('43')), isTrue,
          reason: 'and the flat bonus is the next one');
      // The chain that started all this must not come back.
      expect(text, isNot(contains('1+6+2+3+2+6+23')));
    });
  });
}

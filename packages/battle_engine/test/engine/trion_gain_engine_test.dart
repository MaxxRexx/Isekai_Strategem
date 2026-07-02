import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

void main() {
  group('TrionGainEngine', () {
    test(
        'with zero affinity/modifier, tier frequencies match configured base chances',
        () {
      const config = TrionTierConfig(
        baseChanceLowToMedium: 0.4,
        baseChanceMediumToHigh: 0.25,
        affinityWeightPerPoint: 0.01,
      );
      final engine =
          TrionGainEngine(config: config, diceRoller: DiceRoller(Random(123)));

      const samples = 50000;
      final counts = {for (final t in TrionTier.values) t: 0};
      for (var i = 0; i < samples; i++) {
        final result = engine.rollTier(sumLivingTrionAffinity: 0);
        counts[result.tier] = counts[result.tier]! + 1;
      }

      final pMedium = counts[TrionTier.medium]! / samples;
      final pHigh = counts[TrionTier.high]! / samples;
      final pLow = counts[TrionTier.low]! / samples;

      // P(reach medium-or-higher) ~= baseChanceLowToMedium (0.4)
      expect(pMedium + pHigh, closeTo(0.4, 0.02));
      // P(high) ~= baseChanceLowToMedium * baseChanceMediumToHigh (0.4*0.25=0.10)
      expect(pHigh, closeTo(0.10, 0.02));
      // P(low) ~= 1 - 0.4
      expect(pLow, closeTo(0.6, 0.02));
    });

    test('higher summed Trion Affinity increases probability of higher tiers',
        () {
      const config = TrionTierConfig(
        baseChanceLowToMedium: 0.2,
        baseChanceMediumToHigh: 0.1,
        affinityWeightPerPoint: 0.02,
      );

      const samples = 30000;

      double highOrMediumRate(int affinitySum) {
        final engine = TrionGainEngine(
            config: config, diceRoller: DiceRoller(Random(999)));
        var count = 0;
        for (var i = 0; i < samples; i++) {
          final result = engine.rollTier(sumLivingTrionAffinity: affinitySum);
          if (result.tier != TrionTier.low) count++;
        }
        return count / samples;
      }

      final lowAffinityRate = highOrMediumRate(0);
      final highAffinityRate = highOrMediumRate(20);

      expect(highAffinityRate, greaterThan(lowAffinityRate));
    });

    test('active gameplay modifiers can raise or lower the odds', () {
      const config = TrionTierConfig(
          baseChanceLowToMedium: 0.3, baseChanceMediumToHigh: 0.2);
      const samples = 20000;

      double upgradeRate(double modifier) {
        final engine =
            TrionGainEngine(config: config, diceRoller: DiceRoller(Random(55)));
        var count = 0;
        for (var i = 0; i < samples; i++) {
          final result =
              engine.rollTier(sumLivingTrionAffinity: 0, modifier: modifier);
          if (result.tier != TrionTier.low) count++;
        }
        return count / samples;
      }

      expect(upgradeRate(0.2), greaterThan(upgradeRate(0.0)));
      expect(upgradeRate(-0.2), lessThan(upgradeRate(0.0)));
    });

    test('probabilities are clamped and never throw for extreme inputs', () {
      final engine = TrionGainEngine(diceRoller: DiceRoller(Random(1)));
      expect(() => engine.rollTier(sumLivingTrionAffinity: 100000),
          returnsNormally);
      expect(() => engine.rollTier(sumLivingTrionAffinity: -100000),
          returnsNormally);
    });

    test('grants the configured Trion amount for each tier', () {
      const config = TrionTierConfig(
        baseChanceLowToMedium: 1.0,
        baseChanceMediumToHigh: 1.0,
        lowAmount: 10,
        mediumAmount: 20,
        highAmount: 35,
      );
      final engine =
          TrionGainEngine(config: config, diceRoller: DiceRoller(Random(1)));
      final result = engine.rollTier(sumLivingTrionAffinity: 0);
      expect(result.tier, TrionTier.high);
      expect(result.amount, 35);
    });
  });
}

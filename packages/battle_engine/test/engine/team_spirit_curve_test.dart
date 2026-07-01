import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

void main() {
  group('TeamSpiritCurve', () {
    const curve = TeamSpiritCurve();

    test('at the midpoint, no bonuses apply in either direction', () {
      final bonuses = curve.bonusesFor(50);
      expect(bonuses.singleTargetDamageBonus, 0);
      expect(bonuses.burstDamageBonus, 0);
      expect(bonuses.criticalChanceBonus, 0);
      expect(bonuses.healthRegenBonus, 0);
      expect(bonuses.fatChanceBonus, 0);
    });

    test('below the midpoint boosts offense, not sustain', () {
      final bonuses = curve.bonusesFor(0);
      expect(
          bonuses.singleTargetDamageBonus,
          closeTo(
              TeamSpiritCurveConfig.defaults.maxSingleTargetDamageBonus, 1e-9));
      expect(bonuses.burstDamageBonus,
          closeTo(TeamSpiritCurveConfig.defaults.maxBurstDamageBonus, 1e-9));
      expect(bonuses.criticalChanceBonus,
          closeTo(TeamSpiritCurveConfig.defaults.maxCriticalChanceBonus, 1e-9));
      expect(bonuses.healthRegenBonus, 0);
      expect(bonuses.fatChanceBonus, 0);
    });

    test('above the midpoint boosts sustain, not offense', () {
      final bonuses = curve.bonusesFor(100);
      expect(bonuses.singleTargetDamageBonus, 0);
      expect(bonuses.burstDamageBonus, 0);
      expect(bonuses.criticalChanceBonus, 0);
      expect(bonuses.healthRegenBonus,
          closeTo(TeamSpiritCurveConfig.defaults.maxHealthRegenBonus, 1e-9));
      expect(bonuses.fatChanceBonus,
          closeTo(TeamSpiritCurveConfig.defaults.maxFatChanceBonus, 1e-9));
    });

    test('bonuses scale linearly with distance from the midpoint', () {
      final quarterBelow =
          curve.bonusesFor(25); // halfway between 0 and midpoint(50)
      expect(
        quarterBelow.singleTargetDamageBonus,
        closeTo(TeamSpiritCurveConfig.defaults.maxSingleTargetDamageBonus / 2,
            1e-9),
      );

      final quarterAbove =
          curve.bonusesFor(75); // halfway between midpoint(50) and 100
      expect(
        quarterAbove.healthRegenBonus,
        closeTo(TeamSpiritCurveConfig.defaults.maxHealthRegenBonus / 2, 1e-9),
      );
    });

    test('values are clamped to the configured stat range', () {
      final belowMin = curve.bonusesFor(-1000);
      final atMin = curve.bonusesFor(0);
      expect(belowMin.singleTargetDamageBonus, atMin.singleTargetDamageBonus);

      final aboveMax = curve.bonusesFor(1000);
      final atMax = curve.bonusesFor(100);
      expect(aboveMax.fatChanceBonus, atMax.fatChanceBonus);
    });

    test('a custom config is a drop-in replacement', () {
      const customCurve = TeamSpiritCurve(
        TeamSpiritCurveConfig(maxSingleTargetDamageBonus: 0.5),
      );
      expect(customCurve.bonusesFor(0).singleTargetDamageBonus,
          closeTo(0.5, 1e-9));
    });
  });
}

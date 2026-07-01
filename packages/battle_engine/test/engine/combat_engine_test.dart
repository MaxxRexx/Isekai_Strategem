import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group('CombatEngine.resolveAttackRoll', () {
    test('higher total wins; a tie favors the attacker (hit)', () {
      // Force both d20 rolls to come up 10 (attacker rolls first, then
      // defender), with equal modifiers, so the totals tie exactly.
      final engine =
          CombatEngine(diceRoller: DiceRoller(SequenceRandom([9, 9])));
      final outcome =
          engine.resolveAttackRoll(attackerAttack: 5, defenderDefense: 5);

      expect(outcome.attackerRoll.total, outcome.defenderRoll.total);
      expect(outcome.isHit, isTrue);
    });

    test('a huge attack bonus hits essentially always', () {
      final engine = CombatEngine(diceRoller: DiceRoller(Random(1)));

      var hits = 0;
      const samples = 500;
      for (var i = 0; i < samples; i++) {
        final outcome =
            engine.resolveAttackRoll(attackerAttack: 100, defenderDefense: 0);
        if (outcome.isHit) hits++;
      }
      expect(hits,
          greaterThan(samples - 30)); // allow for the rare nat-1 crit miss
    });

    test(
        'a natural 20 for the attacker is always a critical hit, doubling damage',
        () {
      final engine = CombatEngine(diceRoller: DiceRoller(Random(3)));
      var sawCrit = false;
      for (var i = 0; i < 2000 && !sawCrit; i++) {
        // Force a big disadvantage for the attacker's total so only a
        // natural 20 could possibly win, then check crit flag correlates.
        final outcome =
            engine.resolveAttackRoll(attackerAttack: -1000, defenderDefense: 0);
        if (outcome.attackerRoll.kept == 20) {
          expect(outcome.isCriticalHit, isTrue);
          expect(outcome.isHit, isTrue);
          sawCrit = true;
        }
      }
      expect(sawCrit, isTrue);
    });

    test('a natural 1 for the attacker is always a critical miss (auto-miss)',
        () {
      final engine = CombatEngine(diceRoller: DiceRoller(Random(4)));
      var sawCritMiss = false;
      for (var i = 0; i < 2000 && !sawCritMiss; i++) {
        // Force a huge attack bonus so only a natural 1 could possibly lose.
        final outcome =
            engine.resolveAttackRoll(attackerAttack: 1000, defenderDefense: 0);
        if (outcome.attackerRoll.kept == 1) {
          expect(outcome.isCriticalMiss, isTrue);
          expect(outcome.isHit, isFalse);
          sawCritMiss = true;
        }
      }
      expect(sawCritMiss, isTrue);
    });
  });

  group('CombatEngine.resolveBurst', () {
    test('rolls one independent to-hit roll per hit', () {
      final engine = CombatEngine(diceRoller: DiceRoller(Random(5)));
      final outcomes =
          engine.resolveBurst(hits: 4, attackerAttack: 5, defenderDefense: 5);
      expect(outcomes, hasLength(4));
      // Not all rolls should be identical (sanity check they're independent).
      final keptValues = outcomes.map((o) => o.attackerRoll.kept).toSet();
      expect(keptValues.length, greaterThan(1));
    });
  });

  group('CombatEngine.applyCriticalMissPenalty', () {
    test('reduces the attacker Defense and Team Spirit by 20% for 1 turn', () {
      const config = CombatConfig(
        criticalMissDefensePenaltyPct: 0.20,
        criticalMissTeamSpiritPenaltyPct: 0.20,
        criticalMissPenaltyDurationTurns: 1,
      );
      final engine = CombatEngine(config: config);
      final state = CharacterBattleState(
          testCharacter(stats: testStats(defense: 10, teamSpirit: 50)));

      engine.applyCriticalMissPenalty(state);

      final stats = state.effectiveStats();
      expect(stats.defense, 8); // 10 * 0.8
      expect(stats.teamSpirit, 40); // 50 * 0.8

      state.endTurn();
      final statsAfter = state.effectiveStats();
      expect(statsAfter.defense, 10);
      expect(statsAfter.teamSpirit, 50);
    });
  });

  group('CombatEngine.resolveDamage', () {
    test('critical hits double damage', () {
      final engine = CombatEngine();
      final target =
          CharacterBattleState(testCharacter(stats: testStats(armor: 0)));
      final normal = engine.resolveDamage(
        baseDamage: 10,
        damageType: DamageType.slashing,
        isCriticalHit: false,
        target: target,
      );
      final crit = engine.resolveDamage(
        baseDamage: 10,
        damageType: DamageType.slashing,
        isCriticalHit: true,
        target: target,
      );
      expect(crit, normal * 2);
    });

    test('Armor reduces damage flatly, floored at 0', () {
      final engine = CombatEngine();
      final target =
          CharacterBattleState(testCharacter(stats: testStats(armor: 7)));
      final damage = engine.resolveDamage(
        baseDamage: 10,
        damageType: DamageType.slashing,
        isCriticalHit: false,
        target: target,
      );
      expect(damage, 3);

      final overkillArmorTarget =
          CharacterBattleState(testCharacter(stats: testStats(armor: 999)));
      final flooredDamage = engine.resolveDamage(
        baseDamage: 10,
        damageType: DamageType.slashing,
        isCriticalHit: false,
        target: overkillArmorTarget,
      );
      expect(flooredDamage, 0);
    });

    test('Damage Resistance halves damage after Armor is applied', () {
      final engine = CombatEngine();
      final target = CharacterBattleState(
        testCharacter(
          stats: testStats(armor: 2),
          damageResistances: {DamageType.slashing},
        ),
      );
      // 10 base - 2 armor = 8, then halved by resistance = 4.
      final damage = engine.resolveDamage(
        baseDamage: 10,
        damageType: DamageType.slashing,
        isCriticalHit: false,
        target: target,
      );
      expect(damage, 4);
    });

    test(
        'Wet: immune to Fire, vulnerable (double damage) to Lightning and Cold',
        () {
      final engine = CombatEngine();
      final statusEngine =
          StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final target =
          CharacterBattleState(testCharacter(stats: testStats(armor: 0)));
      statusEngine.apply(target, 'wet');

      final fireDamage = engine.resolveDamage(
        baseDamage: 10,
        damageType: DamageType.fire,
        isCriticalHit: false,
        target: target,
      );
      expect(fireDamage, 0);

      final lightningDamage = engine.resolveDamage(
        baseDamage: 10,
        damageType: DamageType.lightning,
        isCriticalHit: false,
        target: target,
      );
      expect(lightningDamage, 20);

      final coldDamage = engine.resolveDamage(
        baseDamage: 10,
        damageType: DamageType.cold,
        isCriticalHit: false,
        target: target,
      );
      expect(coldDamage, 20);

      // Unrelated damage types are unaffected.
      final slashingDamage = engine.resolveDamage(
        baseDamage: 10,
        damageType: DamageType.slashing,
        isCriticalHit: false,
        target: target,
      );
      expect(slashingDamage, 10);
    });

    test(
        'Wet + Damage Resistance to the same type: vulnerability then resistance halving',
        () {
      final engine = CombatEngine();
      final statusEngine =
          StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final target = CharacterBattleState(
        testCharacter(
            stats: testStats(armor: 0), damageResistances: {DamageType.cold}),
      );
      statusEngine.apply(target, 'wet');

      // 10 base, - 0 armor = 10, * 2 (vulnerable) * 0.5 (resistance) = 10.
      final damage = engine.resolveDamage(
        baseDamage: 10,
        damageType: DamageType.cold,
        isCriticalHit: false,
        target: target,
      );
      expect(damage, 10);
    });

    test(
        'Armor is applied before damage-type multipliers (5e/BG3 & Rogue Trader order)',
        () {
      final engine = CombatEngine();
      final statusEngine =
          StatusEffectEngine(diceRoller: DiceRoller(Random(1)));
      final target =
          CharacterBattleState(testCharacter(stats: testStats(armor: 3)));
      statusEngine.apply(target, 'wet');

      // Armor first: 10 - 3 = 7. Then the Wet vulnerability multiplier: 7 * 2 = 14.
      // (Applying the multiplier before Armor would instead give (10*2)-3=17.)
      final damage = engine.resolveDamage(
        baseDamage: 10,
        damageType: DamageType.cold,
        isCriticalHit: false,
        target: target,
      );
      expect(damage, 14);
    });
  });
}

import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group('TurnEngine.resolveAbilityUse - single target', () {
    test(
        'a landed hit deals damage, mutates health, and applies status effects',
        () {
      // A huge attack/infliction edge (via stats) still leaves a ~5%
      // chance of an unlucky natural 1 auto-miss/auto-fail (crits/misses
      // are decided by the raw die, not the modifier) - force a natural
      // 20 on every roll via FixedRandom so this test is truly
      // deterministic, not just statistically likely to pass.
      final engine = TurnEngine(
        combatEngine:
            CombatEngine(diceRoller: DiceRoller(const FixedRandom(19))),
        statusEffectEngine:
            StatusEffectEngine(diceRoller: DiceRoller(const FixedRandom(19))),
      );
      final attacker = CharacterBattleState(testCharacter(
        id: 'attacker',
        stats: testStats(attack: 1000, statusEffectInfliction: 1000),
      ));
      final target = CharacterBattleState(testCharacter(
        id: 'target',
        stats: testStats(
            defense: 0,
            armor: 0,
            maxHealth: 100,
            statusEffectResistance: -1000),
      ));
      final trigger = testTrigger(
        damage: const DiceExpression(0, 1, flatBonus: 10),
        inflictedStatusEffects: const [StatusEffectApplication('poisoned')],
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [target],
      );

      expect(result.attackerCharacterId, 'attacker');
      expect(result.triggerId, trigger.id);
      expect(result.targetResults, hasLength(1));

      final targetResult = result.targetResults.single;
      expect(targetResult.targetCharacterId, 'target');
      expect(targetResult.attackRolls, hasLength(1));
      expect(targetResult.attackRolls.single.isHit, isTrue);
      expect(targetResult.totalDamageDealt, greaterThan(0));
      expect(target.currentHealth, 100 - targetResult.totalDamageDealt);
      expect(targetResult.statusEffectsApplied, contains('poisoned'));
      expect(target.statusEffects.map((i) => i.definitionId),
          contains('poisoned'));
    });

    test('a miss deals no damage and applies no status effects', () {
      // A natural 1 always forces this deterministically (a natural 20
      // would otherwise still auto-hit ~5% of the time regardless of how
      // unfavorable the modifiers are).
      final engine = TurnEngine(
        combatEngine:
            CombatEngine(diceRoller: DiceRoller(const FixedRandom(0))),
      );
      final attacker = CharacterBattleState(
          testCharacter(id: 'attacker', stats: testStats(attack: -1000)));
      final target = CharacterBattleState(testCharacter(
        id: 'target',
        stats: testStats(defense: 1000, maxHealth: 100),
      ));
      final trigger = testTrigger(
        inflictedStatusEffects: const [StatusEffectApplication('poisoned')],
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [target],
      );

      final targetResult = result.targetResults.single;
      expect(targetResult.attackRolls.single.isHit, isFalse);
      expect(targetResult.totalDamageDealt, 0);
      expect(targetResult.statusEffectsApplied, isEmpty);
      expect(target.currentHealth, 100);
    });

    test('a critical miss applies the critical-miss penalty to the attacker',
        () {
      final engine = TurnEngine(
          combatEngine: CombatEngine(diceRoller: DiceRoller(Random(4))));
      final attacker = CharacterBattleState(testCharacter(
        id: 'attacker',
        stats: testStats(attack: 1000, defense: 10, teamSpirit: 50),
      ));
      final target = CharacterBattleState(testCharacter(id: 'target'));
      final trigger = testTrigger();

      var sawCriticalMiss = false;
      for (var i = 0; i < 2000 && !sawCriticalMiss; i++) {
        final result = engine.resolveAbilityUse(
          attacker: attacker,
          trigger: trigger,
          targets: [target],
        );
        final outcome = result.targetResults.single.attackRolls.single;
        if (outcome.isCriticalMiss) {
          sawCriticalMiss = true;
          final stats = attacker.effectiveStats();
          expect(stats.defense, lessThan(10));
          expect(stats.teamSpirit, lessThan(50));
        }
      }
      expect(sawCriticalMiss, isTrue);
    });

    test('no targets provided resolves to an empty result', () {
      final engine = TurnEngine();
      final attacker = CharacterBattleState(testCharacter());
      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(),
        targets: const [],
      );
      expect(result.targetResults, isEmpty);
    });

    test(
        'a pure status-inflicting Trigger (no damage) still applies its effect',
        () {
      final engine = TurnEngine(
        combatEngine:
            CombatEngine(diceRoller: DiceRoller(const FixedRandom(19))),
        statusEffectEngine:
            StatusEffectEngine(diceRoller: DiceRoller(const FixedRandom(19))),
      );
      final attacker = CharacterBattleState(testCharacter(
        stats: testStats(attack: 1000, statusEffectInfliction: 1000),
      ));
      final target = CharacterBattleState(testCharacter(
        stats: testStats(
            defense: 0, maxHealth: 100, statusEffectResistance: -1000),
      ));
      final trigger = testTrigger(
        includeDamage: false,
        inflictedStatusEffects: const [StatusEffectApplication('poisoned')],
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [target],
      );

      final targetResult = result.targetResults.single;
      expect(targetResult.totalDamageDealt, 0);
      expect(target.currentHealth, 100);
      expect(targetResult.statusEffectsApplied, contains('poisoned'));
    });

    test('a failed infliction roll leaves damage intact but applies no effect',
        () {
      // Fixed at a non-edge roll (kept 10, not a natural 1/20) so the huge
      // stat differences deterministically decide hit/infliction via the
      // normal total comparison, rather than risking an unlucky nat 1
      // auto-miss or nat 20 auto-succeeding the infliction regardless of
      // the (very unfavorable) Infliction stat.
      final engine = TurnEngine(
        combatEngine:
            CombatEngine(diceRoller: DiceRoller(const FixedRandom(9))),
        statusEffectEngine:
            StatusEffectEngine(diceRoller: DiceRoller(const FixedRandom(9))),
      );
      final attacker = CharacterBattleState(testCharacter(
        stats: testStats(attack: 1000, statusEffectInfliction: -1000),
      ));
      final target = CharacterBattleState(testCharacter(
        stats: testStats(defense: 0, armor: 0, maxHealth: 100),
      ));
      final trigger = testTrigger(
        damage: const DiceExpression(0, 1, flatBonus: 10),
        inflictedStatusEffects: const [StatusEffectApplication('poisoned')],
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [target],
      );

      final targetResult = result.targetResults.single;
      expect(targetResult.totalDamageDealt, greaterThan(0));
      expect(targetResult.statusEffectsApplied, isEmpty);
      expect(target.statusEffects, isEmpty);
    });

    test(
        'an invulnerable target never gains the effect even on a successful roll',
        () {
      final engine = TurnEngine(
        combatEngine:
            CombatEngine(diceRoller: DiceRoller(const FixedRandom(19))),
        statusEffectEngine:
            StatusEffectEngine(diceRoller: DiceRoller(const FixedRandom(19))),
      );
      final attacker = CharacterBattleState(testCharacter(
        stats: testStats(attack: 1000, statusEffectInfliction: 1000),
      ));
      final target = CharacterBattleState(testCharacter(
        stats: testStats(defense: 0, statusEffectResistance: -1000),
        statusInvulnerabilities: {'poisoned'},
      ));
      final trigger = testTrigger(
        inflictedStatusEffects: const [StatusEffectApplication('poisoned')],
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [target],
      );

      expect(result.targetResults.single.statusEffectsApplied, isEmpty);
      expect(target.statusEffects, isEmpty);
    });
  });

  group('TurnEngine.resolveAbilityUse - AoE', () {
    test('hits every provided target exactly once', () {
      final engine = TurnEngine();
      final attacker =
          CharacterBattleState(testCharacter(stats: testStats(attack: 1000)));
      final targets = List.generate(
          3, (i) => CharacterBattleState(testCharacter(id: 'target-$i')));
      final trigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.aoe,
        targetCount: 3,
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: targets,
      );

      expect(result.targetResults, hasLength(3));
      for (final targetResult in result.targetResults) {
        expect(targetResult.attackRolls, hasLength(1));
      }
    });
  });

  group('TurnEngine.resolveAbilityUse - Burst', () {
    test('hits each target hitsPerUse times independently', () {
      final engine = TurnEngine();
      final attacker = CharacterBattleState(testCharacter());
      final targetA = CharacterBattleState(testCharacter(id: 'a'));
      final targetB = CharacterBattleState(testCharacter(id: 'b'));
      final trigger = testTrigger(
        rangeTag: RangeTag.long,
        attackType: AttackType.ranged,
        attackSubtype: AttackSubtype.burst,
        hitsPerUse: 5,
        targetCount: 2,
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [targetA, targetB],
      );

      final byId = {
        for (final r in result.targetResults) r.targetCharacterId: r
      };
      // targetCount governs how many targets can be hit at all;
      // hitsPerUse governs how many times each one hit is hit - the two
      // are independent, so both targets get the full hitsPerUse count.
      expect(byId['a']!.attackRolls, hasLength(5));
      expect(byId['b']!.attackRolls, hasLength(5));
    });

    test('targetCount clamps how many targets a Burst ability can reach', () {
      final engine = TurnEngine();
      final attacker = CharacterBattleState(testCharacter());
      final targets = List.generate(
          3, (i) => CharacterBattleState(testCharacter(id: 'target-$i')));
      final trigger = testTrigger(
        rangeTag: RangeTag.long,
        attackType: AttackType.ranged,
        attackSubtype: AttackSubtype.burst,
        hitsPerUse: 2,
        targetCount: 2,
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: targets, // 3 provided, but targetCount only allows 2
      );

      expect(result.targetResults, hasLength(2));
      for (final targetResult in result.targetResults) {
        expect(targetResult.attackRolls, hasLength(2));
      }
      expect(result.targetResults.map((r) => r.targetCharacterId),
          containsAll(['target-0', 'target-1']));
    });

    test('uses burstDamageBonus, not singleTargetDamageBonus', () {
      const curveConfig = TeamSpiritCurveConfig(
        maxSingleTargetDamageBonus: 0.0,
        maxBurstDamageBonus: 1.0, // +100% at the low extreme
      );
      // Fixed at a non-edge roll (kept 10) so the huge attack stat
      // deterministically decides the hit via the normal total
      // comparison, without an unlucky nat 1 auto-miss or a nat 20
      // doubling damage and throwing off these exact-value assertions.
      final engine = TurnEngine(
        teamSpiritCurve: const TeamSpiritCurve(curveConfig),
        combatEngine:
            CombatEngine(diceRoller: DiceRoller(const FixedRandom(9))),
      );
      final attacker = CharacterBattleState(testCharacter(
        stats: testStats(attack: 1000, teamSpirit: 0), // low extreme
      ));

      final singleTarget = CharacterBattleState(
          testCharacter(id: 'single', stats: testStats(armor: 0)));
      final singleTrigger = testTrigger(
        attackSubtype: AttackSubtype.single,
        damage: const DiceExpression(0, 1, flatBonus: 10),
      );
      final singleResult = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: singleTrigger,
        targets: [singleTarget],
      );
      expect(singleResult.targetResults.single.totalDamageDealt, 10);

      final burstTarget = CharacterBattleState(
          testCharacter(id: 'burst', stats: testStats(armor: 0)));
      final burstTrigger = testTrigger(
        rangeTag: RangeTag.long,
        attackType: AttackType.ranged,
        attackSubtype: AttackSubtype.burst,
        hitsPerUse: 1,
        targetCount: 1,
        damage: const DiceExpression(0, 1, flatBonus: 10),
      );
      final burstResult = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: burstTrigger,
        targets: [burstTarget],
      );
      expect(burstResult.targetResults.single.totalDamageDealt,
          20); // 10 * (1 + 1.0)
    });
  });

  group('Blinded targeting restriction', () {
    test('reduces ranged target count by 1 (minimum 1)', () {
      final engine = TurnEngine();
      final attacker = CharacterBattleState(testCharacter());
      engine.statusEffectEngine.apply(attacker, 'blinded');

      final rangedTrigger = testTrigger(
        rangeTag: RangeTag.long,
        attackType: AttackType.ranged,
        attackSubtype: AttackSubtype.aoe,
        targetCount: 3,
      );
      expect(engine.maxRangedTargets(attacker, rangedTrigger), 2);

      final floorTrigger = testTrigger(
        rangeTag: RangeTag.long,
        attackType: AttackType.ranged,
        attackSubtype: AttackSubtype.single,
        targetCount: 1,
      );
      expect(engine.maxRangedTargets(attacker, floorTrigger), 1);
    });

    test('does not affect melee Triggers', () {
      final engine = TurnEngine();
      final attacker = CharacterBattleState(testCharacter());
      engine.statusEffectEngine.apply(attacker, 'blinded');

      final meleeTrigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.aoe,
        targetCount: 3,
      );
      expect(engine.maxRangedTargets(attacker, meleeTrigger), 3);
    });

    test('resolveAbilityUse defensively clamps to the reduced target count',
        () {
      final engine = TurnEngine();
      final attacker =
          CharacterBattleState(testCharacter(stats: testStats(attack: 1000)));
      engine.statusEffectEngine.apply(attacker, 'blinded');
      final targets = List.generate(
          3, (i) => CharacterBattleState(testCharacter(id: 'target-$i')));
      final trigger = testTrigger(
        rangeTag: RangeTag.long,
        attackType: AttackType.ranged,
        attackSubtype: AttackSubtype.aoe,
        targetCount: 3,
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: targets,
      );

      expect(result.targetResults, hasLength(2));
    });
  });

  group('Charmed targeting restriction', () {
    test('canTarget blocks the charmed character from targeting their charmer',
        () {
      final engine = TurnEngine();
      final charmer = CharacterBattleState(testCharacter(id: 'charmer'));
      final victim = CharacterBattleState(testCharacter(id: 'victim'));
      final bystander = CharacterBattleState(testCharacter(id: 'bystander'));
      engine.statusEffectEngine
          .apply(victim, 'charmed', sourceCharacterId: 'charmer');

      expect(engine.canTarget(victim, charmer), isFalse);
      expect(engine.canTarget(victim, bystander), isTrue);
    });

    test(
        'the charmer has a higher observed hit rate against the charmed target',
        () {
      final engine = TurnEngine(
          combatEngine: CombatEngine(diceRoller: DiceRoller(Random(8))));
      final charmer = CharacterBattleState(
          testCharacter(id: 'charmer', stats: testStats(attack: 5)));
      final charmedTarget = CharacterBattleState(
          testCharacter(id: 'charmed', stats: testStats(defense: 5)));
      final plainTarget = CharacterBattleState(
          testCharacter(id: 'plain', stats: testStats(defense: 5)));
      engine.statusEffectEngine
          .apply(charmedTarget, 'charmed', sourceCharacterId: 'charmer');

      const samples = 3000;
      int hitCount(CharacterBattleState target) {
        var count = 0;
        for (var i = 0; i < samples; i++) {
          final result = engine.resolveAbilityUse(
            attacker: charmer,
            trigger: testTrigger(),
            targets: [target],
          );
          if (result.targetResults.single.attackRolls.single.isHit) count++;
        }
        return count;
      }

      final charmedHitRate = hitCount(charmedTarget);
      final plainHitRate = hitCount(plainTarget);
      expect(charmedHitRate, greaterThan(plainHitRate));
    });
  });

  group('Critical Chance / Team Spirit integration', () {
    test('low Team Spirit raises both observed crit rate and average damage',
        () {
      const curveConfig = TeamSpiritCurveConfig(
        maxCriticalChanceBonus: 90,
        maxSingleTargetDamageBonus: 1.0,
      );
      final lowSpiritEngine =
          TurnEngine(teamSpiritCurve: const TeamSpiritCurve(curveConfig));
      final midSpiritEngine =
          TurnEngine(teamSpiritCurve: const TeamSpiritCurve(curveConfig));

      const samples = 3000;
      var lowSpiritCrits = 0;
      var midSpiritCrits = 0;
      var lowSpiritDamage = 0;
      var midSpiritDamage = 0;

      // A fresh attacker each iteration, not reused across samples: a
      // critical miss applies a percent penalty to the attacker that only
      // expires via `endCharacterTurn` (never called here), so reusing
      // one attacker across thousands of samples would let those
      // penalties accumulate indefinitely and corrupt this controlled
      // comparison (the mid-spirit attacker's effective Team Spirit would
      // drift down over time, converging with the low-spirit attacker's).
      for (var i = 0; i < samples; i++) {
        final lowSpiritAttacker = CharacterBattleState(testCharacter(
          stats: testStats(attack: 5, teamSpirit: 0, criticalChance: 0),
        ));
        final target = CharacterBattleState(
            testCharacter(stats: testStats(defense: 5, armor: 0)));
        final result = lowSpiritEngine.resolveAbilityUse(
          attacker: lowSpiritAttacker,
          trigger:
              testTrigger(damage: const DiceExpression(0, 1, flatBonus: 10)),
          targets: [target],
        );
        final outcome = result.targetResults.single.attackRolls.single;
        if (outcome.isCriticalHit) lowSpiritCrits++;
        lowSpiritDamage += result.targetResults.single.totalDamageDealt;
      }
      for (var i = 0; i < samples; i++) {
        final midSpiritAttacker = CharacterBattleState(testCharacter(
          stats: testStats(attack: 5, teamSpirit: 50, criticalChance: 0),
        ));
        final target = CharacterBattleState(
            testCharacter(stats: testStats(defense: 5, armor: 0)));
        final result = midSpiritEngine.resolveAbilityUse(
          attacker: midSpiritAttacker,
          trigger:
              testTrigger(damage: const DiceExpression(0, 1, flatBonus: 10)),
          targets: [target],
        );
        final outcome = result.targetResults.single.attackRolls.single;
        if (outcome.isCriticalHit) midSpiritCrits++;
        midSpiritDamage += result.targetResults.single.totalDamageDealt;
      }

      expect(lowSpiritCrits, greaterThan(midSpiritCrits));
      expect(lowSpiritDamage, greaterThan(midSpiritDamage));
    });
  });
}

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

TurnEngine _engine({DiceRoller? diceRoller}) => TurnEngine(
      combatEngine: CombatEngine(diceRoller: diceRoller ?? DiceRoller()),
    );

CharacterBattleState _state(Character c) => CharacterBattleState(c);

/// A flat, dice-free 10-damage expression (0 dice + 10) so damage is
/// deterministic without needing to control the roller.
const _flat10 = DiceExpression(0, 1, flatBonus: 10);

void main() {
  // =======================================================================
  // Ranged uniques (2)
  // =======================================================================

  group('C3: Curving Shot', () {
    test('bypasses a standing Mirror Ward and hits the target anyway', () {
      final engine = _engine();

      final attacker = _state(testCharacter(
        id: 'atk',
        stats: testStats(maxHealth: 100, teamSpirit: 50, armor: 0),
      ));
      final target = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(maxHealth: 100, teamSpirit: 50, armor: 0),
      ));
      // Mirror Ward would normally reflect a non-AoE hit back at the caster.
      target.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.reflectNonAoe,
        sourceCharacterId: 'enemy-1',
      ));

      final trigger = testTrigger(
        abilityType: AbilityType.ranged,
        rangeTag: RangeTag.long,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.curvingShot,
        damage: _flat10,
        damageType: DamageType.piercing,
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [target],
      );

      // Target took the damage, not the attacker (ward bypassed).
      expect(target.currentHealth, 90);
      expect(attacker.currentHealth, 100);
      // The ward was consumed.
      expect(target.reactiveEffects, isEmpty);
      expect(result.targetResults.first.totalDamageDealt, 10);
    });

    test('always resolves as a guaranteed hit (no to-hit contest)', () {
      // Even with a hopeless attack stat vs. a huge defense, it still lands.
      final engine = _engine(diceRoller: DiceRoller(const FixedRandom(0)));

      final attacker = _state(testCharacter(
        id: 'atk',
        stats: testStats(attack: 0, teamSpirit: 50),
      ));
      final target = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(maxHealth: 100, defense: 1000, armor: 0),
      ));

      final trigger = testTrigger(
        abilityType: AbilityType.ranged,
        rangeTag: RangeTag.long,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.curvingShot,
        damage: _flat10,
        damageType: DamageType.piercing,
      );

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [target],
      );

      expect(target.currentHealth, 90);
    });
  });

  group('C3: Called Shot', () {
    test('zeroes the declared stat for the duration, no damage', () {
      final engine = _engine();

      final attacker = _state(testCharacter(id: 'atk'));
      final target = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(maxHealth: 100, attack: 40),
      ));

      final trigger = testTrigger(
        abilityType: AbilityType.ranged,
        rangeTag: RangeTag.long,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.calledShot,
        includeDamage: false,
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [target],
        uniqueData: {'calledShotStat': ModifiableStat.attack},
      );

      // No damage dealt.
      expect(target.currentHealth, 100);
      // Attack is zeroed while the effect is active.
      expect(target.effectiveStats().attack, 0);
      expect(result.targetResults.first.statusEffectsApplied,
          contains('called_shot_stat_zero'));
    });

    test('can zero a non-attack stat (defense)', () {
      final engine = _engine();

      final attacker = _state(testCharacter(id: 'atk'));
      final target = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(defense: 25),
      ));

      final trigger = testTrigger(
        abilityType: AbilityType.ranged,
        rangeTag: RangeTag.long,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.calledShot,
        includeDamage: false,
      );

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [target],
        uniqueData: {'calledShotStat': ModifiableStat.defense},
      );

      expect(target.effectiveStats().defense, 0);
      // Attack is untouched.
      expect(target.effectiveStats().attack, greaterThan(0));
    });

    test('defaults to zeroing Attack when no stat is declared', () {
      final engine = _engine();

      final attacker = _state(testCharacter(id: 'atk'));
      final target = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(attack: 30),
      ));

      final trigger = testTrigger(
        abilityType: AbilityType.ranged,
        rangeTag: RangeTag.long,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.calledShot,
        includeDamage: false,
      );

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [target],
      );

      expect(target.effectiveStats().attack, 0);
    });
  });

  // =======================================================================
  // Psychic uniques (10)
  // =======================================================================

  ActiveTrigger psychic(
    UniqueBehavior behavior, {
    int targetCount = 1,
    bool includeDamage = false,
    TargetAffiliation targetAffiliation = TargetAffiliation.opponent,
    DamageType? damageType,
    DiceExpression? damage,
  }) =>
      testTrigger(
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: behavior,
        targetCount: targetCount,
        includeDamage: includeDamage,
        targetAffiliation: targetAffiliation,
        damageType: damageType,
        damage: damage,
      );

  group('C3: Mind\'s Eye', () {
    test('reveals the target and marks it, no damage', () {
      final engine = _engine();
      final attacker = _state(testCharacter(id: 'atk'));
      final target = _state(testCharacter(id: 'enemy-1', stats: testStats(maxHealth: 100)));

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: psychic(UniqueBehavior.mindsEye),
        targets: [target],
      );

      expect(attacker.revealedEnemyIds, contains('enemy-1'));
      expect(target.statusEffects.any((i) => i.definitionId == 'minds_eye_reveal'),
          isTrue);
      expect(target.currentHealth, 100);
      expect(result.targetResults.first.statusEffectsApplied,
          contains('minds_eye_reveal'));
    });

    test('cannot be used on the caster', () {
      final engine = _engine();
      final caster = _state(testCharacter(id: 'atk'));

      final result = engine.resolveAbilityUse(
        attacker: caster,
        trigger: psychic(UniqueBehavior.mindsEye),
        targets: [caster],
      );

      expect(caster.revealedEnemyIds, isEmpty);
      expect(result.targetResults, isEmpty);
    });
  });

  group('C3: Forced Choice', () {
    test('whitelists the cheapest ability when mode is cheapest', () {
      final engine = _engine();
      final attacker = _state(testCharacter(id: 'atk'));
      final target = _state(testCharacter(id: 'enemy-1'));

      final cheap = testTrigger(id: 'cheap', trionCost: 5);
      final pricey = testTrigger(id: 'pricey', trionCost: 20);

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: psychic(UniqueBehavior.forcedChoice),
        targets: [target],
        uniqueData: {
          'forcedChoiceMode': 'cheapest',
          'targetEquippedTriggers': [cheap, pricey],
        },
      );

      expect(engine.canUseAbility(target, cheap), isTrue);
      expect(engine.canUseAbility(target, pricey), isFalse);
    });

    test('whitelists the priciest ability when mode is priciest', () {
      final engine = _engine();
      final attacker = _state(testCharacter(id: 'atk'));
      final target = _state(testCharacter(id: 'enemy-1'));

      final cheap = testTrigger(id: 'cheap', trionCost: 5);
      final pricey = testTrigger(id: 'pricey', trionCost: 20);

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: psychic(UniqueBehavior.forcedChoice),
        targets: [target],
        uniqueData: {
          'forcedChoiceMode': 'priciest',
          'targetEquippedTriggers': [cheap, pricey],
        },
      );

      expect(engine.canUseAbility(target, pricey), isTrue);
      expect(engine.canUseAbility(target, cheap), isFalse);
    });
  });

  group('C3: Memory Theft', () {
    test('copies the target\'s last-used ability id onto the caster', () {
      final engine = _engine();
      final attacker = _state(testCharacter(id: 'atk'));
      final target = _state(testCharacter(id: 'enemy-1'));
      target.lastUsedTriggerId = 'enemy-signature-move';

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: psychic(UniqueBehavior.memoryTheft),
        targets: [target],
      );

      expect(attacker.copiedTriggerId, 'enemy-signature-move');
    });
  });

  group('C3: Sensory Swap', () {
    test('moves a named status from the first character to the second', () {
      final engine = _engine();
      final attacker = _state(testCharacter(id: 'atk'));
      final source = _state(testCharacter(id: 'enemy-1'));
      final dest = _state(testCharacter(id: 'enemy-2'));

      source.statusEffects.add(StatusEffectInstance(
        definitionId: 'poisoned',
        remainingTurns: 3,
      ));

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: psychic(UniqueBehavior.sensorySwap, targetCount: 2),
        targets: [source, dest],
        uniqueData: {'sensorySwapStatusId': 'poisoned'},
      );

      expect(source.statusEffects.any((i) => i.definitionId == 'poisoned'),
          isFalse);
      expect(dest.statusEffects.any((i) => i.definitionId == 'poisoned'),
          isTrue);
    });
  });

  group('C3: Dread Resonance', () {
    test('damage scales with the target\'s cumulative damage dealt', () {
      final engine = _engine();
      final attacker = _state(testCharacter(id: 'atk'));
      final target = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(maxHealth: 200, armor: 0),
      ));
      target.cumulativeDamageDealt = 100;

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: psychic(UniqueBehavior.dreadResonance,
            includeDamage: true, damageType: DamageType.force),
        targets: [target],
      );

      // round(100 * 0.15) = 15 damage.
      expect(target.currentHealth, 185);
    });

    test('floors at the configured minimum when the target has dealt nothing',
        () {
      final engine = _engine();
      final attacker = _state(testCharacter(id: 'atk'));
      final target = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(maxHealth: 200, armor: 0),
      ));
      target.cumulativeDamageDealt = 0;

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: psychic(UniqueBehavior.dreadResonance,
            includeDamage: true, damageType: DamageType.force),
        targets: [target],
      );

      // max(round(0), 5) = 5 damage.
      expect(target.currentHealth, 195);
    });
  });

  group('C3: Isolation', () {
    test('applies the isolation status to the target', () {
      final engine = _engine();
      final attacker = _state(testCharacter(id: 'atk'));
      final target = _state(testCharacter(id: 'enemy-1'));

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: psychic(UniqueBehavior.isolation),
        targets: [target],
      );

      expect(target.isIsolated(), isTrue);
    });
  });

  group('C3: Illusory Double', () {
    test('consumes a charge and makes the target untargetable', () {
      final engine = _engine();
      final attacker = _state(testCharacter(id: 'atk'));
      final ally = _state(testCharacter(id: 'ally-1'));
      attacker.illusoryDoubleCharges = 1;

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: psychic(UniqueBehavior.illusoryDouble,
            targetAffiliation: TargetAffiliation.ally),
        targets: [ally],
      );

      expect(ally.isUntargetable(), isTrue);
      expect(attacker.illusoryDoubleCharges, 0);
    });

    test('does nothing without an available charge', () {
      final engine = _engine();
      final attacker = _state(testCharacter(id: 'atk'));
      final ally = _state(testCharacter(id: 'ally-1'));
      attacker.illusoryDoubleCharges = 0;

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: psychic(UniqueBehavior.illusoryDouble,
            targetAffiliation: TargetAffiliation.ally),
        targets: [ally],
      );

      expect(ally.isUntargetable(), isFalse);
      expect(result.targetResults, isEmpty);
    });
  });

  group('C3: Echoing Doubt', () {
    test('applies the forced-miss status to the target', () {
      final engine = _engine();
      final attacker = _state(testCharacter(id: 'atk'));
      final target = _state(testCharacter(id: 'enemy-1'));

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: psychic(UniqueBehavior.echoingDoubt),
        targets: [target],
      );

      expect(target.isNextAttackForced(), isTrue);
    });

    test('the afflicted attack whiffs, backlashes, and Silences', () {
      final engine = _engine();
      final doubted = _state(testCharacter(
        id: 'doubted',
        stats: testStats(maxHealth: 100, attack: 1000, armor: 0),
      ));
      final enemy = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(maxHealth: 100, defense: 0, armor: 0),
      ));

      // Afflict, then the doubted character tries to attack.
      engine.resolveAbilityUse(
        attacker: _state(testCharacter(id: 'psion')),
        trigger: psychic(UniqueBehavior.echoingDoubt),
        targets: [doubted],
      );
      expect(doubted.isNextAttackForced(), isTrue);

      final result = engine.resolveAbilityUse(
        attacker: doubted,
        trigger: testTrigger(damage: const DiceExpression(0, 1, flatBonus: 30)),
        targets: [enemy],
      );

      // The attack whiffed: no targets hit, enemy untouched.
      expect(result.targetResults, isEmpty);
      expect(enemy.currentHealth, 100);
      // Backlash (20) + Silence on the doubted attacker; status consumed.
      expect(doubted.currentHealth, 80);
      expect(doubted.statusEffects.any((i) => i.definitionId == 'silenced'),
          isTrue);
      expect(doubted.isNextAttackForced(), isFalse);
    });
  });

  group('C3: Karmic Bind', () {
    test('links caster to target with a Team-Spirit-scaled fraction', () {
      final engine = _engine();
      final attacker = _state(testCharacter(
        id: 'atk',
        stats: testStats(teamSpirit: 50),
      ));
      final target = _state(testCharacter(id: 'enemy-1'));

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: psychic(UniqueBehavior.karmicBind),
        targets: [target],
      );

      expect(attacker.karmicBindTargetId, 'enemy-1');
      expect(target.statusEffects.any((i) => i.definitionId == 'karmic_bind'),
          isTrue);
      final bind = attacker.statusEffects
          .firstWhere((i) => i.definitionId == 'karmic_bind');
      // TS 50 -> 0.25 + 0.5 * (0.60 - 0.25) = 0.425.
      expect(bind.data['karmicBindFraction'] as double, closeTo(0.425, 0.0001));
    });
  });

  group('C3: Unmaking', () {
    test('inverts active buffs into their debuff equivalents', () {
      final engine = _engine();
      final attacker = _state(testCharacter(id: 'atk'));
      final target = _state(testCharacter(id: 'enemy-1'));

      target.statusEffects.add(StatusEffectInstance(
        definitionId: 'empowered',
        remainingTurns: 2,
      ));
      target.statusEffects.add(StatusEffectInstance(
        definitionId: 'guarded',
        remainingTurns: 2,
      ));

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: psychic(UniqueBehavior.unmaking),
        targets: [target],
      );

      final ids = target.statusEffects.map((i) => i.definitionId).toSet();
      expect(ids, contains('weakened'));
      expect(ids, contains('exposed'));
      expect(ids, isNot(contains('empowered')));
      expect(ids, isNot(contains('guarded')));
    });
  });
}

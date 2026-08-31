import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group('C1: UniqueBehavior enum', () {
    test('has exactly 17 values', () {
      expect(UniqueBehavior.values.length, 17);
    });

    test('contains all expected melee unique behaviors', () {
      expect(UniqueBehavior.values, containsAll([
        UniqueBehavior.sharedAgony,
        UniqueBehavior.graveBargain,
        UniqueBehavior.martyrsEnd,
        UniqueBehavior.vowOfTheDuel,
        UniqueBehavior.sunderArms,
      ]));
    });

    test('contains all expected ranged unique behaviors', () {
      expect(UniqueBehavior.values, containsAll([
        UniqueBehavior.curvingShot,
        UniqueBehavior.calledShot,
      ]));
    });

    test('contains all expected psychic unique behaviors', () {
      expect(UniqueBehavior.values, containsAll([
        UniqueBehavior.mindsEye,
        UniqueBehavior.forcedChoice,
        UniqueBehavior.memoryTheft,
        UniqueBehavior.sensorySwap,
        UniqueBehavior.dreadResonance,
        UniqueBehavior.isolation,
        UniqueBehavior.illusoryDouble,
        UniqueBehavior.echoingDoubt,
        UniqueBehavior.karmicBind,
        UniqueBehavior.unmaking,
      ]));
    });
  });

  group('C1: AbilityType.validSubtypes includes unique', () {
    test('melee allows unique', () {
      expect(AbilityType.melee.validSubtypes, contains(AbilitySubtype.unique));
    });

    test('ranged allows unique', () {
      expect(AbilityType.ranged.validSubtypes, contains(AbilitySubtype.unique));
    });

    test('psychic allows unique', () {
      expect(AbilityType.psychic.validSubtypes, contains(AbilitySubtype.unique));
    });
  });

  group('C1: ActiveTrigger.uniqueBehavior', () {
    test('defaults to null', () {
      final trigger = testTrigger();
      expect(trigger.uniqueBehavior, isNull);
    });

    test('can be set', () {
      final trigger = testTrigger(
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.sharedAgony,
      );
      expect(trigger.uniqueBehavior, UniqueBehavior.sharedAgony);
    });
  });

  group('C1: new status effects in catalog', () {
    final catalog = StatusEffectCatalog.builtIn();

    test('isolation exists and prevents ally interaction', () {
      final def = catalog['isolation'];
      expect(def.name, 'Isolation');
      expect(def.preventsAllyInteraction, isTrue);
      expect(def.defaultDurationTurns, 2);
    });

    test('untargetable exists and prevents targeting', () {
      final def = catalog['untargetable'];
      expect(def.name, 'Untargetable');
      expect(def.preventsTargeting, isTrue);
      expect(def.defaultDurationTurns, 1);
    });

    test('echoing_doubt exists and forces next attack miss', () {
      final def = catalog['echoing_doubt'];
      expect(def.name, 'Echoing Doubt');
      expect(def.forcesNextAttackMiss, isTrue);
      expect(def.defaultDurationTurns, 1);
    });

    test('vow_of_the_duel exists with damage multiplier and heal prevention', () {
      final def = catalog['vow_of_the_duel'];
      expect(def.name, 'Vow of the Duel');
      expect(def.outgoingDamageMultiplier, 2.0);
      expect(def.preventsHealing, isTrue);
      expect(def.defaultDurationTurns, 3);
    });

    test('forced_choice exists', () {
      final def = catalog['forced_choice'];
      expect(def.name, 'Forced Choice');
      expect(def.defaultDurationTurns, 1);
    });

    test('karmic_bind exists', () {
      final def = catalog['karmic_bind'];
      expect(def.name, 'Karmic Bind');
      expect(def.defaultDurationTurns, 3);
    });

    test('called_shot_stat_zero exists', () {
      final def = catalog['called_shot_stat_zero'];
      expect(def.name, 'Called Shot');
      expect(def.defaultDurationTurns, 2);
    });

    test('minds_eye_reveal exists', () {
      final def = catalog['minds_eye_reveal'];
      expect(def.name, "Mind's Eye");
      expect(def.defaultDurationTurns, 3);
    });
  });

  group('C1: CharacterBattleState unique tracking fields', () {
    late CharacterBattleState state;

    setUp(() {
      state = CharacterBattleState(testCharacter());
    });

    test('meleeHitEnemyIds starts empty', () {
      expect(state.meleeHitEnemyIds, isEmpty);
    });

    test('illusoryDoubleCharges starts at 0', () {
      expect(state.illusoryDoubleCharges, 0);
    });

    test('copiedTriggerId starts null', () {
      expect(state.copiedTriggerId, isNull);
    });

    test('duelTargetId starts null', () {
      expect(state.duelTargetId, isNull);
    });

    test('karmicBindTargetId starts null', () {
      expect(state.karmicBindTargetId, isNull);
    });

    test('revealedEnemyIds starts empty', () {
      expect(state.revealedEnemyIds, isEmpty);
    });

    test('destroyedTriggerIds starts empty', () {
      expect(state.destroyedTriggerIds, isEmpty);
    });
  });

  group('C1: CharacterBattleState helpers', () {
    late CharacterBattleState state;

    setUp(() {
      state = CharacterBattleState(testCharacter());
    });

    test('isUntargetable returns false by default', () {
      expect(state.isUntargetable(), isFalse);
    });

    test('isUntargetable returns true when untargetable status is active', () {
      state.statusEffects.add(StatusEffectInstance(
        definitionId: 'untargetable',
        remainingTurns: 1,
      ));
      expect(state.isUntargetable(), isTrue);
    });

    test('isIsolated returns false by default', () {
      expect(state.isIsolated(), isFalse);
    });

    test('isIsolated returns true when isolation status is active', () {
      state.statusEffects.add(StatusEffectInstance(
        definitionId: 'isolation',
        remainingTurns: 2,
      ));
      expect(state.isIsolated(), isTrue);
    });

    test('isNextAttackForced returns false by default', () {
      expect(state.isNextAttackForced(), isFalse);
    });

    test('isNextAttackForced returns true with echoing_doubt', () {
      state.statusEffects.add(StatusEffectInstance(
        definitionId: 'echoing_doubt',
        remainingTurns: 1,
      ));
      expect(state.isNextAttackForced(), isTrue);
    });
  });

  group('C1: UniqueConfig defaults', () {
    const config = UniqueConfig.defaults;

    test('sharedAgonyLinkedDamageMultiplier is 1.2', () {
      expect(config.sharedAgonyLinkedDamageMultiplier, 1.2);
    });

    test('graveBargainHpSpendFraction is 0.25', () {
      expect(config.graveBargainHpSpendFraction, 0.25);
    });

    test('martyrsEndHpThreshold is 0.25', () {
      expect(config.martyrsEndHpThreshold, 0.25);
    });

    test('illusoryDoubleStartingCharges is 1', () {
      expect(config.illusoryDoubleStartingCharges, 1);
    });

    test('karmicBind fractions are 0.25 and 0.60', () {
      expect(config.karmicBindLowTsFraction, 0.25);
      expect(config.karmicBindHighTsFraction, 0.60);
    });
  });

  group('C1: unique dispatch routes to stub methods', () {
    late TurnEngine engine;
    late CharacterBattleState attacker;
    late CharacterBattleState target;

    setUp(() {
      engine = TurnEngine();
      attacker = CharacterBattleState(testCharacter(id: 'atk'));
      target = CharacterBattleState(testCharacter(id: 'def'));
    });

    for (final behavior in UniqueBehavior.values) {
      test('dispatch routes $behavior without error', () {
        final abilityType = switch (behavior) {
          UniqueBehavior.sharedAgony ||
          UniqueBehavior.graveBargain ||
          UniqueBehavior.martyrsEnd ||
          UniqueBehavior.vowOfTheDuel ||
          UniqueBehavior.sunderArms =>
            AbilityType.melee,
          UniqueBehavior.curvingShot ||
          UniqueBehavior.calledShot =>
            AbilityType.ranged,
          _ => AbilityType.psychic,
        };

        final rangeTag = abilityType == AbilityType.ranged
            ? RangeTag.long
            : RangeTag.close;

        final trigger = testTrigger(
          abilityType: abilityType,
          abilitySubtype: AbilitySubtype.unique,
          rangeTag: rangeTag,
          uniqueBehavior: behavior,
          includeDamage: false,
        );

        final result = engine.resolveAbilityUse(
          attacker: attacker,
          trigger: trigger,
          targets: [target],
        );

        expect(result.attackerCharacterId, 'atk');
        expect(result.triggerId, trigger.id);
      });
    }
  });

  group('C1: unique subtype without uniqueBehavior falls through to single', () {
    test('resolves like single when uniqueBehavior is null', () {
      final engine = TurnEngine(
        combatEngine: CombatEngine(diceRoller: DiceRoller(const FixedRandom(15))),
      );
      final attacker = CharacterBattleState(testCharacter(id: 'atk'));
      final target = CharacterBattleState(testCharacter(id: 'def'));

      final trigger = testTrigger(
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.unique,
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [target],
      );

      expect(result.targetResults, hasLength(1));
      expect(result.targetResults.first.targetCharacterId, 'def');
    });
  });

  group('C1: barrel export', () {
    test('UniqueBehavior is accessible from battle_engine', () {
      expect(UniqueBehavior.sharedAgony, isNotNull);
    });
  });
}

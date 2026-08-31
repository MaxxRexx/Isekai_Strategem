import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Combat v2 Phase B2: arming mechanism, reactive expiry, and the first batch
/// of counters (Predictive Parry dodge, Foresight Counter negate+stun, Numbing
/// Toxin burst mitigation, Mirror Ward as a castable Wellspring BT ability).
/// FixedRandom(19) forces natural 20s so every hit lands deterministically.
void main() {
  TurnEngine engine() => TurnEngine(
        combatEngine:
            CombatEngine(diceRoller: DiceRoller(const FixedRandom(19))),
      );

  CharacterBattleState makeChar({
    String id = 'char',
    int attack = 1000,
    int defense = 0,
    int armor = 0,
    int maxHealth = 200,
  }) =>
      CharacterBattleState(testCharacter(
        id: id,
        stats: testStats(
          attack: attack,
          defense: defense,
          armor: armor,
          maxHealth: maxHealth,
        ),
      ));

  final damage = const DiceExpression(0, 1, flatBonus: 10);

  group('Declarative arming mechanism', () {
    test('resolveAbilityUse arms a reactive effect on the target', () {
      final caster = makeChar(id: 'caster');
      final ally = makeChar(id: 'ally');
      final armTrigger = testTrigger(
        targetAffiliation: TargetAffiliation.ally,
        armsReactive: ReactiveKind.reflectNonAoe,
        armsReactiveDefaultTurns: 2,
        includeDamage: false,
      );

      engine().resolveAbilityUse(
        attacker: caster,
        trigger: armTrigger,
        targets: [ally],
      );

      expect(ally.reactiveEffects, hasLength(1));
      expect(ally.reactiveEffects.first.kind, ReactiveKind.reflectNonAoe);
      expect(ally.reactiveEffects.first.remainingTurns, 2);
      expect(ally.reactiveEffects.first.sourceCharacterId, 'caster');
    });

    test('self-targeted arm puts the effect on the caster', () {
      final caster = makeChar(id: 'caster');
      final armTrigger = testTrigger(
        targetAffiliation: TargetAffiliation.self,
        armsReactive: ReactiveKind.dodgeMeleeSingle,
        includeDamage: false,
      );

      engine().resolveAbilityUse(
        attacker: caster,
        trigger: armTrigger,
        targets: [caster],
      );

      expect(caster.reactiveEffects, hasLength(1));
      expect(caster.reactiveEffects.first.kind, ReactiveKind.dodgeMeleeSingle);
      expect(caster.reactiveEffects.first.remainingTurns, isNull);
    });

    test('reactiveData is stored on the armed effect', () {
      final caster = makeChar(id: 'caster');
      final ally = makeChar(id: 'ally');
      final armTrigger = testTrigger(
        targetAffiliation: TargetAffiliation.ally,
        armsReactive: ReactiveKind.negateByOrigin,
        armsReactiveDefaultTurns: 2,
        includeDamage: false,
      );

      engine().resolveAbilityUse(
        attacker: caster,
        trigger: armTrigger,
        targets: [ally],
        reactiveData: {'originTag': 'physical'},
      );

      expect(ally.reactiveEffects.first.data['originTag'], 'physical');
    });
  });

  group('Reactive expiry', () {
    test('tickReactiveEffects decrements remainingTurns', () {
      final holder = makeChar();
      holder.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.reflectNonAoe,
        remainingTurns: 2,
      ));

      engine().tickReactiveEffects(holder);
      expect(holder.reactiveEffects.first.remainingTurns, 1);
    });

    test('expired reactive effects are removed', () {
      final holder = makeChar();
      holder.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.reflectNonAoe,
        remainingTurns: 1,
      ));

      engine().tickReactiveEffects(holder);
      expect(holder.reactiveEffects, isEmpty);
    });

    test('null-duration effects never expire from ticking', () {
      final holder = makeChar();
      holder.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.dodgeMeleeSingle,
      ));

      for (var i = 0; i < 10; i++) {
        engine().tickReactiveEffects(holder);
      }
      expect(holder.reactiveEffects, hasLength(1));
    });
  });

  group('Predictive Parry (dodgeMeleeSingle)', () {
    test('dodges a melee single attack and counter-hits the attacker', () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final defender = makeChar(id: 'defender', maxHealth: 200);
      defender.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.dodgeMeleeSingle,
        sourceCharacterId: 'defender',
      ));

      final result = engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(damage: damage),
        targets: [defender],
      );

      expect(defender.currentHealth, 200,
          reason: 'the parrying defender takes nothing');
      expect(attacker.currentHealth, lessThan(200),
          reason: 'the attacker eats the counter-hit');
      expect(defender.reactiveEffects, isEmpty,
          reason: 'the parry is consumed');
      expect(result.targetResults, isEmpty,
          reason: 'the original hit was negated');
    });

    test('does not trigger against ranged attacks', () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final defender = makeChar(id: 'defender', maxHealth: 200);
      defender.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.dodgeMeleeSingle,
        sourceCharacterId: 'defender',
      ));

      engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(
          damage: damage,
          rangeTag: RangeTag.long,
          abilityType: AbilityType.ranged,
        ),
        targets: [defender],
      );

      expect(defender.currentHealth, lessThan(200),
          reason: 'ranged bypasses parry');
      expect(attacker.currentHealth, 200);
      expect(defender.reactiveEffects, hasLength(1),
          reason: 'the parry stays armed');
    });

    test('does not trigger against melee AoE', () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final defender = makeChar(id: 'defender', maxHealth: 200);
      defender.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.dodgeMeleeSingle,
        sourceCharacterId: 'defender',
      ));

      engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(
          damage: damage,
          abilitySubtype: AbilitySubtype.aoe,
          targetCount: 3,
        ),
        targets: [defender],
      );

      expect(defender.currentHealth, lessThan(200),
          reason: 'melee AoE bypasses parry');
      expect(defender.reactiveEffects, hasLength(1));
    });
  });

  group('Foresight Counter (negateByOrigin)', () {
    test('negates a matching-origin attack and stuns the attacker', () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final defender = makeChar(id: 'defender', maxHealth: 200);
      defender.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.negateByOrigin,
        sourceCharacterId: 'defender',
        data: {'originTag': 'physical'},
      ));

      final result = engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(
          damage: damage,
          originTag: OriginTag.physical,
        ),
        targets: [defender],
      );

      expect(defender.currentHealth, 200,
          reason: 'the hit is negated entirely');
      expect(result.targetResults, isEmpty,
          reason: 'no hit resolves');
      expect(defender.reactiveEffects, isEmpty,
          reason: 'the counter is consumed');
      expect(
        attacker.statusEffects.any((e) => e.definitionId == 'stunned'),
        isTrue,
        reason: 'the attacker is stunned',
      );
    });

    test('does not trigger when origin tag does not match', () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final defender = makeChar(id: 'defender', maxHealth: 200);
      defender.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.negateByOrigin,
        sourceCharacterId: 'defender',
        data: {'originTag': 'energy'},
      ));

      engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(
          damage: damage,
          originTag: OriginTag.physical,
        ),
        targets: [defender],
      );

      expect(defender.currentHealth, lessThan(200),
          reason: 'wrong guess, hit lands');
      expect(defender.reactiveEffects, hasLength(1),
          reason: 'the counter stays armed on a mismatch');
      expect(attacker.statusEffects, isEmpty,
          reason: 'no stun on mismatch');
    });

    test('AoE bypasses Foresight Counter even if origin matches', () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final defender = makeChar(id: 'defender', maxHealth: 200);
      defender.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.negateByOrigin,
        sourceCharacterId: 'defender',
        data: {'originTag': 'physical'},
      ));

      engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(
          damage: damage,
          originTag: OriginTag.physical,
          abilitySubtype: AbilitySubtype.aoe,
          targetCount: 3,
        ),
        targets: [defender],
      );

      expect(defender.currentHealth, lessThan(200),
          reason: 'AoE bypasses negate');
      expect(defender.reactiveEffects, hasLength(1),
          reason: 'counter stays armed');
    });
  });

  group('Numbing Toxin (burstMitigation)', () {
    test('only the first burst hit lands; subsequent hits are suppressed', () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final defender = makeChar(id: 'defender', maxHealth: 200);
      defender.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.burstMitigation,
        sourceCharacterId: 'defender',
        remainingTurns: 2,
      ));

      final result = engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(
          damage: damage,
          abilityType: AbilityType.ranged,
          rangeTag: RangeTag.long,
          abilitySubtype: AbilitySubtype.burst,
          hitsPerUse: 3,
          targetCount: 1,
        ),
        targets: [defender],
      );

      final hits = result.targetResults.single;
      expect(hits.attackRolls, hasLength(1),
          reason: 'only 1 of 3 burst hits resolves');
      expect(defender.reactiveEffects, isEmpty,
          reason: 'the mitigation is consumed');
    });

    test('does not affect single-target attacks', () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final defender = makeChar(id: 'defender', maxHealth: 200);
      defender.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.burstMitigation,
        sourceCharacterId: 'defender',
        remainingTurns: 2,
      ));

      engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(damage: damage),
        targets: [defender],
      );

      expect(defender.currentHealth, lessThan(200),
          reason: 'single-target hit lands normally');
      expect(defender.reactiveEffects, hasLength(1),
          reason: 'burst mitigation stays armed against non-burst');
    });
  });

  group('Mirror Ward as castable Wellspring ability', () {
    test('Wellspring BT now includes Mirror Ward active ability', () {
      final catalog = BlackTriggerCatalog.builtIn();
      final wellspring = catalog['wellspring'];
      expect(wellspring.activeAbilities.length, 3);

      final mirrorWard = wellspring.activeAbilities
          .firstWhere((a) => a.id == 'wellspring_mirror_ward');
      expect(mirrorWard.armsReactive, ReactiveKind.reflectNonAoe);
      expect(mirrorWard.armsReactiveDefaultTurns, 2);
      expect(mirrorWard.trionCost, 25);
      expect(mirrorWard.cooldownTurns, 3);
    });

    test('casting Mirror Ward arms reflectNonAoe on the ally', () {
      final catalog = BlackTriggerCatalog.builtIn();
      final mirrorWard = catalog['wellspring']
          .activeAbilities
          .firstWhere((a) => a.id == 'wellspring_mirror_ward');
      final caster = makeChar(id: 'caster');
      final ally = makeChar(id: 'ally');

      engine().resolveAbilityUse(
        attacker: caster,
        trigger: mirrorWard,
        targets: [ally],
      );

      expect(ally.reactiveEffects, hasLength(1));
      expect(ally.reactiveEffects.first.kind, ReactiveKind.reflectNonAoe);
      expect(ally.reactiveEffects.first.remainingTurns, 2);
    });

    test('armed Mirror Ward then reflects a non-AoE attack', () {
      final catalog = BlackTriggerCatalog.builtIn();
      final mirrorWard = catalog['wellspring']
          .activeAbilities
          .firstWhere((a) => a.id == 'wellspring_mirror_ward');
      final caster = makeChar(id: 'caster');
      final ally = makeChar(id: 'ally');
      final enemy = makeChar(id: 'enemy', maxHealth: 200);

      final e = engine();
      e.resolveAbilityUse(
        attacker: caster,
        trigger: mirrorWard,
        targets: [ally],
      );
      e.resolveAbilityUse(
        attacker: enemy,
        trigger: testTrigger(damage: damage),
        targets: [ally],
      );

      expect(ally.currentHealth, 200, reason: 'ally is protected');
      expect(enemy.currentHealth, lessThan(200),
          reason: 'enemy eats the reflected hit');
      expect(ally.reactiveEffects, isEmpty, reason: 'ward consumed');
    });
  });

  group('Foresight Counter as castable Bastion Frame ability', () {
    test('Bastion Frame BT now includes Foresight Counter', () {
      final catalog = BlackTriggerCatalog.builtIn();
      final bastion = catalog['bastion_frame'];
      expect(bastion.activeAbilities.length, 1);

      final fc = bastion.activeAbilities.first;
      expect(fc.id, 'bastion_frame_foresight');
      expect(fc.armsReactive, ReactiveKind.negateByOrigin);
      expect(fc.armsReactiveDefaultTurns, 2);
      expect(fc.trionCost, 20);
      expect(fc.cooldownTurns, 2);
    });

    test('casting Foresight Counter with originTag data arms the ally', () {
      final catalog = BlackTriggerCatalog.builtIn();
      final fc = catalog['bastion_frame'].activeAbilities.first;
      final caster = makeChar(id: 'caster');
      final ally = makeChar(id: 'ally');

      engine().resolveAbilityUse(
        attacker: caster,
        trigger: fc,
        targets: [ally],
        reactiveData: {'originTag': 'mental'},
      );

      expect(ally.reactiveEffects, hasLength(1));
      expect(ally.reactiveEffects.first.kind, ReactiveKind.negateByOrigin);
      expect(ally.reactiveEffects.first.data['originTag'], 'mental');
    });
  });

  group('Catalog counter triggers', () {
    test('Predictive Parry is in the trigger catalog', () {
      final catalog = TriggerCatalog.builtIn();
      final parry = catalog['predictive_parry'] as ActiveTrigger;
      expect(parry.armsReactive, ReactiveKind.dodgeMeleeSingle);
      expect(parry.armsReactiveDefaultTurns, isNull);
      // Close range, so item #4's range-keyed costing brought it down.
      expect(parry.trionCost, 18);
      expect(parry.cooldownTurns, 2);
      expect(parry.targetAffiliation, TargetAffiliation.self);
    });

    test('Numbing Toxin is in the trigger catalog', () {
      final catalog = TriggerCatalog.builtIn();
      final toxin = catalog['numbing_toxin'] as ActiveTrigger;
      expect(toxin.armsReactive, ReactiveKind.burstMitigation);
      expect(toxin.armsReactiveDefaultTurns, 2);
      // Close range, so item #4's range-keyed costing brought it down.
      expect(toxin.trionCost, 18);
      expect(toxin.cooldownTurns, 2);
      expect(toxin.targetAffiliation, TargetAffiliation.self);
    });
  });

  group('Counter priority ordering', () {
    test('Foresight Counter fires before Mirror Ward when both are present',
        () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final defender = makeChar(id: 'defender', maxHealth: 200);
      defender.reactiveEffects.addAll([
        ReactiveEffect(
          kind: ReactiveKind.reflectNonAoe,
          sourceCharacterId: 'defender',
        ),
        ReactiveEffect(
          kind: ReactiveKind.negateByOrigin,
          sourceCharacterId: 'defender',
          data: {'originTag': 'physical'},
        ),
      ]);

      engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(
          damage: damage,
          originTag: OriginTag.physical,
        ),
        targets: [defender],
      );

      expect(defender.currentHealth, 200, reason: 'negated by Foresight');
      expect(attacker.currentHealth, 200,
          reason: 'not reflected (negated first)');
      expect(
        attacker.statusEffects.any((e) => e.definitionId == 'stunned'),
        isTrue,
        reason: 'attacker stunned by Foresight Counter',
      );
      expect(defender.reactiveEffects, hasLength(1),
          reason: 'Mirror Ward stays armed (Foresight consumed first)');
      expect(defender.reactiveEffects.first.kind, ReactiveKind.reflectNonAoe);
    });
  });
}

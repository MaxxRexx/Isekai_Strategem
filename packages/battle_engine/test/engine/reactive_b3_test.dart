import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Combat v2 Phase B3: the remaining 9 active counters.
/// FixedRandom(19) forces natural 20s so every hit lands deterministically.
void main() {
  TurnEngine engine() => TurnEngine(
        combatEngine:
            CombatEngine(diceRoller: DiceRoller(const FixedRandom(19))),
        statusEffectEngine:
            StatusEffectEngine(diceRoller: DiceRoller(const FixedRandom(19))),
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

  group('Frozen Tempo (cooldownSabotage)', () {
    test('doubles the cooldown of the ranged ability that hit the holder', () {
      final attacker = makeChar(id: 'attacker');
      final defender = makeChar(id: 'defender');
      defender.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.cooldownSabotage,
        sourceCharacterId: 'defender',
        remainingTurns: 2,
      ));

      final trigger = testTrigger(
        id: 'ranged-shot',
        damage: damage,
        rangeTag: RangeTag.ranged,
        attackType: AttackType.ranged,
        cooldownTurns: 2,
      );

      final e = engine();
      e.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [defender],
      );
      attacker.recordAbilityUse(trigger);
      attacker.endTurn();

      expect(attacker.cooldowns['ranged-shot'], 4,
          reason: 'base cooldown 2 x sabotage 2 = 4');
      expect(defender.reactiveEffects, isEmpty,
          reason: 'sabotage consumed on fire');
    });

    test('does not fire against melee attacks', () {
      final attacker = makeChar(id: 'attacker');
      final defender = makeChar(id: 'defender');
      defender.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.cooldownSabotage,
        sourceCharacterId: 'defender',
        remainingTurns: 2,
      ));

      engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(damage: damage),
        targets: [defender],
      );

      expect(defender.reactiveEffects, hasLength(1),
          reason: 'melee does not trigger sabotage');
    });

    test('trigger catalog entry exists', () {
      final catalog = TriggerCatalog.builtIn();
      final ft = catalog['frozen_tempo'] as ActiveTrigger;
      expect(ft.armsReactive, ReactiveKind.cooldownSabotage);
      expect(ft.armsReactiveDefaultTurns, 2);
      expect(ft.targetAffiliation, TargetAffiliation.self);
    });
  });

  group('Puppet Strings (redirectToOwnAlly)', () {
    test('redirects a non-AoE attack onto an ally of the attacker', () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final ally = makeChar(id: 'ally', maxHealth: 200);
      attacker.teammates = [ally];
      ally.teammates = [attacker];

      final defender = makeChar(id: 'defender', maxHealth: 200);
      defender.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.redirectToOwnAlly,
        sourceCharacterId: 'caster',
      ));

      engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(damage: damage),
        targets: [defender],
      );

      expect(defender.currentHealth, 200,
          reason: 'defender is protected');
      expect(ally.currentHealth, lessThan(200),
          reason: 'ally of attacker takes the hit');
      expect(defender.reactiveEffects, isEmpty,
          reason: 'puppet strings consumed');
    });

    test('does not fire against AoE', () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final ally = makeChar(id: 'ally', maxHealth: 200);
      attacker.teammates = [ally];

      final defender = makeChar(id: 'defender', maxHealth: 200);
      defender.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.redirectToOwnAlly,
        sourceCharacterId: 'caster',
      ));

      engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(
          damage: damage,
          attackSubtype: AttackSubtype.aoe,
          targetCount: 3,
        ),
        targets: [defender],
      );

      expect(defender.currentHealth, lessThan(200),
          reason: 'AoE bypasses puppet strings');
      expect(defender.reactiveEffects, hasLength(1),
          reason: 'puppet strings stays armed');
    });

    test('BT catalog entry on Paradox Shard', () {
      final catalog = BlackTriggerCatalog.builtIn();
      final ps = catalog['paradox_shard'];
      expect(ps.activeAbilities.length, 4);
      final puppet = ps.activeAbilities
          .firstWhere((a) => a.id == 'paradox_shard_puppet');
      expect(puppet.armsReactive, ReactiveKind.redirectToOwnAlly);
      expect(puppet.armsReactiveDefaultTurns, 2);
    });

    test('arming Puppet Strings applies Exposed to the caster', () {
      final caster = makeChar(id: 'caster');
      final ally = makeChar(id: 'ally');
      final armTrigger = testTrigger(
        targetAffiliation: TargetAffiliation.ally,
        armsReactive: ReactiveKind.redirectToOwnAlly,
        armsReactiveDefaultTurns: 2,
        includeDamage: false,
      );

      engine().resolveAbilityUse(
        attacker: caster,
        trigger: armTrigger,
        targets: [ally],
      );

      expect(
        caster.statusEffects.any((e) => e.definitionId == 'exposed'),
        isTrue,
        reason: 'caster gains Exposed while Puppet Strings is armed',
      );
    });
  });

  group('Deadfall (trapOnAction)', () {
    test('counters a damaging ability and deals trap damage to attacker', () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final defender = makeChar(id: 'defender', maxHealth: 200);
      attacker.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.trapOnAction,
        sourceCharacterId: 'trapper',
        remainingTurns: 2,
      ));

      final result = engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(damage: damage),
        targets: [defender],
      );

      expect(defender.currentHealth, 200,
          reason: 'the ability is countered');
      expect(attacker.currentHealth, lessThan(200),
          reason: 'attacker takes trap damage');
      expect(result.targetResults, isEmpty,
          reason: 'no hits resolve');
      expect(attacker.reactiveEffects, isEmpty,
          reason: 'deadfall consumed');
    });

    test('does not fire for non-damaging abilities', () {
      final caster = makeChar(id: 'caster');
      final ally = makeChar(id: 'ally');
      caster.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.trapOnAction,
        sourceCharacterId: 'trapper',
        remainingTurns: 2,
      ));

      engine().resolveAbilityUse(
        attacker: caster,
        trigger: testTrigger(
          includeDamage: false,
          targetAffiliation: TargetAffiliation.ally,
          healAmount: const DiceExpression(1, 4, flatBonus: 5),
        ),
        targets: [ally],
      );

      expect(caster.reactiveEffects, hasLength(1),
          reason: 'heal does not trigger deadfall');
    });

    test('BT catalog entry on Paradox Shard', () {
      final catalog = BlackTriggerCatalog.builtIn();
      final ps = catalog['paradox_shard'];
      final deadfall = ps.activeAbilities
          .firstWhere((a) => a.id == 'paradox_shard_deadfall');
      expect(deadfall.armsReactive, ReactiveKind.trapOnAction);
      expect(deadfall.armsReactiveDefaultTurns, 2);
    });

    test('Deadfall arms on the target (enemy), not the caster', () {
      final caster = makeChar(id: 'caster');
      final enemy = makeChar(id: 'enemy');

      engine().resolveAbilityUse(
        attacker: caster,
        trigger: testTrigger(
          includeDamage: false,
          armsReactive: ReactiveKind.trapOnAction,
          armsReactiveDefaultTurns: 2,
        ),
        targets: [enemy],
      );

      expect(caster.reactiveEffects, isEmpty,
          reason: 'caster does not get the trap');
      expect(enemy.reactiveEffects, hasLength(1),
          reason: 'enemy holds the trap');
      expect(enemy.reactiveEffects.first.kind, ReactiveKind.trapOnAction);
    });
  });

  group('Death Ledger (nullifyAoe)', () {
    test('nullifies an AoE ability from the marked attacker', () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final defender = makeChar(id: 'defender', maxHealth: 200);
      attacker.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.nullifyAoe,
        sourceCharacterId: 'marker',
      ));

      final result = engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(
          damage: damage,
          attackSubtype: AttackSubtype.aoe,
          targetCount: 3,
        ),
        targets: [defender],
      );

      expect(defender.currentHealth, 200,
          reason: 'AoE is nullified');
      expect(result.targetResults, isEmpty);
      expect(attacker.reactiveEffects, isEmpty,
          reason: 'ledger consumed');
    });

    test('signals the wielder to swap in the nullified AoE Trigger', () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final defender = makeChar(id: 'defender', maxHealth: 200);
      final marker = makeChar(id: 'marker', maxHealth: 200);
      attacker.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.nullifyAoe,
        sourceCharacterId: 'marker',
      ));

      final e = engine();
      e.characterRegistry = {
        'attacker': attacker,
        'defender': defender,
        'marker': marker,
      };
      e.resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(
          id: 'enemy_aoe',
          damage: damage,
          attackSubtype: AttackSubtype.aoe,
          targetCount: 3,
        ),
        targets: [defender],
      );

      expect(marker.deathLedgerSwapPending?.id, 'enemy_aoe',
          reason: 'wielder is signalled to borrow the nullified AoE');
    });

    test('does not fire against non-AoE attacks', () {
      final attacker = makeChar(id: 'attacker');
      final defender = makeChar(id: 'defender', maxHealth: 200);
      attacker.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.nullifyAoe,
        sourceCharacterId: 'marker',
      ));

      engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(damage: damage),
        targets: [defender],
      );

      expect(defender.currentHealth, lessThan(200),
          reason: 'single-target bypasses ledger');
      expect(attacker.reactiveEffects, hasLength(1),
          reason: 'ledger stays armed');
    });

    test('Death Ledger arms on the target (enemy)', () {
      final caster = makeChar(id: 'caster');
      final enemy = makeChar(id: 'enemy');

      engine().resolveAbilityUse(
        attacker: caster,
        trigger: testTrigger(
          includeDamage: false,
          armsReactive: ReactiveKind.nullifyAoe,
          armsReactiveDefaultTurns: 3,
        ),
        targets: [enemy],
      );

      expect(enemy.reactiveEffects, hasLength(1));
      expect(enemy.reactiveEffects.first.kind, ReactiveKind.nullifyAoe);
      expect(caster.reactiveEffects, isEmpty);
    });

    test('trigger catalog entry exists', () {
      final catalog = TriggerCatalog.builtIn();
      final dl = catalog['death_ledger'] as ActiveTrigger;
      expect(dl.armsReactive, ReactiveKind.nullifyAoe);
      expect(dl.armsReactiveDefaultTurns, 3);
    });
  });

  group('Stored Retribution (bankDamage)', () {
    test('banks damage while Guarded and discharges on next attack', () {
      final holder = makeChar(id: 'holder', maxHealth: 200);
      final enemy = makeChar(id: 'enemy', maxHealth: 200);
      final target = makeChar(id: 'target', maxHealth: 200);

      holder.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.bankDamage,
        sourceCharacterId: 'holder',
      ));
      final statusEngine =
          StatusEffectEngine(diceRoller: DiceRoller(const FixedRandom(19)));
      statusEngine.apply(holder, 'guarded');

      final e = engine();

      // Enemy hits holder while guarded - damage is banked.
      e.resolveAbilityUse(
        attacker: enemy,
        trigger: testTrigger(
          damage: const DiceExpression(0, 1, flatBonus: 30),
        ),
        targets: [holder],
      );

      expect(holder.bankedDamage, greaterThan(0),
          reason: 'damage is banked while guarded');
      final banked = holder.bankedDamage;

      // Holder attacks target - banked damage discharged as bonus.
      e.resolveAbilityUse(
        attacker: holder,
        trigger: testTrigger(
          id: 'attack',
          damage: const DiceExpression(0, 1, flatBonus: 5),
        ),
        targets: [target],
      );

      expect(holder.bankedDamage, 0,
          reason: 'bank emptied after discharge');
      expect(target.currentHealth, lessThan(200 - 5),
          reason: 'target took base damage + banked bonus');
      expect(holder.reactiveEffects, isEmpty,
          reason: 'bankDamage reactive consumed');
    });

    test('does not bank damage when not Guarded/Braced', () {
      final holder = makeChar(id: 'holder', maxHealth: 200);
      final enemy = makeChar(id: 'enemy');

      holder.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.bankDamage,
        sourceCharacterId: 'holder',
      ));

      engine().resolveAbilityUse(
        attacker: enemy,
        trigger: testTrigger(
          damage: const DiceExpression(0, 1, flatBonus: 30),
        ),
        targets: [holder],
      );

      expect(holder.bankedDamage, 0,
          reason: 'no banking without guarded/braced');
    });

    test('trigger catalog entry exists', () {
      final catalog = TriggerCatalog.builtIn();
      final sr = catalog['stored_retribution'] as ActiveTrigger;
      expect(sr.armsReactive, ReactiveKind.bankDamage);
      expect(sr.targetAffiliation, TargetAffiliation.self);
    });
  });

  group('One More Breath (enrichSurviveLethal)', () {
    test('doubles status durations and stuns damage source on survive-lethal',
        () {
      final holder = makeChar(id: 'holder', maxHealth: 50);
      final attacker = makeChar(id: 'attacker', maxHealth: 200);

      final state = CharacterBattleState(
        testCharacter(
          id: 'holder',
          stats: testStats(maxHealth: 50, defense: 0, armor: 0),
        ),
        worldAbility: const WorldAbilityEffect(surviveLethalDamageOnce: true),
      );
      state.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.enrichSurviveLethal,
        sourceCharacterId: 'holder',
      ));
      final statusEngine =
          StatusEffectEngine(diceRoller: DiceRoller(const FixedRandom(19)));
      statusEngine.apply(state, 'empowered', durationOverride: 2);

      engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(
          damage: const DiceExpression(0, 1, flatBonus: 999),
        ),
        targets: [state],
      );

      expect(state.currentHealth, 1,
          reason: 'survived lethal via world ability');
      expect(state.statusEffects.first.remainingTurns, 4,
          reason: 'empowered duration doubled from 2 to 4');
      expect(
        attacker.statusEffects.any((e) => e.definitionId == 'stunned'),
        isTrue,
        reason: 'attacker is stunned by One More Breath',
      );
      expect(state.reactiveEffects, isEmpty,
          reason: 'enrichSurviveLethal consumed');
    });

    test('BT catalog entry on Gravebind', () {
      final catalog = BlackTriggerCatalog.builtIn();
      final gb = catalog['gravebind'];
      expect(gb.activeAbilities, hasLength(1));
      final breath = gb.activeAbilities.first;
      expect(breath.id, 'gravebind_breath');
      expect(breath.armsReactive, ReactiveKind.enrichSurviveLethal);
      expect(gb.worldAbility, isNotNull,
          reason: 'Gravebind still has its world ability');
    });
  });

  group('Seal of Severance (origin_lockout)', () {
    test('locks abilities of the specified origin category', () {
      final attacker = makeChar(id: 'attacker');
      final defender = makeChar(id: 'defender');

      final e = engine();
      final sealTrigger = testTrigger(
        damage: damage,
        inflictedStatusEffects: const [
          StatusEffectApplication('origin_lockout'),
        ],
      );

      e.resolveAbilityUse(
        attacker: attacker,
        trigger: sealTrigger,
        targets: [defender],
        statusEffectData: {'lockedOrigin': 'physical'},
      );

      expect(
        defender.statusEffects.any((e) => e.definitionId == 'origin_lockout'),
        isTrue,
        reason: 'origin_lockout status applied',
      );
      final instance = defender.statusEffects
          .firstWhere((e) => e.definitionId == 'origin_lockout');
      expect(instance.data['lockedOrigin'], 'physical');

      final physicalAbility = testTrigger(
        id: 'phys-attack',
        originTag: OriginTag.physical,
      );
      expect(e.canUseAbility(defender, physicalAbility), isFalse,
          reason: 'physical origin is locked');

      final energyAbility = testTrigger(
        id: 'energy-attack',
        originTag: OriginTag.energy,
      );
      expect(e.canUseAbility(defender, energyAbility), isTrue,
          reason: 'energy origin is not locked');
    });

    test('BT catalog entry on Ashbringer', () {
      final catalog = BlackTriggerCatalog.builtIn();
      final ab = catalog['ashbringer'];
      expect(ab.activeAbilities.length, 3);
      final seal = ab.activeAbilities
          .firstWhere((a) => a.id == 'ashbringer_seal');
      expect(seal.inflictedStatusEffects.single.statusEffectId,
          'origin_lockout');
    });
  });

  group('Root Snare (forced_repetition)', () {
    test('locks target to their last-used ability', () {
      final e = engine();
      final target = makeChar(id: 'target');

      final firstAbility = testTrigger(id: 'ability-a');
      // Set the last-used ability directly rather than via recordAbilityUse:
      // recordAbilityUse also consumes the turn's single ability slot, which
      // would make canUseAbility return false on the per-turn limit before
      // forced_repetition is ever evaluated. In real play the lockout is read
      // on a later turn, after the ability count has reset.
      target.lastUsedTriggerId = firstAbility.id;

      final statusEngine =
          StatusEffectEngine(diceRoller: DiceRoller(const FixedRandom(19)));
      statusEngine.apply(target, 'forced_repetition');

      expect(e.canUseAbility(target, firstAbility), isTrue,
          reason: 'last-used ability is still usable');

      final otherAbility = testTrigger(id: 'ability-b');
      expect(e.canUseAbility(target, otherAbility), isFalse,
          reason: 'other abilities are locked');
    });

    test('trigger catalog entry exists', () {
      final catalog = TriggerCatalog.builtIn();
      final rs = catalog['root_snare'] as ActiveTrigger;
      expect(rs.inflictedStatusEffects.single.statusEffectId,
          'forced_repetition');
    });
  });

  group('Scramble (misfire)', () {
    test('misfire status redirects attacks onto own allies', () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final ally = makeChar(id: 'ally', maxHealth: 200);
      attacker.teammates = [ally];
      ally.teammates = [attacker];

      final target = makeChar(id: 'target', maxHealth: 200);

      final statusEngine =
          StatusEffectEngine(diceRoller: DiceRoller(const FixedRandom(19)));
      statusEngine.apply(attacker, 'misfire');

      engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(damage: damage),
        targets: [target],
      );

      // FixedRandom(19) % 100 = 19 < 50 (misfireChance), so misfire
      // triggers. The attack is redirected onto the attacker's ally.
      expect(target.currentHealth, 200,
          reason: 'original target not hit due to misfire');
      expect(ally.currentHealth, lessThan(200),
          reason: 'ally of attacker takes the redirected hit');
    });

    test('trigger catalog entry exists', () {
      final catalog = TriggerCatalog.builtIn();
      final sc = catalog['scramble'] as ActiveTrigger;
      expect(sc.inflictedStatusEffects.single.statusEffectId, 'misfire');
    });
  });

  group('Counter priority ordering (B3)', () {
    test('Puppet Strings fires after Mirror Ward in priority order', () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final ally = makeChar(id: 'ally', maxHealth: 200);
      attacker.teammates = [ally];

      final defender = makeChar(id: 'defender', maxHealth: 200);
      defender.reactiveEffects.addAll([
        ReactiveEffect(
          kind: ReactiveKind.reflectNonAoe,
          sourceCharacterId: 'defender',
        ),
        ReactiveEffect(
          kind: ReactiveKind.redirectToOwnAlly,
          sourceCharacterId: 'puppet-caster',
        ),
      ]);

      engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(damage: damage),
        targets: [defender],
      );

      // Mirror Ward has higher priority, so it should fire first (reflect).
      expect(attacker.currentHealth, lessThan(200),
          reason: 'Mirror Ward reflects before Puppet Strings');
      expect(defender.currentHealth, 200,
          reason: 'defender is protected by reflect');
      expect(
        defender.reactiveEffects.any(
            (r) => r.kind == ReactiveKind.redirectToOwnAlly),
        isTrue,
        reason: 'Puppet Strings stays armed (Mirror Ward fired first)',
      );
    });

    test('Deadfall fires before target-side reactives', () {
      final attacker = makeChar(id: 'attacker', maxHealth: 200);
      final defender = makeChar(id: 'defender', maxHealth: 200);

      attacker.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.trapOnAction,
        sourceCharacterId: 'trapper',
        remainingTurns: 2,
      ));
      defender.reactiveEffects.add(ReactiveEffect(
        kind: ReactiveKind.reflectNonAoe,
        sourceCharacterId: 'defender',
      ));

      final result = engine().resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(damage: damage),
        targets: [defender],
      );

      expect(result.targetResults, isEmpty,
          reason: 'ability countered by Deadfall');
      expect(attacker.currentHealth, lessThan(200),
          reason: 'attacker takes Deadfall trap damage');
      expect(defender.currentHealth, 200,
          reason: 'defender untouched');
      expect(
        defender.reactiveEffects.any(
            (r) => r.kind == ReactiveKind.reflectNonAoe),
        isTrue,
        reason: 'Mirror Ward stays armed (ability never reached target)',
      );
    });
  });

  group('B3 catalog entries', () {
    test('Root Snare catalog entry', () {
      final catalog = TriggerCatalog.builtIn();
      final rs = catalog['root_snare'] as ActiveTrigger;
      expect(rs.category, TriggerCategory.trapper);
      expect(rs.originTag, OriginTag.physical);
      expect(rs.damageType, DamageType.bludgeoning);
      expect(rs.inflictedStatusEffects.single.statusEffectId,
          'forced_repetition');
    });

    test('Death Ledger catalog entry', () {
      final catalog = TriggerCatalog.builtIn();
      final dl = catalog['death_ledger'] as ActiveTrigger;
      expect(dl.category, TriggerCategory.trapper);
      expect(dl.armsReactive, ReactiveKind.nullifyAoe);
    });

    test('Scramble catalog entry', () {
      final catalog = TriggerCatalog.builtIn();
      final sc = catalog['scramble'] as ActiveTrigger;
      expect(sc.category, TriggerCategory.trapper);
      expect(sc.originTag, OriginTag.mental);
      expect(sc.inflictedStatusEffects.single.statusEffectId, 'misfire');
    });

    test('Stored Retribution catalog entry', () {
      final catalog = TriggerCatalog.builtIn();
      final sr = catalog['stored_retribution'] as ActiveTrigger;
      expect(sr.category, TriggerCategory.optional);
      expect(sr.armsReactive, ReactiveKind.bankDamage);
      expect(sr.targetAffiliation, TargetAffiliation.self);
    });

    test('Frozen Tempo catalog entry', () {
      final catalog = TriggerCatalog.builtIn();
      final ft = catalog['frozen_tempo'] as ActiveTrigger;
      expect(ft.category, TriggerCategory.optional);
      expect(ft.armsReactive, ReactiveKind.cooldownSabotage);
      expect(ft.targetAffiliation, TargetAffiliation.self);
    });

    test('Seal of Severance on Ashbringer', () {
      final catalog = BlackTriggerCatalog.builtIn();
      final ab = catalog['ashbringer'];
      expect(ab.activeAbilities.length, 3);
      final seal = ab.activeAbilities
          .firstWhere((a) => a.id == 'ashbringer_seal');
      expect(seal.name, 'Seal of Severance');
      expect(seal.inflictedStatusEffects.single.statusEffectId,
          'origin_lockout');
    });

    test('One More Breath on Gravebind', () {
      final catalog = BlackTriggerCatalog.builtIn();
      final gb = catalog['gravebind'];
      expect(gb.activeAbilities.length, 1);
      expect(gb.worldAbility, isNotNull);
      final breath = gb.activeAbilities.first;
      expect(breath.name, 'One More Breath');
      expect(breath.armsReactive, ReactiveKind.enrichSurviveLethal);
    });

    test('Puppet Strings and Deadfall on Paradox Shard', () {
      final catalog = BlackTriggerCatalog.builtIn();
      final ps = catalog['paradox_shard'];
      expect(ps.activeAbilities.length, 4);
      expect(
        ps.activeAbilities.any((a) => a.id == 'paradox_shard_puppet'),
        isTrue,
      );
      expect(
        ps.activeAbilities.any((a) => a.id == 'paradox_shard_deadfall'),
        isTrue,
      );
    });
  });

  group('canUseAbility checks', () {
    test('origin lockout blocks matching origin abilities', () {
      final e = engine();
      final state = makeChar(id: 'char');
      state.statusEffects.add(StatusEffectInstance(
        definitionId: 'origin_lockout',
        remainingTurns: 2,
        data: {'lockedOrigin': 'energy'},
      ));

      expect(
        e.canUseAbility(state, testTrigger(originTag: OriginTag.energy)),
        isFalse,
      );
      expect(
        e.canUseAbility(state, testTrigger(originTag: OriginTag.physical)),
        isTrue,
      );
    });

    test('forced repetition locks to last-used ability', () {
      final e = engine();
      final state = makeChar(id: 'char');
      state.lastUsedTriggerId = 'ability-a';
      state.statusEffects.add(StatusEffectInstance(
        definitionId: 'forced_repetition',
        remainingTurns: 2,
      ));

      expect(
        e.canUseAbility(state, testTrigger(id: 'ability-a')),
        isTrue,
      );
      expect(
        e.canUseAbility(state, testTrigger(id: 'ability-b')),
        isFalse,
      );
    });
  });
}

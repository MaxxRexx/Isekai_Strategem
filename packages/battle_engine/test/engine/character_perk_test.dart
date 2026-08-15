import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Builds a 3-member [Battle] whose team A consists of [protagonist] plus
/// two filler teammates, and team B is three filler opponents - enough
/// for team-aware perks (teammates, redirect) to have something to work
/// with, while keeping each test focused on one character.
Battle _battleWith(Character protagonist) {
  final teamA = Team(id: 'team-a', characters: [
    protagonist,
    testCharacter(id: 'ally-2'),
    testCharacter(id: 'ally-3'),
  ]);
  final teamB = Team(id: 'team-b', characters: [
    testCharacter(id: 'foe-1'),
    testCharacter(id: 'foe-2'),
    testCharacter(id: 'foe-3'),
  ]);
  return Battle(teamA: teamA, teamB: teamB);
}

void main() {
  group('Kaito - Last Ace (doublesCritChanceWhenLastAlive)', () {
    test('doubles Critical Chance once both teammates are down', () {
      final kaito = testCharacter(
        id: 'kaito',
        stats: testStats(criticalChance: 10),
        perk: const CharacterPerk(
          id: 'last_ace',
          name: 'Last Ace',
          description: '',
          doublesCritChanceWhenLastAlive: true,
        ),
      );
      final battle = _battleWith(kaito);
      final state = battle.states['kaito']!;

      expect(state.effectiveStats().criticalChance, 10);

      battle.states['ally-2']!.currentHealth = 0;
      expect(state.effectiveStats().criticalChance, 10);

      battle.states['ally-3']!.currentHealth = 0;
      expect(state.effectiveStats().criticalChance, 20);
    });
  });

  group('Marren - Bulwark (doublesArmorWhileAllyBelowQuarterHealth)', () {
    test('doubles Armor while any living ally is below 25% health', () {
      final marren = testCharacter(
        id: 'marren',
        stats: testStats(armor: 10),
        perk: const CharacterPerk(
          id: 'bulwark',
          name: 'Bulwark',
          description: '',
          doublesArmorWhileAllyBelowQuarterHealth: true,
        ),
      );
      final battle = _battleWith(marren);
      final state = battle.states['marren']!;

      expect(state.effectiveStats().armor, 10);

      battle.states['ally-2']!.currentHealth = 10; // < 25 of 100
      expect(state.effectiveStats().armor, 20);
    });
  });

  group('Dorian - Immovable (immuneToTargetCountReduction)', () {
    test('keeps full ranged target count while Blinded', () {
      final dorian = testCharacter(
        id: 'dorian',
        perk: const CharacterPerk(
          id: 'immovable',
          name: 'Immovable',
          description: '',
          immuneToTargetCountReduction: true,
        ),
      );
      final battle = _battleWith(dorian);
      final state = battle.states['dorian']!;
      battle.turnEngine.statusEffectEngine.apply(state, 'blinded');

      final trigger = testTrigger(
        rangeTag: RangeTag.long,
        attackType: AttackType.ranged,
        attackSubtype: AttackSubtype.burst,
        targetCount: 3,
        hitsPerUse: 1,
      );

      expect(battle.turnEngine.maxRangedTargets(state, trigger), 3);
    });
  });

  group('Haru - Battery (teamTrionGainModifierWhileAlive)', () {
    test("boosts the team's Trion gain roll while alive", () {
      final haru = testCharacter(
        id: 'haru',
        stats: testStats(trionAffinity: 0),
        perk: const CharacterPerk(
          id: 'battery',
          name: 'Battery',
          description: '',
          teamTrionGainModifierWhileAlive: 1.0,
        ),
      );
      final teamA = Team(id: 'team-a', characters: [
        haru,
        testCharacter(id: 'ally-2', stats: testStats(trionAffinity: 0)),
        testCharacter(id: 'ally-3', stats: testStats(trionAffinity: 0)),
      ]);
      final teamB = Team(id: 'team-b', characters: [
        testCharacter(id: 'foe-1'),
        testCharacter(id: 'foe-2'),
        testCharacter(id: 'foe-3'),
      ]);
      const config = TrionTierConfig(
          baseChanceLowToMedium: 0.0, baseChanceMediumToHigh: 0.0);
      final battle = Battle(
        teamA: teamA,
        teamB: teamB,
        turnEngine:
            TurnEngine(trionGainEngine: TrionGainEngine(config: config)),
      );

      // Team A's very first turn is the whole battle's first turn, which
      // the first-move handicap forces to Low regardless of any modifier -
      // advance to team A's second turn to observe Haru's perk cleanly.
      battle.startTurn();
      battle.endTurn();
      battle.startTurn();
      battle.endTurn();

      // With 0% base chance and 0 Trion Affinity, only Haru's +1.0
      // modifier (a guaranteed upgrade) can push the roll past Low.
      final result = battle.startTurn();
      expect(result.trionGain.tier, isNot(TrionTier.low));
    });
  });

  group('Yuki - Devoted Aid (incomingHealBonusPercent)', () {
    test(
        'boosts all healing Yuki receives, including a drain that heals '
        'its caster', () {
      final yuki = testCharacter(
        id: 'yuki',
        stats: testStats(maxHealth: 200),
        perk: const CharacterPerk(
          id: 'devoted_aid',
          name: 'Devoted Aid',
          description: '',
          incomingHealBonusPercent: 0.10,
        ),
      );
      final battle = _battleWith(yuki);
      final state = battle.states['yuki']!;
      state.currentHealth = 100;

      final drain = testTrigger(
        healAmount: const DiceExpression(0, 1, flatBonus: 20),
        healsCasterInstead: true,
      );
      final target = battle.states['foe-1']!;

      battle.turnEngine.resolveAbilityUse(
          attacker: state, trigger: drain, targets: [target]);

      // 20 base heal * 1.10 = 22, but only if the attack roll landed;
      // retry a few times against unseeded dice to avoid a flaky miss.
      var landed = false;
      for (var i = 0; i < 50 && !landed; i++) {
        state.currentHealth = 100;
        battle.turnEngine.resolveAbilityUse(
            attacker: state, trigger: drain, targets: [target]);
        if (state.currentHealth != 100) landed = true;
      }
      expect(landed, isTrue);
      expect(state.currentHealth, greaterThanOrEqualTo(100 + 20));
    });
  });

  group('Priya - Combat Medic (healBonusPercentVsAllyBelowHalfHealth)', () {
    test('heals more when the target ally is below 50% health', () {
      final priya = testCharacter(
        id: 'priya',
        perk: const CharacterPerk(
          id: 'combat_medic',
          name: 'Combat Medic',
          description: '',
          healBonusPercentVsAllyBelowHalfHealth: 0.5,
        ),
      );
      final battle = _battleWith(priya);
      final state = battle.states['priya']!;
      final healTrigger = testTrigger(
        includeDamage: false,
        targetAffiliation: TargetAffiliation.ally,
        healAmount: const DiceExpression(0, 1, flatBonus: 10),
      );

      final healthyAlly = battle.states['ally-2']!;
      healthyAlly.currentHealth = 90; // above 50% of 100
      final injuredAlly = battle.states['ally-3']!;
      injuredAlly.currentHealth = 20; // below 50% of 100

      int healedAmount(CharacterBattleState target) {
        var healed = 0;
        for (var i = 0; i < 50 && healed == 0; i++) {
          final before = target.currentHealth;
          target.currentHealth = before; // no-op, keeps loop readable
          battle.turnEngine.resolveAbilityUse(
              attacker: state, trigger: healTrigger, targets: [target]);
          healed = target.currentHealth - before;
          if (healed == 0) continue;
        }
        return healed;
      }

      final healthyHeal = healedAmount(healthyAlly);
      final injuredHeal = healedAmount(injuredAlly);
      expect(injuredHeal, greaterThan(healthyHeal));
    });
  });

  group('Soren - Weaken Resolve (bonusDurationVsAlreadyAffectedTarget)', () {
    test(
        'extends duration when the target already has an effect from '
        'the same caster', () {
      final soren = testCharacter(
        id: 'soren',
        stats: testStats(statusEffectInfliction: 1000),
        perk: const CharacterPerk(
          id: 'weaken_resolve',
          name: 'Weaken Resolve',
          description: '',
          bonusDurationVsAlreadyAffectedTarget: 2,
        ),
      );
      final battle = _battleWith(soren);
      // Force every roll to a mid, non-critical value so both the attack
      // roll and the infliction roll (1000 vs a default ~2 Resistance)
      // land deterministically instead of risking a natural-1 auto-fail
      // on unseeded dice.
      final engine = TurnEngine(
        combatEngine:
            CombatEngine(diceRoller: DiceRoller(const FixedRandom(9))),
        statusEffectEngine:
            StatusEffectEngine(diceRoller: DiceRoller(const FixedRandom(9))),
      );
      final state = battle.states['soren']!;
      final target = battle.states['foe-1']!;

      final debuffTrigger = testTrigger(
        includeDamage: false,
        inflictedStatusEffects: const [StatusEffectApplication('poisoned')],
      );
      final otherDebuffTrigger = testTrigger(
        id: 'other',
        includeDamage: false,
        inflictedStatusEffects: const [StatusEffectApplication('reeling')],
      );

      engine.resolveAbilityUse(
          attacker: state, trigger: otherDebuffTrigger, targets: [target]);
      engine.resolveAbilityUse(
          attacker: state, trigger: debuffTrigger, targets: [target]);

      final poisonedInstance =
          target.statusEffects.firstWhere((i) => i.definitionId == 'poisoned');
      final baseDuration =
          StatusEffectCatalog.defaultCatalog['poisoned'].defaultDurationTurns!;
      expect(poisonedInstance.remainingTurns, baseDuration + 2);
    });
  });

  group(
      'Celestine - Warding Presence '
      '(bonusStatusResistanceGrantedByAllyBuffs)', () {
    test('grants bonus Status Effect Resistance alongside an ally buff', () {
      final celestine = testCharacter(
        id: 'celestine',
        stats: testStats(statusEffectInfliction: 1000),
        perk: const CharacterPerk(
          id: 'warding_presence',
          name: 'Warding Presence',
          description: '',
          bonusStatusResistanceGrantedByAllyBuffs: 5,
        ),
      );
      final battle = _battleWith(celestine);
      // Force a guaranteed hit + infliction success instead of risking an
      // unseeded miss/natural-1.
      final engine = TurnEngine(
        combatEngine:
            CombatEngine(diceRoller: DiceRoller(const FixedRandom(9))),
        statusEffectEngine:
            StatusEffectEngine(diceRoller: DiceRoller(const FixedRandom(9))),
      );
      final state = battle.states['celestine']!;
      final ally = battle.states['ally-2']!;
      final buffTrigger = testTrigger(
        includeDamage: false,
        targetAffiliation: TargetAffiliation.ally,
        inflictedStatusEffects: const [StatusEffectApplication('inspired')],
      );

      final before = ally.effectiveStats().statusEffectResistance;
      engine.resolveAbilityUse(
          attacker: state, trigger: buffTrigger, targets: [ally]);
      final after = ally.effectiveStats().statusEffectResistance;

      expect(after, greaterThanOrEqualTo(before + 5));
    });
  });

  group('Rurik - All or Nothing (maxDamageBonusPercentAtZeroHealth)', () {
    test('deals more damage the lower his own health is', () {
      final rurik = testCharacter(
        id: 'rurik',
        stats: testStats(attack: 1000, maxHealth: 100),
        perk: const CharacterPerk(
          id: 'all_or_nothing',
          name: 'All or Nothing',
          description: '',
          maxDamageBonusPercentAtZeroHealth: 1.0,
        ),
      );
      final battle = _battleWith(rurik);
      final combatEngine =
          CombatEngine(diceRoller: DiceRoller(const FixedRandom(19)));
      final engine = TurnEngine(combatEngine: combatEngine);
      final state = battle.states['rurik']!;
      final target = battle.states['foe-1']!;
      final trigger = testTrigger(
        damage: const DiceExpression(0, 1, flatBonus: 10),
        attackType: AttackType.melee,
      );

      state.currentHealth = 100;
      final fullHealthResult = engine.resolveAbilityUse(
          attacker: state, trigger: trigger, targets: [target]);

      target.currentHealth = target.effectiveStats().maxHealth;
      state.currentHealth = 1;
      final lowHealthResult = engine.resolveAbilityUse(
          attacker: state, trigger: trigger, targets: [target]);

      expect(
        lowHealthResult.targetResults.single.totalDamageDealt,
        greaterThan(fullHealthResult.targetResults.single.totalDamageDealt),
      );
    });
  });

  group('Dross - Overwhelm (aoeDamageBonusPercentVsDebuffedTarget)', () {
    test(
        'AOE deals more damage to a target that already has a status '
        'effect', () {
      final dross = testCharacter(
        id: 'dross',
        stats: testStats(attack: 1000),
        perk: const CharacterPerk(
          id: 'overwhelm',
          name: 'Overwhelm',
          description: '',
          aoeDamageBonusPercentVsDebuffedTarget: 1.0,
        ),
      );
      final battle = _battleWith(dross);
      final combatEngine =
          CombatEngine(diceRoller: DiceRoller(const FixedRandom(19)));
      final engine = TurnEngine(combatEngine: combatEngine);
      final state = battle.states['dross']!;
      final debuffedTarget = battle.states['foe-1']!;
      final cleanTarget = battle.states['foe-2']!;
      battle.turnEngine.statusEffectEngine.apply(debuffedTarget, 'reeling');

      final trigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.aoe,
        targetCount: 2,
        damage: const DiceExpression(0, 1, flatBonus: 10),
      );

      final result = engine.resolveAbilityUse(
          attacker: state,
          trigger: trigger,
          targets: [debuffedTarget, cleanTarget]);

      final debuffedDamage = result.targetResults
          .firstWhere((r) => r.targetCharacterId == 'foe-1')
          .totalDamageDealt;
      final cleanDamage = result.targetResults
          .firstWhere((r) => r.targetCharacterId == 'foe-2')
          .totalDamageDealt;
      expect(debuffedDamage, greaterThan(cleanDamage));
    });
  });

  group('Nadia - Chain Reaction (perExtraAbilityDamageBonusPercent)', () {
    test('each extra ability used this turn deals more than the last', () {
      final nadia = testCharacter(
        id: 'nadia',
        stats: testStats(attack: 1000),
        perk: const CharacterPerk(
          id: 'chain_reaction',
          name: 'Chain Reaction',
          description: '',
          perExtraAbilityDamageBonusPercent: 0.5,
        ),
      );
      final battle = _battleWith(nadia);
      final combatEngine =
          CombatEngine(diceRoller: DiceRoller(const FixedRandom(19)));
      final engine = TurnEngine(combatEngine: combatEngine);
      final state = battle.states['nadia']!;
      final target = battle.states['foe-1']!;
      final trigger = testTrigger(
        trionCost: 0,
        cooldownTurns: 0,
        attackType: AttackType.melee,
        damage: const DiceExpression(0, 1, flatBonus: 10),
      );
      final pool = TrionPool(current: 1000);

      engine.useAbility(state, trigger, pool);
      target.currentHealth = target.effectiveStats().maxHealth;
      final firstUse = engine.resolveAbilityUse(
          attacker: state, trigger: trigger, targets: [target]);

      engine.useAbility(state, trigger, pool);
      target.currentHealth = target.effectiveStats().maxHealth;
      final secondUse = engine.resolveAbilityUse(
          attacker: state, trigger: trigger, targets: [target]);

      expect(
        secondUse.targetResults.single.totalDamageDealt,
        greaterThan(firstUse.targetResults.single.totalDamageDealt),
      );
    });
  });

  group('Zheng - Foresight (canRerollOwnAttackRollOncePerBattle)', () {
    test('rerolls a missed attack once per battle', () {
      final zheng = testCharacter(
        id: 'zheng',
        stats: testStats(attack: -1000),
        perk: const CharacterPerk(
          id: 'foresight',
          name: 'Foresight',
          description: '',
          canRerollOwnAttackRollOncePerBattle: true,
        ),
      );
      final battle = _battleWith(zheng);
      // Force a natural 1 (guaranteed miss) instead of risking an
      // unseeded natural 20 auto-hit, which would skip the reroll branch
      // entirely.
      final engine = TurnEngine(
          combatEngine:
              CombatEngine(diceRoller: DiceRoller(const FixedRandom(0))));
      final state = battle.states['zheng']!;
      expect(state.perkChargeUsed, isFalse);

      final target = battle.states['foe-1']!;
      final trigger = testTrigger(attackType: AttackType.melee);
      engine.resolveAbilityUse(
          attacker: state, trigger: trigger, targets: [target]);

      expect(state.perkChargeUsed, isTrue);
    });
  });

  group('Mireille - Decoy (dodgeChanceOncePerBattle)', () {
    test('consumes the charge on the first incoming attack', () {
      final mireille = testCharacter(
        id: 'mireille',
        perk: const CharacterPerk(
          id: 'decoy',
          name: 'Decoy',
          description: '',
          dodgeChanceOncePerBattle: 1.0,
        ),
      );
      final battle = _battleWith(mireille);
      final state = battle.states['mireille']!;
      final attackerState = battle.states['foe-1']!;
      final trigger = testTrigger(attackType: AttackType.melee);

      expect(state.perkChargeUsed, isFalse);
      final result = battle.turnEngine.resolveAbilityUse(
          attacker: attackerState, trigger: trigger, targets: [state]);

      expect(state.perkChargeUsed, isTrue);
      // A 100% dodge chance guarantees a miss regardless of the roll.
      expect(result.targetResults.single.totalDamageDealt, 0);
    });
  });

  group('Sable - Guardian\'s Instinct (canRedirectAllyAttackOncePerBattle)',
      () {
    test('redirects an attack from a teammate onto Sable once per battle', () {
      final sable = testCharacter(
        id: 'sable',
        perk: const CharacterPerk(
          id: 'guardians_instinct',
          name: "Guardian's Instinct",
          description: '',
          canRedirectAllyAttackOncePerBattle: true,
        ),
      );
      final teamA = Team(id: 'team-a', characters: [
        sable,
        testCharacter(id: 'ally-2'),
        testCharacter(id: 'ally-3'),
      ]);
      final teamB = Team(id: 'team-b', characters: [
        testCharacter(id: 'foe-1'),
        testCharacter(id: 'foe-2'),
        testCharacter(id: 'foe-3'),
      ]);
      final battle = Battle(teamA: teamA, teamB: teamB);

      final attacker = battle.states['foe-1']!;
      final trigger = testTrigger();
      final result = battle.turnEngine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [battle.states['ally-2']!],
      );

      expect(result.targetResults.single.targetCharacterId, 'sable');
      expect(battle.states['sable']!.perkChargeUsed, isTrue);
    });
  });

  group('Ilona - Riposte (attackStackBonusOnMeleeMissAgainstSelf)', () {
    test('gains a stacking Attack buff whenever a melee attack misses her', () {
      final ilona = testCharacter(
        id: 'ilona',
        stats: testStats(attack: 10, defense: 1000),
        perk: const CharacterPerk(
          id: 'riposte',
          name: 'Riposte',
          description: '',
          attackStackBonusOnMeleeMissAgainstSelf: 3,
        ),
      );
      final battle = _battleWith(ilona);
      final combatEngine =
          CombatEngine(diceRoller: DiceRoller(const FixedRandom(9)));
      final engine = TurnEngine(combatEngine: combatEngine);
      final state = battle.states['ilona']!;
      final attackerState = battle.states['foe-1']!;
      final trigger = testTrigger(
          attackType: AttackType.melee, attackSubtype: AttackSubtype.single);

      final before = state.effectiveStats().attack;
      engine.resolveAbilityUse(
          attacker: attackerState, trigger: trigger, targets: [state]);
      final after = state.effectiveStats().attack;

      expect(after, greaterThanOrEqualTo(before + 3));
    });
  });

  group('Bastian - Absorb (firstDamageInstanceReductionPercent)', () {
    test('halves the first damage instance of the battle', () {
      final bastian = testCharacter(
        id: 'bastian',
        stats: testStats(armor: 0, maxHealth: 1000),
        perk: const CharacterPerk(
          id: 'absorb',
          name: 'Absorb',
          description: '',
          firstDamageInstanceReductionPercent: 0.5,
        ),
      );
      final battle = _battleWith(bastian);
      final combatEngine =
          CombatEngine(diceRoller: DiceRoller(const FixedRandom(19)));
      final engine = TurnEngine(combatEngine: combatEngine);
      final state = battle.states['bastian']!;
      final attackerState = battle.states['foe-1']!;
      final trigger = testTrigger(
          attackType: AttackType.melee,
          damage: const DiceExpression(0, 1, flatBonus: 100));

      expect(state.perkChargeUsed, isFalse);
      final firstResult = engine.resolveAbilityUse(
          attacker: attackerState, trigger: trigger, targets: [state]);
      expect(state.perkChargeUsed, isTrue);

      state.currentHealth = state.effectiveStats().maxHealth;
      final secondResult = engine.resolveAbilityUse(
          attacker: attackerState, trigger: trigger, targets: [state]);

      expect(
        firstResult.targetResults.single.totalDamageDealt,
        lessThan(secondResult.targetResults.single.totalDamageDealt),
      );
    });
  });

  group(
      'Vela - First Blood '
      '(firstAttackCritBonusVsFullHealthTarget)', () {
    test("consumes her charge on her first attack of the battle", () {
      final vela = testCharacter(
        id: 'vela',
        perk: const CharacterPerk(
          id: 'first_blood',
          name: 'First Blood',
          description: '',
          firstAttackCritBonusVsFullHealthTarget: 50,
        ),
      );
      final battle = _battleWith(vela);
      final state = battle.states['vela']!;
      final target = battle.states['foe-1']!;
      final trigger = testTrigger();

      expect(state.perkChargeUsed, isFalse);
      battle.turnEngine.resolveAbilityUse(
          attacker: state, trigger: trigger, targets: [target]);
      expect(state.perkChargeUsed, isTrue);
    });
  });

  group('Airi - Feint (firstIncomingAttackHasDisadvantage)', () {
    test('the first attack against her rolls with disadvantage', () {
      final airi = testCharacter(
        id: 'airi',
        perk: const CharacterPerk(
          id: 'feint',
          name: 'Feint',
          description: '',
          firstIncomingAttackHasDisadvantage: true,
        ),
      );
      final battle = _battleWith(airi);
      final state = battle.states['airi']!;
      final attackerState = battle.states['foe-1']!;
      final trigger = testTrigger();

      expect(state.perkChargeUsed, isFalse);
      final result = battle.turnEngine.resolveAbilityUse(
          attacker: attackerState, trigger: trigger, targets: [state]);

      expect(state.perkChargeUsed, isTrue);
      expect(result.targetResults.single.attackRolls.single.attackerRoll.mode,
          RollMode.disadvantage);
    });
  });

  group('Ren - First Strike (firstTurnAttackBonus)', () {
    test('adds a flat Attack bonus on the first ability use of the battle', () {
      final ren = testCharacter(
        id: 'ren',
        stats: testStats(attack: 10),
        perk: const CharacterPerk(
          id: 'first_strike',
          name: 'First Strike',
          description: '',
          firstTurnAttackBonus: 5,
        ),
      );
      final battle = _battleWith(ren);
      final state = battle.states['ren']!;
      final target = battle.states['foe-1']!;
      final trigger = testTrigger(attackType: AttackType.melee);

      expect(state.perkChargeUsed, isFalse);
      final firstUse = battle.turnEngine.resolveAbilityUse(
          attacker: state, trigger: trigger, targets: [target]);
      expect(state.perkChargeUsed, isTrue);
      expect(
          firstUse
              .targetResults.single.attackRolls.single.attackerRoll.modifier,
          15);

      final secondUse = battle.turnEngine.resolveAbilityUse(
          attacker: state, trigger: trigger, targets: [target]);
      expect(
          secondUse
              .targetResults.single.attackRolls.single.attackerRoll.modifier,
          10);
    });
  });

  group('Tobias - Versatile (grantsBonusForLastUsedAbilityCategory)', () {
    test(
        'grants a stat bonus matching the category of the last ability '
        'used', () {
      final tobias = testCharacter(
        id: 'tobias',
        stats: testStats(attack: 10),
        perk: const CharacterPerk(
          id: 'versatile',
          name: 'Versatile',
          description: '',
          grantsBonusForLastUsedAbilityCategory: true,
        ),
      );
      final battle = _battleWith(tobias);
      final state = battle.states['tobias']!;
      expect(state.effectiveStats().attack, 10);

      final trigger = testTrigger(category: TriggerCategory.attacker);
      final pool = TrionPool(current: 1000);
      battle.turnEngine.useAbility(state, trigger, pool);

      expect(state.effectiveStats().attack, 12);
    });
  });
}

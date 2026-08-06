import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Combat v2 Phase B4: the 6 passive-trigger counters (Draegor, Nullhymn,
/// Reckoning, Gravehour, Coldread, Ironvow).
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
    int trionAffinity = 10,
  }) =>
      CharacterBattleState(testCharacter(
        id: id,
        stats: testStats(
          attack: attack,
          defense: defense,
          armor: armor,
          maxHealth: maxHealth,
          trionAffinity: trionAffinity,
        ),
      ));

  void wireTeam(List<CharacterBattleState> team) {
    for (final state in team) {
      state.teammates = team.where((s) => !identical(s, state)).toList();
    }
  }

  final damage = const DiceExpression(0, 1, flatBonus: 10);

  // -------------------------------------------------------------------------
  // Draegor
  // -------------------------------------------------------------------------

  group('Draegor', () {
    test('accumulates Enmity and generates Regret at threshold', () {
      final holder = makeChar(id: 'holder');
      holder.passiveCounters[PassiveCounterKind.draegor] =
          PassiveCounterState(PassiveCounterKind.draegor);
      wireTeam([holder]);

      final e = engine();
      final trigger = testTrigger(damage: damage);

      for (var i = 0; i < 5; i++) {
        e.notifyAbilityResolved(
          attacker: holder,
          trigger: trigger,
          result: AbilityUseResult(
            attackerCharacterId: holder.character.id,
            triggerId: trigger.id,
            targetResults: const [],
          ),
          defenderTeamStates: [],
        );
      }

      final draegor = holder.passiveCounters[PassiveCounterKind.draegor]!;
      expect(draegor.counter, 0, reason: 'counter resets after threshold');
      expect(draegor.regretRemainingTurns, 2);
      expect(draegor.totalRegretGenerated, 1);
    });

    test('Regret consumed on FAT chain gives TA boost', () {
      final holder = makeChar(id: 'holder', trionAffinity: 20);
      holder.passiveCounters[PassiveCounterKind.draegor] =
          PassiveCounterState(PassiveCounterKind.draegor);
      final ally = makeChar(id: 'ally', trionAffinity: 30);
      wireTeam([holder, ally]);

      final draegor = holder.passiveCounters[PassiveCounterKind.draegor]!;
      draegor.regretRemainingTurns = 2;
      draegor.totalRegretGenerated = 1;

      final opponent = makeChar(id: 'opp');
      wireTeam([opponent]);
      // Simulate opponent chaining 2+ abilities (FAT threshold).
      opponent.recordAbilityUse(testTrigger(id: 'a1', damage: damage));
      opponent.recordAbilityUse(testTrigger(id: 'a2', damage: damage));

      final e = engine();
      e.tickEndOfTurnPassiveCounters(
        activeTeamStates: [opponent],
        inactiveTeamStates: [holder, ally],
        activeTeamPool: TrionPool(current: 100),
        inactiveTeamPool: TrionPool(current: 100),
        activeTeamDealtDamage: true,
      );

      expect(draegor.regretRemainingTurns, 0, reason: 'Regret consumed');
      expect(ally.tempFlatBonuses, isNotEmpty,
          reason: 'highest-TA ally gets bonus');
    });
  });

  // -------------------------------------------------------------------------
  // Nullhymn
  // -------------------------------------------------------------------------

  group('Nullhymn', () {
    test('discord from BT active hits threshold and discharges', () {
      final holder = makeChar(id: 'holder');
      holder.passiveCounters[PassiveCounterKind.nullhymn] =
          PassiveCounterState(PassiveCounterKind.nullhymn);
      wireTeam([holder]);

      final enemy = makeChar(id: 'enemy');
      wireTeam([enemy]);

      final trigger = testTrigger(id: 'bt-attack', damage: damage);
      final e = engine();

      for (var i = 0; i < 5; i++) {
        e.notifyAbilityResolved(
          attacker: enemy,
          trigger: trigger,
          result: AbilityUseResult(
            attackerCharacterId: enemy.character.id,
            triggerId: trigger.id,
            targetResults: const [],
          ),
          defenderTeamStates: [holder],
          isBlackTriggerAbility: true,
        );
      }

      final nullhymn = holder.passiveCounters[PassiveCounterKind.nullhymn]!;
      expect(nullhymn.counter, 5);

      e.tickEndOfTurnPassiveCounters(
        activeTeamStates: [enemy],
        inactiveTeamStates: [holder],
        activeTeamPool: TrionPool(current: 100),
        inactiveTeamPool: TrionPool(current: 100),
        activeTeamDealtDamage: true,
      );

      expect(nullhymn.counter, 0, reason: 'reset after discharge');
      expect(nullhymn.chargesUsed, 1);
    });

    test('discord from status infliction is deduped per status per turn', () {
      final holder = makeChar(id: 'holder');
      holder.passiveCounters[PassiveCounterKind.nullhymn] =
          PassiveCounterState(PassiveCounterKind.nullhymn);
      wireTeam([holder]);

      final e = engine();
      e.notifyStatusInflicted(holder, 'poisoned');
      e.notifyStatusInflicted(holder, 'poisoned');
      e.notifyStatusInflicted(holder, 'stunned');

      final nullhymn = holder.passiveCounters[PassiveCounterKind.nullhymn]!;
      expect(nullhymn.counter, 2,
          reason: 'poisoned counted once, stunned counted once');
    });
  });

  // -------------------------------------------------------------------------
  // Reckoning
  // -------------------------------------------------------------------------

  group('Reckoning', () {
    test('accumulates Debt from crits and 2+ cooldown abilities', () {
      final holder = makeChar(id: 'holder');
      holder.passiveCounters[PassiveCounterKind.reckoning] =
          PassiveCounterState(PassiveCounterKind.reckoning);
      wireTeam([holder]);

      final enemy = makeChar(id: 'enemy');
      wireTeam([enemy]);

      final trigger = testTrigger(
        id: 'heavy-attack',
        damage: damage,
        cooldownTurns: 3,
      );

      final e = engine();
      final critResult = AbilityUseResult(
        attackerCharacterId: enemy.character.id,
        triggerId: trigger.id,
        targetResults: [
          TargetHitResult(
            targetCharacterId: holder.character.id,
            attackRolls: [
              AttackRollOutcome(
                attackerRoll: D20RollResult(
                  rawRolls: const [20],
                  kept: 20,
                  mode: RollMode.normal,
                  modifier: 0,
                ),
                defenderRoll: D20RollResult(
                  rawRolls: const [5],
                  kept: 5,
                  mode: RollMode.normal,
                  modifier: 0,
                ),
                isHit: true,
                isCriticalHit: true,
                isCriticalMiss: false,
                criticalHitThreshold: 20,
              ),
            ],
            damagePerHit: const [10],
            damageDetails: const [null],
            totalDamageDealt: 10,
            statusEffectsApplied: const [],
          ),
        ],
      );

      e.notifyAbilityResolved(
        attacker: enemy,
        trigger: trigger,
        result: critResult,
        defenderTeamStates: [holder],
      );

      final reckoning = holder.passiveCounters[PassiveCounterKind.reckoning]!;
      expect(reckoning.counter, 2,
          reason: '+1 for crit, +1 for 2+ cooldown');
    });

    test('discharges at 6 Debt: cooldown extension + forced crit miss + Levy',
        () {
      final holder = makeChar(id: 'holder');
      holder.passiveCounters[PassiveCounterKind.reckoning] =
          PassiveCounterState(PassiveCounterKind.reckoning);
      wireTeam([holder]);

      final enemy = makeChar(id: 'enemy');
      enemy.cooldowns['attack-1'] = 2;
      enemy.cooldowns['attack-2'] = 1;
      wireTeam([enemy]);

      final reckoning = holder.passiveCounters[PassiveCounterKind.reckoning]!;
      reckoning.counter = 6;
      reckoning.counterByEnemyId['enemy'] = 6;

      final enemyPool = TrionPool(current: 100)..gain(50);
      final holderPool = TrionPool(current: 100);
      final e = engine();

      e.tickEndOfTurnPassiveCounters(
        activeTeamStates: [enemy],
        inactiveTeamStates: [holder],
        activeTeamPool: enemyPool,
        inactiveTeamPool: holderPool,
        activeTeamDealtDamage: true,
      );

      expect(enemy.cooldowns['attack-1'], 3,
          reason: 'cooldown extended +1');
      expect(enemy.cooldowns['attack-2'], 2,
          reason: 'cooldown extended +1');
      expect(
          enemy.statusEffects
              .any((i) => i.definitionId == 'forced_critical_miss'),
          isTrue);
      expect(holderPool.current, greaterThan(0), reason: 'Levy transferred');
      expect(reckoning.lockedOut, isTrue, reason: 'one-shot per battle');
    });

    test('forced_critical_miss overrides attack roll to crit miss', () {
      final attacker = makeChar(id: 'attacker');
      final defender = makeChar(id: 'defender');

      attacker.statusEffects.add(StatusEffectInstance(
        definitionId: 'forced_critical_miss',
        remainingTurns: 1,
      ));

      final e = engine();
      final result = e.resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(damage: damage),
        targets: [defender],
      );

      expect(result.targetResults.first.attackRolls.first.isCriticalMiss,
          isTrue);
      expect(result.targetResults.first.totalDamageDealt, 0);
      expect(
          attacker.statusEffects
              .any((i) => i.definitionId == 'forced_critical_miss'),
          isFalse,
          reason: 'consumed after use');
    });
  });

  // -------------------------------------------------------------------------
  // Gravehour
  // -------------------------------------------------------------------------

  group('Gravehour', () {
    test('fires finisher on lowest-HP enemy when opponent stalls', () {
      final holder = makeChar(id: 'holder');
      holder.passiveCounters[PassiveCounterKind.gravehour] =
          PassiveCounterState(PassiveCounterKind.gravehour);
      wireTeam([holder]);

      final enemy1 = makeChar(id: 'enemy-1', maxHealth: 200);
      enemy1.currentHealth = 100;
      final enemy2 = makeChar(id: 'enemy-2', maxHealth: 200);
      enemy2.currentHealth = 50;
      wireTeam([enemy1, enemy2]);

      final e = engine();
      e.tickEndOfTurnPassiveCounters(
        activeTeamStates: [enemy1, enemy2],
        inactiveTeamStates: [holder],
        activeTeamPool: TrionPool(current: 100),
        inactiveTeamPool: TrionPool(current: 100),
        activeTeamDealtDamage: false,
      );

      expect(enemy2.currentHealth, lessThan(50),
          reason: 'finisher hits lowest-HP enemy');
      expect(
          enemy2.statusEffects.any((i) => i.definitionId == 'cursed'), isTrue,
          reason: 'heal prevention applied');
      final gravehour =
          holder.passiveCounters[PassiveCounterKind.gravehour]!;
      expect(gravehour.cooldownTurns, 3,
          reason: 'on cooldown after firing');
    });

    test('fires when enemy is at 30% HP or below', () {
      final holder = makeChar(id: 'holder');
      holder.passiveCounters[PassiveCounterKind.gravehour] =
          PassiveCounterState(PassiveCounterKind.gravehour);
      wireTeam([holder]);

      final enemy = makeChar(id: 'enemy', maxHealth: 200);
      enemy.currentHealth = 60;
      wireTeam([enemy]);

      final e = engine();
      e.tickEndOfTurnPassiveCounters(
        activeTeamStates: [enemy],
        inactiveTeamStates: [holder],
        activeTeamPool: TrionPool(current: 100),
        inactiveTeamPool: TrionPool(current: 100),
        activeTeamDealtDamage: true,
      );

      expect(enemy.currentHealth, lessThan(60),
          reason: 'finisher fires on low-HP target');
    });

    test('does not fire while on cooldown', () {
      final holder = makeChar(id: 'holder');
      holder.passiveCounters[PassiveCounterKind.gravehour] =
          PassiveCounterState(PassiveCounterKind.gravehour);
      holder.passiveCounters[PassiveCounterKind.gravehour]!.cooldownTurns = 2;
      wireTeam([holder]);

      final enemy = makeChar(id: 'enemy');
      enemy.currentHealth = 10;
      wireTeam([enemy]);

      final healthBefore = enemy.currentHealth;

      final e = engine();
      e.tickEndOfTurnPassiveCounters(
        activeTeamStates: [enemy],
        inactiveTeamStates: [holder],
        activeTeamPool: TrionPool(current: 100),
        inactiveTeamPool: TrionPool(current: 100),
        activeTeamDealtDamage: false,
      );

      expect(enemy.currentHealth, healthBefore,
          reason: 'Gravehour on cooldown, should not fire');
    });
  });

  // -------------------------------------------------------------------------
  // Coldread
  // -------------------------------------------------------------------------

  group('Coldread', () {
    test('marks enemy at start of turn and resolves at end of opponent turn',
        () {
      final holder = makeChar(id: 'holder');
      holder.passiveCounters[PassiveCounterKind.coldread] =
          PassiveCounterState(PassiveCounterKind.coldread);
      wireTeam([holder]);

      final enemy = makeChar(id: 'enemy');
      wireTeam([enemy]);

      final e = engine();

      // Start of holder's turn: mark an enemy.
      e.tickStartOfTurnPassiveCounters([holder], [enemy]);

      final coldread = holder.passiveCounters[PassiveCounterKind.coldread]!;
      expect(coldread.markedEnemyId, 'enemy');
      expect(coldread.pendingResolution, isTrue);
    });

    test('correct read transfers Trion via Levy', () {
      final holder = makeChar(id: 'holder');
      holder.passiveCounters[PassiveCounterKind.coldread] =
          PassiveCounterState(PassiveCounterKind.coldread);
      wireTeam([holder]);

      final enemy = makeChar(id: 'enemy');
      enemy.triggersUsedThisTurn.add('some-attack');
      wireTeam([enemy]);

      final coldread = holder.passiveCounters[PassiveCounterKind.coldread]!;
      coldread.markedEnemyId = 'enemy';
      coldread.pendingResolution = true;
      coldread.markedEnemyActedDamaging = true;

      final enemyPool = TrionPool(current: 100)..gain(60);
      final holderPool = TrionPool(current: 100);

      final e = engine();
      e.tickEndOfTurnPassiveCounters(
        activeTeamStates: [enemy],
        inactiveTeamStates: [holder],
        activeTeamPool: enemyPool,
        inactiveTeamPool: holderPool,
        activeTeamDealtDamage: true,
      );

      expect(holderPool.current, greaterThan(0),
          reason: 'Levy transfers Trion on correct read');
      expect(coldread.pendingResolution, isFalse);
      expect(coldread.cooldownTurns, 1);
    });

    test('correct reads alternate Levy then Seize (Levy first)', () {
      final holder = makeChar(id: 'holder', attack: 1000, defense: 5);
      final ally = makeChar(id: 'ally', attack: 500, defense: 5);
      holder.passiveCounters[PassiveCounterKind.coldread] =
          PassiveCounterState(PassiveCounterKind.coldread);
      wireTeam([holder, ally]);

      final enemy = makeChar(id: 'enemy');
      enemy.triggersUsedThisTurn.add('some-attack');
      wireTeam([enemy]);

      final coldread = holder.passiveCounters[PassiveCounterKind.coldread]!;

      void resolveCorrectRead(TrionPool enemyPool, TrionPool holderPool) {
        coldread.markedEnemyId = 'enemy';
        coldread.pendingResolution = true;
        coldread.markedEnemyActedDamaging = true;
        engine().tickEndOfTurnPassiveCounters(
          activeTeamStates: [enemy],
          inactiveTeamStates: [holder, ally],
          activeTeamPool: enemyPool,
          inactiveTeamPool: holderPool,
          activeTeamDealtDamage: true,
        );
      }

      // First correct read: Levy (Trion transfers, no roll bonus yet).
      resolveCorrectRead(
          TrionPool(current: 100)..gain(60), TrionPool(current: 100));
      expect(holder.effectiveStats(fatConfig: FatConfig.defaults).attack, 1000,
          reason: 'no Seize bonus on the first (Levy) read');
      expect(coldread.coldreadNextRewardIsSeize, isTrue);

      // Second correct read: Seize (+2 to all rolls squad-wide, no Levy).
      resolveCorrectRead(
          TrionPool(current: 100)..gain(60), TrionPool(current: 100));
      expect(holder.effectiveStats(fatConfig: FatConfig.defaults).attack, 1002);
      expect(holder.effectiveStats(fatConfig: FatConfig.defaults).defense, 7);
      expect(ally.effectiveStats(fatConfig: FatConfig.defaults).attack, 502,
          reason: 'Seize buffs the whole living squad, not just the holder');
      expect(coldread.coldreadNextRewardIsSeize, isFalse,
          reason: 'alternation flips back to Levy for the next read');
    });

    test('wrong read docks Trion gain next turn', () {
      final holder = makeChar(id: 'holder');
      holder.passiveCounters[PassiveCounterKind.coldread] =
          PassiveCounterState(PassiveCounterKind.coldread);
      wireTeam([holder]);

      final enemy = makeChar(id: 'enemy');
      wireTeam([enemy]);

      final coldread = holder.passiveCounters[PassiveCounterKind.coldread]!;
      coldread.markedEnemyId = 'enemy';
      coldread.pendingResolution = true;
      coldread.markedEnemyActedDamaging = false;

      final e = engine();
      e.tickEndOfTurnPassiveCounters(
        activeTeamStates: [enemy],
        inactiveTeamStates: [holder],
        activeTeamPool: TrionPool(current: 100),
        inactiveTeamPool: TrionPool(current: 100),
        activeTeamDealtDamage: false,
      );

      expect(coldread.trionGainDockedNextTurn, isTrue);
      expect(coldread.pendingResolution, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Ironvow
  // -------------------------------------------------------------------------

  group('Ironvow', () {
    test('sanctions a type at start of turn', () {
      final holder = makeChar(id: 'holder');
      holder.passiveCounters[PassiveCounterKind.ironvow] =
          PassiveCounterState(PassiveCounterKind.ironvow);
      wireTeam([holder]);

      final e = engine();
      e.tickStartOfTurnPassiveCounters([holder], []);

      final ironvow = holder.passiveCounters[PassiveCounterKind.ironvow]!;
      expect(ironvow.sanctionedType, isNotNull);
    });

    test('sanctioned strike strips buff + applies interdict + exposes allies',
        () {
      final holder = makeChar(id: 'holder');
      holder.passiveCounters[PassiveCounterKind.ironvow] =
          PassiveCounterState(PassiveCounterKind.ironvow);
      final ally = makeChar(id: 'ally');
      wireTeam([holder, ally]);

      final ironvow = holder.passiveCounters[PassiveCounterKind.ironvow]!;
      ironvow.sanctionedType = AttackType.melee;

      final target = makeChar(id: 'target');
      target.statusEffects.add(StatusEffectInstance(
        definitionId: 'empowered',
        remainingTurns: 2,
      ));
      wireTeam([target]);

      final trigger =
          testTrigger(damage: damage, attackType: AttackType.melee);
      final e = engine();

      final fired = e.checkSanctionedStrike(holder, trigger, target);

      expect(fired, isTrue);
      expect(
          target.statusEffects
              .any((i) => i.definitionId == 'empowered'),
          isFalse,
          reason: 'buff stripped');
      expect(
          target.statusEffects.any((i) => i.definitionId == 'interdict'),
          isTrue,
          reason: 'branded with Interdict');
      expect(
          ally.statusEffects.any((i) => i.definitionId == 'exposed'), isTrue,
          reason: 'allies exposed');
      expect(ironvow.chargesUsed, 1);
    });

    test('Interdict reduces damage when repeating an ability', () {
      final attacker = makeChar(id: 'attacker');
      final defender = makeChar(id: 'defender', armor: 0);

      attacker.statusEffects.add(StatusEffectInstance(
        definitionId: 'interdict',
        remainingTurns: 2,
      ));
      attacker.triggersUsedLastTurn.add('repeat-attack');

      final trigger =
          testTrigger(id: 'repeat-attack', damage: damage);
      final e = engine();

      final result = e.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [defender],
      );

      final fullDamageDefender = makeChar(id: 'full-defender', armor: 0);
      final cleanAttacker = makeChar(id: 'clean-attacker');
      final fullResult = e.resolveAbilityUse(
        attacker: cleanAttacker,
        trigger: trigger,
        targets: [fullDamageDefender],
      );

      expect(result.targetResults.first.totalDamageDealt,
          lessThan(fullResult.targetResults.first.totalDamageDealt),
          reason: 'Interdict reduces repeated-ability damage');
    });

    test('does not fire when attack type does not match', () {
      final holder = makeChar(id: 'holder');
      holder.passiveCounters[PassiveCounterKind.ironvow] =
          PassiveCounterState(PassiveCounterKind.ironvow);
      wireTeam([holder]);

      final ironvow = holder.passiveCounters[PassiveCounterKind.ironvow]!;
      ironvow.sanctionedType = AttackType.ranged;

      final target = makeChar(id: 'target');
      wireTeam([target]);

      final trigger =
          testTrigger(damage: damage, attackType: AttackType.melee);
      final e = engine();

      final fired = e.checkSanctionedStrike(holder, trigger, target);
      expect(fired, isFalse);
    });

    test('max 3 strikes per battle', () {
      final holder = makeChar(id: 'holder');
      holder.passiveCounters[PassiveCounterKind.ironvow] =
          PassiveCounterState(PassiveCounterKind.ironvow);
      wireTeam([holder]);

      final ironvow = holder.passiveCounters[PassiveCounterKind.ironvow]!;
      ironvow.sanctionedType = AttackType.melee;
      ironvow.chargesUsed = 3;

      final target = makeChar(id: 'target');
      wireTeam([target]);

      final trigger =
          testTrigger(damage: damage, attackType: AttackType.melee);
      final e = engine();

      final fired = e.checkSanctionedStrike(holder, trigger, target);
      expect(fired, isFalse, reason: 'all 3 strikes exhausted');
    });
  });

  // -------------------------------------------------------------------------
  // Battle integration: initializePassiveCounters + hook wiring
  // -------------------------------------------------------------------------

  group('Battle passive counter integration', () {
    test('initializePassiveCounters sets up counter state from triggers', () {
      final teamA = Team(
        id: 'A',
        characters: [
          testCharacter(id: 'a1'),
          testCharacter(id: 'a2'),
          testCharacter(id: 'a3'),
        ],
      );
      final teamB = Team(
        id: 'B',
        characters: [
          testCharacter(id: 'b1'),
          testCharacter(id: 'b2'),
          testCharacter(id: 'b3'),
        ],
      );
      final battle = Battle(teamA: teamA, teamB: teamB);

      battle.initializePassiveCounters({
        'a1': [
          testPassiveTrigger(
            id: 'draegor',
            counterKind: PassiveCounterKind.draegor,
          ),
        ],
        'b1': [
          testPassiveTrigger(
            id: 'reckoning',
            counterKind: PassiveCounterKind.reckoning,
          ),
        ],
      });

      expect(
          battle.states['a1']!.passiveCounters
              .containsKey(PassiveCounterKind.draegor),
          isTrue);
      expect(
          battle.states['b1']!.passiveCounters
              .containsKey(PassiveCounterKind.reckoning),
          isTrue);
      expect(
          battle.states['a2']!.passiveCounters.isEmpty, isTrue,
          reason: 'a2 has no counter-bearing passive');
    });

    test('recordDamageDealt tracks active team damage for Gravehour', () {
      final teamA = Team(
        id: 'A',
        characters: [
          testCharacter(id: 'a1'),
          testCharacter(id: 'a2'),
          testCharacter(id: 'a3'),
        ],
      );
      final teamB = Team(
        id: 'B',
        characters: [
          testCharacter(id: 'b1'),
          testCharacter(id: 'b2'),
          testCharacter(id: 'b3'),
        ],
      );
      final battle = Battle(teamA: teamA, teamB: teamB);
      battle.startTurn();

      expect(battle.activeTeamDealtDamageThisTurn, isFalse);
      battle.recordDamageDealt();
      expect(battle.activeTeamDealtDamageThisTurn, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Trigger catalog: 6 new counter passives
  // -------------------------------------------------------------------------

  group('Trigger catalog counter passives', () {
    final catalog = TriggerCatalog.defaultCatalog;

    test('all 6 counter passives exist in catalog', () {
      for (final id in [
        'draegor',
        'nullhymn',
        'reckoning',
        'gravehour',
        'coldread',
        'ironvow',
      ]) {
        expect(catalog.contains(id), isTrue, reason: '$id missing');
        final trigger = catalog[id];
        expect(trigger, isA<PassiveTrigger>());
        final passive = trigger as PassiveTrigger;
        expect(passive.counterKind, isNotNull,
            reason: '$id should have counterKind');
      }
    });

    test('counter passives map to the right PassiveCounterKind', () {
      expect((catalog['draegor'] as PassiveTrigger).counterKind,
          PassiveCounterKind.draegor);
      expect((catalog['nullhymn'] as PassiveTrigger).counterKind,
          PassiveCounterKind.nullhymn);
      expect((catalog['reckoning'] as PassiveTrigger).counterKind,
          PassiveCounterKind.reckoning);
      expect((catalog['gravehour'] as PassiveTrigger).counterKind,
          PassiveCounterKind.gravehour);
      expect((catalog['coldread'] as PassiveTrigger).counterKind,
          PassiveCounterKind.coldread);
      expect((catalog['ironvow'] as PassiveTrigger).counterKind,
          PassiveCounterKind.ironvow);
    });
  });
}

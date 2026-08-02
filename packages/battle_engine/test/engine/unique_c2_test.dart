import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

TurnEngine _engine({DiceRoller? diceRoller}) => TurnEngine(
      combatEngine: CombatEngine(diceRoller: diceRoller ?? DiceRoller()),
    );

CharacterBattleState _state(
  Character c, {
  List<String> equippedTriggerIds = const [],
}) =>
    CharacterBattleState(c, equippedTriggerIds: equippedTriggerIds);

void main() {
  // -----------------------------------------------------------------------
  // Shared Agony
  // -----------------------------------------------------------------------
  group('C2: Shared Agony', () {
    test('auto-targets a melee-hit enemy and deals self + boosted damage', () {
      // FixedRandom(5): each die is nextInt(sides) + 1, so a d6 rolls
      // 5 + 1 = 6. Damage dice 2d6 = 6 + 6 = 12.
      final engine = _engine(
        diceRoller: DiceRoller(const FixedRandom(5)),
      );

      final attacker = _state(testCharacter(
        id: 'atk',
        stats: testStats(maxHealth: 100, armor: 0),
      ));
      attacker.currentHealth = 80;

      final enemy = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(maxHealth: 100, armor: 0),
      ));

      // Mark that the attacker has melee-hit this enemy before.
      attacker.meleeHitEnemyIds.add('enemy-1');

      final trigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.unique,
        uniqueBehavior: UniqueBehavior.sharedAgony,
        damage: const DiceExpression(2, 6),
        damageType: DamageType.slashing,
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [enemy],
      );

      // Self-damage: full rolled amount (12), no mitigation.
      // 80 - 12 = 68
      expect(attacker.currentHealth, 68);

      // Enemy damage: round(12 * 1.2) = 14, through damage pipeline (armor 0).
      // 100 - 14 = 86
      expect(enemy.currentHealth, 86);

      expect(result.targetResults, hasLength(1));
      expect(result.targetResults.first.targetCharacterId, 'enemy-1');
    });

    test('returns empty when no melee-hit enemies exist', () {
      final engine = _engine();
      final attacker = _state(testCharacter(id: 'atk'));
      final enemy = _state(testCharacter(id: 'enemy-1'));

      final trigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.unique,
        uniqueBehavior: UniqueBehavior.sharedAgony,
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [enemy],
      );

      expect(result.targetResults, isEmpty);
    });

    test('self-damage can kill the caster', () {
      final engine = _engine(
        diceRoller: DiceRoller(const FixedRandom(5)),
      );

      final attacker = _state(testCharacter(
        id: 'atk',
        stats: testStats(maxHealth: 100, armor: 0),
      ));
      attacker.currentHealth = 5;
      attacker.meleeHitEnemyIds.add('enemy-1');

      final enemy = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(maxHealth: 100, armor: 0),
      ));

      final trigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.unique,
        uniqueBehavior: UniqueBehavior.sharedAgony,
        damage: const DiceExpression(2, 6),
      );

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [enemy],
      );

      // 2d6 with FixedRandom(5) = 12. 5 - 12 = -7, clamped to 0.
      expect(attacker.currentHealth, 0);
      expect(attacker.isAlive, isFalse);
    });
  });

  // -----------------------------------------------------------------------
  // Grave Bargain
  // -----------------------------------------------------------------------
  group('C2: Grave Bargain', () {
    test('spends 25% HP and deals true damage to target', () {
      final engine = _engine();

      final attacker = _state(testCharacter(
        id: 'atk',
        stats: testStats(maxHealth: 100),
      ));
      attacker.currentHealth = 80;

      final enemy = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(maxHealth: 100, armor: 20),
      ));

      final trigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.unique,
        uniqueBehavior: UniqueBehavior.graveBargain,
        includeDamage: false,
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [enemy],
      );

      // HP cost: 80 * 0.25 = 20. Attacker: 80 - 20 = 60.
      expect(attacker.currentHealth, 60);
      // True damage ignores armor (20). Enemy: 100 - 20 = 80.
      expect(enemy.currentHealth, 80);

      expect(result.targetResults, hasLength(1));
      expect(result.targetResults.first.totalDamageDealt, 20);
    });

    test('caster HP floors at 1 (cannot self-kill)', () {
      final engine = _engine();

      final attacker = _state(testCharacter(
        id: 'atk',
        stats: testStats(maxHealth: 100),
      ));
      attacker.currentHealth = 2;

      final enemy = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(maxHealth: 100, armor: 0),
      ));

      final trigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.unique,
        uniqueBehavior: UniqueBehavior.graveBargain,
        includeDamage: false,
      );

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [enemy],
      );

      // HP cost: 2 * 0.25 = 0.5 rounded to 1. Attacker: max(1, 2-1) = 1.
      expect(attacker.currentHealth, 1);
      expect(attacker.isAlive, isTrue);
    });

    test('true damage bypasses damage resistance', () {
      final engine = _engine();

      final attacker = _state(testCharacter(
        id: 'atk',
        stats: testStats(maxHealth: 100),
      ));
      attacker.currentHealth = 40;

      // Enemy has slashing resistance, but true damage ignores it.
      final enemy = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(maxHealth: 100, armor: 50),
        damageResistances: {DamageType.slashing},
      ));

      final trigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.unique,
        uniqueBehavior: UniqueBehavior.graveBargain,
        includeDamage: false,
      );

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [enemy],
      );

      // HP cost: 40 * 0.25 = 10. True damage: 10 directly subtracted.
      // Neither armor (50) nor damage resistance apply.
      expect(enemy.currentHealth, 90);
    });
  });

  // -----------------------------------------------------------------------
  // Martyr's End
  // -----------------------------------------------------------------------
  group("C2: Martyr's End", () {
    test('kills the caster and deals massive damage to all enemies', () {
      final engine = _engine();

      final attacker = _state(testCharacter(
        id: 'atk',
        stats: testStats(maxHealth: 100, armor: 0),
      ));
      attacker.currentHealth = 20; // Below 25% of 100

      final enemy1 = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(maxHealth: 200, armor: 0),
      ));
      final enemy2 = _state(testCharacter(
        id: 'enemy-2',
        stats: testStats(maxHealth: 200, armor: 0),
      ));

      final trigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.unique,
        uniqueBehavior: UniqueBehavior.martyrsEnd,
        includeDamage: false,
        targetCount: 3,
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [enemy1, enemy2],
      );

      expect(attacker.currentHealth, 0);
      expect(attacker.isAlive, isFalse);

      // Default martyrsEndDamage is 80, force damage, armor 0.
      expect(enemy1.currentHealth, 120);
      expect(enemy2.currentHealth, 120);

      expect(result.targetResults, hasLength(2));
    });

    test('does nothing when caster is above HP threshold', () {
      final engine = _engine();

      final attacker = _state(testCharacter(
        id: 'atk',
        stats: testStats(maxHealth: 100),
      ));
      attacker.currentHealth = 50; // Above 25%

      final enemy = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(maxHealth: 100),
      ));

      final trigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.unique,
        uniqueBehavior: UniqueBehavior.martyrsEnd,
        includeDamage: false,
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [enemy],
      );

      expect(attacker.currentHealth, 50);
      expect(enemy.currentHealth, 100);
      expect(result.targetResults, isEmpty);
    });

    test('exactly at 25% threshold triggers the ability', () {
      final engine = _engine();

      final attacker = _state(testCharacter(
        id: 'atk',
        stats: testStats(maxHealth: 100, armor: 0),
      ));
      attacker.currentHealth = 25; // Exactly 25%

      final enemy = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(maxHealth: 200, armor: 0),
      ));

      final trigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.unique,
        uniqueBehavior: UniqueBehavior.martyrsEnd,
        includeDamage: false,
        targetCount: 3,
      );

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [enemy],
      );

      expect(attacker.currentHealth, 0);
      expect(enemy.currentHealth, 120);
    });
  });

  // -----------------------------------------------------------------------
  // Vow of the Duel
  // -----------------------------------------------------------------------
  group('C2: Vow of the Duel', () {
    test('applies status and sets duelTargetId', () {
      final engine = _engine();

      final attacker = _state(testCharacter(id: 'atk'));
      final enemy = _state(testCharacter(id: 'enemy-1'));

      final trigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.unique,
        uniqueBehavior: UniqueBehavior.vowOfTheDuel,
        includeDamage: false,
      );

      final result = engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [enemy],
      );

      expect(attacker.duelTargetId, 'enemy-1');
      expect(
        attacker.statusEffects.any((i) => i.definitionId == 'vow_of_the_duel'),
        isTrue,
      );
      expect(result.targetResults.first.statusEffectsApplied,
          contains('vow_of_the_duel'));
    });

    test('canTarget restricts to duel target for opponents', () {
      final engine = _engine();

      final attacker = _state(testCharacter(id: 'atk'));
      final duelTarget = _state(testCharacter(id: 'enemy-1'));
      final otherEnemy = _state(testCharacter(id: 'enemy-2'));
      final ally = _state(testCharacter(id: 'ally-1'));
      attacker.teammates = [ally];

      attacker.duelTargetId = 'enemy-1';

      expect(engine.canTarget(attacker, duelTarget), isTrue);
      expect(engine.canTarget(attacker, otherEnemy), isFalse);
      // Allies remain targetable.
      expect(engine.canTarget(attacker, ally), isTrue);
    });

    test('checkVowOfTheDuelExpiry stuns caster if target alive', () {
      final engine = _engine();

      final caster = _state(testCharacter(id: 'atk'));
      final enemy = _state(testCharacter(id: 'enemy-1'));
      enemy.currentHealth = 50;

      caster.duelTargetId = 'enemy-1';
      // No vow_of_the_duel status = it has expired.

      engine.checkVowOfTheDuelExpiry(caster, [enemy]);

      expect(caster.duelTargetId, isNull);
      expect(
        caster.statusEffects.any((i) => i.definitionId == 'stunned'),
        isTrue,
      );
    });

    test('checkVowOfTheDuelExpiry does not stun if target dead', () {
      final engine = _engine();

      final caster = _state(testCharacter(id: 'atk'));
      final enemy = _state(testCharacter(id: 'enemy-1'));
      enemy.currentHealth = 0;

      caster.duelTargetId = 'enemy-1';

      engine.checkVowOfTheDuelExpiry(caster, [enemy]);

      expect(caster.duelTargetId, isNull);
      expect(
        caster.statusEffects.any((i) => i.definitionId == 'stunned'),
        isFalse,
      );
    });

    test('checkVowOfTheDuelExpiry no-op if vow still active', () {
      final engine = _engine();

      final caster = _state(testCharacter(id: 'atk'));
      final enemy = _state(testCharacter(id: 'enemy-1'));

      caster.duelTargetId = 'enemy-1';
      caster.statusEffects.add(StatusEffectInstance(
        definitionId: 'vow_of_the_duel',
        remainingTurns: 2,
      ));

      engine.checkVowOfTheDuelExpiry(caster, [enemy]);

      // Still bound, not stunned.
      expect(caster.duelTargetId, 'enemy-1');
      expect(
        caster.statusEffects.any((i) => i.definitionId == 'stunned'),
        isFalse,
      );
    });
  });

  // -----------------------------------------------------------------------
  // Sunder Arms
  // -----------------------------------------------------------------------
  group('C2: Sunder Arms', () {
    test('on hit: destroys random enemy trigger and caster sacrifice', () {
      // FixedRandom(15) gives natural d20 of 16 (hit for most configs).
      final engine = _engine(
        diceRoller: DiceRoller(const FixedRandom(15)),
      );

      final attacker = _state(
        testCharacter(
          id: 'atk',
          stats: testStats(maxHealth: 100, attack: 15, armor: 0),
        ),
        equippedTriggerIds: ['t-a1', 't-a2', 't-a3'],
      );

      final enemy = _state(
        testCharacter(
          id: 'enemy-1',
          stats: testStats(maxHealth: 200, defense: 5, armor: 0),
        ),
        equippedTriggerIds: ['t-e1', 't-e2', 't-e3'],
      );

      final trigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.unique,
        uniqueBehavior: UniqueBehavior.sunderArms,
        damage: const DiceExpression(2, 6),
        damageType: DamageType.slashing,
      );

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [enemy],
        uniqueData: {'casterSacrificeTriggerId': 't-a2'},
      );

      // One enemy trigger destroyed (random pick).
      expect(enemy.destroyedTriggerIds, hasLength(1));
      // Caster's specified trigger destroyed.
      expect(attacker.destroyedTriggerIds, contains('t-a2'));
    });

    test('on miss: no trigger destruction', () {
      // FixedRandom(0) gives natural d20 of 1 (critical miss).
      final engine = _engine(
        diceRoller: DiceRoller(const FixedRandom(0)),
      );

      final attacker = _state(
        testCharacter(id: 'atk'),
        equippedTriggerIds: ['t-a1', 't-a2'],
      );
      final enemy = _state(
        testCharacter(id: 'enemy-1'),
        equippedTriggerIds: ['t-e1', 't-e2'],
      );

      final trigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.unique,
        uniqueBehavior: UniqueBehavior.sunderArms,
      );

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [enemy],
      );

      expect(enemy.destroyedTriggerIds, isEmpty);
      expect(attacker.destroyedTriggerIds, isEmpty);
    });

    test('skips already-destroyed triggers when picking', () {
      final engine = _engine(
        diceRoller: DiceRoller(const FixedRandom(15)),
      );

      final enemy = _state(
        testCharacter(
          id: 'enemy-1',
          stats: testStats(maxHealth: 200, defense: 0, armor: 0),
        ),
        equippedTriggerIds: ['t-e1', 't-e2'],
      );
      enemy.destroyedTriggerIds.add('t-e1');

      final attacker = _state(
        testCharacter(
          id: 'atk',
          stats: testStats(attack: 15, armor: 0),
        ),
        equippedTriggerIds: ['t-a1'],
      );

      final trigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.unique,
        uniqueBehavior: UniqueBehavior.sunderArms,
        damage: const DiceExpression(1, 6),
      );

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [enemy],
        uniqueData: {'casterSacrificeTriggerId': 't-a1'},
      );

      // Only t-e2 was eligible; it must be the one destroyed.
      expect(enemy.destroyedTriggerIds, containsAll(['t-e1', 't-e2']));
    });

    test('random caster sacrifice when no uniqueData provided', () {
      final engine = _engine(
        diceRoller: DiceRoller(const FixedRandom(15)),
      );

      final attacker = _state(
        testCharacter(
          id: 'atk',
          stats: testStats(attack: 15, armor: 0),
        ),
        equippedTriggerIds: ['t-a1', 't-a2'],
      );

      final enemy = _state(
        testCharacter(
          id: 'enemy-1',
          stats: testStats(maxHealth: 200, defense: 0, armor: 0),
        ),
        equippedTriggerIds: ['t-e1'],
      );

      final trigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.unique,
        uniqueBehavior: UniqueBehavior.sunderArms,
        damage: const DiceExpression(1, 6),
      );

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: trigger,
        targets: [enemy],
      );

      // No uniqueData, so caster loses a random trigger.
      expect(attacker.destroyedTriggerIds, hasLength(1));
    });
  });

  // -----------------------------------------------------------------------
  // Melee-hit tracking (standard flow feeds Shared Agony)
  // -----------------------------------------------------------------------
  group('C2: melee-hit tracking', () {
    test('standard melee hit records target in meleeHitEnemyIds', () {
      final engine = _engine(
        diceRoller: DiceRoller(const FixedRandom(15)),
      );

      final attacker = _state(testCharacter(
        id: 'atk',
        stats: testStats(attack: 15, armor: 0),
      ));
      final enemy = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(maxHealth: 100, defense: 5, armor: 0),
      ));

      final meleeTrigger = testTrigger(
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.single,
        damage: const DiceExpression(1, 6),
      );

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: meleeTrigger,
        targets: [enemy],
      );

      expect(attacker.meleeHitEnemyIds, contains('enemy-1'));
    });

    test('ranged hit does not record in meleeHitEnemyIds', () {
      final engine = _engine(
        diceRoller: DiceRoller(const FixedRandom(15)),
      );

      final attacker = _state(testCharacter(
        id: 'atk',
        stats: testStats(attack: 15),
      ));
      final enemy = _state(testCharacter(
        id: 'enemy-1',
        stats: testStats(maxHealth: 100, defense: 5, armor: 0),
      ));

      final rangedTrigger = testTrigger(
        attackType: AttackType.ranged,
        attackSubtype: AttackSubtype.single,
        rangeTag: RangeTag.ranged,
        damage: const DiceExpression(1, 6),
      );

      engine.resolveAbilityUse(
        attacker: attacker,
        trigger: rangedTrigger,
        targets: [enemy],
      );

      expect(attacker.meleeHitEnemyIds, isEmpty);
    });
  });
}

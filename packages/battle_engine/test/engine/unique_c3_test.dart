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
        attackType: AttackType.ranged,
        rangeTag: RangeTag.ranged,
        attackSubtype: AttackSubtype.unique,
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
        attackType: AttackType.ranged,
        rangeTag: RangeTag.ranged,
        attackSubtype: AttackSubtype.unique,
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
        attackType: AttackType.ranged,
        rangeTag: RangeTag.ranged,
        attackSubtype: AttackSubtype.unique,
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
        attackType: AttackType.ranged,
        rangeTag: RangeTag.ranged,
        attackSubtype: AttackSubtype.unique,
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
        attackType: AttackType.ranged,
        rangeTag: RangeTag.ranged,
        attackSubtype: AttackSubtype.unique,
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
}

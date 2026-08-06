import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Combat-v2 section 5.2: TEG Effects 1 (offense advantage), 2 (defense
/// advantage), and 5 (SSS crit widener), injected via [TurnEngine.tegProfiles]
/// and applied on the attack roll.
void main() {
  TurnEngine engineWith(Map<String, TegRollProfile> profiles, {int fixed = 10}) {
    final e =
        TurnEngine(combatEngine: CombatEngine(diceRoller: DiceRoller(FixedRandom(fixed))));
    e.tegProfiles = profiles;
    return e;
  }

  CharacterBattleState attacker() =>
      CharacterBattleState(testCharacter(id: 'atk', stats: testStats(attack: 5, criticalChance: 0)))
        ..teammates = [];
  CharacterBattleState defender() => CharacterBattleState(
      testCharacter(id: 'def', stats: testStats(maxHealth: 200, defense: 0, criticalChance: 0)))
    ..teammates = [];

  final flat5 = testTrigger(damage: const DiceExpression(0, 1, flatBonus: 5));

  AbilityUseResult attack(TurnEngine e, CharacterBattleState atk, CharacterBattleState def) =>
      e.resolveAbilityUse(attacker: atk, trigger: flat5, targets: [def]);

  group('TEG Effect 1 (offense advantage)', () {
    test('a full-chance offense profile rolls the attacker with advantage', () {
      final atk = attacker();
      final e = engineWith({'atk': const TegRollProfile(offenseAdvantagePercent: 100)});
      final r = attack(e, atk, defender());
      expect(r.targetResults.single.attackRolls.single.attackerRoll.mode,
          RollMode.advantage);
    });

    test('no injected profile leaves the attack a normal roll', () {
      final e = engineWith({});
      final r = attack(e, attacker(), defender());
      expect(r.targetResults.single.attackRolls.single.attackerRoll.mode,
          RollMode.normal);
    });
  });

  group('TEG Effect 2 (defense advantage)', () {
    test('a full-chance defense profile rolls the defender with advantage', () {
      final e = engineWith({'def': const TegRollProfile(defenseAdvantagePercent: 100)});
      final r = attack(e, attacker(), defender());
      expect(r.targetResults.single.attackRolls.single.defenderRoll.mode,
          RollMode.advantage);
    });

    test("the defender's advantage does not bleed onto the attacker", () {
      final e = engineWith({'def': const TegRollProfile(defenseAdvantagePercent: 100)});
      final r = attack(e, attacker(), defender());
      expect(r.targetResults.single.attackRolls.single.attackerRoll.mode,
          RollMode.normal);
    });
  });

  group('TEG Effect 5 (SSS crit widener)', () {
    test('a natural 18 crits when the crit threshold is widened to 18', () {
      // FixedRandom(17) -> a d20 kept die of 18.
      final e = engineWith({'atk': const TegRollProfile(maxCritThreshold: 18)}, fixed: 17);
      final r = attack(e, attacker(), defender());
      expect(r.targetResults.single.attackRolls.single.isCriticalHit, isTrue);
    });

    test('a natural 18 does not crit at the normal threshold', () {
      final e = engineWith({}, fixed: 17);
      final r = attack(e, attacker(), defender());
      expect(r.targetResults.single.attackRolls.single.isCriticalHit, isFalse);
    });
  });
}

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

  group('TEG Effect 4 (combo advantage over the live ledger)', () {
    // Two same-team attackers (matching team key) and a shared enemy.
    ({
      CharacterBattleState a1,
      CharacterBattleState a2,
      CharacterBattleState enemy
    }) squad() {
      final a1 = CharacterBattleState(
          testCharacter(id: 'a1', stats: testStats(attack: 20, criticalChance: 0)));
      final a2 = CharacterBattleState(
          testCharacter(id: 'a2', stats: testStats(attack: 20, criticalChance: 0)));
      a1.teammates = [a2];
      a2.teammates = [a1];
      final enemy = CharacterBattleState(testCharacter(
          id: 'e',
          stats: testStats(
              maxHealth: 500, defense: 0, armor: 0, criticalChance: 0)))
        ..teammates = [];
      return (a1: a1, a2: a2, enemy: enemy);
    }

    final hit = testTrigger(damage: const DiceExpression(1, 4, flatBonus: 3));

    test('a recognized focus-fire combo grants the follow-up advantage', () {
      final s = squad();
      final e = engineWith({}, fixed: 5)
        ..comboRecognizer = ComboCatalog.defaultRecognizer;
      // First attacker strikes the enemy: records the focus-fire setup.
      e.resolveAbilityUse(attacker: s.a1, trigger: hit, targets: [s.enemy]);
      // Second attacker follows up on the same enemy: focus_fire recognized,
      // strength-1 advantage chance (7%) succeeds at rollPercent 6.
      final r = e.resolveAbilityUse(attacker: s.a2, trigger: hit, targets: [s.enemy]);
      expect(r.targetResults.single.attackRolls.single.attackerRoll.mode,
          RollMode.advantage);
    });

    test('no recognizer injected means no combo advantage', () {
      final s = squad();
      final e = engineWith({}, fixed: 5); // comboRecognizer stays null
      e.resolveAbilityUse(attacker: s.a1, trigger: hit, targets: [s.enemy]);
      final r = e.resolveAbilityUse(attacker: s.a2, trigger: hit, targets: [s.enemy]);
      expect(r.targetResults.single.attackRolls.single.attackerRoll.mode,
          RollMode.normal);
    });

    group('TEG Effect 3 (setup->payoff Trion refund)', () {
      final payoff = testTrigger(
          id: 'strike', trionCost: 10, damage: const DiceExpression(1, 4, flatBonus: 3));

      test('refunds the team percent when an ally set the target up', () {
        final s = squad();
        final e = engineWith({'a2': const TegRollProfile(trionRefundPercent: 20)},
            fixed: 5)
          ..comboRecognizer = ComboCatalog.defaultRecognizer;
        // Ally applied a control status (stunned) to the enemy this turn.
        e.comboLedger.record(
          actorId: 'a1',
          teamId: 'a1|a2',
          trigger: testTrigger(id: 'stunner'),
          targetIds: ['e'],
          statusesApplied: ['stunned'],
          dealtDamage: false,
        );
        final r = e.resolveAbilityUse(attacker: s.a2, trigger: payoff, targets: [s.enemy]);
        expect(r.trionRefund, 2); // round(10 * 20%)
      });

      test('no refund for focus fire alone (not a setup->payoff)', () {
        final s = squad();
        final e = engineWith({'a2': const TegRollProfile(trionRefundPercent: 20)},
            fixed: 5)
          ..comboRecognizer = ComboCatalog.defaultRecognizer;
        // Prior ally action merely struck the enemy (no ally-applied status).
        e.comboLedger.record(
          actorId: 'a1',
          teamId: 'a1|a2',
          trigger: testTrigger(id: 'hit'),
          targetIds: ['e'],
          statusesApplied: const [],
          dealtDamage: true,
        );
        final r = e.resolveAbilityUse(attacker: s.a2, trigger: payoff, targets: [s.enemy]);
        expect(r.trionRefund, 0);
      });

      test('no refund at a 0% refund tier even with a real setup', () {
        final s = squad();
        final e = engineWith({}, fixed: 5) // no profile -> 0% refund
          ..comboRecognizer = ComboCatalog.defaultRecognizer;
        e.comboLedger.record(
          actorId: 'a1',
          teamId: 'a1|a2',
          trigger: testTrigger(id: 'stunner'),
          targetIds: ['e'],
          statusesApplied: ['stunned'],
          dealtDamage: false,
        );
        final r = e.resolveAbilityUse(attacker: s.a2, trigger: payoff, targets: [s.enemy]);
        expect(r.trionRefund, 0);
      });
    });
  });
}

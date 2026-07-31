import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Combat v2 Phase B1: the reactive-stack resolution seam. Mirror Ward is the
/// first counter through it - a non-AoE hit against a warded holder reflects
/// back onto its attacker at full effect and consumes the ward; an AoE
/// bypasses it. FixedRandom(19) forces natural 20s so every hit lands and the
/// reflection is deterministic.
void main() {
  TurnEngine engine() => TurnEngine(
        combatEngine: CombatEngine(diceRoller: DiceRoller(const FixedRandom(19))),
      );

  CharacterBattleState attacker() => CharacterBattleState(testCharacter(
        id: 'attacker',
        stats: testStats(attack: 1000, defense: 0, armor: 0, maxHealth: 100),
      ));

  CharacterBattleState wardedDefender() {
    final defender = CharacterBattleState(testCharacter(
      id: 'defender',
      stats: testStats(defense: 0, armor: 0, maxHealth: 100),
    ));
    defender.reactiveEffects.add(
      ReactiveEffect(
        kind: ReactiveKind.reflectNonAoe,
        sourceCharacterId: 'defender',
      ),
    );
    return defender;
  }

  final damage = const DiceExpression(0, 1, flatBonus: 10);

  test('Mirror Ward reflects a non-AoE hit back onto the attacker', () {
    final a = attacker();
    final d = wardedDefender();
    final result = engine().resolveAbilityUse(
      attacker: a,
      trigger: testTrigger(damage: damage), // single-target opponent melee
      targets: [d],
    );

    expect(d.currentHealth, 100, reason: 'the warded holder takes nothing');
    expect(a.currentHealth, lessThan(100), reason: 'the attacker eats it');
    expect(d.reactiveEffects, isEmpty, reason: 'the ward is consumed');
    expect(
      result.targetResults.single.targetCharacterId,
      'attacker',
      reason: 'the hit resolves against the reflected-onto attacker',
    );
  });

  test('an AoE hit bypasses Mirror Ward and leaves it armed', () {
    final a = attacker();
    final d = wardedDefender();
    engine().resolveAbilityUse(
      attacker: a,
      trigger: testTrigger(
        attackSubtype: AttackSubtype.aoe,
        targetCount: 3,
        damage: damage,
      ),
      targets: [d],
    );

    expect(d.currentHealth, lessThan(100), reason: 'AoE lands on the holder');
    expect(a.currentHealth, 100, reason: 'nothing reflects');
    expect(d.reactiveEffects, hasLength(1), reason: 'the ward stays armed');
  });

  test('the ward reflects only once; the next hit lands normally', () {
    final a = attacker();
    final d = wardedDefender();
    final e = engine();

    // First hit: reflected onto the attacker, ward consumed.
    e.resolveAbilityUse(
      attacker: a,
      trigger: testTrigger(damage: damage),
      targets: [d],
    );
    expect(d.reactiveEffects, isEmpty);
    final attackerHealthAfterReflect = a.currentHealth;

    // Second hit: no ward left, so it lands on the defender and the attacker
    // takes no further damage.
    e.resolveAbilityUse(
      attacker: a,
      trigger: testTrigger(damage: damage),
      targets: [d],
    );
    expect(d.currentHealth, lessThan(100));
    expect(a.currentHealth, attackerHealthAfterReflect);
  });
}

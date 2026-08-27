import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// A playtest read the battle log and found "Rurik Voss (1 hit) [Guarded,
/// Braced] -> HP 100" after a squad buff, and asked for buffs on yourself or
/// an ally to auto-apply rather than roll a die.
///
/// They were already auto-applying, in the sense that the answer was fixed:
/// the roll was made against the recipient's own Defense and then overridden
/// to a hit. Fixing the answer left everything the pipeline does on the way
/// to it still done, which is the bigger half of this. Casting a buff burned
/// the recipient's once-per-battle Decoy charge, spent the caster's First
/// Blood on a full-health teammate, and consumed a Reckoning that should have
/// wrecked their next real attack.
///
/// A friendly ability does not enter the attack pipeline at all now. It rolls
/// nothing, so there is no hit to count and nothing for the log to show.
class CountingRandom implements Random {
  final Random _inner;
  int rolls = 0;
  CountingRandom(this._inner);

  @override
  int nextInt(int max) {
    rolls++;
    return _inner.nextInt(max);
  }

  @override
  double nextDouble() {
    rolls++;
    return _inner.nextDouble();
  }

  @override
  bool nextBool() {
    rolls++;
    return _inner.nextBool();
  }
}

void main() {
  const guarded = StatusEffectApplication('guarded');

  ({
    TurnEngine engine,
    CharacterBattleState caster,
    CharacterBattleState ally,
    CountingRandom dice,
  }) setUpPair({SideEffect? casterSideEffect, SideEffect? allySideEffect}) {
    final dice = CountingRandom(Random(7));
    final engine = TurnEngine(
      combatEngine: CombatEngine(diceRoller: DiceRoller(dice)),
      statusEffectEngine: StatusEffectEngine(diceRoller: DiceRoller(dice)),
    );
    final caster = CharacterBattleState(
      testCharacter(id: 'caster', sideEffect: casterSideEffect),
    );
    final ally = CharacterBattleState(
      testCharacter(id: 'ally', sideEffect: allySideEffect),
    );
    caster.teammates.add(ally);
    ally.teammates.add(caster);
    return (engine: engine, caster: caster, ally: ally, dice: dice);
  }

  ActiveTrigger buff({
    TargetAffiliation affiliation = TargetAffiliation.ally,
    RangeTag range = RangeTag.close,
  }) =>
      testTrigger(
        id: 'test_buff',
        rangeTag: range,
        includeDamage: false,
        targetAffiliation: affiliation,
        inflictedStatusEffects: const [guarded],
      );

  group('a buff on your own side is not an attack', () {
    test('it reports no attack roll, so the log counts no hits', () {
      final s = setUpPair();
      final result = s.engine.resolveAbilityUse(
        attacker: s.caster,
        trigger: buff(),
        targets: [s.ally],
      );

      final target = result.targetResults.single;
      expect(target.attackRolls, isEmpty,
          reason: '"(1 hit)" on a squad buff is what this replaced');
      expect(target.statusEffectsApplied, ['guarded']);
      expect(s.ally.statusEffects.single.definitionId, 'guarded');
    });

    test('it rolls no dice at all', () {
      final s = setUpPair();
      final before = s.dice.rolls;
      s.engine.resolveAbilityUse(
        attacker: s.caster,
        trigger: buff(),
        targets: [s.ally],
      );
      expect(s.dice.rolls, before,
          reason: 'a roll that cannot fail and cannot be read is not a roll');
    });

    test('a self-cast is the same', () {
      final s = setUpPair();
      final result = s.engine.resolveAbilityUse(
        attacker: s.caster,
        trigger: buff(affiliation: TargetAffiliation.self),
        targets: [s.caster],
      );
      expect(result.targetResults.single.attackRolls, isEmpty);
      expect(s.caster.statusEffects.single.definitionId, 'guarded');
    });

    test('an attack still rolls, and still reports what it rolled', () {
      final s = setUpPair();
      final before = s.dice.rolls;
      final result = s.engine.resolveAbilityUse(
        attacker: s.caster,
        trigger: testTrigger(id: 'test_attack'),
        targets: [s.ally],
      );

      expect(result.targetResults.single.attackRolls, hasLength(1));
      expect(s.dice.rolls, greaterThan(before));
    });
  });

  group('a buff spends nothing the pipeline used to spend', () {
    test("it does not burn the recipient's once-per-battle dodge", () {
      final s = setUpPair(
        allySideEffect: const SideEffect(
          id: 'decoy',
          name: 'Decoy',
          description: 'Once per battle, an incoming attack misses.',
          dodgeChanceOncePerBattle: 1.0,
        ),
      );

      s.engine.resolveAbilityUse(
        attacker: s.caster,
        trigger: buff(),
        targets: [s.ally],
      );

      expect(s.ally.sideEffectChargeUsed, isFalse,
          reason: 'a teammate does not dodge their own squad buff');
      expect(s.ally.statusEffects, hasLength(1),
          reason: 'and the dodge cannot make the buff fizzle either');
    });

    test("it does not spend the caster's first-attack crit bonus", () {
      final s = setUpPair(
        casterSideEffect: const SideEffect(
          id: 'first_blood',
          name: 'First Blood',
          description: 'Bonus crit on the first attack of the battle.',
          firstAttackCritBonusVsFullHealthTarget: 50,
        ),
      );

      s.engine.resolveAbilityUse(
        attacker: s.caster,
        trigger: buff(),
        targets: [s.ally],
      );

      expect(s.caster.sideEffectChargeUsed, isFalse,
          reason: 'buffing a full-health ally is not a first attack');
    });

    test('it does not consume a forced critical miss meant for a real attack',
        () {
      // Reckoning: the caster's next attack roll is a critical miss. A buff
      // used to eat it and then override itself back to a hit, which spent
      // the debuff for nothing.
      final catalog = StatusEffectCatalog.defaultCatalog;
      final forcing = catalog.all
          .where((d) => d.forcesNextAttackCriticalMiss)
          .toList();
      expect(forcing, isNotEmpty, reason: 'the fixture needs one to exist');

      final s = setUpPair();
      s.engine.statusEffectEngine.apply(s.caster, forcing.first.id);
      expect(s.caster.statusEffects, hasLength(1));

      s.engine.resolveAbilityUse(
        attacker: s.caster,
        trigger: buff(affiliation: TargetAffiliation.self),
        targets: [s.caster],
      );

      expect(
        s.caster.statusEffects.any((i) => i.definitionId == forcing.first.id),
        isTrue,
        reason: 'it is still waiting for the next real attack',
      );
    });
  });
}

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Sealed shuts off one whole ability type, and Origin Lockout one whole
/// origin. Both name their victim when they land.
///
/// Two things are pinned here. Sealed used to zero Trion Affinity and FAT
/// Chance, an effect that had nothing to do with its name or with what the
/// design document said it did. And Origin Lockout, though a Black Trigger
/// applies it, never wrote `lockedOrigin` anywhere outside a test, so the
/// engine compared its lock against null and the status blocked nothing at
/// all. Every sibling lock (Prone's random ability, Forced Choice's single
/// allowed ability, Karmic Bind's fraction) seeds its own data; this one was
/// simply missed.
void main() {
  // AbilityType.values is [melee, ranged, psychic] and OriginTag.values is
  // [physical, energy, afflict, mental], so a die stuck on 0 always picks
  // the first of each.
  StatusEffectEngine engineWithFixedPick() =>
      StatusEffectEngine(diceRoller: DiceRoller(const FixedRandom(0)));

  CharacterBattleState freshTarget() =>
      CharacterBattleState(testCharacter());

  StatusEffectInstance instanceOf(CharacterBattleState s, String id) =>
      s.statusEffects.firstWhere((i) => i.definitionId == id);

  group('Sealed seals one ability type', () {
    test('names the ability type it seals when it lands', () {
      final target = freshTarget();
      engineWithFixedPick().apply(target, 'sealed');

      expect(instanceOf(target, 'sealed').data['lockedAbilityType'],
          AbilityType.melee.name);
    });

    test('blocks that ability type and leaves the others alone', () {
      final target = freshTarget();
      final statuses = engineWithFixedPick();
      statuses.apply(target, 'sealed');
      final engine = TurnEngine(statusEffectEngine: statuses);

      expect(
        engine.canUseAbility(
            target, testTrigger(id: 'a', abilityType: AbilityType.melee)),
        isFalse,
        reason: 'the sealed type is melee',
      );
      expect(
        engine.canUseAbility(
            target, testTrigger(id: 'b', abilityType: AbilityType.ranged)),
        isTrue,
      );
      expect(
        engine.canUseAbility(
            target, testTrigger(id: 'c', abilityType: AbilityType.psychic)),
        isTrue,
      );
    });

    test('no longer zeroes Trion Affinity or FAT Chance', () {
      final target = freshTarget();
      engineWithFixedPick().apply(target, 'sealed');
      final stats = target.effectiveStats();

      expect(stats.trionAffinity, greaterThan(0));
      expect(stats.fatChance, greaterThan(0));
    });
  });

  group('Origin Lockout locks one origin', () {
    test('names the origin it locks when it lands, which it never used to',
        () {
      final target = freshTarget();
      engineWithFixedPick().apply(target, 'origin_lockout');

      expect(instanceOf(target, 'origin_lockout').data['lockedOrigin'],
          OriginTag.physical.name);
    });

    test('blocks that origin and leaves the others alone', () {
      final target = freshTarget();
      final statuses = engineWithFixedPick();
      statuses.apply(target, 'origin_lockout');
      final engine = TurnEngine(statusEffectEngine: statuses);

      expect(
        engine.canUseAbility(
            target, testTrigger(id: 'a', originTag: OriginTag.physical)),
        isFalse,
      );
      expect(
        engine.canUseAbility(
            target, testTrigger(id: 'b', originTag: OriginTag.energy)),
        isTrue,
      );
    });
  });

  test('a caller that names the lock itself still wins', () {
    final target = freshTarget();
    engineWithFixedPick().apply(
      target,
      'origin_lockout',
      instanceData: {'lockedOrigin': OriginTag.mental.name},
    );

    expect(instanceOf(target, 'origin_lockout').data['lockedOrigin'],
        OriginTag.mental.name);
  });
}

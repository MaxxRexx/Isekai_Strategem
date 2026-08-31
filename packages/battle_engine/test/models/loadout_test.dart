import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group('Loadout.validateFor', () {
    ActiveTrigger active(String id, {int equipCost = 10}) => testTrigger(
          id: id,
          equipCost: equipCost,
          abilityType: AbilityType.melee,
          abilitySubtype: AbilitySubtype.single,
        );

    PassiveTrigger passive(String id, {int equipCost = 5}) =>
        testPassiveTrigger(id: id, equipCost: equipCost);

    test(
        'valid with Trion Capacity headroom, within the equip cap, and '
        'exactly 4 active abilities', () {
      final character = testCharacter(stats: testStats(trionCapacity: 100));
      final loadout = Loadout(
        characterId: character.id,
        triggers: [
          active('a1'),
          active('a2'),
          active('a3'),
          active('a4'),
          passive('p1'),
        ],
      );

      final result = loadout.validateFor(character);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('invalid when total equip cost exceeds Trion Capacity', () {
      final character = testCharacter(stats: testStats(trionCapacity: 15));
      final loadout = Loadout(
        characterId: character.id,
        triggers: [
          active('a1', equipCost: 10),
          active('a2', equipCost: 10),
          active('a3'),
          active('a4'),
        ],
      );

      final result = loadout.validateFor(character);
      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('Trion Capacity')));
    });

    test('invalid when total equipped items exceeds the 8-item cap', () {
      final character = testCharacter(stats: testStats(trionCapacity: 1000));
      final loadout = Loadout(
        characterId: character.id,
        triggers: [
          active('a1'),
          active('a2'),
          active('a3'),
          active('a4'),
          passive('p1'),
          passive('p2'),
          passive('p3'),
          passive('p4'),
          passive('p5'),
        ],
      );

      final result = loadout.validateFor(character);
      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('exceeds the max of 8')));
    });

    test(
        'invalid when fewer than the required 4 active abilities are '
        'equipped', () {
      final character = testCharacter(stats: testStats(trionCapacity: 1000));
      final loadout = Loadout(
        characterId: character.id,
        triggers: [active('a1'), active('a2'), passive('p1')],
      );

      final result = loadout.validateFor(character);
      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('must equal exactly 4')));
    });

    test(
        'invalid when more than the required 4 active abilities are '
        'equipped', () {
      final character = testCharacter(stats: testStats(trionCapacity: 1000));
      final loadout = Loadout(
        characterId: character.id,
        triggers: [
          active('a1'),
          active('a2'),
          active('a3'),
          active('a4'),
          active('a5'),
        ],
      );

      final result = loadout.validateFor(character);
      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('must equal exactly 4')));
    });

    test(
        'a Black Trigger counts as one equipped item and contributes its '
        'own active abilities toward the requirement', () {
      final character = testCharacter(stats: testStats(trionCapacity: 1000));
      final blackTrigger = BlackTrigger(
        id: 'bt-1',
        name: 'Test Black Trigger',
        type: BlackTriggerType.attack,
        equipCost: 20,
        activeAbilities: [active('bt-active-1'), active('bt-active-2')],
      );
      final loadout = Loadout(
        characterId: character.id,
        triggers: [active('a1'), active('a2')],
        blackTrigger: blackTrigger,
      );

      expect(loadout.totalEquippedCount, 3);
      expect(loadout.totalActiveAbilityCount, 4);

      final result = loadout.validateFor(character);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('reports every violated rule independently', () {
      final character = testCharacter(stats: testStats(trionCapacity: 1));
      final loadout = Loadout(
        characterId: character.id,
        triggers: [active('a1', equipCost: 50)],
      );

      final result = loadout.validateFor(character);
      expect(result.isValid, isFalse);
      expect(result.errors, hasLength(2));
    });
  });

  group('Trigger ability type/subtype validity', () {
    test('rejects an invalid subtype for a given ability type', () {
      expect(
        () => testTrigger(
            abilityType: AbilityType.melee, abilitySubtype: AbilitySubtype.burst),
        throwsA(isA<AssertionError>()),
      );
    });

    test('allows every documented combination', () {
      expect(
          () => testTrigger(
              abilityType: AbilityType.melee,
              abilitySubtype: AbilitySubtype.single),
          returnsNormally);
      expect(
          () => testTrigger(
              abilityType: AbilityType.melee, abilitySubtype: AbilitySubtype.aoe),
          returnsNormally);
      expect(
          () => testTrigger(
              abilityType: AbilityType.ranged,
              abilitySubtype: AbilitySubtype.single),
          returnsNormally);
      expect(
          () => testTrigger(
              abilityType: AbilityType.ranged,
              abilitySubtype: AbilitySubtype.burst),
          returnsNormally);
      expect(
          () => testTrigger(
              abilityType: AbilityType.ranged, abilitySubtype: AbilitySubtype.aoe),
          returnsNormally);
      expect(
          () => testTrigger(
              abilityType: AbilityType.psychic,
              abilitySubtype: AbilitySubtype.unique),
          returnsNormally);
      expect(
          () => testTrigger(
              abilityType: AbilityType.psychic,
              abilitySubtype: AbilitySubtype.single),
          returnsNormally);
      expect(
          () => testTrigger(
              abilityType: AbilityType.psychic, abilitySubtype: AbilitySubtype.aoe),
          returnsNormally);
    });
  });
}

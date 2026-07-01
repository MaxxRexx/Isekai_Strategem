import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group('Loadout.validateFor', () {
    test('valid when within both Trion Capacity and slot capacity', () {
      final character =
          testCharacter(stats: testStats(trionCapacity: 30, slotCapacity: 3));
      final loadout = Loadout(
        characterId: character.id,
        triggers: [
          testTrigger(id: 'a', equipCost: 10, slotCost: 1),
          testTrigger(id: 'b', equipCost: 10, slotCost: 1),
        ],
      );

      final result = loadout.validateFor(character);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('invalid when total equip cost exceeds Trion Capacity', () {
      final character =
          testCharacter(stats: testStats(trionCapacity: 15, slotCapacity: 10));
      final loadout = Loadout(
        characterId: character.id,
        triggers: [
          testTrigger(id: 'a', equipCost: 10, slotCost: 1),
          testTrigger(id: 'b', equipCost: 10, slotCost: 1),
        ],
      );

      final result = loadout.validateFor(character);
      expect(result.isValid, isFalse);
      expect(result.errors, hasLength(1));
    });

    test('invalid when total slot cost exceeds slot capacity', () {
      final character =
          testCharacter(stats: testStats(trionCapacity: 100, slotCapacity: 2));
      final loadout = Loadout(
        characterId: character.id,
        triggers: [
          testTrigger(id: 'a', equipCost: 1, slotCost: 2),
          testTrigger(id: 'b', equipCost: 1, slotCost: 2),
        ],
      );

      final result = loadout.validateFor(character);
      expect(result.isValid, isFalse);
      expect(result.errors, hasLength(1));
    });

    test('reports both errors independently when both budgets are exceeded',
        () {
      final character =
          testCharacter(stats: testStats(trionCapacity: 1, slotCapacity: 1));
      final loadout = Loadout(
        characterId: character.id,
        triggers: [testTrigger(id: 'a', equipCost: 50, slotCost: 5)],
      );

      final result = loadout.validateFor(character);
      expect(result.isValid, isFalse);
      expect(result.errors, hasLength(2));
    });
  });

  group('Trigger attack type/subtype validity', () {
    test('rejects an invalid subtype for a given attack type', () {
      expect(
        () => testTrigger(
            attackType: AttackType.melee, attackSubtype: AttackSubtype.burst),
        throwsA(isA<AssertionError>()),
      );
    });

    test('allows every documented combination', () {
      expect(
          () => testTrigger(
              attackType: AttackType.melee,
              attackSubtype: AttackSubtype.single),
          returnsNormally);
      expect(
          () => testTrigger(
              attackType: AttackType.melee, attackSubtype: AttackSubtype.aoe),
          returnsNormally);
      expect(
          () => testTrigger(
              attackType: AttackType.ranged,
              attackSubtype: AttackSubtype.single),
          returnsNormally);
      expect(
          () => testTrigger(
              attackType: AttackType.ranged,
              attackSubtype: AttackSubtype.burst),
          returnsNormally);
      expect(
          () => testTrigger(
              attackType: AttackType.ranged, attackSubtype: AttackSubtype.aoe),
          returnsNormally);
      expect(
          () => testTrigger(
              attackType: AttackType.psychic,
              attackSubtype: AttackSubtype.unique),
          returnsNormally);
      expect(
          () => testTrigger(
              attackType: AttackType.psychic,
              attackSubtype: AttackSubtype.single),
          returnsNormally);
      expect(
          () => testTrigger(
              attackType: AttackType.psychic, attackSubtype: AttackSubtype.aoe),
          returnsNormally);
    });
  });
}

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

void main() {
  group('CharacterRoster.defaultRoster', () {
    final roster = CharacterRoster.defaultRoster;

    test('has exactly 20 characters', () {
      expect(roster.all, hasLength(20));
    });

    test('has exactly 5 characters per Character Type', () {
      for (final type in CharacterType.values) {
        expect(roster.ofType(type), hasLength(5), reason: '$type');
      }
    });

    test('every character has a unique id', () {
      final ids = roster.all.map((c) => c.id);
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('every character has a perk', () {
      for (final c in roster.all) {
        expect(c.perk, isNotNull, reason: c.id);
      }
    });

    test(
        'a valid Loadout can legally use any Trigger regardless of the '
        "character's own Character Type", () {
      final attackChar = roster['kaito_reyes']; // CharacterType.attack
      final supportTrigger =
          TriggerCatalog.defaultCatalog['mending_light'] as ActiveTrigger;
      final loadout = Loadout(
        characterId: attackChar.id,
        triggers: [
          supportTrigger,
          TriggerCatalog.defaultCatalog['fortify'] as ActiveTrigger,
          TriggerCatalog.defaultCatalog['war_chant'] as ActiveTrigger,
          TriggerCatalog.defaultCatalog['adrenal_rush'] as ActiveTrigger,
        ],
      );
      final result = loadout.validateFor(attackChar);
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
    });
  });

  group('TriggerCatalog.defaultCatalog', () {
    final catalog = TriggerCatalog.defaultCatalog;

    test('has exactly 40 Triggers', () {
      expect(catalog.all, hasLength(40));
    });

    test('has 34 active and 6 passive Triggers', () {
      expect(catalog.activeTriggers, hasLength(34));
      expect(catalog.passiveTriggers, hasLength(6));
    });

    test('every Trigger has a unique id', () {
      final ids = catalog.all.map((t) => t.id);
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('every active Trigger has a valid attack type/subtype combination',
        () {
      for (final t in catalog.activeTriggers) {
        expect(t.attackType.validSubtypes.contains(t.attackSubtype), isTrue,
            reason: '${t.id}: ${t.attackType}/${t.attackSubtype}');
      }
    });
  });

  group('BlackTriggerCatalog.defaultCatalog', () {
    final catalog = BlackTriggerCatalog.defaultCatalog;

    test('has exactly 10 Black Triggers', () {
      expect(catalog.all, hasLength(10));
    });

    test('spans every Black Trigger Type', () {
      for (final type in BlackTriggerType.values) {
        expect(catalog.all.where((bt) => bt.type == type), isNotEmpty,
            reason: '$type');
      }
    });

    test('every Black Trigger has a unique id', () {
      final ids = catalog.all.map((bt) => bt.id);
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('every Black Trigger has abilities xor a World ability', () {
      for (final bt in catalog.all) {
        final hasAbilities =
            bt.activeAbilities.isNotEmpty || bt.passiveAbilities.isNotEmpty;
        expect(hasAbilities != (bt.worldAbility != null), isTrue,
            reason: bt.id);
      }
    });
  });
}

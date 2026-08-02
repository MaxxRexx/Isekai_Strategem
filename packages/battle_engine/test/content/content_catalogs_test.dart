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

    test('has exactly 70 Triggers', () {
      expect(catalog.all, hasLength(70));
    });

    test('has 58 active and 12 passive Triggers', () {
      expect(catalog.activeTriggers, hasLength(58));
      expect(catalog.passiveTriggers, hasLength(12));
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

    test('includes an equippable Trigger for all 17 unique behaviors', () {
      final byBehavior = {
        for (final t in catalog.activeTriggers)
          if (t.uniqueBehavior != null) t.uniqueBehavior!: t,
      };
      // Every UniqueBehavior has exactly one wired Trigger.
      expect(byBehavior.keys.toSet(), UniqueBehavior.values.toSet());
      expect(byBehavior, hasLength(UniqueBehavior.values.length));
    });

    test('every unique-behavior Trigger uses the unique subtype and a valid '
        'attack type', () {
      const meleeBehaviors = {
        UniqueBehavior.sharedAgony,
        UniqueBehavior.graveBargain,
        UniqueBehavior.martyrsEnd,
        UniqueBehavior.vowOfTheDuel,
        UniqueBehavior.sunderArms,
      };
      const rangedBehaviors = {
        UniqueBehavior.curvingShot,
        UniqueBehavior.calledShot,
      };
      for (final t in catalog.activeTriggers) {
        final behavior = t.uniqueBehavior;
        if (behavior == null) continue;
        expect(t.attackSubtype, AttackSubtype.unique, reason: t.id);
        final expectedType = meleeBehaviors.contains(behavior)
            ? AttackType.melee
            : rangedBehaviors.contains(behavior)
                ? AttackType.ranged
                : AttackType.psychic;
        expect(t.attackType, expectedType, reason: t.id);
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

    test('every Black Trigger has abilities or a World ability', () {
      for (final bt in catalog.all) {
        final hasAbilities =
            bt.activeAbilities.isNotEmpty || bt.passiveAbilities.isNotEmpty;
        expect(hasAbilities || bt.worldAbility != null, isTrue,
            reason: bt.id);
      }
    });
  });
}

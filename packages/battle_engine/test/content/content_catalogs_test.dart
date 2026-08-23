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
          TriggerCatalog.defaultCatalog['guardians_aegis'] as ActiveTrigger;
      final loadout = Loadout(
        characterId: attackChar.id,
        triggers: [
          supportTrigger,
          TriggerCatalog.defaultCatalog['cleansing_ward'] as ActiveTrigger,
          TriggerCatalog.defaultCatalog['war_chant'] as ActiveTrigger,
          TriggerCatalog.defaultCatalog['twin_fang_strike'] as ActiveTrigger,
        ],
      );
      final result = loadout.validateFor(attackChar);
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
    });
  });

  group('TriggerCatalog.defaultCatalog', () {
    final catalog = TriggerCatalog.defaultCatalog;

    /// The 60 combat Triggers, which are what the even splits below describe.
    ///
    /// Refuse to Bail (item #2) is the 61st active Trigger and is excluded on
    /// purpose. It is self-targeted and deals nothing, so `canReach`
    /// short-circuits before its band is ever consulted and its attack type
    /// never rolls against anything: giving it either would tilt a grid that
    /// is a statement about the attacking catalog. Counted here, it would make
    /// psychic 21 and Close Range 21 while changing nothing anyone can play
    /// against.
    final combatTriggers = catalog.activeTriggers
        .where((t) => t.id != 'refuse_to_bail')
        .toList();

    test('has exactly 73 Triggers', () {
      expect(catalog.all, hasLength(73));
    });

    test('has 61 active and 12 passive Triggers', () {
      expect(catalog.activeTriggers, hasLength(61));
      expect(combatTriggers, hasLength(60));
      expect(catalog.passiveTriggers, hasLength(12));
    });

    test('active Triggers are balanced to exactly 20 / 20 / 20 by attack type '
        'with the target subtype distribution', () {
      int count(AttackType type, AttackSubtype subtype) => combatTriggers
          .where((t) => t.attackType == type && t.attackSubtype == subtype)
          .length;

      // Melee: 10 single, 5 aoe, 0 burst, 5 unique.
      expect(count(AttackType.melee, AttackSubtype.single), 10);
      expect(count(AttackType.melee, AttackSubtype.aoe), 5);
      expect(count(AttackType.melee, AttackSubtype.burst), 0);
      expect(count(AttackType.melee, AttackSubtype.unique), 5);

      // Ranged: 5 single, 5 aoe, 8 burst, 2 unique.
      expect(count(AttackType.ranged, AttackSubtype.single), 5);
      expect(count(AttackType.ranged, AttackSubtype.aoe), 5);
      expect(count(AttackType.ranged, AttackSubtype.burst), 8);
      expect(count(AttackType.ranged, AttackSubtype.unique), 2);

      // Psychic: 5 single, 5 aoe, 0 burst, 10 unique.
      expect(count(AttackType.psychic, AttackSubtype.single), 5);
      expect(count(AttackType.psychic, AttackSubtype.aoe), 5);
      expect(count(AttackType.psychic, AttackSubtype.burst), 0);
      expect(count(AttackType.psychic, AttackSubtype.unique), 10);

      for (final type in AttackType.values) {
        expect(combatTriggers.where((t) => t.attackType == type).length, 20,
            reason: '$type should total 20');
      }
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

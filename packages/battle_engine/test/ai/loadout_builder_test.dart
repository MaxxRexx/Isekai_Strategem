import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

void main() {
  group('LoadoutBuilder against the real content catalogs', () {
    final builder = const LoadoutBuilder();
    final roster = CharacterRoster.defaultRoster;
    final triggers = TriggerCatalog.defaultCatalog;
    final blackTriggers = BlackTriggerCatalog.defaultCatalog;

    for (final profile in AiProfile.all) {
      for (final character in roster.all) {
        test('${profile.name} builds a valid Loadout for ${character.name}',
            () {
          final loadout = builder.build(
            character,
            activeTriggerPool: triggers.activeTriggers,
            passiveTriggerPool: triggers.passiveTriggers,
            blackTriggerPool: blackTriggers.all,
            profile: profile,
          );

          final result = loadout.validateFor(character);
          expect(result.isValid, isTrue,
              reason: '${profile.name} x ${character.name}: '
                  '${result.errors.join('; ')}');
        });
      }
    }

    test(
        "The Gambler equips a Black Trigger even when it doesn't resonate "
        'well', () {
      final defenseChar = roster.ofType(CharacterType.attack).first;
      final loadout = builder.build(
        defenseChar,
        activeTriggerPool: triggers.activeTriggers,
        passiveTriggerPool: triggers.passiveTriggers,
        blackTriggerPool: blackTriggers.all,
        profile: AiProfile.theGambler,
      );

      expect(loadout.blackTrigger, isNotNull);
    });

    test('a Black Trigger bias of 0 never equips one', () {
      const noBtProfile = AiProfile(
        id: 'test_no_bt',
        name: 'Test No BT',
        description: '',
        skillClass: AiSkillClass.beginner,
        targetPriority: AiTargetPriority.lowestHealth,
        abilityPriority: AiAbilityPriority.highestDamage,
        fatPolicy: AiFatPolicy.alwaysChain,
        blackTriggerBias: 0.0,
      );
      final character = roster.all.first;
      final loadout = builder.build(
        character,
        activeTriggerPool: triggers.activeTriggers,
        passiveTriggerPool: triggers.passiveTriggers,
        blackTriggerPool: blackTriggers.all,
        profile: noBtProfile,
      );

      expect(loadout.blackTrigger, isNull);
    });

    test(
        'AOE-favoring profiles equip at least one AOE-tagged Trigger when '
        'one fits the budget', () {
      final character = roster['dross']; // high Trion Capacity attacker
      final loadout = builder.build(
        character,
        activeTriggerPool: triggers.activeTriggers,
        passiveTriggerPool: triggers.passiveTriggers,
        blackTriggerPool: blackTriggers.all,
        profile: AiProfile.theBlastRadius,
      );

      final activeIds =
          loadout.triggers.whereType<ActiveTrigger>().map((t) => t.id);
      final hasAoe = activeIds.any((id) =>
          (triggers[id] as ActiveTrigger).attackSubtype == AttackSubtype.aoe);
      expect(hasAoe, isTrue);
    });
  });
}

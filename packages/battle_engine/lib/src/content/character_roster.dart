import '../models/character.dart';
import '../models/character_perk.dart';
import '../models/character_type.dart';
import '../models/stats.dart';

/// The built-in 20-character roster (5 per [CharacterType]), each with a
/// unique, always-on [CharacterPerk] loosely inspired by World Trigger
/// character beats. Any character can equip any Trigger or Black
/// Trigger regardless of their own [CharacterType] - nothing here
/// restricts that; resonance only scales how strong a character's *own*
/// Black Trigger is for them (see `ResonanceGrid`), it never blocks
/// equipping a mismatched one.
///
/// Note: [Character.blackTrigger] is a static field on the template
/// (used by `TurnEngine.resonanceMultiplierFor`), separate from
/// `Loadout.blackTrigger` (used for equip-cost/active-ability
/// validation) - the roster below leaves it null. Baking a specific
/// Black Trigger choice into a per-battle `Character` copy is a future
/// AI-loadout-building concern, not a roster-content one.
class CharacterRoster {
  final Map<String, Character> _byId;

  CharacterRoster._(this._byId);

  Character operator [](String id) {
    final character = _byId[id];
    if (character == null) {
      throw ArgumentError('Unknown character id: $id');
    }
    return character;
  }

  bool contains(String id) => _byId.containsKey(id);

  Iterable<Character> get all => _byId.values;

  Iterable<Character> ofType(CharacterType type) =>
      _byId.values.where((c) => c.type == type);

  factory CharacterRoster.builtIn() {
    final characters = <Character>[
      // --- Attack ---
      Character(
        id: 'kaito_reyes',
        name: 'Kaito Reyes',
        type: CharacterType.attack,
        baseStats: const Stats(
          trionCapacity: 110,
          trionAffinity: 10,
          teamSpirit: 35,
          criticalChance: 15,
          fatChance: 12,
          armor: 4,
          maxHealth: 100,
          attack: 16,
          defense: 8,
          statusEffectInfliction: 8,
          statusEffectResistance: 3,
        ),
        perk: const CharacterPerk(
          id: 'last_ace',
          name: 'Last Ace',
          description:
              'Critical Chance is doubled while Kaito is the last living '
              'member of his team.',
          doublesCritChanceWhenLastAlive: true,
        ),
      ),
      Character(
        id: 'vela_ashworth',
        name: 'Vela Ashworth',
        type: CharacterType.attack,
        baseStats: const Stats(
          trionCapacity: 105,
          trionAffinity: 9,
          teamSpirit: 40,
          criticalChance: 12,
          fatChance: 10,
          armor: 4,
          maxHealth: 100,
          attack: 15,
          defense: 7,
          statusEffectInfliction: 9,
          statusEffectResistance: 3,
        ),
        perk: const CharacterPerk(
          id: 'first_blood',
          name: 'First Blood',
          description: "Vela's first attack of the battle gains bonus Critical "
              'Chance if the target is at full health.',
          firstAttackCritBonusVsFullHealthTarget: 25,
        ),
      ),
      Character(
        id: 'dross',
        name: 'Dross',
        type: CharacterType.attack,
        baseStats: const Stats(
          trionCapacity: 115,
          trionAffinity: 8,
          teamSpirit: 35,
          criticalChance: 6,
          fatChance: 9,
          armor: 7,
          maxHealth: 100,
          attack: 14,
          defense: 9,
          statusEffectInfliction: 7,
          statusEffectResistance: 3,
        ),
        perk: const CharacterPerk(
          id: 'overwhelm',
          name: 'Overwhelm',
          description:
              "Dross's AOE abilities deal bonus damage to a target that "
              'already has an active status effect.',
          aoeDamageBonusPercentVsDebuffedTarget: 0.25,
        ),
      ),
      Character(
        id: 'ren_kobayashi',
        name: 'Ren Kobayashi',
        type: CharacterType.attack,
        baseStats: const Stats(
          trionCapacity: 100,
          trionAffinity: 11,
          teamSpirit: 30,
          criticalChance: 10,
          fatChance: 14,
          armor: 4,
          maxHealth: 100,
          attack: 15,
          defense: 8,
          statusEffectInfliction: 8,
          statusEffectResistance: 2,
        ),
        perk: const CharacterPerk(
          id: 'first_strike',
          name: 'First Strike',
          description:
              'Ren gets a flat Attack bonus on the first ability he uses '
              'each battle.',
          firstTurnAttackBonus: 5,
        ),
      ),
      Character(
        id: 'airi_tanaka',
        name: 'Airi Tanaka',
        type: CharacterType.attack,
        baseStats: const Stats(
          trionCapacity: 100,
          trionAffinity: 10,
          teamSpirit: 45,
          criticalChance: 13,
          fatChance: 11,
          armor: 5,
          maxHealth: 100,
          attack: 13,
          defense: 9,
          statusEffectInfliction: 9,
          statusEffectResistance: 4,
        ),
        perk: const CharacterPerk(
          id: 'feint',
          name: 'Feint',
          description:
              'The first attack made against Airi each battle is rolled '
              'with disadvantage.',
          firstIncomingAttackHasDisadvantage: true,
        ),
      ),

      // --- Defense ---
      Character(
        id: 'marren_osei',
        name: 'Marren Osei',
        type: CharacterType.defense,
        baseStats: const Stats(
          trionCapacity: 120,
          trionAffinity: 8,
          teamSpirit: 55,
          criticalChance: 3,
          fatChance: 7,
          armor: 12,
          maxHealth: 100,
          attack: 7,
          defense: 16,
          statusEffectInfliction: 5,
          statusEffectResistance: 6,
        ),
        perk: const CharacterPerk(
          id: 'bulwark',
          name: 'Bulwark',
          description: "Marren's Armor is doubled while any living teammate is "
              'below 25% health.',
          doublesArmorWhileAllyBelowQuarterHealth: true,
        ),
      ),
      Character(
        id: 'ilona_vance',
        name: 'Ilona Vance',
        type: CharacterType.defense,
        baseStats: const Stats(
          trionCapacity: 110,
          trionAffinity: 9,
          teamSpirit: 50,
          criticalChance: 5,
          fatChance: 8,
          armor: 9,
          maxHealth: 100,
          attack: 10,
          defense: 15,
          statusEffectInfliction: 6,
          statusEffectResistance: 6,
        ),
        perk: const CharacterPerk(
          id: 'riposte',
          name: 'Riposte',
          description:
              'Whenever a melee attack against Ilona misses, she gains a '
              'stacking Attack buff for her next turn.',
          attackStackBonusOnMeleeMissAgainstSelf: 3,
        ),
      ),
      Character(
        id: 'bastian_cole',
        name: 'Bastian Cole',
        type: CharacterType.defense,
        baseStats: const Stats(
          trionCapacity: 115,
          trionAffinity: 8,
          teamSpirit: 50,
          criticalChance: 3,
          fatChance: 7,
          armor: 10,
          maxHealth: 100,
          attack: 8,
          defense: 14,
          statusEffectInfliction: 5,
          statusEffectResistance: 7,
        ),
        perk: const CharacterPerk(
          id: 'absorb',
          name: 'Absorb',
          description:
              'The first instance of damage Bastian takes each battle is '
              'reduced by half, independent of any World ability.',
          firstDamageInstanceReductionPercent: 0.5,
        ),
      ),
      Character(
        id: 'dorian_voss',
        name: 'Dorian Voss',
        type: CharacterType.defense,
        baseStats: const Stats(
          trionCapacity: 110,
          trionAffinity: 9,
          teamSpirit: 48,
          criticalChance: 4,
          fatChance: 8,
          armor: 9,
          maxHealth: 100,
          attack: 9,
          defense: 14,
          statusEffectInfliction: 5,
          statusEffectResistance: 5,
        ),
        perk: const CharacterPerk(
          id: 'immovable',
          name: 'Immovable',
          description:
              "Dorian is immune to any effect that would reduce how many "
              "targets his ranged abilities can hit.",
          immuneToTargetCountReduction: true,
        ),
      ),
      Character(
        id: 'sable_whitlock',
        name: 'Sable Whitlock',
        type: CharacterType.defense,
        baseStats: const Stats(
          trionCapacity: 115,
          trionAffinity: 9,
          teamSpirit: 55,
          criticalChance: 4,
          fatChance: 8,
          armor: 10,
          maxHealth: 100,
          attack: 8,
          defense: 15,
          statusEffectInfliction: 5,
          statusEffectResistance: 6,
        ),
        perk: const CharacterPerk(
          id: 'guardians_instinct',
          name: "Guardian's Instinct",
          description:
              'Once per battle, Sable can redirect an attack targeting a '
              'living teammate onto himself instead.',
          canRedirectAllyAttackOncePerBattle: true,
        ),
      ),

      // --- Support ---
      Character(
        id: 'priya_nakamura',
        name: 'Priya Nakamura',
        type: CharacterType.support,
        baseStats: const Stats(
          trionCapacity: 105,
          trionAffinity: 12,
          teamSpirit: 65,
          criticalChance: 4,
          fatChance: 9,
          armor: 5,
          maxHealth: 100,
          attack: 6,
          defense: 10,
          statusEffectInfliction: 10,
          statusEffectResistance: 5,
        ),
        perk: const CharacterPerk(
          id: 'combat_medic',
          name: 'Combat Medic',
          description:
              "Priya's heal-over-time effects heal for more when applied "
              'to an ally below 50% health.',
          healBonusPercentVsAllyBelowHalfHealth: 0.3,
        ),
      ),
      Character(
        id: 'soren_talvik',
        name: 'Soren Talvik',
        type: CharacterType.support,
        baseStats: const Stats(
          trionCapacity: 105,
          trionAffinity: 10,
          teamSpirit: 60,
          criticalChance: 5,
          fatChance: 9,
          armor: 5,
          maxHealth: 100,
          attack: 7,
          defense: 9,
          statusEffectInfliction: 16,
          statusEffectResistance: 5,
        ),
        perk: const CharacterPerk(
          id: 'weaken_resolve',
          name: 'Weaken Resolve',
          description:
              "Status effects Soren inflicts last 1 turn longer against a "
              'target already carrying one of his other debuffs.',
          bonusDurationVsAlreadyAffectedTarget: 1,
        ),
      ),
      Character(
        id: 'yuki_amaral',
        name: 'Yuki Amaral',
        type: CharacterType.support,
        baseStats: const Stats(
          trionCapacity: 105,
          trionAffinity: 11,
          teamSpirit: 70,
          criticalChance: 4,
          fatChance: 8,
          armor: 6,
          maxHealth: 100,
          attack: 6,
          defense: 11,
          statusEffectInfliction: 9,
          statusEffectResistance: 6,
        ),
        perk: const CharacterPerk(
          id: 'devoted_aid',
          name: 'Devoted Aid',
          description: 'Yuki receives 10% bonus to all healing regardless of '
              'source, including a drain-style Trigger that heals its '
              'user off someone else\'s health.',
          incomingHealBonusPercent: 0.10,
        ),
      ),
      Character(
        id: 'haru_ellison',
        name: 'Haru Ellison',
        type: CharacterType.support,
        baseStats: const Stats(
          trionCapacity: 130,
          trionAffinity: 16,
          teamSpirit: 60,
          criticalChance: 4,
          fatChance: 9,
          armor: 5,
          maxHealth: 100,
          attack: 6,
          defense: 10,
          statusEffectInfliction: 8,
          statusEffectResistance: 5,
        ),
        perk: const CharacterPerk(
          id: 'battery',
          name: 'Battery',
          description: "While Haru is alive, her team's Trion gain roll gets a "
              'small positive modifier.',
          teamTrionGainModifierWhileAlive: 0.1,
        ),
      ),
      Character(
        id: 'celestine_moreau',
        name: 'Celestine Moreau',
        type: CharacterType.support,
        baseStats: const Stats(
          trionCapacity: 110,
          trionAffinity: 10,
          teamSpirit: 62,
          criticalChance: 4,
          fatChance: 8,
          armor: 6,
          maxHealth: 100,
          attack: 6,
          defense: 11,
          statusEffectInfliction: 10,
          statusEffectResistance: 6,
        ),
        perk: const CharacterPerk(
          id: 'warding_presence',
          name: 'Warding Presence',
          description: "Celestine's ally-targeted buffs also grant a bonus to "
              'Status Effect Resistance.',
          bonusStatusResistanceGrantedByAllyBuffs: 5,
        ),
      ),

      // --- Unique ---
      Character(
        id: 'zheng_anders',
        name: 'Zheng Anders',
        type: CharacterType.unique,
        baseStats: const Stats(
          trionCapacity: 105,
          trionAffinity: 12,
          teamSpirit: 45,
          criticalChance: 8,
          fatChance: 12,
          armor: 5,
          maxHealth: 100,
          attack: 11,
          defense: 10,
          statusEffectInfliction: 12,
          statusEffectResistance: 5,
        ),
        perk: const CharacterPerk(
          id: 'foresight',
          name: 'Foresight',
          description:
              'Once per battle, Zheng can reroll one of his own attack '
              'rolls.',
          canRerollOwnAttackRollOncePerBattle: true,
        ),
      ),
      Character(
        id: 'nadia_kessler',
        name: 'Nadia Kessler',
        type: CharacterType.unique,
        baseStats: const Stats(
          trionCapacity: 100,
          trionAffinity: 10,
          teamSpirit: 40,
          criticalChance: 9,
          fatChance: 16,
          armor: 5,
          maxHealth: 100,
          attack: 13,
          defense: 9,
          statusEffectInfliction: 9,
          statusEffectResistance: 4,
        ),
        perk: const CharacterPerk(
          id: 'chain_reaction',
          name: 'Chain Reaction',
          description: 'Each additional ability Nadia uses in the same '
              'FAT-triggered turn deals more damage than the last.',
          perExtraAbilityDamageBonusPercent: 0.15,
        ),
      ),
      Character(
        id: 'rurik_voss',
        name: 'Rurik Voss',
        type: CharacterType.unique,
        baseStats: const Stats(
          trionCapacity: 100,
          trionAffinity: 9,
          teamSpirit: 30,
          criticalChance: 14,
          fatChance: 13,
          armor: 3,
          maxHealth: 100,
          attack: 17,
          defense: 6,
          statusEffectInfliction: 7,
          statusEffectResistance: 2,
        ),
        perk: const CharacterPerk(
          id: 'all_or_nothing',
          name: 'All or Nothing',
          description:
              "Rurik's damage output rises as his own health drops, up "
              'to double at 0 health.',
          maxDamageBonusPercentAtZeroHealth: 1.0,
        ),
      ),
      Character(
        id: 'mireille_song',
        name: 'Mireille Song',
        type: CharacterType.unique,
        baseStats: const Stats(
          trionCapacity: 100,
          trionAffinity: 10,
          teamSpirit: 45,
          criticalChance: 8,
          fatChance: 11,
          armor: 5,
          maxHealth: 100,
          attack: 11,
          defense: 9,
          statusEffectInfliction: 9,
          statusEffectResistance: 5,
        ),
        perk: const CharacterPerk(
          id: 'decoy',
          name: 'Decoy',
          description:
              'Once per battle, an attack against Mireille has a chance '
              'to simply miss, as if she was never really there.',
          dodgeChanceOncePerBattle: 0.35,
        ),
      ),
      Character(
        id: 'tobias_renner',
        name: 'Tobias Renner',
        type: CharacterType.unique,
        baseStats: const Stats(
          trionCapacity: 105,
          trionAffinity: 10,
          teamSpirit: 45,
          criticalChance: 7,
          fatChance: 11,
          armor: 5,
          maxHealth: 100,
          attack: 11,
          defense: 10,
          statusEffectInfliction: 10,
          statusEffectResistance: 4,
        ),
        perk: const CharacterPerk(
          id: 'versatile',
          name: 'Versatile',
          description:
              'Tobias gets a small bonus to whichever stat matches the '
              'category of ability he last used.',
          grantsBonusForLastUsedAbilityCategory: true,
        ),
      ),
    ];

    return CharacterRoster._({for (final c in characters) c.id: c});
  }

  static final CharacterRoster defaultRoster = CharacterRoster.builtIn();
}

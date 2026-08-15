import '../models/black_trigger.dart';
import '../models/character_type.dart';
import '../models/damage_type.dart';
import '../models/passive_effect.dart';
import '../models/reactive_effect.dart';
import '../models/status_effect.dart';
import '../models/trigger.dart';
import '../models/world_ability_effect.dart';
import '../util/dice.dart';

/// The built-in 10-Black-Trigger catalog, spread across all 4
/// [BlackTriggerType]s with active/passive/World-ability shapes. Any
/// character may equip any Black Trigger regardless of their own
/// [CharacterType] - resonance (see `ResonanceGrid`) only scales how
/// strong it is for them, it never blocks the equip.
class BlackTriggerCatalog {
  final Map<String, BlackTrigger> _byId;

  BlackTriggerCatalog._(this._byId);

  BlackTrigger operator [](String id) {
    final trigger = _byId[id];
    if (trigger == null) throw ArgumentError('Unknown Black Trigger id: $id');
    return trigger;
  }

  bool contains(String id) => _byId.containsKey(id);

  Iterable<BlackTrigger> get all => _byId.values;

  factory BlackTriggerCatalog.builtIn() {
    final triggers = <BlackTrigger>[
      BlackTrigger(
        id: 'ashbringer',
        name: 'Ashbringer',
        type: BlackTriggerType.attack,
        equipCost: 45,
        description: 'A high-damage melee/ranged pair with short cooldowns.',
        activeAbilities: [
          ActiveTrigger(
            id: 'ashbringer_melee',
            name: 'Ashbringer Slash',
            category: TriggerCategory.attacker,
            equipCost: 0,
            trionCost: 20,
            cooldownTurns: 2,
            originTag: OriginTag.energy,
            rangeTag: RangeTag.close,
            attackType: AttackType.melee,
            attackSubtype: AttackSubtype.single,
            damageType: DamageType.fire,
            damage: const DiceExpression(6, 8, flatBonus: 33),
          ),
          ActiveTrigger(
            id: 'ashbringer_ranged',
            name: 'Ashbringer Volley',
            category: TriggerCategory.shooter,
            equipCost: 0,
            trionCost: 20,
            cooldownTurns: 2,
            originTag: OriginTag.energy,
            rangeTag: RangeTag.long,
            attackType: AttackType.ranged,
            attackSubtype: AttackSubtype.single,
            damageType: DamageType.fire,
            damage: const DiceExpression(5, 10, flatBonus: 32),
          ),
          ActiveTrigger(
            id: 'ashbringer_seal',
            name: 'Seal of Severance',
            category: TriggerCategory.trapper,
            equipCost: 0,
            trionCost: 22,
            cooldownTurns: 2,
            originTag: OriginTag.energy,
            rangeTag: RangeTag.close,
            attackType: AttackType.melee,
            attackSubtype: AttackSubtype.single,
            damageType: DamageType.fire,
            damage: const DiceExpression(3, 6, flatBonus: 11),
            inflictedStatusEffects: const [
              StatusEffectApplication('origin_lockout')
            ],
          ),
        ],
      ),
      BlackTrigger(
        id: 'fracture_edge',
        name: 'Fracture Edge',
        type: BlackTriggerType.attack,
        equipCost: 42,
        description: 'A burst attack plus offense-focused passives.',
        activeAbilities: [
          ActiveTrigger(
            id: 'fracture_edge_burst',
            name: 'Fracture Burst',
            category: TriggerCategory.shooter,
            equipCost: 0,
            trionCost: 22,
            cooldownTurns: 2,
            originTag: OriginTag.energy,
            rangeTag: RangeTag.mid,
            attackType: AttackType.ranged,
            attackSubtype: AttackSubtype.burst,
            hitsPerUse: 3,
            targetCount: 2,
            damageType: DamageType.force,
            damage: const DiceExpression(2, 4, flatBonus: 6),
          ),
        ],
        passiveAbilities: const [
          BlackTriggerPassiveAbility(
            id: 'fracture_edge_crit',
            name: "Fracture's Edge",
            effect: PassiveEffect(
              flatStatModifiers: {ModifiableStat.criticalChance: 10},
            ),
          ),
          // +6 Attack was a quarter of the old Attack spread; in the
          // compressed band (4-14) it would have been worth more than the
          // difference between a Support and an Attacker.
          BlackTriggerPassiveAbility(
            id: 'fracture_edge_offense',
            name: 'Sundering Focus',
            effect: PassiveEffect(
              flatStatModifiers: {ModifiableStat.attack: 3},
            ),
          ),
        ],
      ),
      BlackTrigger(
        id: 'solar_flare',
        name: 'Solar Flare',
        type: BlackTriggerType.attack,
        equipCost: 48,
        description:
            'A single massive AOE nuke on a long cooldown, plus a Critical '
            'Chance passive - the glass-cannon Black Trigger.',
        activeAbilities: [
          ActiveTrigger(
            id: 'solar_flare_nuke',
            name: 'Solar Flare',
            category: TriggerCategory.attacker,
            equipCost: 0,
            trionCost: 35,
            cooldownTurns: 2,
            originTag: OriginTag.energy,
            rangeTag: RangeTag.long,
            attackType: AttackType.ranged,
            attackSubtype: AttackSubtype.aoe,
            targetCount: 3,
            damageType: DamageType.radiant,
            damage: const DiceExpression(3, 10, flatBonus: 20),
          ),
        ],
        passiveAbilities: const [
          BlackTriggerPassiveAbility(
            id: 'solar_flare_crit',
            name: 'Blazing Focus',
            effect: PassiveEffect(
              flatStatModifiers: {ModifiableStat.criticalChance: 12},
            ),
          ),
        ],
      ),
      BlackTrigger(
        id: 'aegis_core',
        name: 'Aegis Core',
        type: BlackTriggerType.defense,
        equipCost: 40,
        description: 'A World ability that negates the first few instances '
            'of damage taken each battle.',
        worldAbility: const WorldAbilityEffect(damagePreventionInstances: 3),
      ),
      BlackTrigger(
        id: 'bastion_frame',
        name: 'Bastion Frame',
        type: BlackTriggerType.defense,
        equipCost: 42,
        description:
            'Armor, Damage Resistance, Status Resistance, and Foresight '
            'Counter negate.',
        activeAbilities: [
          ActiveTrigger(
            id: 'bastion_frame_foresight',
            name: 'Foresight Counter',
            category: TriggerCategory.trapper,
            equipCost: 0,
            trionCost: 20,
            cooldownTurns: 2,
            originTag: OriginTag.energy,
            rangeTag: RangeTag.close,
            attackType: AttackType.melee,
            attackSubtype: AttackSubtype.single,
            targetAffiliation: TargetAffiliation.ally,
            armsReactive: ReactiveKind.negateByOrigin,
            armsReactiveDefaultTurns: 2,
          ),
        ],
        passiveAbilities: const [
          BlackTriggerPassiveAbility(
            id: 'bastion_frame_armor',
            name: 'Bastion Plating',
            effect: PassiveEffect(
              flatStatModifiers: {ModifiableStat.armor: 8},
            ),
          ),
          BlackTriggerPassiveAbility(
            id: 'bastion_frame_resistance',
            name: 'Hardened Shell',
            effect: PassiveEffect(
              damageResistancesGranted: {DamageType.bludgeoning},
            ),
          ),
          BlackTriggerPassiveAbility(
            id: 'bastion_frame_status',
            name: 'Steady Mind',
            effect: PassiveEffect(
              flatStatModifiers: {ModifiableStat.statusEffectResistance: 8},
            ),
          ),
        ],
      ),
      BlackTrigger(
        id: 'wellspring',
        name: 'Wellspring',
        type: BlackTriggerType.support,
        equipCost: 40,
        description:
            'A direct heal, a Regenerating buff, and Mirror Ward reflect.',
        activeAbilities: [
          ActiveTrigger(
            id: 'wellspring_heal',
            name: 'Wellspring Surge',
            category: TriggerCategory.optional,
            equipCost: 0,
            trionCost: 20,
            cooldownTurns: 2,
            originTag: OriginTag.energy,
            rangeTag: RangeTag.mid,
            attackType: AttackType.melee,
            attackSubtype: AttackSubtype.single,
            targetAffiliation: TargetAffiliation.ally,
            healAmount: const DiceExpression(3, 6, flatBonus: -5),
          ),
          ActiveTrigger(
            id: 'wellspring_regen',
            name: "Wellspring's Blessing",
            category: TriggerCategory.optional,
            equipCost: 0,
            trionCost: 18,
            cooldownTurns: 2,
            originTag: OriginTag.energy,
            rangeTag: RangeTag.mid,
            attackType: AttackType.melee,
            attackSubtype: AttackSubtype.single,
            targetAffiliation: TargetAffiliation.ally,
            inflictedStatusEffects: const [
              StatusEffectApplication('regenerating')
            ],
          ),
          ActiveTrigger(
            id: 'wellspring_mirror_ward',
            name: 'Mirror Ward',
            category: TriggerCategory.optional,
            equipCost: 0,
            trionCost: 25,
            cooldownTurns: 3,
            originTag: OriginTag.energy,
            rangeTag: RangeTag.close,
            attackType: AttackType.melee,
            attackSubtype: AttackSubtype.single,
            targetAffiliation: TargetAffiliation.ally,
            armsReactive: ReactiveKind.reflectNonAoe,
            armsReactiveDefaultTurns: 2,
          ),
        ],
      ),
      BlackTrigger(
        id: 'chorus_bond',
        name: 'Chorus Bond',
        type: BlackTriggerType.support,
        equipCost: 42,
        description: 'Team Spirit and healing-focused passives, a suite for a '
            'dedicated support build.',
        passiveAbilities: const [
          BlackTriggerPassiveAbility(
            id: 'chorus_bond_spirit',
            name: 'Bonded Resolve',
            effect: PassiveEffect(
              flatStatModifiers: {ModifiableStat.teamSpirit: 10},
            ),
          ),
          BlackTriggerPassiveAbility(
            id: 'chorus_bond_infliction',
            name: 'Harmonic Focus',
            effect: PassiveEffect(
              flatStatModifiers: {ModifiableStat.statusEffectInfliction: 6},
            ),
          ),
          BlackTriggerPassiveAbility(
            id: 'chorus_bond_resistance',
            name: 'Warding Chorus',
            effect: PassiveEffect(
              flatStatModifiers: {ModifiableStat.statusEffectResistance: 6},
            ),
          ),
          BlackTriggerPassiveAbility(
            id: 'chorus_bond_max_health',
            name: 'Vital Chorus',
            effect: PassiveEffect(
              flatStatModifiers: {ModifiableStat.maxHealth: 15},
            ),
          ),
        ],
      ),
      BlackTrigger(
        id: 'paradox_shard',
        name: 'Paradox Shard',
        type: BlackTriggerType.unique,
        equipCost: 44,
        description: 'An unpredictable debuff ability paired with a disruptive '
            'psychic strike.',
        activeAbilities: [
          ActiveTrigger(
            id: 'paradox_shard_debuff',
            name: 'Paradox Whisper',
            category: TriggerCategory.trapper,
            equipCost: 0,
            trionCost: 20,
            cooldownTurns: 2,
            originTag: OriginTag.mental,
            rangeTag: RangeTag.mid,
            attackType: AttackType.psychic,
            attackSubtype: AttackSubtype.single,
            damageType: DamageType.psychic,
            damage: const DiceExpression(3, 6, flatBonus: 11),
            inflictedStatusEffects: const [
              StatusEffectApplication('overwhelmed')
            ],
          ),
          ActiveTrigger(
            id: 'paradox_shard_strike',
            name: 'Paradox Fracture',
            category: TriggerCategory.attacker,
            equipCost: 0,
            trionCost: 22,
            cooldownTurns: 2,
            originTag: OriginTag.mental,
            rangeTag: RangeTag.mid,
            attackType: AttackType.psychic,
            attackSubtype: AttackSubtype.unique,
            damageType: DamageType.psychic,
            damage: const DiceExpression(5, 8, flatBonus: 29),
          ),
          ActiveTrigger(
            id: 'paradox_shard_puppet',
            name: 'Puppet Strings',
            category: TriggerCategory.trapper,
            equipCost: 0,
            trionCost: 22,
            cooldownTurns: 2,
            originTag: OriginTag.mental,
            rangeTag: RangeTag.close,
            attackType: AttackType.psychic,
            attackSubtype: AttackSubtype.single,
            targetAffiliation: TargetAffiliation.ally,
            armsReactive: ReactiveKind.redirectToOwnAlly,
            armsReactiveDefaultTurns: 2,
          ),
          ActiveTrigger(
            id: 'paradox_shard_deadfall',
            name: 'Deadfall',
            category: TriggerCategory.trapper,
            equipCost: 0,
            trionCost: 20,
            cooldownTurns: 2,
            originTag: OriginTag.mental,
            rangeTag: RangeTag.long,
            attackType: AttackType.psychic,
            attackSubtype: AttackSubtype.single,
            armsReactive: ReactiveKind.trapOnAction,
            armsReactiveDefaultTurns: 2,
          ),
        ],
      ),
      BlackTrigger(
        id: 'gravebind',
        name: 'Gravebind',
        type: BlackTriggerType.unique,
        equipCost: 38,
        description:
            'A World ability: once per battle, survive a hit that would '
            'have reduced health to 0, landing on 1 instead. One More '
            'Breath enriches the survive-lethal trigger.',
        activeAbilities: [
          ActiveTrigger(
            id: 'gravebind_breath',
            name: 'One More Breath',
            category: TriggerCategory.optional,
            equipCost: 0,
            trionCost: 20,
            cooldownTurns: 3,
            originTag: OriginTag.energy,
            rangeTag: RangeTag.close,
            attackType: AttackType.melee,
            attackSubtype: AttackSubtype.single,
            targetAffiliation: TargetAffiliation.self,
            armsReactive: ReactiveKind.enrichSurviveLethal,
          ),
        ],
        worldAbility: const WorldAbilityEffect(surviveLethalDamageOnce: true),
      ),
      BlackTrigger(
        id: 'chrono_fragment',
        name: 'Chrono Fragment',
        type: BlackTriggerType.unique,
        equipCost: 30,
        description:
            "A World ability: increases the wielder's team's turn timer "
            'each turn - a tempo tool, not a combat one.',
        worldAbility: const WorldAbilityEffect(turnTimerSecondsDelta: 5),
      ),
    ];

    return BlackTriggerCatalog._({for (final t in triggers) t.id: t});
  }

  static final BlackTriggerCatalog defaultCatalog =
      BlackTriggerCatalog.builtIn();
}

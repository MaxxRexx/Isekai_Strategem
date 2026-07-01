import 'damage_type.dart';
import '../util/dice.dart';

/// Broad equipment category for a Trigger.
enum TriggerCategory { attacker, shooter, sniper, trapper, optional }

/// What "kind" of energy/action underlies an ability. Used for
/// interactions that key off origin (e.g. resistances, future synergy
/// rules) independent of its damage type.
enum OriginTag { physical, energy, afflict, mental }

enum RangeTag { melee, ranged }

/// Attack type tag. `psychic` is intentionally distinct from `melee`
/// /`ranged` per the design (Psychic Attack: Unique, Single, AoE) rather
/// than being folded into ranged.
enum AttackType { melee, ranged, psychic }

/// Attack subtype tag. Not every (AttackType, AttackSubtype) pair is
/// meaningful - see [AttackType.validSubtypes] - but subtypes are shared
/// across attack types rather than split into per-type enums so new
/// combinations can be added without introducing parallel enum families.
enum AttackSubtype { single, aoe, burst, unique }

extension AttackTypeSubtypes on AttackType {
  /// The subtypes the design currently allows for this attack type:
  /// Melee: Single, AoE. Ranged: Single, Burst, AoE. Psychic: Unique,
  /// Single, AoE.
  Set<AttackSubtype> get validSubtypes {
    switch (this) {
      case AttackType.melee:
        return {AttackSubtype.single, AttackSubtype.aoe};
      case AttackType.ranged:
        return {AttackSubtype.single, AttackSubtype.burst, AttackSubtype.aoe};
      case AttackType.psychic:
        return {AttackSubtype.unique, AttackSubtype.single, AttackSubtype.aoe};
    }
  }
}

/// A status effect a Trigger may inflict on hit, with its own infliction
/// value override (falls back to the wielder's stat when null) and
/// duration.
class StatusEffectApplication {
  final String statusEffectId;
  final int? durationTurnsOverride;

  const StatusEffectApplication(this.statusEffectId,
      {this.durationTurnsOverride});
}

/// An equippable ability. Triggers are not fixed per character; they're
/// assigned during the pre-match Loadout phase (see [Loadout]).
class Trigger {
  final String id;
  final String name;
  final TriggerCategory category;

  /// Trion cost paid once to equip this Trigger during the Loadout phase.
  final int equipCost;

  /// Slot cost consumed from the wielder's slot capacity.
  final int slotCost;

  /// Trion cost paid from the team's [TrionPool] each time this is used.
  final int trionCost;

  /// Cooldown, in turns, before this Trigger can be used again.
  final int cooldownTurns;

  final OriginTag originTag;
  final RangeTag rangeTag;
  final AttackType attackType;
  final AttackSubtype attackSubtype;

  /// Number of independent to-hit rolls made against *each* targeted
  /// character. Only meaningful for `AttackSubtype.burst`; every other
  /// subtype should leave this at 1.
  final int hitsPerUse;

  /// Number of simultaneous targets. For Burst, this is independent of
  /// [hitsPerUse]: `targetCount` governs how many characters the ability
  /// can hit at all, `hitsPerUse` governs how many times it hits each one.
  final int targetCount;

  final DamageType? damageType;
  final DiceExpression? damage;

  final List<StatusEffectApplication> inflictedStatusEffects;

  Trigger({
    required this.id,
    required this.name,
    required this.category,
    required this.equipCost,
    required this.slotCost,
    required this.trionCost,
    required this.cooldownTurns,
    required this.originTag,
    required this.rangeTag,
    required this.attackType,
    required this.attackSubtype,
    this.hitsPerUse = 1,
    this.targetCount = 1,
    this.damageType,
    this.damage,
    this.inflictedStatusEffects = const [],
  }) : assert(
          attackType.validSubtypes.contains(attackSubtype),
          '$attackSubtype is not a valid subtype for $attackType',
        );
}

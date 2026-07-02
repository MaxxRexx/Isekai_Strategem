import 'character_type.dart';
import 'passive_effect.dart';
import 'trigger.dart';
import 'world_ability_effect.dart';

/// A single named passive ability on a [BlackTrigger] (kept as its own
/// small wrapper, rather than a bare [PassiveEffect], so each one still
/// has an id/name for flavor/UI - even though mechanically all of a BT's
/// passive abilities just apply simultaneously while it's equipped).
class BlackTriggerPassiveAbility {
  final String id;
  final String name;
  final PassiveEffect effect;

  const BlackTriggerPassiveAbility({
    required this.id,
    required this.name,
    required this.effect,
  });
}

/// A Black Trigger: a character may select at most one, whose [type]
/// resonates with the character's own [CharacterType] (see
/// [ResonanceGrid]) - the resonance grade scales this Black Trigger's
/// ability particulars (damage/heal/cooldown for actives, bonus magnitude
/// for passives and the World ability) for whoever wields it.
///
/// Unlike a regular Trigger (always exactly one Active or Passive
/// ability), a Black Trigger has [activeAbilities] (0-4) and
/// [passiveAbilities] (0-4) independently. If both are empty, it instead
/// has exactly one [worldAbility]: a bespoke, battle-state-modifying rule
/// rather than a targeted action or a stat buff. A Black Trigger is
/// deliberately bespoke content, not a template - some are narrow or
/// situational enough that a normal Trigger set is the better pick for a
/// given team, that trade-off is the point.
class BlackTrigger {
  final String id;
  final String name;
  final BlackTriggerType type;
  final String description;
  final int equipCost;

  final List<ActiveTrigger> activeAbilities;
  final List<BlackTriggerPassiveAbility> passiveAbilities;
  final WorldAbilityEffect? worldAbility;

  BlackTrigger({
    required this.id,
    required this.name,
    required this.type,
    required this.equipCost,
    this.description = '',
    this.activeAbilities = const [],
    this.passiveAbilities = const [],
    this.worldAbility,
  })  : assert(activeAbilities.length <= 4,
            'A Black Trigger may have at most 4 active abilities'),
        assert(passiveAbilities.length <= 4,
            'A Black Trigger may have at most 4 passive abilities'),
        assert(
          (activeAbilities.isEmpty && passiveAbilities.isEmpty) ==
              (worldAbility != null),
          'A Black Trigger has a World ability if and only if it has zero '
          'active and zero passive abilities',
        );

  /// Total number of active abilities this Black Trigger contributes
  /// toward a Loadout's "exactly 4 active abilities" requirement.
  int get activeAbilityCount => activeAbilities.length;
}

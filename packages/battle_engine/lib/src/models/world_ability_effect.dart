/// A Black Trigger's "World" ability: a bespoke, battle-state-modifying
/// rule rather than a targeted action or a continuous stat buff. A Black
/// Trigger has a World ability only when it has zero Active and zero
/// Passive abilities (see `BlackTrigger`).
///
/// Data-driven like `StatusEffectDefinition`: each named field is one
/// mechanic the engine knows how to interpret. New World ability
/// concepts are added as new fields here, not as engine-side special
/// cases per Black Trigger.
class WorldAbilityEffect {
  /// Seconds added to (or, if negative, subtracted from) the wielder's
  /// team's per-turn timer (see `TurnTimerConfig`). Applies per team per
  /// turn, not per character.
  final int? turnTimerSecondsDelta;

  /// The wielder fully negates the first N instances of damage they take
  /// this battle (a consumable per-battle pool, not reset per turn).
  final int? damagePreventionInstances;

  /// Once per battle: if damage would reduce the wielder's health to 0
  /// while their current health is above 1, their health is set to 1
  /// instead.
  final bool surviveLethalDamageOnce;

  const WorldAbilityEffect({
    this.turnTimerSecondsDelta,
    this.damagePreventionInstances,
    this.surviveLethalDamageOnce = false,
  });
}

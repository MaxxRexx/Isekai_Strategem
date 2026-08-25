/// A character's innate, always-on trait - distinct from anything a
/// Trigger/Black Trigger grants, and never removed by re-equipping. Every field
/// is optional/off by default; a given [SideEffect] sets only the ones relevant
/// to its own effect, mirroring the "bespoke enumerable options" shape used by
/// `WorldAbilityEffect` rather than a single generic mechanism - twenty
/// individually-flavored Side Effects don't share enough structure to
/// generalize further without forcing a fake abstraction.
///
/// Side Effects interact with whatever a player equips rather than being tied
/// to a specific Trigger: e.g. an incoming-heal bonus applies no matter what
/// heals the character, including a drain-style Trigger that heals its user off
/// someone else's health.
class SideEffect {
  final String id;
  final String name;
  final String description;

  /// Critical Chance is doubled while this character is the last living
  /// member of their team.
  final bool doublesCritChanceWhenLastAlive;

  /// Bonus Critical Chance on this character's first attack of the battle,
  /// only if that attack's target is at full health. One-time per battle.
  final double? firstAttackCritBonusVsFullHealthTarget;

  /// AOE abilities deal bonus damage (percent) against a target that
  /// already has at least one active status effect.
  final double? aoeDamageBonusPercentVsDebuffedTarget;

  /// Flat Attack bonus on the first turn this character acts in a battle.
  final int? firstTurnAttackBonus;

  /// The first attack roll made against this character each battle is
  /// rolled with disadvantage. One-time per battle.
  final bool firstIncomingAttackHasDisadvantage;

  /// Armor is doubled while any living teammate is below 25% health.
  final bool doublesArmorWhileAllyBelowQuarterHealth;

  /// Whenever a melee attack against this character misses, they gain a
  /// stacking Attack buff for their next turn.
  final int? attackStackBonusOnMeleeMissAgainstSelf;

  /// The first instance of damage this character takes in a battle is
  /// reduced by this percent, on top of any other mitigation. One-time
  /// per battle.
  final double? firstDamageInstanceReductionPercent;

  /// Immune to any effect that would reduce how many targets this
  /// character's ranged abilities can hit (e.g. Blinded-style effects).
  final bool immuneToTargetCountReduction;

  /// Once per battle, this character can redirect an attack targeting a
  /// living teammate onto themself instead.
  final bool canRedirectAllyAttackOncePerBattle;

  /// Heal-over-time effects this character applies heal for bonus percent
  /// when the recipient is below 50% health.
  final double? healBonusPercentVsAllyBelowHalfHealth;

  /// Status effects this character inflicts last this many turns longer
  /// when the target already has at least one active status effect from
  /// this character.
  final int? bonusDurationVsAlreadyAffectedTarget;

  /// Bonus percent applied to all healing this character receives,
  /// regardless of source.
  final double? incomingHealBonusPercent;

  /// While this character is alive, their team's Trion gain roll gets
  /// this additive modifier (see `TrionGainEngine.rollTier`'s `modifier`
  /// parameter).
  final double? teamTrionGainModifierWhileAlive;

  /// Ally-targeted buffs this character applies also grant this much
  /// bonus Status Effect Resistance alongside their normal effect.
  final int? bonusStatusResistanceGrantedByAllyBuffs;

  /// Once per battle, this character can reroll one of their own attack
  /// rolls.
  final bool canRerollOwnAttackRollOncePerBattle;

  /// Each additional ability this character uses in the same
  /// FAT-triggered turn deals this much more damage (percent) than the
  /// one before it, compounding.
  final double? perExtraAbilityDamageBonusPercent;

  /// Maximum damage bonus (percent), reached at 0 health, scaling
  /// linearly with this character's own missing health fraction.
  final double? maxDamageBonusPercentAtZeroHealth;

  /// Once per battle, an attack against this character has this percent
  /// chance to miss entirely, independent of the normal to-hit roll.
  final double? dodgeChanceOncePerBattle;

  /// Grants a small bonus to whichever stat (Attack/Defense/Status Effect
  /// Infliction) matches the category of ability this character last used.
  final bool grantsBonusForLastUsedAbilityCategory;

  const SideEffect({
    required this.id,
    required this.name,
    required this.description,
    this.doublesCritChanceWhenLastAlive = false,
    this.firstAttackCritBonusVsFullHealthTarget,
    this.aoeDamageBonusPercentVsDebuffedTarget,
    this.firstTurnAttackBonus,
    this.firstIncomingAttackHasDisadvantage = false,
    this.doublesArmorWhileAllyBelowQuarterHealth = false,
    this.attackStackBonusOnMeleeMissAgainstSelf,
    this.firstDamageInstanceReductionPercent,
    this.immuneToTargetCountReduction = false,
    this.canRedirectAllyAttackOncePerBattle = false,
    this.healBonusPercentVsAllyBelowHalfHealth,
    this.bonusDurationVsAlreadyAffectedTarget,
    this.incomingHealBonusPercent,
    this.teamTrionGainModifierWhileAlive,
    this.bonusStatusResistanceGrantedByAllyBuffs,
    this.canRerollOwnAttackRollOncePerBattle = false,
    this.perExtraAbilityDamageBonusPercent,
    this.maxDamageBonusPercentAtZeroHealth,
    this.dodgeChanceOncePerBattle,
    this.grantsBonusForLastUsedAbilityCategory = false,
  });
}

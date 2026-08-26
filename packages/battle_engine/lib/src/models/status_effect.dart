import '../util/dice.dart';
import 'damage_type.dart';
import 'status_reaction.dart';

/// Roll categories that advantage/disadvantage sources can target. Status
/// effects grant entries on the relevant [RollContext] (see
/// [StatusEffectDefinition.disadvantageRollTags]).
enum StatusRollTag { attackRoll, rangedAttackRoll, statusResistanceRoll }

/// How a status effect changes a character's relationship to a damage
/// type. Used to implement e.g. Wet (immune to Fire, vulnerable to
/// Lightning/Cold) without hardcoding the interaction in the combat
/// engine - the engine just asks "does the target have any active status
/// with a [DamageTypeInteractionRule] for this damage type?".
enum DamageInteractionKind { immune, vulnerable }

class DamageTypeInteractionRule {
  final DamageType damageType;
  final DamageInteractionKind kind;

  /// Multiplier applied for `vulnerable` (e.g. 2.0 for double damage).
  /// Ignored for `immune`, which always zeroes damage of that type.
  final double vulnerableMultiplier;

  const DamageTypeInteractionRule.immune(this.damageType)
      : kind = DamageInteractionKind.immune,
        vulnerableMultiplier = 1.0;

  const DamageTypeInteractionRule.vulnerable(this.damageType,
      {double multiplier = 2.0})
      : kind = DamageInteractionKind.vulnerable,
        vulnerableMultiplier = multiplier;
}

/// A named stat key a status effect can modify. Kept as a small closed
/// enum (rather than raw strings) so typos fail at compile time, while
/// still letting [StatusEffectDefinition] stay fully data-driven (no
/// per-effect switch statements - the engine just folds every active
/// instance's modifiers for a given key).
enum ModifiableStat {
  attack,
  defense,
  armor,
  maxHealth,
  trionAffinity,
  teamSpirit,
  criticalChance,
  fatChance,
  statusEffectInfliction,
  statusEffectResistance,
}

/// A data-driven status effect definition.
///
/// New status effects are added by constructing another instance of this
/// class (see [StatusEffectCatalog]) - the engine (`StatusEffectEngine`)
/// interprets these generic fields uniformly, so adding an effect never
/// requires touching a switch statement in the engine.
class StatusEffectDefinition {
  final String id;
  final String name;

  /// Turns the effect lasts once applied. Null means it persists until
  /// explicitly cured/removed (no natural expiry).
  final int? defaultDurationTurns;

  /// While active, the affected character cannot take actions (Stunned,
  /// Frozen).
  final bool preventsActions;

  /// While active, the affected character is pinned in place and cannot
  /// Reposition (zone lock). Separate from [preventsActions] because being
  /// held still is not the same as being unable to act: a snared character
  /// can still fight, just not from anywhere else.
  final bool preventsReposition;

  /// Stats forced to zero while this effect is active (Stunned ->
  /// Team Spirit, Frozen -> Trion Affinity).
  final Set<ModifiableStat> zeroedStats;

  /// Flat modifier applied for the lifetime of the effect (Acid -> armor,
  /// Inspired -> attack and defense).
  final Map<ModifiableStat, double> flatStatModifiers;

  /// Modifier scaled by the instance's remaining-turns counter, i.e.
  /// `delta * remainingTurns` (Reeling -> attack -1/turn, Prepared ->
  /// attack +1/turn, Braced -> defense +1/turn). Requires a finite
  /// [defaultDurationTurns].
  final Map<ModifiableStat, double> perRemainingTurnStatModifiers;

  /// Roll categories on which the affected character rolls with
  /// disadvantage while this effect is active (Poisoned's own attack
  /// rolls, Threatened/Blinded's own ranged attack rolls).
  final Set<StatusRollTag> disadvantageRollTags;

  /// Damage-type interactions granted by this effect (Wet).
  final List<DamageTypeInteractionRule> damageTypeInteractions;

  /// Damage dealt at the start of the affected character's turn
  /// (Bleeding, Electrocuted).
  final DiceExpression? turnStartDamage;
  final DamageType? turnStartDamageType;

  /// Health healed at the start of the affected character's turn
  /// (Regenerating), scaled by the character's own Team Spirit-driven
  /// Health Regeneration bonus. Health is not a mechanic on its own per
  /// the design brief, it's entirely ability-driven, so this (and
  /// [ActiveTrigger.healAmount] for instant heals) are the only two ways
  /// health is restored.
  final DiceExpression? turnStartHeal;

  /// Fraction (0-1) of the target's Trion Capacity drained to the
  /// causing character each turn this effect is active (Sapped).
  final double? trionCapacityDrainPercentToCauser;

  /// Number of random damage types the target becomes vulnerable to for
  /// the duration of the effect, chosen once at apply time and stored on
  /// the [StatusEffectInstance] (Sickened).
  final int? vulnerableToRandomDamageTypesCount;

  /// Locks one random equipped ability each turn this is active (Prone).
  final bool locksRandomAbilityEachTurn;

  /// The affected character cannot target the effect's source, and the
  /// source has advantage on rolls against the affected character
  /// (Charmed).
  final bool cannotTargetSource;
  final bool sourceHasAdvantageAgainstTarget;

  /// Ranged abilities used by the affected character target one fewer
  /// target (minimum 1) (Blinded). Combine with
  /// `disadvantageRollTags: {StatusRollTag.rangedAttackRoll}` as needed.
  final bool rangedTargetsReducedByOne;

  /// Roll categories on which the affected character rolls with
  /// *advantage* while this effect is active (Focused's own attack rolls,
  /// Hastened's own attack rolls) - the buff mirror of
  /// [disadvantageRollTags].
  final Set<StatusRollTag> advantageRollTags;

  /// Flat multiplier on *all* damage the affected character takes,
  /// regardless of damage type, combined multiplicatively with any
  /// type-specific [damageTypeInteractions] (Guarded: 0.75, Exposed/
  /// Marked: >1.0). Unlike [damageTypeInteractions], this isn't keyed to a
  /// single damage type.
  final double? allDamageTakenMultiplier;

  /// Flat multiplier on all damage the affected character *deals* with
  /// their own abilities (Empowered: >1.0, Weakened/Enraged's fragility
  /// trade-off: <1.0). Applied by `TurnEngine.resolveAbilityUse` alongside
  /// the Team Spirit damage bonus.
  final double? outgoingDamageMultiplier;

  /// While active, the affected character cannot be healed by any means
  /// (instant heal-on-hit or heal-over-time) (Cursed, Necrotic Wound).
  final bool preventsHealing;

  /// Flat multiplier on the Trion cost of abilities the affected character
  /// uses (Overcharged: <1.0 cheaper, Choked: >1.0 more expensive).
  /// Applied by `TurnEngine.useAbility`.
  final double? trionCostMultiplier;

  /// While active, abilities whose [OriginTag] matches the origin stored
  /// in the instance's `data['lockedOrigin']` are blocked. Seal of
  /// Severance inflicts this.
  final bool locksOriginFromData;

  /// While active, the character may only use the ability whose id matches
  /// their last-used trigger (`CharacterBattleState.lastUsedTriggerId`).
  /// Root Snare inflicts this.
  final bool forcesRepetitionOfLastAbility;

  /// While active, each offensive ability the character uses has this
  /// probability (0-1) of being redirected onto one of their own living
  /// allies. Scramble inflicts this.
  final double? misfireChance;

  /// If non-null, when the affected character uses the same ability they
  /// used last turn, damage is multiplied by this value (e.g. 0.25 for
  /// heavily reduced). Ironvow's Interdict brands the target with this.
  final double? repeatAbilityDamageMultiplier;

  /// While active, the affected character cannot be targeted by any
  /// ability (Illusory Double's untargetable effect).
  final bool preventsTargeting;

  /// While active, the affected character cannot be healed or buffed by
  /// allies, and cannot heal or buff allies (Isolation).
  final bool preventsAllyInteraction;

  /// While active, the affected character's next offensive ability
  /// automatically misses (Echoing Doubt's forced whiff).
  final bool forcesNextAttackMiss;

  /// While active, the affected character's targets are picked at random
  /// from the legal ones rather than by whoever is playing them (Enraged).
  ///
  /// Different from [misfireChance], which sends an attack onto the
  /// attacker's own side with some probability: this one keeps the attack on
  /// the enemy and takes away the choice of which enemy.
  final bool randomizesOwnTargeting;

  /// What this status does when its holder is hit by a damage type, or has
  /// another status land on them (item 3b). Empty for the 50 effects that do
  /// not react to anything.
  final List<StatusReaction> reactions;

  /// How many times this effect can pile up on one character (item 5b).
  ///
  /// 1, the default, means re-applying it refreshes the timer and nothing
  /// else, which is what 50 of the 62 do. The twelve that stack carry 3 here,
  /// and a stack multiplies the effect's magnitude: three stacks of Bleeding
  /// tick three times the damage, three of Inspired give three times the
  /// stat step. There is still only ever **one instance** with one duration,
  /// so a character never shows the same badge twice and never has two
  /// timers running out of step.
  ///
  /// Stacking has to be declared. It used to be the accidental default: two
  /// applications made two instances, ticking separately and counting down
  /// separately, which is unreadable on a character strip and doubles a
  /// magnitude nobody priced.
  final int maxStacks;

  const StatusEffectDefinition({
    required this.id,
    required this.name,
    this.defaultDurationTurns,
    this.preventsActions = false,
    this.preventsReposition = false,
    this.zeroedStats = const {},
    this.flatStatModifiers = const {},
    this.perRemainingTurnStatModifiers = const {},
    this.disadvantageRollTags = const {},
    this.damageTypeInteractions = const [],
    this.turnStartDamage,
    this.turnStartDamageType,
    this.turnStartHeal,
    this.trionCapacityDrainPercentToCauser,
    this.vulnerableToRandomDamageTypesCount,
    this.locksRandomAbilityEachTurn = false,
    this.cannotTargetSource = false,
    this.sourceHasAdvantageAgainstTarget = false,
    this.rangedTargetsReducedByOne = false,
    this.advantageRollTags = const {},
    this.allDamageTakenMultiplier,
    this.outgoingDamageMultiplier,
    this.preventsHealing = false,
    this.trionCostMultiplier,
    this.locksOriginFromData = false,
    this.forcesRepetitionOfLastAbility = false,
    this.misfireChance,
    this.repeatAbilityDamageMultiplier,
    this.preventsTargeting = false,
    this.preventsAllyInteraction = false,
    this.forcesNextAttackMiss = false,
    this.randomizesOwnTargeting = false,
    this.reactions = const [],
    this.maxStacks = 1,
  }) : assert(maxStacks >= 1, 'an effect applies at least once');

  /// Whether this effect piles up rather than merely refreshing.
  bool get stacks => maxStacks > 1;

  /// The reaction [damageType] fires on this status, or null.
  StatusReaction? reactionToDamage(DamageType damageType) {
    for (final r in reactions) {
      if (r.firesOnDamage(damageType)) return r;
    }
    return null;
  }

  /// The reaction [statusEffectId] landing fires on this status, or null.
  StatusReaction? reactionToStatus(String statusEffectId) {
    for (final r in reactions) {
      if (r.firesOnStatus(statusEffectId)) return r;
    }
    return null;
  }
}

/// A live application of a [StatusEffectDefinition] on a character.
class StatusEffectInstance {
  final String definitionId;

  /// Turns remaining, ticked down by the engine. Null for effects with no
  /// natural expiry.
  int? remainingTurns;

  /// The character who caused this effect, if relevant (Sapped, Charmed).
  final String? sourceCharacterId;

  /// Instance-specific randomized/derived state, e.g. the damage types
  /// chosen for Sickened, or the currently-locked ability id for Prone.
  final Map<String, Object?> data;

  /// How many times this effect has piled up, 1 or more (item 5b). Always 1
  /// for an effect whose definition does not stack.
  ///
  /// Every magnitude the effect carries is multiplied by this: the damage or
  /// heal it ticks, the Trion it drains, and each of its stat steps.
  int stacks;

  /// Set when the effect lands on a character who is in the middle of
  /// their own turn, and cleared by the first countdown that sees it.
  ///
  /// The countdown runs at the end of the holder's turn (item #D), so
  /// without this an effect applied on the holder's own turn would spend
  /// one of its turns before the holder ever had one: a self-buff cast on
  /// your turn would burn a turn immediately, and a counter's Stun landing
  /// on the attacker mid-turn would expire before their next turn began.
  /// Skipping exactly the turn it was applied on is what makes a duration
  /// of N mean "the holder's next N turns" for every effect, whoever
  /// applied it and whenever.
  bool skipsNextCountdown;

  StatusEffectInstance({
    required this.definitionId,
    this.remainingTurns,
    this.sourceCharacterId,
    this.skipsNextCountdown = false,
    this.stacks = 1,
    Map<String, Object?>? data,
  }) : data = data ?? {};
}

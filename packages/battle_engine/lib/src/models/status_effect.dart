import '../util/dice.dart';
import 'damage_type.dart';

/// Roll categories that advantage/disadvantage sources can target. Status
/// effects grant entries on the relevant [RollContext] (see
/// [StatusEffectDefinition.disadvantageRollTags] and
/// [StatusEffectDefinition.advantageRollTags]).
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
  teamSpirit
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

  /// Stats forced to zero while this effect is active (Stunned ->
  /// Team Spirit, Frozen -> Trion Affinity).
  final Set<ModifiableStat> zeroedStats;

  /// Flat modifier applied for the lifetime of the effect (Rallied ->
  /// maxHealth, Acid -> armor).
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

  /// Roll categories that get advantage *against* the affected character
  /// while this effect is active. For `statusResistanceRoll`, this means
  /// whoever attempts to inflict a *new* status effect on this character
  /// rolls with advantage (see Bleeding: it's a debuff that makes the
  /// bleeding character more likely to catch further status effects, not
  /// a buff to their own rolls - see the doc comment on
  /// `StatusEffectEngine.resolveInfliction` for why this needed to be
  /// advantage-for-the-roll rather than disadvantage-on-the-target).
  final Set<StatusRollTag> advantageRollTags;

  /// Damage-type interactions granted by this effect (Wet).
  final List<DamageTypeInteractionRule> damageTypeInteractions;

  /// Damage dealt at the start of the affected character's turn
  /// (Bleeding, Electrocuted).
  final DiceExpression? turnStartDamage;
  final DamageType? turnStartDamageType;

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

  const StatusEffectDefinition({
    required this.id,
    required this.name,
    this.defaultDurationTurns,
    this.preventsActions = false,
    this.zeroedStats = const {},
    this.flatStatModifiers = const {},
    this.perRemainingTurnStatModifiers = const {},
    this.disadvantageRollTags = const {},
    this.advantageRollTags = const {},
    this.damageTypeInteractions = const [],
    this.turnStartDamage,
    this.turnStartDamageType,
    this.trionCapacityDrainPercentToCauser,
    this.vulnerableToRandomDamageTypesCount,
    this.locksRandomAbilityEachTurn = false,
    this.cannotTargetSource = false,
    this.sourceHasAdvantageAgainstTarget = false,
    this.rangedTargetsReducedByOne = false,
  });
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

  StatusEffectInstance({
    required this.definitionId,
    this.remainingTurns,
    this.sourceCharacterId,
    Map<String, Object?>? data,
  }) : data = data ?? {};
}

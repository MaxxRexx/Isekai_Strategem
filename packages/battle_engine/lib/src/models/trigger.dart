import 'damage_type.dart';
import 'passive_counter.dart';
import 'passive_effect.dart';
import 'reactive_effect.dart';
import 'unique_behavior.dart';
import '../util/dice.dart';

/// Broad equipment category for a Trigger.
enum TriggerCategory { attacker, shooter, sniper, trapper, optional }

/// What "kind" of energy/action underlies an ability. Used for
/// interactions that key off origin (e.g. resistances, future synergy
/// rules) independent of its damage type.
enum OriginTag { physical, energy, afflict, mental }

/// How far away a Trigger operates: the band the wielder has to be in to
/// use it.
///
/// Deliberately named apart from [AttackType], which also has melee and
/// ranged members but answers a different question. [AttackType] is *what
/// kind of attack this is* (a blade, a shot, or a psychic assault);
/// [RangeTag] is *how far away it reaches*. A psychic attack still sits in
/// one of these bands, and two Triggers of the same attack type can sit in
/// different ones.
///
/// [mid] was added in the balance pass. Before it the catalog only had
/// near and far, and every non-melee Trigger was lumped into far, which
/// made this tag perfectly derivable from the attack type and therefore
/// carrying no information of its own. The catalog is now split 20 / 20 /
/// 20 across the three bands by what each ability actually does, so the
/// band is a real property.
///
/// Mechanically [mid] and [long] behave identically today: everything that
/// keys off "is this attack made at a distance" uses [isAtRange], which is
/// true for both. The band only becomes a decision of its own once the
/// spatial pillar lands.
enum RangeTag { close, mid, long }

extension RangeTagReach on RangeTag {
  /// True for anything not made in contact. Every rule that cares about
  /// attacking from a distance - Threatened's and Blinded's penalties to
  /// ranged rolls, Blinded's cut to how many targets a ranged attack can
  /// reach, Frozen Tempo's cooldown sabotage - keys off this rather than
  /// naming a specific band, so adding or re-banding Triggers never
  /// silently changes which of them those rules apply to.
  bool get isAtRange => this != RangeTag.close;

  /// Player-facing name of the band.
  String get label => switch (this) {
        RangeTag.close => 'Close Range',
        RangeTag.mid => 'Mid Range',
        RangeTag.long => 'Long Range',
      };
}

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
  Set<AttackSubtype> get validSubtypes {
    switch (this) {
      case AttackType.melee:
        return {AttackSubtype.single, AttackSubtype.aoe, AttackSubtype.unique};
      case AttackType.ranged:
        return {
          AttackSubtype.single,
          AttackSubtype.burst,
          AttackSubtype.aoe,
          AttackSubtype.unique,
        };
      case AttackType.psychic:
        return {AttackSubtype.unique, AttackSubtype.single, AttackSubtype.aoe};
    }
  }
}

/// Who an active ability can be used on.
enum TargetAffiliation { opponent, ally, self }

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
///
/// A Trigger is either [ActiveTrigger] (costs Trion, has a cooldown, rolls
/// to hit/heal/inflict) or [PassiveTrigger] (always on while equipped, no
/// activation at all) - never both, so the two shapes are split into
/// separate classes rather than one class with a pile of nullable fields
/// that only make sense for one kind or the other.
sealed class Trigger {
  final String id;
  final String name;
  final TriggerCategory category;

  /// Trion cost paid once to equip this Trigger during the Loadout phase.
  final int equipCost;

  const Trigger({
    required this.id,
    required this.name,
    required this.category,
    required this.equipCost,
  });
}

/// An activated ability: costs Trion per use, has a cooldown, and rolls
/// to hit/heal/inflict a target.
class ActiveTrigger extends Trigger {
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

  /// Who this ability can be used on. Defaults to `opponent` (an attack);
  /// support abilities set this to `ally` or `self`.
  final TargetAffiliation targetAffiliation;

  final DamageType? damageType;
  final DiceExpression? damage;

  /// Instant heal on a landed hit, scaled by the recipient's own Team
  /// Spirit-driven Health Regeneration bonus. Health isn't a mechanic on
  /// its own per the design brief, so this (and the `regenerating` status
  /// effect for heal-over-time) are the only two ways health is restored.
  ///
  /// By default the recipient is whoever the ability's damage landed on
  /// (or the target, for a non-damaging support ability). If
  /// [healsCasterInstead] is true, the recipient is the ability's own
  /// user instead - a drain: damage the target, heal the caster off it
  /// (e.g. "Soul Siphon"). Only meaningful when [targetAffiliation] is
  /// `opponent`, since an ally/self-targeted heal already heals the
  /// caster or a chosen ally directly.
  final DiceExpression? healAmount;
  final bool healsCasterInstead;

  final List<StatusEffectApplication> inflictedStatusEffects;

  /// If non-null, using this ability arms a [ReactiveEffect] of the given
  /// [ReactiveKind] on the target (for self/ally-targeted counters) or on
  /// the caster (for opponent-targeted traps). The arm step is declarative
  /// (no roll, no separate resolution) and happens alongside normal
  /// ability resolution. The armed effect persists for
  /// [armsReactiveDefaultTurns] opponent turns unless triggered first.
  final ReactiveKind? armsReactive;

  /// How many opponent turns the armed reactive lasts before expiring on
  /// its own. Null means it only ends when triggered.
  final int? armsReactiveDefaultTurns;

  /// If non-null, this trigger uses unique-subtype resolution: the engine
  /// dispatches on this value instead of standard hit/damage/status flow.
  /// Only meaningful when [attackSubtype] is [AttackSubtype.unique].
  final UniqueBehavior? uniqueBehavior;

  ActiveTrigger({
    required super.id,
    required super.name,
    required super.category,
    required super.equipCost,
    required this.trionCost,
    required this.cooldownTurns,
    required this.originTag,
    required this.rangeTag,
    required this.attackType,
    required this.attackSubtype,
    this.hitsPerUse = 1,
    this.targetCount = 1,
    this.targetAffiliation = TargetAffiliation.opponent,
    this.damageType,
    this.damage,
    this.healAmount,
    this.healsCasterInstead = false,
    this.inflictedStatusEffects = const [],
    this.armsReactive,
    this.armsReactiveDefaultTurns,
    this.uniqueBehavior,
  }) : assert(
          attackType.validSubtypes.contains(attackSubtype),
          '$attackSubtype is not a valid subtype for $attackType',
        );
}

/// An always-on ability: no cooldown, no Trion cost, no targeting -
/// just a [PassiveEffect] applied for as long as it's equipped. If
/// [counterKind] is non-null, this trigger also activates a stateful
/// passive counter (see [PassiveCounterKind]) whose state machine the
/// engine tracks across the battle.
class PassiveTrigger extends Trigger {
  final PassiveEffect effect;

  /// If non-null, equipping this trigger activates a passive counter
  /// whose state the engine tracks in [CharacterBattleState]. The
  /// [PassiveEffect] may still carry stat buffs alongside the counter.
  final PassiveCounterKind? counterKind;

  const PassiveTrigger({
    required super.id,
    required super.name,
    required super.category,
    required super.equipCost,
    required this.effect,
    this.counterKind,
  });
}

/// What a status effect *does*, and whose side it is on, derived from the
/// fields the definition already declares.
///
/// This exists because of a playtest report: the status badges were too small
/// to read. The measurement behind the fix found the real problem was not
/// size. All 62 effects drew one shared icon in one shared colour, so a bleed
/// killing a character and a ward protecting them were the same picture, and
/// the two 8-pixel numbers in the corners were the only differentiated pixels
/// on the badge. Making it bigger would have produced a bigger picture that
/// still meant nothing.
///
/// The catalogue is far narrower than 62 suggests: those effects do about
/// **fourteen different things**. That is a learnable icon set, where 62 is
/// not. Nothing here is a hand-kept list, so an effect written tomorrow gets
/// the right glyph and the right colour the day it is written, and an effect
/// re-tuned in wave 4 re-classifies itself.
library;

import 'status_effect.dart';

/// The kind of thing an effect does. One glyph each, in a picker or on a
/// badge.
///
/// Deliberately coarse. A badge is ten pixels of glyph, so it answers "what
/// sort of thing is happening to me"; the exact stat and magnitude are what
/// the description is for. The order of the cases is the order they are
/// tested in ([StatusRoleX.role]), which is the order of how much the effect
/// changes about a turn: losing the turn outright beats losing two points of
/// Armor.
enum StatusRole {
  /// The holder does not act at all (Stunned, Frozen, Petrified).
  actionDenied,

  /// The holder acts, but something they could normally do is closed off: a
  /// heal they cannot receive, an ability locked, a line they cannot step to.
  optionDenied,

  /// Health comes off every turn (Bleeding, Scorched).
  damageOverTime,

  /// Health goes back on every turn (Regenerating).
  healOverTime,

  /// Trion is moved out of the holder's squad and into the causer's (Sapped).
  trionDrain,

  /// Incoming damage is reduced, or cannot be aimed at them at all
  /// (Guarded, Untargetable).
  takesLess,

  /// Incoming damage is increased (Exposed, Marked).
  takesMore,

  /// Outgoing damage is increased (Empowered).
  dealsMore,

  /// Outgoing damage is reduced (Weakened).
  dealsLess,

  /// A stat steps up, or a roll gains advantage (Inspired, Braced, Focused).
  statUp,

  /// A stat steps down, or a roll takes disadvantage (Acid, Poisoned).
  statDown,

  /// A stat is taken to zero outright, which is a different kind of problem
  /// from a step (Shattered Guard, Sealed, Overwhelmed).
  statZeroed,

  /// The holder's own attacks go wrong: forced to miss, redirected onto
  /// their own side, or aimed by something other than the player
  /// (Scramble, Enraged, Charmed, Reckoning).
  aimSpoiled,

  /// Everything the rule cannot read as one of the above. A glyph of its own
  /// rather than a silent default, so "this one is unusual, tap it" is
  /// itself the message.
  special,
}

/// Whose side an effect is on, from the point of view of whoever carries it.
///
/// Redundant with [StatusRole] on purpose. The accessibility guidance behind
/// this whole change is that no single channel should carry the meaning
/// alone: shape says what kind, colour says whose side, and either one alone
/// is enough to tell a bleed from a ward.
enum StatusValence { helpful, harmful, neutral }

extension StatusRoleX on StatusEffectDefinition {
  /// What this effect does, in one of [StatusRole]'s fourteen answers.
  ///
  /// First match wins, and the order is deliberate: an effect that both
  /// denies the turn and ticks damage is described by the denial, because
  /// that is the one that changes what the player can do about it.
  StatusRole get role {
    if (preventsActions) return StatusRole.actionDenied;
    if (turnStartDamage != null) return StatusRole.damageOverTime;
    if (turnStartHeal != null) return StatusRole.healOverTime;
    if (trionCapacityDrainPercentToCauser != null) return StatusRole.trionDrain;

    // Not being targetable at all is the strongest form of taking less.
    if (preventsTargeting) return StatusRole.takesLess;
    final taken = allDamageTakenMultiplier;
    if (taken != null) {
      return taken < 1 ? StatusRole.takesLess : StatusRole.takesMore;
    }
    // Above the damage multipliers on purpose. Enraged hits harder *and*
    // picks its own targets, and the catalogue's own note calls the aiming
    // the cost: losing the choice of who to hit is what changes the turn.
    if (_spoilsAim) return StatusRole.aimSpoiled;

    final dealt = outgoingDamageMultiplier;
    if (dealt != null) {
      return dealt > 1 ? StatusRole.dealsMore : StatusRole.dealsLess;
    }
    if (zeroedStats.isNotEmpty) return StatusRole.statZeroed;

    final steps = _statSteps.toList();
    if (steps.isNotEmpty) {
      return steps.every((v) => v > 0) ? StatusRole.statUp : StatusRole.statDown;
    }
    if (disadvantageRollTags.isNotEmpty) return StatusRole.statDown;
    if (advantageRollTags.isNotEmpty) return StatusRole.statUp;

    if (_closesAnOption) return StatusRole.optionDenied;
    return StatusRole.special;
  }

  /// Whose side this effect is on.
  ///
  /// Counted rather than looked up: an effect is helpful if every signal it
  /// declares helps its holder, harmful if every signal hurts them, and
  /// neutral if it carries both. That last case is not a failure to decide,
  /// it is the answer. Enraged buys damage and Psychic immunity at the cost
  /// of choosing your own targets; the Vow of the Duel buys damage and
  /// closes off healing. Painting either of them green or red would be a
  /// claim the effect does not support.
  StatusValence get valence {
    final helps = _helpfulSignals;
    final hurts = _harmfulSignals;
    if (helps > 0 && hurts == 0) return StatusValence.helpful;
    if (hurts > 0 && helps == 0) return StatusValence.harmful;
    return StatusValence.neutral;
  }

  int get _helpfulSignals {
    var n = 0;
    if (turnStartHeal != null) n++;
    if (preventsTargeting) n++;
    if ((allDamageTakenMultiplier ?? 1) < 1) n++;
    if ((outgoingDamageMultiplier ?? 1) > 1) n++;
    if ((trionCostMultiplier ?? 1) < 1) n++;
    if (advantageRollTags.isNotEmpty) n++;
    n += _statSteps.where((v) => v > 0).length;
    n += damageTypeInteractions
        .where((r) => r.kind == DamageInteractionKind.immune)
        .length;
    return n;
  }

  int get _harmfulSignals {
    var n = 0;
    if (preventsActions) n++;
    if (turnStartDamage != null) n++;
    if (trionCapacityDrainPercentToCauser != null) n++;
    if ((allDamageTakenMultiplier ?? 1) > 1) n++;
    if ((outgoingDamageMultiplier ?? 1) < 1) n++;
    if ((trionCostMultiplier ?? 1) > 1) n++;
    if ((repeatAbilityDamageMultiplier ?? 1) < 1) n++;
    if (disadvantageRollTags.isNotEmpty) n++;
    if (zeroedStats.isNotEmpty) n++;
    if (vulnerableToRandomDamageTypesCount != null) n++;
    if (sharesMagnitudeWithBoundEnemy) n++;
    if (_spoilsAim) n++;
    if (_closesAnOption) n++;
    n += _statSteps.where((v) => v < 0).length;
    n += damageTypeInteractions
        .where((r) => r.kind == DamageInteractionKind.vulnerable)
        .length;
    return n;
  }

  Iterable<double> get _statSteps => [
        ...flatStatModifiers.values,
        ...perRemainingTurnStatModifiers.values,
      ];

  /// The holder's own offence is compromised: they miss, they hit the wrong
  /// thing, or somebody else is choosing the target.
  bool get _spoilsAim =>
      forcesNextAttackMiss ||
      forcesNextAttackCriticalMiss ||
      misfireChance != null ||
      randomizesOwnTargeting ||
      cannotTargetSource ||
      sourceHasAdvantageAgainstTarget ||
      rangedTargetsReducedByOne;

  /// Something the holder could otherwise do is shut off, without any number
  /// moving.
  bool get _closesAnOption =>
      preventsHealing ||
      preventsAllyInteraction ||
      preventsReposition ||
      locksOriginFromData ||
      locksRandomAbilityEachTurn ||
      locksToSingleChosenAbility ||
      forcesRepetitionOfLastAbility;

}

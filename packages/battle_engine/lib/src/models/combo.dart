import 'trigger.dart';

/// Combat-v2 Phase I (Combo Recognition). A deterministic, data-driven
/// record of one resolved action, kept in a per-turn [ComboLedger] so the
/// [ComboRecognizer] can tell whether a later "payoff" action completes a
/// real combo (setup -> payoff, focus fire, affliction detonate, ...).
///
/// This is pure data (no engine types) so the recognizer and its catalog
/// stay in the models layer and fully unit-testable: build a ledger + a
/// payoff by hand and assert which combos fire.
class ComboLedgerEntry {
  final String actorId;

  /// The team the actor belongs to (so the recognizer can require a combo's
  /// setup and payoff to come from the *same* team).
  final String teamId;

  final String triggerId;
  final OriginTag originTag;
  final AttackType attackType;
  final AttackSubtype attackSubtype;
  final TargetAffiliation targetAffiliation;

  /// Character ids this action actually resolved against (post targeting).
  final List<String> targetIds;

  /// Status effect ids this action successfully applied to its targets.
  final List<String> statusesApplied;

  /// Whether this action dealt any damage (for focus-fire recognition).
  final bool dealtDamage;

  /// Monotonic order within the turn (0-based), so "prior" is well defined.
  final int sequence;

  const ComboLedgerEntry({
    required this.actorId,
    required this.teamId,
    required this.triggerId,
    required this.originTag,
    required this.attackType,
    required this.attackSubtype,
    required this.targetAffiliation,
    required this.targetIds,
    required this.statusesApplied,
    required this.dealtDamage,
    required this.sequence,
  });

  /// This action's primary target (first resolved target), or null if it
  /// had none (self-only / untargeted).
  String? get primaryTargetId => targetIds.isEmpty ? null : targetIds.first;

  bool get isOffensive => targetAffiliation == TargetAffiliation.opponent;
}

/// Everything a [ComboCondition] evaluates against for one payoff: the
/// payoff action itself, the same-team actions that already resolved this
/// turn (the potential "setups"), and a little live state about the
/// payoff's primary target.
class ComboContext {
  final ComboLedgerEntry payoff;

  /// Same-team actions that resolved earlier this turn (sequence <
  /// payoff.sequence). Enemy actions and the payoff itself are excluded.
  final List<ComboLedgerEntry> priorSameTeamActions;

  /// The payoff primary target's current status ids (empty if no target).
  final Set<String> targetStatusIds;

  /// The payoff primary target's current-health fraction in [0, 1] (1 when
  /// there is no target, so hp-gated combos simply do not fire).
  final double targetHpFraction;

  const ComboContext({
    required this.payoff,
    required this.priorSameTeamActions,
    this.targetStatusIds = const {},
    this.targetHpFraction = 1.0,
  });

  String? get targetId => payoff.primaryTargetId;
}

/// A closed, composable predicate over a [ComboContext]. New combo shapes
/// add a leaf here rather than running open scripts, matching the engine's
/// enumerable-behaviour discipline ([UniqueBehavior] / reactive kinds).
sealed class ComboCondition {
  const ComboCondition();
  bool matches(ComboContext ctx);
}

class AllOf extends ComboCondition {
  final List<ComboCondition> conditions;
  const AllOf(this.conditions);
  @override
  bool matches(ComboContext ctx) => conditions.every((c) => c.matches(ctx));
}

class AnyOf extends ComboCondition {
  final List<ComboCondition> conditions;
  const AnyOf(this.conditions);
  @override
  bool matches(ComboContext ctx) => conditions.any((c) => c.matches(ctx));
}

class NotCombo extends ComboCondition {
  final ComboCondition condition;
  const NotCombo(this.condition);
  @override
  bool matches(ComboContext ctx) => !condition.matches(ctx);
}

/// The payoff is an offensive action (targets an opponent).
class PayoffIsOffensive extends ComboCondition {
  const PayoffIsOffensive();
  @override
  bool matches(ComboContext ctx) => ctx.payoff.isOffensive;
}

/// The payoff's origin is [origin] (e.g. energy detonating an affliction).
class PayoffOrigin extends ComboCondition {
  final OriginTag origin;
  const PayoffOrigin(this.origin);
  @override
  bool matches(ComboContext ctx) => ctx.payoff.originTag == origin;
}

/// The payoff's primary target currently carries one of [statusIds].
class TargetHasAnyStatus extends ComboCondition {
  final Set<String> statusIds;
  const TargetHasAnyStatus(this.statusIds);
  @override
  bool matches(ComboContext ctx) =>
      ctx.targetStatusIds.any(statusIds.contains);
}

/// A same-team ally, earlier this turn, applied one of [statusIds] to the
/// payoff's primary target (the setup half of a setup -> payoff combo).
class AllyAppliedStatusToTarget extends ComboCondition {
  final Set<String> statusIds;
  const AllyAppliedStatusToTarget(this.statusIds);
  @override
  bool matches(ComboContext ctx) {
    final target = ctx.targetId;
    if (target == null) return false;
    return ctx.priorSameTeamActions.any((e) =>
        e.targetIds.contains(target) &&
        e.statusesApplied.any(statusIds.contains));
  }
}

/// A same-team ally, earlier this turn, already struck (dealt damage to)
/// the payoff's primary target (focus fire).
class AllyStruckTarget extends ComboCondition {
  const AllyStruckTarget();
  @override
  bool matches(ComboContext ctx) {
    final target = ctx.targetId;
    if (target == null) return false;
    return ctx.priorSameTeamActions
        .any((e) => e.dealtDamage && e.targetIds.contains(target));
  }
}

/// The payoff's primary target is at or below [fraction] of max health.
class TargetHpBelow extends ComboCondition {
  final double fraction;
  const TargetHpBelow(this.fraction);
  @override
  bool matches(ComboContext ctx) =>
      ctx.targetId != null && ctx.targetHpFraction <= fraction;
}

// --- Identity leaves (Layer-2 / signature combos) -----------------------
// These key off specific trigger / character ids so authored combos can
// name the exact abilities and characters that make a signature play.

/// The payoff was cast with one of [triggerIds].
class PayoffUsesTrigger extends ComboCondition {
  final Set<String> triggerIds;
  const PayoffUsesTrigger(this.triggerIds);
  @override
  bool matches(ComboContext ctx) => triggerIds.contains(ctx.payoff.triggerId);
}

/// The payoff's actor is one of [characterIds].
class PayoffActorIs extends ComboCondition {
  final Set<String> characterIds;
  const PayoffActorIs(this.characterIds);
  @override
  bool matches(ComboContext ctx) => characterIds.contains(ctx.payoff.actorId);
}

/// A same-team ally, earlier this turn, used one of [triggerIds] against the
/// payoff's primary target (the setup half of a named signature chain).
class AllyUsedTriggerOnTarget extends ComboCondition {
  final Set<String> triggerIds;
  const AllyUsedTriggerOnTarget(this.triggerIds);
  @override
  bool matches(ComboContext ctx) {
    final target = ctx.targetId;
    if (target == null) return false;
    return ctx.priorSameTeamActions.any((e) =>
        triggerIds.contains(e.triggerId) && e.targetIds.contains(target));
  }
}

/// One recognizable combo: a matchable [condition], a display [name] /
/// [flavor], and a [strength] that downstream effects (TEG Effect 4's
/// advantage, Effect 3's Trion refund) scale their reward by.
class ComboDefinition {
  final String id;
  final String name;
  final String flavor;
  final ComboCondition condition;
  final int strength;

  /// True for setup->payoff combos (a payoff exploiting a control/debuff an
  /// ally applied to the target). TEG Effect 3's Trion refund is granted only
  /// for these; focus-fire / affliction combos amplify (Effect 4) but do not
  /// refund.
  final bool isSetupPayoff;

  const ComboDefinition({
    required this.id,
    required this.name,
    required this.flavor,
    required this.condition,
    this.strength = 1,
    this.isSetupPayoff = false,
  });
}

/// A [ComboDefinition] that matched a given payoff.
class RecognizedCombo {
  final ComboDefinition definition;
  const RecognizedCombo(this.definition);

  String get id => definition.id;
  int get strength => definition.strength;
  bool get isSetupPayoff => definition.isSetupPayoff;
}

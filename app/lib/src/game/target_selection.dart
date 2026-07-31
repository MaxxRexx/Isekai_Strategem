/// Pure helpers describing how the battle screen's portrait-based target
/// picker behaves for a given ability, factored out of the widget so the
/// rules can be unit-tested against the whole trigger catalog.
///
/// The picker has three shapes:
/// - Self-cast: the caster's own portrait is auto-highlighted, nothing to
///   pick.
/// - Area of effect: every legal target is auto-highlighted (capped at how
///   many the ability may actually hit), nothing to pick.
/// - Everything else (single / unique / burst against opponents or allies):
///   the player picks targets by tapping portraits, up to `maxTargets`.
library;

import 'package:battle_engine/battle_engine.dart';

/// Whether [trigger] leaves target choice up to the player (tapping
/// portraits) rather than auto-selecting them. True for single/unique/burst
/// against opponents or allies; false for self-cast and AoE.
bool awaitingManualTargets(ActiveTrigger trigger) =>
    trigger.targetAffiliation != TargetAffiliation.self &&
    trigger.attackSubtype != AttackSubtype.aoe;

/// The targets highlighted automatically the moment [trigger] is selected,
/// before any portrait taps:
/// - self-cast -> the caster alone,
/// - AoE -> every legal target it can hit (never more than [maxTargets]),
/// - otherwise -> none (the player picks them).
///
/// The result is always a subset of [legalTargetIds] (for self-cast the
/// caster is assumed to be its own legal target) and never longer than
/// [maxTargets].
List<String> autoSelectedTargets(
  ActiveTrigger trigger,
  String casterId,
  List<String> legalTargetIds,
  int maxTargets,
) {
  if (trigger.targetAffiliation == TargetAffiliation.self) {
    return [casterId];
  }
  if (trigger.attackSubtype == AttackSubtype.aoe) {
    return legalTargetIds.take(maxTargets).toList();
  }
  return const [];
}

/// Pure helpers describing how the battle screen's portrait-based target
/// picker behaves for a given ability, factored out of the widget so the
/// rules can be unit-tested against the whole trigger catalog.
///
/// The picker has three shapes:
/// - Self-cast: the caster's own portrait is auto-highlighted, nothing to
///   pick.
/// - Area of effect: the player picks a **line** by tapping anyone standing
///   on it, and everyone legal on that line is highlighted together.
/// - Everything else (single / unique / burst against opponents or allies):
///   the player picks targets by tapping portraits, up to `maxTargets`.
library;

import 'package:battle_engine/battle_engine.dart';

/// Whether [trigger] leaves target choice up to the player (tapping
/// portraits) rather than auto-selecting them. True for everything except
/// self-cast.
///
/// An area ability used to auto-select every target it could reach, across
/// every line. That promised something the rules do not deliver: an area
/// ability catches **one line**, so the engine quietly narrowed the list to
/// whichever line the first target happened to be standing on. The highlight
/// said three characters, the queue said three, and one line's worth of them
/// were affected. It is a choice now, because it always was one.
bool awaitingManualTargets(ActiveTrigger trigger) =>
    trigger.targetAffiliation != TargetAffiliation.self;

/// The targets highlighted automatically the moment [trigger] is selected,
/// before any portrait taps: the caster alone for a self-cast, and nothing
/// for anything else.
List<String> autoSelectedTargets(
  ActiveTrigger trigger,
  String casterId,
  List<String> legalTargetIds,
  int maxTargets,
) {
  if (trigger.targetAffiliation == TargetAffiliation.self) {
    return [casterId];
  }
  return const [];
}

/// Who an area ability catches when it is aimed at [tappedId]: everyone legal
/// standing on the same line, capped at how many it may actually affect.
///
/// This is the whole of what "area" means in this game. It is the same rule
/// for a buff over your own line as for an attack across theirs, and it is
/// what makes the highlight, the queue and the resolution agree.
List<String> lineTargets({
  required String tappedId,
  required List<String> legalTargetIds,
  required BattlePosition Function(String id) positionOf,
  required int maxTargets,
}) {
  final line = positionOf(tappedId);
  return [
    for (final id in legalTargetIds)
      if (positionOf(id) == line) id,
  ].take(maxTargets).toList();
}

import 'trigger.dart';

/// The id a Reposition records against its action slot. Not a real Trigger,
/// so nothing that scans used-Trigger ids will ever match it.
const String repositionActionId = '__reposition__';

/// Where a character is standing on the battlefield.
///
/// The two squads face each other across a gap, so how far apart two
/// characters are depends on both of them, and it depends on which side
/// each one is on:
///
///  - **To an enemy, the two positions add.** You are on opposite sides of
///    the gap, so you hanging back and them hanging back both widen it.
///    Range 0 to 4.
///  - **To an ally, the two positions subtract.** You are on the same side,
///    so only the difference between you matters. Range 0 to 2.
///
/// That single asymmetry is what makes position a decision rather than a
/// number. A Front attacker sits 2 away from an enemy Back sniper, which is
/// outside every Close Range ability, so reaching that sniper needs either a
/// Long Range melee ability (a lunge that crosses the gap) or for the sniper
/// to be forced forward.
enum BattlePosition {
  front(0),
  middle(1),
  back(2);

  const BattlePosition(this.step);

  /// How far back this position stands, 0 at the front through 2 at the
  /// back. This is the number the distance rules add or subtract.
  final int step;

  String get label => switch (this) {
        BattlePosition.front => 'Front',
        BattlePosition.middle => 'Middle',
        BattlePosition.back => 'Back',
      };

  /// The position one step further forward, or null when already at Front.
  BattlePosition? get forward => switch (this) {
        BattlePosition.front => null,
        BattlePosition.middle => BattlePosition.front,
        BattlePosition.back => BattlePosition.middle,
      };

  /// The position one step further back, or null when already at Back.
  BattlePosition? get backward => switch (this) {
        BattlePosition.front => BattlePosition.middle,
        BattlePosition.middle => BattlePosition.back,
        BattlePosition.back => null,
      };

  /// Every position reachable in a single Reposition action from here.
  List<BattlePosition> get adjacent =>
      [if (forward != null) forward!, if (backward != null) backward!];
}

/// The distance rules. Kept as plain functions on the two positions rather
/// than as methods on battle state, so they can be reasoned about and
/// tested without constructing a battle.
abstract final class BattleDistance {
  /// Distance between two characters on **opposite** sides of the gap.
  /// The positions add, giving 0 (both pressed all the way forward) to 4
  /// (both hanging all the way back).
  static int betweenEnemies(BattlePosition a, BattlePosition b) =>
      a.step + b.step;

  /// Distance between two characters on the **same** side. Only the
  /// difference matters, giving 0 (standing together) to 2 (opposite ends
  /// of your own formation).
  static int betweenAllies(BattlePosition a, BattlePosition b) =>
      (a.step - b.step).abs();

  /// The widest gap that can exist between two enemies.
  static const int maxEnemyDistance = 4;
}

/// How far each [RangeTag] can operate.
///
/// Each band is a *window*, not a ceiling. Close cannot reach across the
/// field, and, just as importantly, Long has a minimum: a sniper caught in a
/// scrum has no shot. The windows overlap in the middle, so at most
/// distances a character has two bands available and therefore a choice,
/// while distance 0 allows only Close and distance 4 only Long.
extension RangeTagReachWindow on RangeTag {
  /// Closest distance this band can operate at.
  int get minDistance => switch (this) {
        RangeTag.close => 0,
        RangeTag.mid => 1,
        RangeTag.long => 2,
      };

  /// Furthest distance this band can operate at.
  int get maxDistance => switch (this) {
        RangeTag.close => 1,
        RangeTag.mid => 3,
        RangeTag.long => 4,
      };

  /// Whether an ability in this band works at [distance].
  bool reaches(int distance) =>
      distance >= minDistance && distance <= maxDistance;

  /// Human-readable window, e.g. "0 to 1".
  String get windowLabel => '$minDistance to $maxDistance';
}

/// Where a character should start, given the range bands their Loadout
/// actually carries.
///
/// Derived from the Loadout rather than from the character's type or the
/// Trigger category, because the Loadout is what decides which distances
/// they can operate at. A kit full of Close Range work wants to start at
/// the Front where those abilities reach; a sniper's kit wants the Back.
/// Ties, and an empty Loadout, fall to Middle, which is the band with the
/// widest reach and therefore the safest default.
BattlePosition startingPositionFor(Iterable<RangeTag> equippedBands) {
  final counts = <RangeTag, int>{};
  for (final band in equippedBands) {
    counts[band] = (counts[band] ?? 0) + 1;
  }
  if (counts.isEmpty) return BattlePosition.middle;

  final close = counts[RangeTag.close] ?? 0;
  final mid = counts[RangeTag.mid] ?? 0;
  final long = counts[RangeTag.long] ?? 0;

  // Middle wins ties on purpose: it is the only position from which both
  // of the other bands are one step away.
  if (close > mid && close > long) return BattlePosition.front;
  if (long > mid && long > close) return BattlePosition.back;
  return BattlePosition.middle;
}

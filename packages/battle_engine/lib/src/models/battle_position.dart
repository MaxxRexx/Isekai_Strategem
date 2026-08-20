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
  /// Distance from a character at [a] to an enemy at [b], on **opposite**
  /// sides of the gap.
  ///
  /// The two lines add, because you hanging back and them hanging back both
  /// widen the gap, and then **screening** adds the bodies in the way: see
  /// [screensFor]. So the number runs 0 (both squads pressed all the way
  /// forward) to 6 (both hanging all the way back, with the target shielded
  /// by two squadmates).
  ///
  /// [targetSquad] is where **[b]'s own living squad** is standing, which is
  /// the only thing that screens them. Passing [b] itself inside it is
  /// harmless, since nobody screens themselves. It is required rather than
  /// optional on purpose: an omitted squad would silently compute the old
  /// unscreened distance, and every caller in the game has the squad to hand.
  /// Pass `const []` only where the raw geometry is genuinely what is wanted,
  /// and say why.
  static int betweenEnemies(
    BattlePosition a,
    BattlePosition b, {
    required Iterable<BattlePosition> targetSquad,
  }) =>
      a.step + b.step + screensFor(b, targetSquad);

  /// How many of [targetSquad] are screening a character standing at
  /// [target]: those on a line **strictly in front** of them, on their own
  /// side.
  ///
  /// Screening is a property of the *line*, not of the character. Two enemies
  /// standing together always have the same number of bodies in front of
  /// them, which is why the battlefield strip can print one distance per line
  /// rather than one per enemy.
  ///
  /// Only living squadmates screen. Killing a screen is how a back-line
  /// target is brought within reach, and that is the whole point of the rule:
  /// a squad stacked on one line screens nobody, so camping stops working of
  /// its own accord.
  static int screensFor(
    BattlePosition target,
    Iterable<BattlePosition> targetSquad,
  ) =>
      targetSquad.where((p) => p.step < target.step).length;

  /// Distance between two characters on the **same** side. Only the
  /// difference matters, giving 0 (standing together) to 2 (opposite ends
  /// of your own formation). Screening does not apply: your own squad does
  /// not block a heal handed to the person beside you.
  static int betweenAllies(BattlePosition a, BattlePosition b) =>
      (a.step - b.step).abs();

  /// The widest gap that can exist between two enemies: both back lines,
  /// plus two screens. Larger than any band reaches, which is deliberate and
  /// safe. Measured from your own **front** line the distance never exceeds
  /// [RangeTagReachWindow.maxDistance] for Long Range, so a character who can
  /// walk forward always has a shot; 5 and 6 only ever mean "I chose to stand
  /// too far back". Guarded by `battle_position_test`.
  static const int maxEnemyDistance = 6;

  /// The widest gap the two lines alone can produce, before screening. The
  /// old value of [maxEnemyDistance], kept because it is still the ceiling
  /// on an unscreened board and on every ally-side question.
  static const int maxUnscreenedEnemyDistance = 4;
}

/// How far each [RangeTag] can operate.
///
/// Each band is a *window*, not a ceiling. Close cannot reach across the
/// field, and, just as importantly, Long has a minimum: a sniper caught in a
/// scrum has no shot. The windows overlap in the middle, so at most
/// distances a character has two bands available and therefore a choice,
/// while distance 0 allows only Close and distance 4 only Long.
///
/// A band carries **two** maximums, because the two questions are different.
/// Against an enemy the whole window applies. Towards an ally only a maximum
/// applies, and it is a tighter one for Close Range: widening Close to 0-2
/// was decided to let Close Range *attacks* reach an enemy back line, and
/// letting it widen the ally side too would have quietly handed three
/// defensive abilities the whole formation instead of a neighbouring line.
extension RangeTagReachWindow on RangeTag {
  /// Closest distance this band can operate at against an enemy.
  int get minDistance => switch (this) {
        RangeTag.close => 0,
        RangeTag.mid => 1,
        RangeTag.long => 2,
      };

  /// Furthest distance this band can operate at **against an enemy**.
  int get maxDistance => switch (this) {
        RangeTag.close => 2,
        RangeTag.mid => 3,
        RangeTag.long => 4,
      };

  /// Furthest distance this band can operate at **towards an ally**, where
  /// only a maximum applies (see `TurnEngine.canReach`).
  ///
  /// Mid and Long match their enemy-facing maximums, which is no constraint
  /// at all since two allies are never more than 2 apart. Close stays at 1,
  /// so a Close Range ward still reaches only a neighbouring line.
  int get allyMaxDistance => switch (this) {
        RangeTag.close => 1,
        RangeTag.mid => 3,
        RangeTag.long => 4,
      };

  /// Whether an ability in this band works at [distance] against an enemy.
  bool reaches(int distance) =>
      distance >= minDistance && distance <= maxDistance;

  /// Whether an ability in this band reaches an ally [distance] away.
  bool reachesAlly(int distance) => distance <= allyMaxDistance;

  /// Human-readable enemy-facing window, e.g. "0 to 2".
  String get windowLabel => '$minDistance to $maxDistance';

  /// Human-readable ally-facing reach, e.g. "up to 1".
  String get allyWindowLabel => 'up to $allyMaxDistance';
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

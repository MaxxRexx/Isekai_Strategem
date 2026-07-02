/// The tier rolled for a team's per-turn Trion gain.
enum TrionTier { low, medium, high }

/// The team's shared in-battle Trion resource (a single untyped pool,
/// replenished each turn via a tier roll and spent on ability Trion
/// costs). Distinct from the per-character `Stats.trionCapacity`, which
/// only gates the pre-match Loadout phase.
class TrionPool {
  int current;
  final int? cap;

  TrionPool({this.current = 0, this.cap});

  void gain(int amount) {
    current += amount;
    if (cap != null && current > cap!) current = cap!;
  }

  /// Attempts to spend [amount]; returns false (no state change) if the
  /// pool doesn't have enough.
  bool trySpend(int amount) {
    if (amount > current) return false;
    current -= amount;
    return true;
  }
}

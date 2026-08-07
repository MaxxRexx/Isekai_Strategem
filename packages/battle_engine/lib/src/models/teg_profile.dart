/// Combat-v2 section 5.2, TEG Effects 1 / 2 / 5. A per-team "combination
/// amplifier" roll profile, computed app-side from the team's Team
/// Efficiency Grade and injected into the engine. The engine never reads
/// the grade itself - it only consumes these three numbers, so the pure
/// engine stays decoupled from the app-layer TEG scoring (the coupling that
/// killed the old cross-team tiebreak).
class TegRollProfile {
  /// Effect 1 (Coordination): percent chance in [0, 100] that a qualifying
  /// OFFENSIVE roll (attack to-hit; later, status infliction) gains
  /// advantage. Scales up with grade (D 0% -> SSS 20%).
  final int offenseAdvantagePercent;

  /// Effect 2 (Operator's Read, inverted): percent chance in [0, 100] that a
  /// DEFENSIVE roll (the defender's contest; later, status resistance) gains
  /// advantage. Scales DOWN with grade (D 20% -> SSS 0%).
  final int defenseAdvantagePercent;

  /// Effect 5 (Crit Range Widener, SSS only): the ceiling on this team's
  /// natural-die crit threshold. 18 at SSS (crit on nat 18-20), 20 otherwise.
  /// The engine crits when the kept die >= min(computed threshold, this).
  final int maxCritThreshold;

  /// Effect 3 (Synergy Refunds): percent of a setup->payoff combo's Trion
  /// cost refunded to the team. Scales up to SS (20%); SSS is 0% (it takes
  /// Effect 5 instead). 0 grants no refund.
  final int trionRefundPercent;

  const TegRollProfile({
    this.offenseAdvantagePercent = 0,
    this.defenseAdvantagePercent = 0,
    this.maxCritThreshold = 20,
    this.trionRefundPercent = 0,
  });

  /// A no-op profile (used when a character has no injected TEG data, e.g.
  /// a standalone-engine test). Grants nothing and never widens crits.
  static const TegRollProfile none = TegRollProfile();
}

import 'team_efficiency.dart';

/// Combat-v2 section 5.2 / 15.8: the **inverse-TEG battle-XP counterweight**.
/// A weaker-graded squad earns more post-battle XP (a fast-leveling underdog),
/// while an elite squad pays an "elite tax" - so the Team Efficiency Grade is a
/// risk/reward dial rather than a strictly-better stat. These are the spec's
/// first-pass numbers (tunable, Phase H).
///
/// IMPORTANT: this is only the shared *formula*. The design requires real
/// player XP to be **server-authoritative** (section 15): the server applies
/// this multiplier at battle end from a client-reported, server-validated
/// result. This function is safe for a client-side *preview* of the reward,
/// but must NOT be trusted as the source of truth for a player's XP. Wiring it
/// to an account system + XP ledger is the remaining product task.
int battleXpBonusPercentFor(TegTier tier) => switch (tier) {
  TegTier.d => 75,
  TegTier.c => 63,
  TegTier.b => 51,
  TegTier.a => 40,
  TegTier.s => 28,
  TegTier.ss => 16,
  TegTier.sss => 5,
};

/// The multiplier applied to base battle XP for a squad at [tier]
/// (`1 + bonus%`), e.g. D -> 1.75x, SSS -> 1.05x.
double battleXpMultiplierFor(TegTier tier) =>
    1 + battleXpBonusPercentFor(tier) / 100;

/// Scales [baseXp] by the inverse-TEG multiplier for [tier]. See the note above:
/// the authoritative award must happen server-side.
int awardBattleXp(int baseXp, TegTier tier) =>
    (baseXp * battleXpMultiplierFor(tier)).round();

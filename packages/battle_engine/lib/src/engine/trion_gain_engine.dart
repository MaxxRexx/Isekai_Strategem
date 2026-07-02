import '../constants.dart';
import '../models/trion.dart';
import '../util/dice.dart';

class TrionGainResult {
  final TrionTier tier;
  final int amount;

  const TrionGainResult(this.tier, this.amount);
}

/// Resolves the per-turn Trion tier roll.
///
/// ## Design note (flagged ambiguity)
/// The brief specifies "Probability of a higher tier = base chance + sum
/// of team's living members' Trion Affinity + active gameplay modifiers"
/// but Trion gain has three tiers (Low/Medium/High), and it's not
/// specified whether that's one three-way weighted roll or something
/// else. This engine models it as **two sequential upgrade checks**:
/// start at Low, roll to upgrade to Medium, and if that succeeds, roll
/// again to upgrade to High. Both steps reuse the exact formula from the
/// brief (with independently tunable base chances), which lets a single
/// additive modifier (e.g. "+10% chance for 2 turns") cleanly apply to
/// "the chance of a higher tier" at every step, matching the wording
/// literally. Revisit if a different tier model was actually intended.
class TrionGainEngine {
  final TrionTierConfig config;
  final DiceRoller diceRoller;

  TrionGainEngine({
    this.config = TrionTierConfig.defaults,
    DiceRoller? diceRoller,
  }) : diceRoller = diceRoller ?? DiceRoller();

  /// Rolls this turn's Trion tier and resulting amount.
  ///
  /// [sumLivingTrionAffinity] is the sum of Trion Affinity across all
  /// living members of the team. [modifier] is the net of any active
  /// temporary gameplay modifiers (positive raises the odds of a higher
  /// tier, negative lowers them); pass 0 if none are active.
  TrionGainResult rollTier({
    required int sumLivingTrionAffinity,
    double modifier = 0,
  }) {
    final base =
        sumLivingTrionAffinity * config.affinityWeightPerPoint + modifier;

    final chanceToMedium =
        (config.baseChanceLowToMedium + base).clamp(0.0, 1.0);
    if (diceRoller.random.nextDouble() >= chanceToMedium) {
      return TrionGainResult(TrionTier.low, config.lowAmount);
    }

    final chanceToHigh = (config.baseChanceMediumToHigh + base).clamp(0.0, 1.0);
    if (diceRoller.random.nextDouble() >= chanceToHigh) {
      return TrionGainResult(TrionTier.medium, config.mediumAmount);
    }

    return TrionGainResult(TrionTier.high, config.highAmount);
  }
}

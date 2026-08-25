import 'dart:math';

/// Net roll mode after combining every advantage/disadvantage source that
/// applies to a single roll.
enum RollMode { normal, advantage, disadvantage }

/// Composable source list for advantage/disadvantage.
///
/// Multiple sources of advantage don't stack with each other, multiple
/// sources of disadvantage don't stack with each other, and if a roll has
/// at least one of each they cancel out to a normal roll. This mirrors the
/// common tabletop convention and is the simplest rule that lets many
/// independent effects (abilities, status effects, terrain, etc.) each
/// contribute a source without needing to know about one another.
///
/// This is an explicit design choice for an underspecified rule ("keep
/// this composable, a character can have advantage/disadvantage from
/// multiple stacking sources") - stacking sources change the *chance* an
/// advantage/disadvantage state is active in future extensions (e.g. a
/// source that grants advantage 50% of the time), but plain boolean
/// sources always collapse to this net result.
class RollContext {
  final Set<String> _advantageSources = {};
  final Set<String> _disadvantageSources = {};

  void addAdvantage(String source) => _advantageSources.add(source);
  void addDisadvantage(String source) => _disadvantageSources.add(source);

  bool get hasAdvantage => _advantageSources.isNotEmpty;
  bool get hasDisadvantage => _disadvantageSources.isNotEmpty;

  RollMode get netMode {
    if (hasAdvantage && hasDisadvantage) return RollMode.normal;
    if (hasAdvantage) return RollMode.advantage;
    if (hasDisadvantage) return RollMode.disadvantage;
    return RollMode.normal;
  }

  Set<String> get advantageSources => Set.unmodifiable(_advantageSources);
  Set<String> get disadvantageSources => Set.unmodifiable(_disadvantageSources);
}

/// Result of a single d20 roll, keeping enough detail to evaluate
/// natural-20/natural-1 rules even when advantage/disadvantage caused two
/// dice to be rolled.
class D20RollResult {
  /// The die (or dice, if advantage/disadvantage) that were actually
  /// rolled, in roll order.
  final List<int> rawRolls;

  /// The die value that was kept (higher for advantage, lower for
  /// disadvantage, the only value for a normal roll).
  final int kept;

  final RollMode mode;
  final int modifier;

  D20RollResult({
    required this.rawRolls,
    required this.kept,
    required this.mode,
    required this.modifier,
  });

  /// Natural 20 is evaluated against the kept die, not the total.
  bool get isCriticalHit => kept == 20;

  /// Natural 1 is evaluated against the kept die, not the total.
  bool get isCriticalMiss => kept == 1;

  int get total => kept + modifier;

  @override
  String toString() =>
      'D20RollResult(rawRolls: $rawRolls, kept: $kept, mode: $mode, '
      'modifier: $modifier, total: $total)';
}

/// Reusable dice utility. Takes a [Random] instance so callers (and tests)
/// can seed it for deterministic behavior.
class DiceRoller {
  final Random random;

  DiceRoller([Random? random]) : random = random ?? Random();

  /// Rolls a single d20, honoring [mode] for advantage/disadvantage.
  D20RollResult rollD20({RollMode mode = RollMode.normal, int modifier = 0}) {
    final first = random.nextInt(20) + 1;
    if (mode == RollMode.normal) {
      return D20RollResult(
        rawRolls: [first],
        kept: first,
        mode: mode,
        modifier: modifier,
      );
    }
    final second = random.nextInt(20) + 1;
    final kept =
        mode == RollMode.advantage ? max(first, second) : min(first, second);
    return D20RollResult(
      rawRolls: [first, second],
      kept: kept,
      mode: mode,
      modifier: modifier,
    );
  }

  /// Convenience overload that derives [RollMode] from a [RollContext].
  D20RollResult rollD20WithContext(RollContext context, {int modifier = 0}) {
    return rollD20(mode: context.netMode, modifier: modifier);
  }

  /// Rolls a flat percentage check (1-100 inclusive), used for rolls that
  /// are expressed as a plain percentage chance stat (e.g. FAT Chance)
  /// rather than a d20 + modifier contest.
  int rollPercent() => random.nextInt(100) + 1;

  /// Rolls an arbitrary NdM dice expression, returning each individual die
  /// (in roll order) rather than just the sum - what a UI needs to show
  /// the actual dice behind a damage roll instead of only its total.
  List<int> rollDiceRaw(int count, int sides) {
    return [for (var i = 0; i < count; i++) random.nextInt(sides) + 1];
  }

  /// Rolls an arbitrary NdM dice expression (e.g. 1d4), summing the dice.
  int rollDice(int count, int sides) =>
      rollDiceRaw(count, sides).fold(0, (sum, d) => sum + d);
}

/// The individual dice (in roll order) behind one [DiceExpression.roll],
/// kept alongside the total so a UI can show the actual roll (e.g.
/// "14+27+3 = 44") rather than just the resulting number.
class DiceExpressionRollResult {
  final List<int> rawRolls;
  final int flatBonus;
  final int total;

  /// How many faces each die in [rawRolls] had. Carried so a log can say
  /// "6d6" rather than printing seven numbers in a row and leaving the
  /// reader to work out which of them was not a die.
  final int sides;

  const DiceExpressionRollResult({
    required this.rawRolls,
    required this.flatBonus,
    required this.total,
    required this.sides,
  });

  /// The expression this came from, in dice notation.
  String get notation => '${rawRolls.length}d$sides';
}

/// A simple NdM+K dice expression, used for damage rolls like status
/// effect ticks (e.g. Electrocuted's 1d4 lightning damage).
class DiceExpression {
  final int count;
  final int sides;
  final int flatBonus;

  const DiceExpression(this.count, this.sides, {this.flatBonus = 0});

  /// Rolls this expression, keeping the individual dice - see
  /// [DiceExpressionRollResult].
  DiceExpressionRollResult rollDetailed(DiceRoller roller) {
    final raw = roller.rollDiceRaw(count, sides);
    return DiceExpressionRollResult(
      rawRolls: raw,
      flatBonus: flatBonus,
      total: raw.fold(0, (sum, d) => sum + d) + flatBonus,
      sides: sides,
    );
  }

  int roll(DiceRoller roller) => rollDetailed(roller).total;

  /// Expected value of a roll, e.g. `1d6+2` -> 5.5. Used by heuristics
  /// (like `RuleBasedAi`'s ability scoring) that need a single comparable
  /// number rather than an actual roll.
  double get average => count * (sides + 1) / 2 + flatBonus;

  @override
  String toString() =>
      '${count}d$sides${flatBonus == 0 ? '' : (flatBonus > 0 ? '+$flatBonus' : '$flatBonus')}';
}

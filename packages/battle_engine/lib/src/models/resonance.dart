import 'character_type.dart';

/// Resonance grade between a character's [CharacterType] and their Black
/// Trigger's [BlackTriggerType].
///
/// A-D for now (S dropped per design revision - the one cell that used to
/// be S, Defense char x Support Black Trigger, is now A, the new top
/// grade). This is deliberately a plain enum (not an int/index)
/// specifically so it can grow to a finer scale later (e.g.
/// SSS/SS/S/A+/A/A-/...) by adding new members - nothing in
/// [ResonanceGrid] or [ResonanceMultipliers] depends on enum ordering or
/// index, only on explicit map lookups, so adding grades is additive and
/// doesn't change the lookup interface (`ResonanceGrade lookup(...)` /
/// `double multiplierFor(...)`).
enum ResonanceGrade { d, c, b, a }

/// Maps a [ResonanceGrade] to a mechanical multiplier. Kept separate from
/// the grade lookup table so the "exact mechanical effect of each grade"
/// (currently TBD per design) can be tuned independently, and so a future
/// finer-grained scale only needs new entries here, not a rewrite of
/// [ResonanceGrid].
class ResonanceMultipliers {
  final Map<ResonanceGrade, double> _multipliers;

  const ResonanceMultipliers(Map<ResonanceGrade, double> multipliers)
      : _multipliers = multipliers;

  double multiplierFor(ResonanceGrade grade) {
    final value = _multipliers[grade];
    if (value == null) {
      throw ArgumentError('No multiplier configured for grade $grade');
    }
    return value;
  }

  /// Placeholder default multipliers (exact mechanical effect TBD, see
  /// design notes) - tune freely, this is the single source of truth for
  /// "how strong is grade X". Applied by whichever engine resolves a
  /// Black Trigger ability (see `TurnEngine.resonanceMultiplierFor`) as a
  /// multiplier on damage/heal, an inverse multiplier on cooldown, and a
  /// multiplier on passive/World ability magnitudes.
  static const ResonanceMultipliers defaults = ResonanceMultipliers({
    ResonanceGrade.a: 1.5,
    ResonanceGrade.b: 1.15,
    ResonanceGrade.c: 1.0,
    ResonanceGrade.d: 0.85,
  });
}

/// Lookup table for Character Type x Black Trigger Type -> [ResonanceGrade].
class ResonanceGrid {
  final Map<CharacterType, Map<BlackTriggerType, ResonanceGrade>> _grid;

  const ResonanceGrid(this._grid);

  ResonanceGrade lookup(
      CharacterType characterType, BlackTriggerType blackTriggerType) {
    final row = _grid[characterType];
    if (row == null) {
      throw ArgumentError('No resonance row configured for $characterType');
    }
    final grade = row[blackTriggerType];
    if (grade == null) {
      throw ArgumentError(
          'No resonance grade configured for $characterType x $blackTriggerType');
    }
    return grade;
  }

  /// The grid specified in the current design.
  static const ResonanceGrid defaultGrid = ResonanceGrid({
    CharacterType.attack: {
      BlackTriggerType.attack: ResonanceGrade.a,
      BlackTriggerType.defense: ResonanceGrade.b,
      BlackTriggerType.support: ResonanceGrade.c,
      BlackTriggerType.unique: ResonanceGrade.a,
    },
    CharacterType.defense: {
      BlackTriggerType.attack: ResonanceGrade.c,
      BlackTriggerType.defense: ResonanceGrade.a,
      BlackTriggerType.support: ResonanceGrade.a,
      BlackTriggerType.unique: ResonanceGrade.b,
    },
    CharacterType.support: {
      BlackTriggerType.attack: ResonanceGrade.d,
      BlackTriggerType.defense: ResonanceGrade.a,
      BlackTriggerType.support: ResonanceGrade.a,
      BlackTriggerType.unique: ResonanceGrade.b,
    },
    CharacterType.unique: {
      BlackTriggerType.attack: ResonanceGrade.b,
      BlackTriggerType.defense: ResonanceGrade.b,
      BlackTriggerType.support: ResonanceGrade.b,
      BlackTriggerType.unique: ResonanceGrade.b,
    },
  });
}

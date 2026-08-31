import 'trigger.dart';

/// The kinds a Trion token comes in: one per origin, plus Wild.
///
/// Item #15. The Trion pool answers *how much* a squad can do this turn; these
/// tokens answer *what kind*. They are keyed to origin because origin is the
/// game's own "what sort of energy is behind it" tag, and because item #16
/// evened the four out so each can anchor a build.
enum TrionTokenType {
  physical,
  energy,
  afflict,
  mental,

  /// Pays for any origin. Naruto-Arena's Random chakra, and the reason a squad
  /// running one origin is never simply starved by the roll.
  wild;

  /// The token that matches [origin] exactly.
  static TrionTokenType of(OriginTag origin) => switch (origin) {
        OriginTag.physical => TrionTokenType.physical,
        OriginTag.energy => TrionTokenType.energy,
        OriginTag.afflict => TrionTokenType.afflict,
        OriginTag.mental => TrionTokenType.mental,
      };

  /// Whether this token can pay a cost of [origin]. Wild pays for anything.
  bool pays(OriginTag origin) =>
      this == TrionTokenType.wild || this == TrionTokenType.of(origin);
}

/// A squad's shared, banked reserve of typed Trion.
///
/// Shared and banked on purpose, both borrowed from the source material: the
/// squad pools what it earns, and holding a token back to afford next turn's
/// big play is the decision the mechanic exists to create.
class TypedTrionReserve {
  final Map<TrionTokenType, int> _counts;

  TypedTrionReserve([Map<TrionTokenType, int>? counts])
      : _counts = {
          for (final t in TrionTokenType.values) t: counts?[t] ?? 0,
        };

  int operator [](TrionTokenType type) => _counts[type] ?? 0;

  /// Every token held, by kind. A copy, so callers cannot mutate the reserve
  /// by the back door.
  Map<TrionTokenType, int> get counts => Map.unmodifiable(_counts);

  int get total => _counts.values.fold(0, (a, b) => a + b);

  void gain(TrionTokenType type, [int amount = 1]) {
    _counts[type] = (_counts[type] ?? 0) + amount;
  }

  /// Whether anything held can pay a cost of [origin].
  bool canPay(OriginTag origin) =>
      this[TrionTokenType.of(origin)] > 0 || this[TrionTokenType.wild] > 0;

  /// Spends one token against [origin], preferring the exact match so Wild is
  /// kept back for the cost nothing else can pay. Returns false, spending
  /// nothing, when the reserve cannot cover it.
  bool spend(OriginTag origin) {
    final exact = TrionTokenType.of(origin);
    if (this[exact] > 0) {
      _counts[exact] = this[exact] - 1;
      return true;
    }
    if (this[TrionTokenType.wild] > 0) {
      _counts[TrionTokenType.wild] = this[TrionTokenType.wild] - 1;
      return true;
    }
    return false;
  }
}

import 'trigger.dart';

/// The four kinds Trion comes in, one per origin.
///
/// Item #15. The Trion pool answers *how much* a squad can do this turn; these
/// answer *what kind*. They are keyed to origin because origin is the game's
/// own "what sort of energy is behind it" tag, and because item #16 evened the
/// four out so each can anchor a build.
///
/// There is deliberately no fifth kind. Naruto-Arena, which this is modelled
/// on, has four chakra types and no more: its "Random" is a *cost* that any
/// one chakra can pay, never something you hold. A fifth kind you could hold
/// would be strictly better than the other four, which turns the roll into a
/// good-day / bad-day axis instead of a question of which kind you drew.
enum TrionType {
  physical,
  energy,
  afflict,
  mental;

  /// The kind that matches [origin].
  static TrionType of(OriginTag origin) => switch (origin) {
        OriginTag.physical => TrionType.physical,
        OriginTag.energy => TrionType.energy,
        OriginTag.afflict => TrionType.afflict,
        OriginTag.mental => TrionType.mental,
      };
}

/// What one ability asks for in typed Trion, on top of its Raw Trion cost.
///
/// Up to four in total: any mix of the four kinds, plus [random] slots that
/// any kind can pay. So "two Physical and one Random" is
/// `TrionTypeCost({TrionType.physical: 2}, random: 1)`.
class TrionTypeCost {
  /// How many of each named kind this ability needs. Kinds it does not need
  /// are absent rather than present at zero.
  final Map<TrionType, int> typed;

  /// Slots any one kind may pay, the player's choice. Naruto-Arena's Random,
  /// and the reason a squad running one origin is never simply starved.
  final int random;

  /// The most any ability may ask for, counting Random slots.
  static const int maxTotal = 4;

  const TrionTypeCost(this.typed, {this.random = 0});

  const TrionTypeCost.random(this.random) : typed = const {};

  /// One of a single kind, the commonest shape.
  TrionTypeCost.one(TrionType type)
      : typed = {type: 1},
        random = 0;

  int get total => typed.values.fold(random, (a, b) => a + b);

  /// How many of [type] this names outright, ignoring Random slots.
  int operator [](TrionType type) => typed[type] ?? 0;

  bool get isEmpty => total == 0;

  /// Reads as the player sees it: named kinds in enum order, then Random.
  @override
  String toString() {
    final parts = [
      for (final t in TrionType.values)
        if (this[t] > 0) '${t.name} x${this[t]}',
      if (random > 0) 'random x$random',
    ];
    return parts.isEmpty ? 'free' : parts.join(', ');
  }

  @override
  bool operator ==(Object other) =>
      other is TrionTypeCost &&
      other.random == random &&
      TrionType.values.every((t) => other[t] == this[t]);

  @override
  int get hashCode => Object.hashAll([
        random,
        for (final t in TrionType.values) this[t],
      ]);
}

/// A squad's shared, banked Trion Types.
///
/// Shared and banked on purpose, both from the source material: the squad
/// pools what it earns, and what it does not spend this turn is still there
/// next turn.
class TrionTypeReserve {
  final Map<TrionType, int> _counts;

  TrionTypeReserve([Map<TrionType, int>? counts])
      : _counts = {
          for (final t in TrionType.values) t: counts?[t] ?? 0,
        };

  int operator [](TrionType type) => _counts[type] ?? 0;

  /// Every kind held, including the ones at zero, because the interface shows
  /// all four whether you hold them or not. A copy, so callers cannot mutate
  /// the reserve by the back door.
  Map<TrionType, int> get counts => Map.unmodifiable(_counts);

  int get total => _counts.values.fold(0, (a, b) => a + b);

  void gain(TrionType type, [int amount = 1]) {
    _counts[type] = (_counts[type] ?? 0) + amount;
  }

  /// Whether [cost] can be met out of what is held.
  ///
  /// The named kinds have to come from their own piles; the Random slots then
  /// come from whatever is left over, of any kind.
  bool canPay(TrionTypeCost cost) {
    var spare = 0;
    for (final type in TrionType.values) {
      final held = this[type];
      final named = cost[type];
      if (held < named) return false;
      spare += held - named;
    }
    return spare >= cost.random;
  }

  /// Spends [cost], returning what was actually taken of each kind, or null
  /// (spending nothing) when the reserve cannot cover it.
  ///
  /// The Random slots are paid from the **most abundant** kinds first, which
  /// keeps a scarce kind back for the ability that can only be paid with it.
  /// That is this engine's stand-in for the player choosing at the moment of
  /// use, which the interface will offer later; the rule is the one a careful
  /// player would follow anyway.
  Map<TrionType, int>? pay(TrionTypeCost cost) {
    if (!canPay(cost)) return null;
    final spent = <TrionType, int>{};
    for (final type in TrionType.values) {
      final named = cost[type];
      if (named > 0) {
        _counts[type] = this[type] - named;
        spent[type] = named;
      }
    }
    for (var i = 0; i < cost.random; i++) {
      final richest = TrionType.values
          .reduce((a, b) => this[a] >= this[b] ? a : b);
      _counts[richest] = this[richest] - 1;
      spent[richest] = (spent[richest] ?? 0) + 1;
    }
    return spent;
  }
}

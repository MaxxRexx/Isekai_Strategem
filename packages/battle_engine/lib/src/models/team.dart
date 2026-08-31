import 'character.dart';
import 'trion.dart';
import 'trion_token.dart';

/// A 3-character team sharing a single [TrionPool].
class Team {
  final String id;
  final List<Character> characters;
  final TrionPool trionPool;

  /// Item #15: the squad's banked typed Trion, earned one token per living
  /// member per turn and spent on the plays the pool alone cannot buy.
  final TypedTrionReserve typedTrion;

  /// Set when one of this squad's shots bends (see `TurnEngine.canReach`'s
  /// band minimums): their next Trion income is forced to the Low tier.
  ///
  /// A flag rather than a counter on purpose. Bending three shots in one turn
  /// costs exactly what bending one does, so a squad that has decided to break
  /// a screen is never taxed per shot for following through.
  bool trionBacklash = false;

  Team({
    required this.id,
    required this.characters,
    TrionPool? trionPool,
    TypedTrionReserve? typedTrion,
  })  : trionPool = trionPool ?? TrionPool(),
        typedTrion = typedTrion ?? TypedTrionReserve(),
        assert(characters.length == 3, 'A team must have exactly 3 characters');
}

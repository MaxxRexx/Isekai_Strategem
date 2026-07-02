import 'character.dart';
import 'trion.dart';

/// A 3-character team sharing a single [TrionPool].
class Team {
  final String id;
  final List<Character> characters;
  final TrionPool trionPool;

  Team({
    required this.id,
    required this.characters,
    TrionPool? trionPool,
  })  : trionPool = trionPool ?? TrionPool(),
        assert(characters.length == 3, 'A team must have exactly 3 characters');
}

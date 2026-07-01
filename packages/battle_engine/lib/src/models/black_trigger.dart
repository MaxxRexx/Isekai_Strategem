import 'character_type.dart';

/// A Black Trigger: a single powerful ability a character may select,
/// whose [type] resonates with the character's own [CharacterType] (see
/// [ResonanceGrid]).
class BlackTrigger {
  final String id;
  final String name;
  final BlackTriggerType type;
  final String description;

  const BlackTrigger({
    required this.id,
    required this.name,
    required this.type,
    this.description = '',
  });
}

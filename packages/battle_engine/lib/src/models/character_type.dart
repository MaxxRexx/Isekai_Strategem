/// Character archetype, used for Black Trigger resonance lookups and for
/// general ability/AI categorization.
enum CharacterType { attack, defense, support, unique }

/// Type of an equipped Black Trigger. Resonates with [CharacterType] via
/// the [ResonanceGrid].
enum BlackTriggerType { attack, defense, support, unique }

import 'black_trigger.dart';
import 'side_effect.dart';
import 'character_type.dart';
import 'damage_type.dart';
import 'stats.dart';

/// Static character template data: identity, base stats, and
/// battle-invariant properties. Mutable in-battle state (current health,
/// active status effects, cooldowns, etc.) lives in `CharacterBattleState`
/// so the same `Character` can be reused cleanly across battles.
class Character {
  final String id;
  final String name;
  final CharacterType type;
  final Stats baseStats;

  /// Damage types this character takes half damage from (post all other
  /// modifiers).
  final Set<DamageType> damageResistances;

  /// Status effect ids this character is entirely immune to (bypasses the
  /// infliction roll).
  final Set<String> statusInvulnerabilities;

  final BlackTrigger? blackTrigger;

  /// This character's innate trait, always active regardless of Loadout.
  /// Null for a character with no Side Effect.
  final SideEffect? sideEffect;

  const Character({
    required this.id,
    required this.name,
    required this.type,
    required this.baseStats,
    this.damageResistances = const {},
    this.statusInvulnerabilities = const {},
    this.blackTrigger,
    this.sideEffect,
  });
}

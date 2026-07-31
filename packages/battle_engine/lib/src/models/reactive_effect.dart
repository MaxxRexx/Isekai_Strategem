/// A "reactive" combat effect standing on a character: the counter / ward /
/// trap layer introduced by combat v2 (see docs/combat_v2_design.md section
/// 6). Unlike a [StatusEffectDefinition] - a named, duration-based stat
/// modifier drawn from the fixed 50-effect catalog - a reactive effect
/// alters *resolution flow* when the opponent acts into it: reflect, dodge,
/// negate, redirect, and so on. It is armed on the holder's turn and fires
/// during the opponent's turn, then is consumed.
///
/// Following the same "bespoke enumerable behaviours" shape as
/// [CharacterPerk] / `WorldAbilityEffect`, the engine dispatches on [kind]
/// rather than running open scripts. New counters add a [ReactiveKind] and a
/// handler at the matching resolution seam.
library;

/// The closed set of reactive behaviours the engine knows how to dispatch.
/// Grows one entry per counter archetype as combat-v2 Phase B lands.
enum ReactiveKind {
  /// Mirror Ward: the next non-AoE hit against the holder is reflected back
  /// onto its attacker at full effect, and the ward is then consumed. An AoE
  /// bypasses it entirely (and leaves it armed).
  reflectNonAoe,
}

/// One armed reactive effect on a [CharacterBattleState].
class ReactiveEffect {
  final ReactiveKind kind;

  /// The character who armed this effect (its holder/owner), when relevant.
  final String? sourceCharacterId;

  /// Bespoke per-instance parameters for counters that take one (e.g. a
  /// named attack class, or a marked target id), mirroring
  /// [StatusEffectInstance.data].
  final Map<String, Object?> data;

  /// Turns remaining before this effect expires on its own, or null for an
  /// effect that only ends when it triggers (the usual ward/trap lifecycle).
  int? remainingTurns;

  ReactiveEffect({
    required this.kind,
    this.sourceCharacterId,
    Map<String, Object?>? data,
    this.remainingTurns,
  }) : data = data ?? {};
}

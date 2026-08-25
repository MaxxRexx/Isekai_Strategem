/// A "reactive" combat effect standing on a character: the counter / ward /
/// trap layer (see docs/game_design.md section 13). Unlike a
/// [StatusEffectDefinition] - a named, duration-based stat modifier drawn from
/// the fixed status effect catalog - a reactive effect
/// alters *resolution flow* when the opponent acts into it: reflect, dodge,
/// negate, redirect, and so on. It is armed on the holder's turn and fires
/// during the opponent's turn, then is consumed.
///
/// Following the same "bespoke enumerable behaviours" shape as
/// [SideEffect] / `WorldAbilityEffect`, the engine dispatches on [kind]
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

  /// Predictive Parry: once per battle, dodge a melee single-target attack
  /// and answer with a free counter-hit (standard Twin Fang Strike damage).
  dodgeMeleeSingle,

  /// Foresight Counter: call an attack class (stored in `data['originTag']`
  /// as an [OriginTag] name). If the opponent's move against the warded ally
  /// matches, negate it and Stun the attacker for 2 turns.
  negateByOrigin,

  /// Numbing Toxin: a multi-hit Burst against the holder only lands its
  /// first hit; subsequent hits in the same burst are suppressed.
  burstMitigation,

  /// Frozen Tempo: when the holder is hit by a ranged attack, the
  /// attacker's cooldown for that ability is doubled. Consumed on fire.
  cooldownSabotage,

  /// Puppet Strings: redirect any non-AoE attack against the protected
  /// ally onto a random living ally of the attacker. The caster is
  /// Exposed while this is armed. Consumed on fire.
  redirectToOwnAlly,

  /// Deadfall: placed on an enemy. If that enemy uses a damaging ability,
  /// the ability is countered (does not resolve) and they take trap damage
  /// instead. Consumed on fire.
  trapOnAction,

  /// Death Ledger: placed on an enemy (once per enemy per battle). If
  /// that enemy uses an AoE against the marker's team, it is nullified.
  /// Trigger swap deferred to Phase E. Consumed on fire.
  nullifyAoe,

  /// Stored Retribution: while the holder is Guarded or Braced, incoming
  /// damage is banked. The holder's next offensive ability deals the
  /// banked amount as bonus damage, then the bank and this effect reset.
  bankDamage,

  /// Refuse to Bail: pre-declared on yourself. When the holder would be
  /// reduced to zero health they stay standing at 1 health instead, act for
  /// one more turn of their own, and are then destroyed for good: no Bailing
  /// Out window, and no Trion Salvage. Consumed when it fires.
  refuseToBail,

  /// One More Breath: enriches Gravebind's survive-lethal-damage-once.
  /// When the survive-lethal charge fires, doubles all the wielder's
  /// current status durations and Stuns whoever dealt the lethal blow
  /// for 2 turns.
  enrichSurviveLethal,
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

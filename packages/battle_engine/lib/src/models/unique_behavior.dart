/// The closed set of unique-subtype resolution behaviors the engine
/// dispatches on. Each maps 1:1 to a specific Unique ability in the
/// trigger catalog. Mirrors the [CharacterPerk] / [WorldAbilityEffect]
/// pattern: a named enum the engine switches on, not open scripting.
enum UniqueBehavior {
  // --- Melee unique (5) ---

  /// Auto-targets a random enemy the caster has melee-hit this battle.
  /// Roll damage; deal it to self in full (can kill the caster), and
  /// +20% to that enemy.
  sharedAgony,

  /// Chosen. Spend a chunk of current HP; deal that exact amount as
  /// unavoidable true damage (no roll, ignores armor/defense).
  graveBargain,

  /// None. Only usable below 25% HP. The caster is removed from the
  /// battle; every enemy takes massive damage.
  martyrsEnd,

  /// Chosen. Bind to one enemy for 3 turns: double damage to them, but
  /// the caster cannot act on anyone else or be healed. If the bound
  /// enemy is alive when it ends, the caster is Stunned 2.
  vowOfTheDuel,

  /// Chosen. Strike plus permanently destroy one random equipped Trigger
  /// of theirs for the battle; the caster permanently loses one of their
  /// own (their choice, deferred to caller).
  sunderArms,

  // --- Ranged unique (2) ---

  /// Chosen. Ignores the first ward/dodge/counter the target has up and
  /// always resolves.
  curvingShot,

  /// Chosen plus a declared stat. Zero that stat on the target for 2
  /// turns. No damage.
  calledShot,

  // --- Psychic unique (10) ---

  /// Reveal one enemy's full loadout in their panel, clickable, for N
  /// turns. Cannot be used by the caster.
  mindsEye,

  /// Next turn the target may only use their cheapest or priciest
  /// ability (caster declares which).
  forcedChoice,

  /// Copy the target's last-used ability; the caster may cast it once
  /// next turn. The copy occupies Memory Theft's own slot.
  memoryTheft,

  /// Swap one active status effect between two characters (enemy to
  /// enemy, or self to enemy).
  sensorySwap,

  /// Damage scales with the total damage that enemy has dealt this
  /// battle.
  dreadResonance,

  /// For 2 turns, that enemy cannot be healed/buffed by allies and
  /// cannot heal/buff them.
  isolation,

  /// 0 Trion cost, 2-turn cooldown. Starts with 1 charge; +1 charge
  /// each time an ally is defeated. Target self or an ally: that
  /// character is untargetable for the opponent's next turn.
  illusoryDouble,

  /// Force the target's next attack to whiff while they still pay Trion
  /// and cooldown, then backlash plus Silence. Deterministic.
  echoingDoubt,

  /// 3-turn damage/heal link with a chosen enemy; both fractions scale
  /// with the caster's Team Spirit (25% at low TS, 60% at high TS).
  karmicBind,

  /// Invert all the target's active buffs into their debuff equivalents
  /// for the remaining duration (Empowered to Weakened, Guarded to
  /// Exposed, etc.).
  unmaking,
}

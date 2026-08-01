import 'trigger.dart';

/// The closed set of passive-counter archetypes the engine dispatches on.
/// Each maps 1:1 to a [PassiveTrigger] in the trigger catalog. Unlike
/// [PassiveEffect] (flat stat buffs), these are stateful state machines
/// that track counters, fire at specific turn phases, and modify
/// resolution flow.
enum PassiveCounterKind {
  /// Draegor: +1 Enmity per ability use. At 5 Enmity, generate 1 Regret
  /// (2 turns). While Regret is up and the opponent chains 2+ abilities
  /// in a FAT turn, consume Regret for a TEG boost (or double highest-TA
  /// ally's Trion Affinity if TEG is already SS+). Team-wide cap: 3 Regret.
  draegor,

  /// Nullhymn: +1 Discord when an enemy uses a BT active against your team
  /// or inflicts a status on the holder (deduped per status per turn). At 5
  /// Discord, discharge (max 2/battle): downgrade enemy BT resonance, or
  /// purge team debuffs and reflect them.
  nullhymn,

  /// Reckoning: +1 Debt when an enemy crits your team or uses a 2+ cooldown
  /// ability against your team. At 6 Debt: most-indebted enemy gets all
  /// cooldowns extended +1, next attack forced to critical miss, and your
  /// team levies their Trion.
  reckoning,

  /// Gravehour: end of opponent turn, if opponent stalled (dealt no damage)
  /// or left any enemy alive at 30% HP or below, fire a free uncounterable
  /// finisher on the lowest-HP living enemy. That enemy cannot be healed on
  /// the opponent's next turn. 3-turn cooldown after firing.
  gravehour,

  /// Coldread: start of your turn, secretly mark one enemy. End of
  /// opponent's next turn: if the marked enemy took a damaging action,
  /// seize initiative and Levy their costliest action's Trion. If not,
  /// your Trion gain is docked next turn. 1-turn cooldown between reads.
  coldread,

  /// Ironvow: start of holder's turn, one attack type sanctioned at random
  /// (never last turn's type). Attack with sanctioned type = Sanctioned
  /// Strike: unblockable/undodgeable, strips one buff, brands target with
  /// Interdict. Allies Vulnerable to sanctioned type until next turn.
  /// 3 strikes per battle, 2-turn cooldown between strikes.
  ironvow,
}

/// Mutable per-battle state for one passive counter on one character.
/// Fields are grouped by counter; the engine dispatches on [kind].
class PassiveCounterState {
  final PassiveCounterKind kind;

  /// Generic accumulator: Enmity (Draegor), Discord (Nullhymn), Debt
  /// (Reckoning). Reset when threshold is reached.
  int counter = 0;

  /// Per-enemy contribution tracking (Reckoning: which enemy caused most
  /// Debt). Keys are character ids.
  final Map<String, int> counterByEnemyId = {};

  /// Battle-wide charges used: Nullhymn max 2 discharges, Ironvow max 3
  /// Sanctioned Strikes.
  int chargesUsed = 0;

  /// Cooldown turns before this counter can fire again: Gravehour 3,
  /// Coldread 1, Ironvow 2.
  int cooldownTurns = 0;

  // --- Draegor ---
  /// Remaining turns of active Regret (0 = no active Regret).
  int regretRemainingTurns = 0;

  /// Total Regrets generated this battle (team-wide cap of 3).
  int totalRegretGenerated = 0;

  // --- Nullhymn ---
  /// Status ids already counted for discord this turn (dedup per turn).
  final Set<String> discordedStatusIdsThisTurn = {};

  // --- Reckoning ---
  /// Internal lockout after discharge (one-shot per battle).
  bool lockedOut = false;

  // --- Coldread ---
  /// The enemy character id secretly marked this turn.
  String? markedEnemyId;

  /// Whether the mark is waiting for the opponent's turn to resolve.
  bool pendingResolution = false;

  /// Whether the marked enemy took a damaging action this opponent turn.
  bool markedEnemyActedDamaging = false;

  /// Trion gain docked next turn (wrong Coldread guess).
  bool trionGainDockedNextTurn = false;

  // --- Ironvow ---
  /// The attack type sanctioned this turn (null if on cooldown or unset).
  AttackType? sanctionedType;

  /// The attack type the holder used last turn (for forced rotation).
  AttackType? lastTurnAttackType;

  /// Cooldown between Sanctioned Strikes.
  int sanctionedStrikeCooldown = 0;

  PassiveCounterState(this.kind);
}

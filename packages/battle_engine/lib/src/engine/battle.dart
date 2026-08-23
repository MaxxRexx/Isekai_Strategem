import '../models/passive_counter.dart';
import '../models/team.dart';
import '../models/trigger.dart';
import '../models/trion.dart';
import '../models/unique_behavior.dart';
import 'character_battle_state.dart';
import 'status_effect_engine.dart';
import 'trion_gain_engine.dart';
import 'turn_engine.dart';

/// Events produced by [Battle.startTurn]: this team's Trion gain roll,
/// each living member's start-of-turn status tick (damage/heal/drain),
/// and whether Full Arms Trigger rolled true for each. AI/UI callers use
/// this to know what happened before deciding actions for the turn.
class TeamTurnStartResult {
  final TrionGainResult trionGain;
  final Map<String, StatusTickResult> statusTicks;
  final Map<String, bool> fatTriggered;

  const TeamTurnStartResult({
    required this.trionGain,
    required this.statusTicks,
    required this.fatTriggered,
  });
}

/// One body leaving the board at a turn boundary, so the caller can log it.
///
/// Either a Bailing Out body being recalled (with the Trion Salvage its squad
/// banked for getting the operator out), or a Refuse to Bail running out of
/// the turn it bought.
class BailOutResolution {
  final String characterId;

  /// Trion banked by that character's **own** squad. Zero for a spent
  /// refusal, which is the whole price of refusing.
  final int trionSalvaged;

  /// Whether this was a Refuse to Bail expiring rather than a recall.
  final bool refused;

  const BailOutResolution({
    required this.characterId,
    required this.trionSalvaged,
    required this.refused,
  });
}

/// What [Battle.endTurn] settled at the turn boundary. Empty on almost every
/// turn; a caller that does not care may ignore it.
class TeamTurnEndResult {
  final List<BailOutResolution> bailOuts;

  const TeamTurnEndResult({this.bailOuts = const []});
}

/// A battle's outcome. [ongoing] until one or both teams are fully
/// defeated (see [Battle.isTeamDefeated]).
enum BattleOutcome { ongoing, teamAWins, teamBWins, draw }

/// Orchestrates a full 3v3 battle's round loop on top of [TurnEngine]:
/// whose team's turn it is, starting/ending a team's turn (Trion gain,
/// status ticking, FAT rolls, cooldown/penalty bookkeeping), and win/loss
/// detection. Deciding *which* ability a character uses against *which*
/// target is deliberately left to the caller (a future rule-based AI or
/// story-triggered scripted battle, or a UI) - during the window between
/// [startTurn] and [endTurn], the caller drives as many
/// `turnEngine.canUseAbility`/`useAbility`/`resolveAbilityUse` calls as
/// the FAT-gated per-character ability limit allows, using [states] and
/// [activeTeam]/[activeTeamPool].
///
/// Turn structure (per the design brief: "the turn timer applies per team
/// per turn"): a "turn" belongs to one whole team - any/all of its living
/// members may act within it - not to a single character. A "round" is
/// one turn for each team; [roundNumber] increments once both teams have
/// gone.
class Battle {
  final Team teamA;
  final Team teamB;
  final Map<String, CharacterBattleState> states;
  final TurnEngine turnEngine;

  int roundNumber = 1;
  bool isTeamATurn;

  /// Whether the active team dealt any damage this turn (for Gravehour
  /// stall detection). Reset at start of turn, set by [recordDamageDealt].
  bool activeTeamDealtDamageThisTurn = false;

  /// Whether the very first turn of the battle (round 1's opening turn,
  /// whichever team that belongs to) has already had its first-move
  /// Trion handicap applied - see [startTurn].
  bool _firstTurnHandicapApplied = false;

  /// Character ids holding an Illusory Double active Trigger, populated by
  /// [initializeIllusoryDoubleCharges]. Only these gain a charge when an
  /// ally is defeated.
  final Set<String> _illusoryDoubleHolders = {};

  /// Character ids already handled as defeated, so each defeat grants
  /// Illusory Double charges to living allies at most once.
  final Set<String> _processedDefeats = {};

  Battle({
    required this.teamA,
    required this.teamB,
    TurnEngine? turnEngine,
    bool teamAGoesFirst = true,
    Map<String, CharacterBattleState>? states,
  })  : turnEngine = turnEngine ?? TurnEngine(),
        isTeamATurn = teamAGoesFirst,
        states = states ??
            {
              for (final c in teamA.characters) c.id: CharacterBattleState(c),
              for (final c in teamB.characters) c.id: CharacterBattleState(c),
            } {
    // Every character id in a battle has to be unique, because the id is the
    // key to everything: one entry in [states], one row in the squad panel,
    // one target id in the interface, one `teammates` wiring. Draft the same
    // character onto both squads and that map silently holds five states for
    // six characters, so the two of them share one health pool, both squads
    // count them as a teammate, and killing yours kills theirs. Found in a
    // playtest, where a mirror-matched Ilona Vance died on both sides at once.
    //
    // This throws rather than asserting, because an assert is compiled out of
    // the release web build and this failure is silent corruption rather than
    // a crash. Mirror matches are meant to be allowed: supporting them needs a
    // battle-scoped id rather than the character's own, which is item #14 in
    // the work queue. Until then this is the guard that keeps a battle sane.
    final ids = [
      for (final c in [...teamA.characters, ...teamB.characters]) c.id,
    ];
    final duplicates = <String>{
      for (final id in ids)
        if (ids.where((other) => other == id).length > 1) id,
    };
    if (duplicates.isNotEmpty) {
      throw ArgumentError(
        'The same character cannot be in a battle twice: '
        '${duplicates.join(', ')}. Every character id has to be unique across '
        'both squads, since it is the key to their battle state.',
      );
    }

    // Wire up each character's `teammates` for team-aware CharacterPerks
    // (Kaito's last-one-standing crit bonus, Marren's ally-health-aware
    // Armor bonus, Sable's guardian redirect).
    for (final team in [teamA, teamB]) {
      final teamStates =
          team.characters.map((c) => this.states[c.id]!).toList();
      for (final state in teamStates) {
        state.teammates =
            teamStates.where((s) => !identical(s, state)).toList();
      }
    }

    // Give the engine the battle-wide registry so cross-team unique effects
    // (Karmic Bind's live link) can look up a partner on the other team, and
    // the pool map it needs to pay a squad for destroying a Bailing Out body.
    this.turnEngine.characterRegistry = this.states;
    this.turnEngine.teamTrionPools = _teamPoolsByCharacterId;
  }

  Team get activeTeam => isTeamATurn ? teamA : teamB;
  Team get inactiveTeam => isTeamATurn ? teamB : teamA;
  TrionPool get activeTeamPool => activeTeam.trionPool;

  List<CharacterBattleState> get activeTeamStates =>
      activeTeam.characters.map((c) => states[c.id]!).toList();
  List<CharacterBattleState> get inactiveTeamStates =>
      inactiveTeam.characters.map((c) => states[c.id]!).toList();

  /// Records that the active team dealt damage this turn.
  void recordDamageDealt() {
    activeTeamDealtDamageThisTurn = true;
  }

  /// Every character's id mapped to the [TrionPool] of the team they
  /// belong to - used to credit Trion-draining status effects (Sapped) to
  /// the causer's own team pool regardless of which team they're on.
  Map<String, TrionPool> get _teamPoolsByCharacterId => {
        for (final c in teamA.characters) c.id: teamA.trionPool,
        for (final c in teamB.characters) c.id: teamB.trionPool,
      };

  /// A team is defeated once every member's current health is at or below
  /// 0 - not necessarily all 3 characters having ever acted, just their
  /// health.
  bool isTeamDefeated(Team team) =>
      team.characters.every((c) => states[c.id]!.currentHealth <= 0);

  BattleOutcome get outcome {
    final aDefeated = isTeamDefeated(teamA);
    final bDefeated = isTeamDefeated(teamB);
    if (aDefeated && bDefeated) return BattleOutcome.draw;
    if (aDefeated) return BattleOutcome.teamBWins;
    if (bDefeated) return BattleOutcome.teamAWins;
    return BattleOutcome.ongoing;
  }

  bool get isOver => outcome != BattleOutcome.ongoing;

  /// Initializes passive counter state for characters whose equipped
  /// passive triggers declare a [PassiveCounterKind]. Called once at
  /// battle start, after states are created. [equippedPassiveTriggers]
  /// maps character ids to the list of passive triggers in their loadout.
  void initializePassiveCounters(
      Map<String, List<PassiveTrigger>> equippedPassiveTriggers) {
    for (final entry in equippedPassiveTriggers.entries) {
      final state = states[entry.key];
      if (state == null) continue;
      for (final trigger in entry.value) {
        if (trigger.counterKind != null) {
          state.passiveCounters[trigger.counterKind!] =
              PassiveCounterState(trigger.counterKind!);
        }
      }
    }
  }

  /// Grants each character holding an Illusory Double active Trigger its
  /// starting charge(s) (see `UniqueConfig.illusoryDoubleStartingCharges`)
  /// and records them as a holder, so a later ally defeat grants them an
  /// extra charge (see [checkForDefeats]). Called once at battle start with
  /// the same active-Trigger loadout map used elsewhere.
  void initializeIllusoryDoubleCharges(
      Map<String, List<ActiveTrigger>> equippedActiveTriggers) {
    for (final entry in equippedActiveTriggers.entries) {
      final state = states[entry.key];
      if (state == null) continue;
      final holdsIllusoryDouble = entry.value
          .any((t) => t.uniqueBehavior == UniqueBehavior.illusoryDouble);
      if (holdsIllusoryDouble) {
        _illusoryDoubleHolders.add(entry.key);
        state.illusoryDoubleCharges =
            turnEngine.uniqueConfig.illusoryDoubleStartingCharges;
      }
    }
  }

  /// Illusory Double: for each newly-defeated character, every living
  /// teammate that holds an Illusory Double Trigger gains one extra charge.
  /// Idempotent per defeat. Called automatically at the start and end of a
  /// turn; a host driving mid-turn resolutions may also call it after each
  /// ability resolves so charges are granted the instant an ally falls.
  void checkForDefeats() {
    for (final team in [teamA, teamB]) {
      for (final character in team.characters) {
        final state = states[character.id]!;
        if (state.isAlive) continue;
        if (!_processedDefeats.add(character.id)) continue;
        for (final ally in team.characters) {
          if (ally.id == character.id) continue;
          final allyState = states[ally.id]!;
          if (allyState.isAlive && _illusoryDoubleHolders.contains(ally.id)) {
            allyState.illusoryDoubleCharges += 1;
          }
        }
      }
    }
  }

  /// Begins [activeTeam]'s turn: rolls the team's Trion gain (using
  /// members' health at the start of the turn, before any status damage
  /// below - forced to the Low tier on the very first turn of the whole
  /// battle, a first-move handicap offsetting the tempo advantage of
  /// acting first, mirroring Naruto-Arena's reduced opening Chakra draw
  /// for whoever goes first), then for each living member ticks
  /// start-of-turn status effects (damage/heal/Trion drain - crediting
  /// drains to whichever team the causer belongs to), refreshes any
  /// Prone-style random ability lock (if that character's currently
  /// equipped active abilities are supplied via [equippedActiveTriggers]),
  /// and rolls whether Full Arms Trigger triggers for them this turn.
  TeamTurnStartResult startTurn({
    Map<String, List<ActiveTrigger>> equippedActiveTriggers = const {},
  }) {
    final team = activeTeam;
    activeTeamDealtDamageThisTurn = false;
    // Combos never span turns under alternating resolution: start each turn
    // with an empty combo ledger.
    turnEngine.comboLedger.clearTurn();
    // Draegor's 2-tier TEG boost decays once per turn.
    turnEngine.tickTegBoost();
    final isFirstTurnOfBattle = !_firstTurnHandicapApplied;
    _firstTurnHandicapApplied = true;
    final trionGain = turnEngine.resolveTeamTrionGain(team, states,
        forceLowestTier: isFirstTurnOfBattle);

    final statusTicks = <String, StatusTickResult>{};
    final fatTriggered = <String, bool>{};
    final causerPools = _teamPoolsByCharacterId;

    for (final character in team.characters) {
      final state = states[character.id]!;
      if (!state.isAlive) continue;

      statusTicks[character.id] =
          turnEngine.tickStatusEffects(state, causerTrionPools: causerPools);
      if (!state.isAlive) continue;

      final equipped = equippedActiveTriggers[character.id];
      if (equipped != null) {
        turnEngine.statusEffectEngine.refreshAbilityLocks(state, equipped);
      }

      fatTriggered[character.id] = turnEngine.rollFatTrigger(state);
    }

    // Phase B4: start-of-turn passive counter hooks.
    turnEngine.tickStartOfTurnPassiveCounters(
      activeTeamStates,
      inactiveTeamStates,
    );

    // Tick reactive-effect expiry for the active team once per turn, so a
    // timed ward/trap/mark that was never triggered still times out (it was
    // armed on this team's previous turn and has survived the opponent's
    // turn in between). Untimed effects (remainingTurns == null) persist
    // until they fire.
    for (final state in activeTeamStates) {
      if (state.isAlive) turnEngine.tickReactiveEffects(state);
    }

    // Bail Out (#2). Two things get armed here, both deliberately at a turn
    // boundary rather than at the moment somebody fell:
    //
    //  - Every Bailing Out body on the team about to be *attacked* now has its
    //    contested window. The turn the enemy killed them in was committed
    //    before the kill landed, so it was never a decision; this one is.
    //  - Anyone on the active team who refused to bail is spending the extra
    //    turn they bought right now, and is destroyed at the end of it.
    for (final state in inactiveTeamStates) {
      if (state.bailOutState == BailOutState.bailingOut) {
        state.bailOutWindowArmed = true;
      }
    }
    for (final state in activeTeamStates) {
      if (state.hasRefusedToBail && state.isAlive) {
        state.refuseToBailFinalTurn = true;
      }
    }

    // Phase E: grant Illusory Double charges for any deaths from
    // start-of-turn status ticks.
    checkForDefeats();

    return TeamTurnStartResult(
      trionGain: trionGain,
      statusTicks: statusTicks,
      fatTriggered: fatTriggered,
    );
  }

  /// Ends [activeTeam]'s turn: settles any Bail Out window that has now run
  /// its course, finalizes cooldowns/penalties for every living member (see
  /// `TurnEngine.endCharacterTurn`), then passes control to the other team,
  /// incrementing [roundNumber] once both teams have gone.
  ///
  /// Returns what it settled, for the battle log. Callers that do not log may
  /// ignore it.
  TeamTurnEndResult endTurn() {
    // Phase B4: end-of-turn passive counter hooks (fire before character
    // bookkeeping so triggersUsedThisTurn is still populated for Levy).
    turnEngine.tickEndOfTurnPassiveCounters(
      activeTeamStates: activeTeamStates,
      inactiveTeamStates: inactiveTeamStates,
      activeTeamPool: activeTeam.trionPool,
      inactiveTeamPool: inactiveTeam.trionPool,
      activeTeamDealtDamage: activeTeamDealtDamageThisTurn,
    );

    for (final character in activeTeam.characters) {
      final state = states[character.id]!;
      if (state.isAlive) turnEngine.endCharacterTurn(state);
    }

    final bailOuts = _settleBailOuts();

    // Phase E: grant Illusory Double charges for any deaths this turn
    // (ability resolutions, end-of-turn finishers like Gravehour).
    checkForDefeats();

    if (!isTeamATurn) roundNumber++;
    isTeamATurn = !isTeamATurn;
    return TeamTurnEndResult(bailOuts: bailOuts);
  }

  /// Closes out the turn's Bail Out bookkeeping: a body whose contested
  /// window has just passed untouched is recalled and its squad banks the
  /// Trion Salvage, and anyone who refused to bail has now spent the turn
  /// they bought and is destroyed for good.
  List<BailOutResolution> _settleBailOuts() {
    final settled = <BailOutResolution>[];
    final config = turnEngine.bailOutConfig;

    // The window belongs to the team that was *not* acting: the enemy just
    // had their turn with the body standing there and left it alone.
    for (final team in [teamA, teamB]) {
      final isActive = identical(team, activeTeam);
      for (final character in team.characters) {
        final state = states[character.id]!;

        if (!isActive &&
            state.bailOutState == BailOutState.bailingOut &&
            state.bailOutWindowArmed) {
          state.bailOutState = BailOutState.recalled;
          state.bailOutWindowArmed = false;
          final salvage =
              config.salvageFor(character.baseStats.trionCapacity);
          team.trionPool.gain(salvage);
          settled.add(BailOutResolution(
            characterId: character.id,
            trionSalvaged: salvage,
            refused: false,
          ));
          continue;
        }

        if (isActive && state.refuseToBailFinalTurn) {
          state.refuseToBailFinalTurn = false;
          state.currentHealth = 0;
          settled.add(BailOutResolution(
            characterId: character.id,
            trionSalvaged: 0,
            refused: true,
          ));
        }
      }
    }
    return settled;
  }
}

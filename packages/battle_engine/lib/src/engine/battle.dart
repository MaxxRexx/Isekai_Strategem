import '../constants.dart';
import '../models/character.dart';
import '../models/combatant_id.dart';
import '../models/passive_counter.dart';
import '../models/status_effect.dart';
import '../models/team.dart';
import '../models/trigger.dart';
import '../models/trion.dart';
import '../models/trion_type.dart';
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

  /// Item #15: the typed Trion tokens this turn paid out, in order, so the
  /// log can say what the squad actually earned.
  final List<TrionType> trionTypeGain;

  const TeamTurnStartResult({
    required this.trionGain,
    required this.statusTicks,
    required this.fatTriggered,
    this.trionTypeGain = const [],
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

  /// Status effects that ran out at the end of this turn, by combatant id
  /// (item #D moved the countdown here). Empty for a turn where nothing
  /// expired.
  final Map<String, List<StatusEffectInstance>> statusesExpired;

  const TeamTurnEndResult({
    this.bailOuts = const [],
    this.statusesExpired = const {},
  });
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

  /// Item #4's round limit, and the health tiebreak that settles it.
  final RoundLimitConfig roundLimitConfig;

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
    this.roundLimitConfig = RoundLimitConfig.defaults,
  })  : turnEngine = turnEngine ?? TurnEngine(),
        isTeamATurn = teamAGoesFirst,
        // Built without states, a battle keys by the character's own id and
        // nothing is scoped. That is the honest default: with no states handed
        // in there is nothing to tell two identical characters apart with, so
        // the duplicate guard below correctly still refuses them. Scoped
        // combatant ids come from the draft, where the squads are real (see
        // `DraftedTeam`).
        states = states ??
            {
              for (final c in [...teamA.characters, ...teamB.characters])
                c.id: CharacterBattleState(c),
            } {
    if (teamA.id == teamB.id) {
      throw ArgumentError(
        'Both squads have the id "${teamA.id}". A squad id is half of every '
        'combatant id in the battle (see CombatantIds), so two squads sharing '
        'one would put both of their characters on the same keys.',
      );
    }

    // Index each squad's states once, in squad order. Everything that wants
    // "this team's states" reads it from here rather than looking each
    // character up, which is what used to force every such site to know how
    // the map was keyed.
    for (final team in [teamA, teamB]) {
      _statesByTeamId[team.id] = [
        for (final c in team.characters) _stateFor(team, c),
      ];
    }

    // A combatant id has to be unique, because it is the key to everything:
    // one entry in [states], one row in the squad panel, one target id in the
    // interface, one `teammates` wiring. Since a combatant id carries the
    // squad's id, the same character on *opposite* squads is now two
    // combatants, which is the whole of item #14. The same character twice
    // **within one squad** still collides, and that is still a genuine
    // mistake, so this guard stays and now catches exactly that.
    //
    // It throws rather than asserting, because an assert is compiled out of
    // the release web build and this failure is silent corruption rather than
    // a crash: the map would hold five states for six characters, so two of
    // them would share one health pool and killing one would kill the other.
    // That is what the #2 playtest found.
    final ids = [
      for (final team in [teamA, teamB])
        for (final c in team.characters) _stateFor(team, c).combatantId,
    ];
    final duplicates = <String>{
      for (final id in ids)
        if (ids.where((other) => other == id).length > 1) id,
    };
    if (duplicates.isNotEmpty) {
      throw ArgumentError(
        'The same character cannot be on one squad twice: '
        '${duplicates.map(CombatantIds.characterOf).join(', ')}. Every '
        'combatant id has to be unique, since it is the key to their battle '
        'state. Both squads fielding the same character is fine.',
      );
    }

    // Wire up each character's `teammates` for team-aware SideEffects
    // (Kaito's last-one-standing crit bonus, Marren's ally-health-aware
    // Armor bonus, Sable's guardian redirect).
    for (final team in [teamA, teamB]) {
      final teamStates = statesOf(team);
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
    this.turnEngine.teamTrionTypes = _teamTrionTypesByCharacterId;
  }

  /// Each squad's states, in squad order, keyed by the squad's id.
  final Map<String, List<CharacterBattleState>> _statesByTeamId = {};

  /// [team]'s states, in the order its characters were drafted.
  ///
  /// This is the way to ask. Looking a character up in [states] by hand needs
  /// the caller to know whether the battle was keyed by combatant ids or by
  /// plain character ids, and the answer differs between a drafted battle and
  /// a test harness.
  List<CharacterBattleState> statesOf(Team team) =>
      _statesByTeamId[team.id] ??
      [for (final c in team.characters) _stateFor(team, c)];

  /// The state for the character [characterId] on [team].
  ///
  /// For a caller holding a **character** id rather than a combatant id: a
  /// scenario setting a board up, a draft screen, anything that knew who it
  /// wanted before the battle scoped them. Throws if that character is not on
  /// that squad.
  CharacterBattleState stateOf(Team team, String characterId) {
    final character = team.characters.firstWhere(
      (c) => c.id == characterId,
      orElse: () => throw ArgumentError(
        '$characterId is not on squad ${team.id}.',
      ),
    );
    return _stateFor(team, character);
  }

  /// The state for [id], which may be a combatant id or a character id.
  ///
  /// For callers that hold an id but not the squad it belongs to: mostly
  /// tests, and anything reading an id back out of a log. A character id is
  /// resolved by searching both squads, and **throws if both are fielding
  /// them**, because that is precisely the question a character id cannot
  /// answer once mirror matches exist. Ask with a combatant id, or with
  /// [stateOf] and the squad, when that can happen.
  CharacterBattleState stateById(String id) =>
      stateByIdOrNull(id) ??
      (throw ArgumentError('No combatant in this battle for "$id".'));

  /// [stateById], or null when nobody in this battle answers to [id].
  ///
  /// Still throws when [id] is a character id and **both** squads are
  /// fielding them: that is not "not found", it is a question a character id
  /// cannot answer, and answering it with either one would be the silent
  /// corruption item #14 exists to remove.
  CharacterBattleState? stateByIdOrNull(String id) {
    final direct = states[id];
    if (direct != null) return direct;

    final matches = [
      for (final team in [teamA, teamB])
        for (final c in team.characters)
          if (c.id == id) _stateFor(team, c),
    ];
    if (matches.isEmpty) return null;
    if (matches.length == 1) return matches.single;
    throw ArgumentError(
      'Both squads are fielding "$id", so a character id does not say which '
      'one you mean. Use a combatant id (see CombatantIds) or stateOf(team, '
      'id).',
    );
  }

  /// The state for [character] on [team], whichever convention [states] was
  /// keyed by.
  ///
  /// A drafted battle keys by combatant id; an engine test or a tool harness
  /// hands over a map keyed by the character's own id and gets states whose
  /// `combatantId` defaults to the same thing. Both are legitimate, so this
  /// tries the scoped key first and falls back to the plain one.
  CharacterBattleState _stateFor(Team team, Character character) {
    final scoped = states[CombatantIds.of(team.id, character.id)];
    if (scoped != null) return scoped;
    final plain = states[character.id];
    if (plain != null) return plain;
    throw ArgumentError(
      'No battle state for ${character.id} on squad ${team.id}. The states '
      'map has to hold one entry per character, keyed either by their '
      'combatant id or by their character id.',
    );
  }

  Team get activeTeam => isTeamATurn ? teamA : teamB;
  Team get inactiveTeam => isTeamATurn ? teamB : teamA;
  TrionPool get activeTeamPool => activeTeam.trionPool;

  List<CharacterBattleState> get activeTeamStates => statesOf(activeTeam);
  List<CharacterBattleState> get inactiveTeamStates => statesOf(inactiveTeam);

  /// Records that the active team dealt damage this turn.
  void recordDamageDealt() {
    activeTeamDealtDamageThisTurn = true;
  }

  /// Every character's id mapped to the [TrionPool] of the team they
  /// belong to - used to credit Trion-draining status effects (Sapped) to
  /// the causer's own team pool regardless of which team they're on.
  /// Item #15's typed reserve, keyed the same way as the Trion pools.
  Map<String, TrionTypeReserve> get _teamTrionTypesByCharacterId => {
        for (final s in statesOf(teamA)) s.combatantId: teamA.trionTypes,
        for (final s in statesOf(teamB)) s.combatantId: teamB.trionTypes,
      };

  Map<String, TrionPool> get _teamPoolsByCharacterId => {
        for (final s in statesOf(teamA)) s.combatantId: teamA.trionPool,
        for (final s in statesOf(teamB)) s.combatantId: teamB.trionPool,
      };

  /// A team is defeated once every member's current health is at or below
  /// 0 - not necessarily all 3 characters having ever acted, just their
  /// health.
  bool isTeamDefeated(Team team) =>
      statesOf(team).every((s) => s.currentHealth <= 0);

  /// A team's total remaining health, which is what the round limit judges
  /// on. Bailing Out bodies count for nothing, having no health left.
  int remainingHealthOf(Team team) => statesOf(team)
      .fold(0, (total, s) => total + (s.currentHealth < 0 ? 0 : s.currentHealth));

  /// Whether the round limit has been reached: [roundLimitConfig]'s rounds
  /// have all been played out and neither squad has won.
  ///
  /// [roundNumber] counts the round now being played, and only increments
  /// once both teams have gone, so round 30 is finished when the number
  /// passes 30.
  bool get roundLimitReached => roundNumber > roundLimitConfig.maxRounds;

  BattleOutcome get outcome {
    final aDefeated = isTeamDefeated(teamA);
    final bDefeated = isTeamDefeated(teamB);
    if (aDefeated && bDefeated) return BattleOutcome.draw;
    if (aDefeated) return BattleOutcome.teamBWins;
    if (bDefeated) return BattleOutcome.teamAWins;
    // Item #4's round limit: a battle nobody has won by the end goes to
    // whoever is ahead on health, and is a draw if they are level. Measured
    // at 3% of battles, of which the health leader was going on to win 81%
    // anyway, so this decides very little and ends the stalls.
    if (roundLimitReached) {
      final a = remainingHealthOf(teamA);
      final b = remainingHealthOf(teamB);
      if (a > b) return BattleOutcome.teamAWins;
      if (b > a) return BattleOutcome.teamBWins;
      return BattleOutcome.draw;
    }
    return BattleOutcome.ongoing;
  }

  /// Whether this battle ended on the round limit rather than on a defeat.
  /// The interface says so, because "you won on health at round 30" is a
  /// different result from "you wiped them out" and should not read the same.
  bool get endedOnRoundLimit =>
      roundLimitReached && !isTeamDefeated(teamA) && !isTeamDefeated(teamB);

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
      final teamStates = statesOf(team);
      for (final state in teamStates) {
        if (state.isAlive) continue;
        if (!_processedDefeats.add(state.combatantId)) continue;
        for (final ally in teamStates) {
          if (identical(ally, state)) continue;
          if (ally.isAlive &&
              _illusoryDoubleHolders.contains(ally.combatantId)) {
            ally.illusoryDoubleCharges += 1;
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
    // Item #D: a status landing on someone mid-turn must not spend that
    // turn. Everything that applies one reads this flag, so it is set
    // before any of the turn's own effects resolve.
    for (final state in statesOf(team)) {
      state.isTakingTurn = true;
    }
    // Combos never span turns under alternating resolution: start each turn
    // with an empty combo ledger.
    turnEngine.comboLedger.clearTurn();
    // Draegor's 2-tier TEG boost decays once per turn.
    turnEngine.tickTegBoost();
    final isFirstTurnOfBattle = !_firstTurnHandicapApplied;
    _firstTurnHandicapApplied = true;
    final trionGain = turnEngine.resolveTeamTrionGain(team, statesOf(team),
        forceLowestTier: isFirstTurnOfBattle);
    // Item #15: typed Trion is earned alongside the pool, one token per living
    // member. It is not tiered and not affected by the first-turn handicap:
    // what the roll decides is the kind, not the amount.
    final trionTypeGain =
        turnEngine.resolveTrionTypeGain(team, statesOf(team));

    final statusTicks = <String, StatusTickResult>{};
    final fatTriggered = <String, bool>{};
    final fatEligible = <CharacterBattleState>[];
    final causerPools = _teamPoolsByCharacterId;

    for (final state in statesOf(team)) {
      if (!state.isAlive) continue;

      statusTicks[state.combatantId] =
          turnEngine.tickStatusEffects(state, causerTrionPools: causerPools);
      if (!state.isAlive) continue;

      final equipped = equippedActiveTriggers[state.combatantId];
      if (equipped != null) {
        turnEngine.statusEffectEngine.refreshAbilityLocks(state, equipped);
      }

      fatEligible.add(state);
    }

    // Item #4: everyone rolls, one of the winners is drawn, and only that
    // character gets Full Arms Trigger this turn. Rolled after the status
    // ticks above, because a tick can drop a character out of the turn.
    fatTriggered.addAll(turnEngine.rollSquadFatTrigger(fatEligible));

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
      trionTypeGain: trionTypeGain,
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

    final statusesExpired = <String, List<StatusEffectInstance>>{};
    for (final state in activeTeamStates) {
      if (!state.isAlive) continue;
      final expired = turnEngine.endCharacterTurn(state);
      if (expired.isNotEmpty) statusesExpired[state.combatantId] = expired;
    }
    // The turn is over for everyone on this team, including anyone who was
    // not alive to take it.
    for (final state in statesOf(activeTeam)) {
      state.isTakingTurn = false;
    }

    final bailOuts = _settleBailOuts();

    // Phase E: grant Illusory Double charges for any deaths this turn
    // (ability resolutions, end-of-turn finishers like Gravehour).
    checkForDefeats();

    if (!isTeamATurn) roundNumber++;
    isTeamATurn = !isTeamATurn;
    return TeamTurnEndResult(
      bailOuts: bailOuts,
      statusesExpired: statusesExpired,
    );
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
      for (final state in statesOf(team)) {

        if (!isActive &&
            state.bailOutState == BailOutState.bailingOut &&
            state.bailOutWindowArmed) {
          state.bailOutState = BailOutState.recalled;
          state.bailOutWindowArmed = false;
          final salvage =
              config.salvageFor(state.character.baseStats.trionCapacity);
          team.trionPool.gain(salvage);
          settled.add(BailOutResolution(
            characterId: state.combatantId,
            trionSalvaged: salvage,
            refused: false,
          ));
          continue;
        }

        if (isActive && state.refuseToBailFinalTurn) {
          state.refuseToBailFinalTurn = false;
          state.currentHealth = 0;
          settled.add(BailOutResolution(
            characterId: state.combatantId,
            trionSalvaged: 0,
            refused: true,
          ));
        }
      }
    }
    return settled;
  }
}

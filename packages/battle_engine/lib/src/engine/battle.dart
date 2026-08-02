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

    // Phase E: grant Illusory Double charges for any deaths from
    // start-of-turn status ticks.
    checkForDefeats();

    return TeamTurnStartResult(
      trionGain: trionGain,
      statusTicks: statusTicks,
      fatTriggered: fatTriggered,
    );
  }

  /// Ends [activeTeam]'s turn: finalizes cooldowns/penalties for every
  /// living member (see `TurnEngine.endCharacterTurn`), then passes
  /// control to the other team, incrementing [roundNumber] once both
  /// teams have gone.
  void endTurn() {
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

    // Phase E: grant Illusory Double charges for any deaths this turn
    // (ability resolutions, end-of-turn finishers like Gravehour).
    checkForDefeats();

    if (!isTeamATurn) roundNumber++;
    isTeamATurn = !isTeamATurn;
  }
}

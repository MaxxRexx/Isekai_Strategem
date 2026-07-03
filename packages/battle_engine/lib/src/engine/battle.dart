import '../models/team.dart';
import '../models/trigger.dart';
import '../models/trion.dart';
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

  /// Begins [activeTeam]'s turn: rolls the team's Trion gain (using
  /// members' health at the start of the turn, before any status damage
  /// below), then for each living member ticks start-of-turn status
  /// effects (damage/heal/Trion drain - crediting drains to whichever
  /// team the causer belongs to), refreshes any Prone-style random
  /// ability lock (if that character's currently equipped active
  /// abilities are supplied via [equippedActiveTriggers]), and rolls
  /// whether Full Arms Trigger triggers for them this turn.
  TeamTurnStartResult startTurn({
    Map<String, List<ActiveTrigger>> equippedActiveTriggers = const {},
  }) {
    final team = activeTeam;
    final trionGain = turnEngine.resolveTeamTrionGain(team, states);

    final statusTicks = <String, StatusTickResult>{};
    final fatTriggered = <String, bool>{};
    final causerPools = _teamPoolsByCharacterId;

    for (final character in team.characters) {
      final state = states[character.id]!;
      if (!state.isAlive) continue;

      statusTicks[character.id] =
          turnEngine.tickStatusEffects(state, causerTrionPools: causerPools);
      if (!state.isAlive) continue; // a status tick's damage could kill

      final equipped = equippedActiveTriggers[character.id];
      if (equipped != null) {
        turnEngine.statusEffectEngine.refreshAbilityLocks(state, equipped);
      }

      fatTriggered[character.id] = turnEngine.rollFatTrigger(state);
    }

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
    for (final character in activeTeam.characters) {
      final state = states[character.id]!;
      if (state.isAlive) turnEngine.endCharacterTurn(state);
    }
    if (!isTeamATurn) roundNumber++;
    isTeamATurn = !isTeamATurn;
  }
}

import 'dart:math';

import 'package:battle_engine/battle_engine.dart';

import '../game/draft.dart' show rollBreakdownsFor;
import '../game/team_efficiency.dart';
import 'quick_battle_result.dart';

const _builder = LoadoutBuilder();
final _roster = CharacterRoster.defaultRoster;
final _triggers = TriggerCatalog.defaultCatalog;
final _blackTriggers = BlackTriggerCatalog.defaultCatalog;
final _statusCatalog = StatusEffectCatalog.defaultCatalog;

/// Quick Battle's own copy of [statusEffectNames]: each applied effect named
/// once, carrying the stack count the target ended up with.
List<String> _statusEffectNames(
  List<String> ids, {
  Map<String, int> stacks = const {},
}) {
  final seen = <String>{};
  return [
    for (final id in ids)
      if (seen.add(id)) '${_statusCatalog[id].name} x${stacks[id] ?? 1}',
  ];
}

/// Mirrors the web demo's `_buildBattleState`: folds a drafted [Loadout]'s
/// equipped Passive Triggers/Black Trigger passives into
/// [CharacterBattleState.equippedPassiveEffects], its World ability into
/// [CharacterBattleState.worldAbility], and bridges the Loadout's Black
/// Trigger choice into a battle-ready [Character].
CharacterBattleState _buildBattleState(
  Character character,
  Loadout loadout, {
  String? combatantId,
}) {
  final passiveEffects = <PassiveEffect>[
    for (final t in loadout.triggers.whereType<PassiveTrigger>()) t.effect,
    if (loadout.blackTrigger != null)
      for (final p in loadout.blackTrigger!.passiveAbilities) p.effect,
  ];

  final wieldingCharacter = Character(
    id: character.id,
    name: character.name,
    type: character.type,
    baseStats: character.baseStats,
    damageResistances: character.damageResistances,
    statusInvulnerabilities: character.statusInvulnerabilities,
    blackTrigger: loadout.blackTrigger,
    sideEffect: character.sideEffect,
  );

  return CharacterBattleState(
    wieldingCharacter,
    combatantId: combatantId,
    equippedPassiveEffects: passiveEffects,
    worldAbility: loadout.blackTrigger?.worldAbility,
  );
}

class _DraftedTeam {
  final Team team;
  final Map<String, CharacterBattleState> states;
  final Map<String, List<ActiveTrigger>> equippedActiveTriggers;
  final Map<String, Loadout> loadouts;

  /// The same Loadouts keyed by the character's own id, for anything about
  /// the squad's build rather than the battle (the Team Efficiency Grade).
  final Map<String, Loadout> loadoutsByCharacterId;

  const _DraftedTeam(
    this.team,
    this.states,
    this.equippedActiveTriggers,
    this.loadouts,
    this.loadoutsByCharacterId,
  );

  factory _DraftedTeam.draft({
    required String teamId,
    required List<String> characterIds,
    required AiProfile profile,
  }) {
    final characters = characterIds.map((id) => _roster[id]).toList();
    final team = Team(id: teamId, characters: characters);
    final states = <String, CharacterBattleState>{};
    final equipped = <String, List<ActiveTrigger>>{};
    final loadouts = <String, Loadout>{};
    final loadoutsByCharacterId = <String, Loadout>{};

    for (final character in characters) {
      final loadout = _builder.build(
        character,
        activeTriggerPool: _triggers.activeTriggers,
        passiveTriggerPool: _triggers.passiveTriggers,
        blackTriggerPool: _blackTriggers.all,
        profile: profile,
      );
      // Keyed by combatant id, like every other draft (item #14), so Quick
      // Battle can field a mirror match too.
      final combatantId = CombatantIds.of(teamId, character.id);
      states[combatantId] =
          _buildBattleState(character, loadout, combatantId: combatantId);
      equipped[combatantId] = loadout.triggers
          .whereType<ActiveTrigger>()
          .toList();
      loadouts[combatantId] = loadout;
      loadoutsByCharacterId[character.id] = loadout;
    }

    return _DraftedTeam(
        team, states, equipped, loadouts, loadoutsByCharacterId);
  }
}

QuickBattleFighter _fighterSummary(CharacterBattleState s) =>
    QuickBattleFighter(
      name: s.character.name,
      currentHealth: s.currentHealth,
      maxHealth: s.effectiveStats().maxHealth,
      alive: s.isAlive,
      bailingOut: s.bailOutState == BailOutState.bailingOut,
    );

/// Picks 3 distinct random character ids from the full roster, avoiding any
/// id already in [taken].
List<String> _randomTeam(Random random, Set<String> taken) {
  final pool = _roster.all
      .map((c) => c.id)
      .where((id) => !taken.contains(id))
      .toList();
  pool.shuffle(random);
  final picked = pool.take(3).toList();
  taken.addAll(picked);
  return picked;
}

AiProfile _randomProfile(Random random) =>
    AiProfile.all[random.nextInt(AiProfile.all.length)];

/// Drafts two random 3-character squads (with AI profile-biased Loadouts)
/// and runs a full AI-vs-AI battle to completion, up to [maxRounds] team
/// turns each. Which side moves first is decided randomly per the real
/// rules, with the usual first-move Trion handicap applying either way.
QuickBattleResult runQuickBattle({int maxRounds = 60}) {
  final random = Random();
  final taken = <String>{};
  final teamAIds = _randomTeam(random, taken);
  final teamBIds = _randomTeam(random, taken);
  final teamAProfile = _randomProfile(random);
  final teamBProfile = _randomProfile(random);

  final teamADraft = _DraftedTeam.draft(
    teamId: 'team-a',
    characterIds: teamAIds,
    profile: teamAProfile,
  );
  final teamBDraft = _DraftedTeam.draft(
    teamId: 'team-b',
    characterIds: teamBIds,
    profile: teamBProfile,
  );
  final teamAAi = ProfileDrivenAi(teamAProfile);
  final teamBAi = ProfileDrivenAi(teamBProfile);

  // The opening turn is weighted by each squad's Team Efficiency Grade, the
  // same rule the player-facing session uses (see `openingTurnChanceFor`).
  final teamAEfficiency = computeTeamEfficiency(
    characterIds: teamAIds,
    loadouts: teamADraft.loadoutsByCharacterId,
  );
  final teamBEfficiency = computeTeamEfficiency(
    characterIds: teamBIds,
    loadouts: teamBDraft.loadoutsByCharacterId,
  );

  final battle = Battle(
    teamA: teamADraft.team,
    teamB: teamBDraft.team,
    states: {...teamADraft.states, ...teamBDraft.states},
    teamAGoesFirst: rollsOpeningTurn(
      teamAEfficiency.tier,
      teamBEfficiency.tier,
      random: random,
    ),
  );

  final rounds = <QuickBattleRound>[];
  var concluded = false;

  for (var i = 0; i < maxRounds * 2; i++) {
    if (battle.isOver) {
      concluded = true;
      break;
    }

    final teamLabel = battle.isTeamATurn ? 'A' : 'B';
    final activeDraft = battle.isTeamATurn ? teamADraft : teamBDraft;
    final activeAi = battle.isTeamATurn ? teamAAi : teamBAi;

    battle.startTurn(
      equippedActiveTriggers: activeDraft.equippedActiveTriggers,
    );
    if (battle.isOver) {
      rounds.add(
        QuickBattleRound(
          roundNumber: battle.roundNumber,
          team: teamLabel,
          actions: const [],
        ),
      );
      concluded = true;
      break;
    }

    final actionResults = activeAi.takeTurn(
      battle,
      equippedActiveTriggers: activeDraft.equippedActiveTriggers,
    );

    final actions = <QuickBattleAction>[];
    for (final result in actionResults) {
      final trigger = activeDraft.equippedActiveTriggers[result.characterId]!
          .firstWhere((t) => t.id == result.triggerId);
      actions.add(
        QuickBattleAction(
          characterName: battle.states[result.characterId]!.character.name,
          triggerName: trigger.name,
          fatTriggered: battle.states[result.characterId]!.fatTriggeredThisTurn,
          targets: [
            for (final t in result.useResult.targetResults)
              QuickBattleTargetResult(
                targetName: battle.states[t.targetCharacterId]!.character.name,
                hits: t.attackRolls.length,
                crits: t.attackRolls.where((r) => r.isCriticalHit).length,
                misses: t.attackRolls
                    .where((r) => !r.isHit && !r.isCriticalMiss)
                    .length,
                damage: t.totalDamageDealt,
                statusEffectsApplied: _statusEffectNames(
                  t.statusEffectsApplied,
                  stacks: t.statusEffectStacks,
                ),
                healthAfter: battle.states[t.targetCharacterId]!.currentHealth,
                maxHealth: battle.states[t.targetCharacterId]!
                    .effectiveStats()
                    .maxHealth,
                died: !battle.states[t.targetCharacterId]!.isAlive,
                startedBailingOut: battle
                        .states[t.targetCharacterId]!
                        .bailOutState ==
                    BailOutState.bailingOut,
                rolls: rollBreakdownsFor(t),
              ),
          ],
        ),
      );
    }

    rounds.add(
      QuickBattleRound(
        roundNumber: battle.roundNumber,
        team: teamLabel,
        actions: actions,
      ),
    );

    if (battle.isOver) {
      concluded = true;
      break;
    }
    battle.endTurn();
  }

  return QuickBattleResult(
    concluded: concluded,
    outcome: battle.outcome,
    roundsPlayed: battle.roundNumber,
    rounds: rounds,
    finalTeamA: [
      for (final s in battle.statesOf(teamADraft.team)) _fighterSummary(s),
    ],
    finalTeamB: [
      for (final s in battle.statesOf(teamBDraft.team)) _fighterSummary(s),
    ],
  );
}

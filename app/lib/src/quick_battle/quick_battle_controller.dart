import 'dart:math';

import 'package:battle_engine/battle_engine.dart';

import 'quick_battle_result.dart';

const _builder = LoadoutBuilder();
final _roster = CharacterRoster.defaultRoster;
final _triggers = TriggerCatalog.defaultCatalog;
final _blackTriggers = BlackTriggerCatalog.defaultCatalog;
final _statusCatalog = StatusEffectCatalog.defaultCatalog;

List<String> _statusEffectNames(List<String> ids) =>
    [for (final id in ids) _statusCatalog[id].name];

/// Mirrors the web demo's `_buildBattleState`: folds a drafted [Loadout]'s
/// equipped Passive Triggers/Black Trigger passives into
/// [CharacterBattleState.equippedPassiveEffects], its World ability into
/// [CharacterBattleState.worldAbility], and bridges the Loadout's Black
/// Trigger choice into a battle-ready [Character].
CharacterBattleState _buildBattleState(Character character, Loadout loadout) {
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
    perk: character.perk,
  );

  return CharacterBattleState(
    wieldingCharacter,
    equippedPassiveEffects: passiveEffects,
    worldAbility: loadout.blackTrigger?.worldAbility,
  );
}

class _DraftedTeam {
  final Team team;
  final Map<String, CharacterBattleState> states;
  final Map<String, List<ActiveTrigger>> equippedActiveTriggers;

  const _DraftedTeam(this.team, this.states, this.equippedActiveTriggers);

  factory _DraftedTeam.draft({
    required String teamId,
    required List<String> characterIds,
    required AiProfile profile,
  }) {
    final characters = characterIds.map((id) => _roster[id]).toList();
    final team = Team(id: teamId, characters: characters);
    final states = <String, CharacterBattleState>{};
    final equipped = <String, List<ActiveTrigger>>{};

    for (final character in characters) {
      final loadout = _builder.build(
        character,
        activeTriggerPool: _triggers.activeTriggers,
        passiveTriggerPool: _triggers.passiveTriggers,
        blackTriggerPool: _blackTriggers.all,
        profile: profile,
      );
      states[character.id] = _buildBattleState(character, loadout);
      equipped[character.id] =
          loadout.triggers.whereType<ActiveTrigger>().toList();
    }

    return _DraftedTeam(team, states, equipped);
  }
}

QuickBattleFighter _fighterSummary(CharacterBattleState s) => QuickBattleFighter(
      name: s.character.name,
      currentHealth: s.currentHealth,
      maxHealth: s.effectiveStats().maxHealth,
      alive: s.isAlive,
    );

/// Picks 3 distinct random character ids from the full roster, avoiding any
/// id already in [taken].
List<String> _randomTeam(Random random, Set<String> taken) {
  final pool = _roster.all.map((c) => c.id).where((id) => !taken.contains(id)).toList();
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
      teamId: 'team-a', characterIds: teamAIds, profile: teamAProfile);
  final teamBDraft = _DraftedTeam.draft(
      teamId: 'team-b', characterIds: teamBIds, profile: teamBProfile);
  final teamAAi = ProfileDrivenAi(teamAProfile);
  final teamBAi = ProfileDrivenAi(teamBProfile);

  final battle = Battle(
    teamA: teamADraft.team,
    teamB: teamBDraft.team,
    states: {...teamADraft.states, ...teamBDraft.states},
    teamAGoesFirst: random.nextBool(),
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

    battle.startTurn(equippedActiveTriggers: activeDraft.equippedActiveTriggers);
    if (battle.isOver) {
      rounds.add(QuickBattleRound(
          roundNumber: battle.roundNumber, team: teamLabel, actions: const []));
      concluded = true;
      break;
    }

    final actionResults = activeAi.takeTurn(battle,
        equippedActiveTriggers: activeDraft.equippedActiveTriggers);

    final actions = <QuickBattleAction>[];
    for (final result in actionResults) {
      final trigger = activeDraft.equippedActiveTriggers[result.characterId]!
          .firstWhere((t) => t.id == result.triggerId);
      actions.add(QuickBattleAction(
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
              statusEffectsApplied: _statusEffectNames(t.statusEffectsApplied),
              healthAfter: battle.states[t.targetCharacterId]!.currentHealth,
              maxHealth:
                  battle.states[t.targetCharacterId]!.effectiveStats().maxHealth,
              died: !battle.states[t.targetCharacterId]!.isAlive,
            ),
        ],
      ));
    }

    rounds.add(QuickBattleRound(
        roundNumber: battle.roundNumber, team: teamLabel, actions: actions));

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
      for (final c in teamADraft.team.characters)
        _fighterSummary(battle.states[c.id]!)
    ],
    finalTeamB: [
      for (final c in teamBDraft.team.characters)
        _fighterSummary(battle.states[c.id]!)
    ],
  );
}

// Compiled with `dart compile js` into a single JS file that the web demo
// Artifact loads inline. Exposes a small JSON-in/JSON-out API on
// `globalThis` - everything crossing the Dart/JS boundary is a plain
// string, so the JS side never has to deal with Dart types directly.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:battle_engine/battle_engine.dart';

final _roster = CharacterRoster.defaultRoster;
final _triggers = TriggerCatalog.defaultCatalog;
final _blackTriggers = BlackTriggerCatalog.defaultCatalog;
const _builder = LoadoutBuilder();

/// Mirrors `full_battle_simulation_test.dart`'s `buildBattleState`: folds a
/// drafted [Loadout]'s equipped Passive Triggers/Black Trigger passives
/// into [CharacterBattleState.equippedPassiveEffects], its World ability
/// into [CharacterBattleState.worldAbility], and bridges the Loadout's
/// Black Trigger choice into a battle-ready [Character] (`Character.
/// blackTrigger` and `Loadout.blackTrigger` are separate fields today -
/// nothing wires them together automatically).
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
  final Map<String, Loadout> loadouts;

  const _DraftedTeam(
      this.team, this.states, this.equippedActiveTriggers, this.loadouts);

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
      loadouts[character.id] = loadout;
    }

    return _DraftedTeam(team, states, equipped, loadouts);
  }
}

Map<String, dynamic> _characterSummary(Character c) => {
      'id': c.id,
      'name': c.name,
      'type': c.type.name,
      'perkName': c.perk?.name,
      'perkDescription': c.perk?.description,
    };

Map<String, dynamic> _profileSummary(AiProfile p) => {
      'id': p.id,
      'name': p.name,
      'description': p.description,
      'skillClass': p.skillClass.name,
    };

Map<String, dynamic> _loadoutSummary(Loadout loadout) => {
      'blackTrigger': loadout.blackTrigger == null
          ? null
          : {
              'id': loadout.blackTrigger!.id,
              'name': loadout.blackTrigger!.name,
            },
      'triggers': [
        for (final t in loadout.triggers) {'id': t.id, 'name': t.name}
      ],
    };

Map<String, dynamic> _characterStateSummary(CharacterBattleState s) => {
      'id': s.character.id,
      'name': s.character.name,
      'currentHealth': s.currentHealth,
      'maxHealth': s.effectiveStats().maxHealth,
      'alive': s.isAlive,
    };

/// Runs one full battle between two drafted teams, collecting a
/// turn-by-turn log for the demo UI to render, up to [maxRounds] (a
/// battle that hasn't concluded by then reports `concluded: false` rather
/// than looping forever - see the real engine's own integration test for
/// why some AI-mirror matchups can be this slow: a content-balance
/// property of the current placeholder damage/heal magnitudes, not a bug).
Map<String, dynamic> _runBattle({
  required _DraftedTeam teamADraft,
  required _DraftedTeam teamBDraft,
  required ProfileDrivenAi teamAAi,
  required ProfileDrivenAi teamBAi,
  int maxRounds = 800,
}) {
  final battle = Battle(
    teamA: teamADraft.team,
    teamB: teamBDraft.team,
    states: {...teamADraft.states, ...teamBDraft.states},
  );

  final rounds = <Map<String, dynamic>>[];
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
        equippedActiveTriggers: activeDraft.equippedActiveTriggers);
    if (battle.isOver) {
      rounds.add({
        'roundNumber': battle.roundNumber,
        'team': teamLabel,
        'actions': const [],
      });
      concluded = true;
      break;
    }

    final actionResults = activeAi.takeTurn(battle,
        equippedActiveTriggers: activeDraft.equippedActiveTriggers);

    final actions = <Map<String, dynamic>>[];
    for (final result in actionResults) {
      final trigger = activeDraft.equippedActiveTriggers[result.characterId]!
          .firstWhere((t) => t.id == result.triggerId);
      actions.add({
        'characterId': result.characterId,
        'characterName': battle.states[result.characterId]!.character.name,
        'triggerId': trigger.id,
        'triggerName': trigger.name,
        'targets': [
          for (final t in result.useResult.targetResults)
            {
              'targetId': t.targetCharacterId,
              'targetName': battle.states[t.targetCharacterId]!.character.name,
              'hits': t.attackRolls.length,
              'crits': t.attackRolls.where((r) => r.isCriticalHit).length,
              'misses': t.attackRolls
                  .where((r) => !r.isHit && !r.isCriticalMiss)
                  .length,
              'damage': t.totalDamageDealt,
              'statusEffectsApplied': t.statusEffectsApplied,
              'healthAfter': battle.states[t.targetCharacterId]!.currentHealth,
              'died': !battle.states[t.targetCharacterId]!.isAlive,
            }
        ],
      });
    }

    rounds.add({
      'roundNumber': battle.roundNumber,
      'team': teamLabel,
      'actions': actions,
    });

    if (battle.isOver) {
      concluded = true;
      break;
    }

    battle.endTurn();
  }

  return {
    'concluded': concluded,
    'outcome': battle.outcome.name,
    'roundsPlayed': battle.roundNumber,
    'rounds': rounds,
    'finalTeamA': [
      for (final c in teamADraft.team.characters)
        _characterStateSummary(battle.states[c.id]!)
    ],
    'finalTeamB': [
      for (final c in teamBDraft.team.characters)
        _characterStateSummary(battle.states[c.id]!)
    ],
  };
}

AiProfile _profileById(String id) =>
    AiProfile.all.firstWhere((p) => p.id == id);

String _listCharactersJson() =>
    jsonEncode([for (final c in _roster.all) _characterSummary(c)]);

String _listProfilesJson() =>
    jsonEncode([for (final p in AiProfile.all) _profileSummary(p)]);

/// [configJsonString] shape:
/// `{"teamA": {"characterIds": [id,id,id], "profileId": "..."},
///   "teamB": {"characterIds": [id,id,id], "profileId": "..."}}`
String _simulateBattleJson(String configJsonString) {
  final config = jsonDecode(configJsonString) as Map<String, dynamic>;

  _DraftedTeam draft(String teamId, Map<String, dynamic> side) {
    final characterIds = (side['characterIds'] as List).cast<String>();
    final profile = _profileById(side['profileId'] as String);
    return _DraftedTeam.draft(
      teamId: teamId,
      characterIds: characterIds,
      profile: profile,
    );
  }

  final teamADraft = draft('team-a', config['teamA'] as Map<String, dynamic>);
  final teamBDraft = draft('team-b', config['teamB'] as Map<String, dynamic>);

  final maxRounds = (config['maxRounds'] as num?)?.toInt() ?? 800;
  final result = _runBattle(
    teamADraft: teamADraft,
    teamBDraft: teamBDraft,
    teamAAi:
        ProfileDrivenAi(_profileById(config['teamA']['profileId'] as String)),
    teamBAi:
        ProfileDrivenAi(_profileById(config['teamB']['profileId'] as String)),
    maxRounds: maxRounds,
  );

  result['teamALoadouts'] = {
    for (final c in teamADraft.team.characters)
      c.id: _loadoutSummary(teamADraft.loadouts[c.id]!)
  };
  result['teamBLoadouts'] = {
    for (final c in teamBDraft.team.characters)
      c.id: _loadoutSummary(teamBDraft.loadouts[c.id]!)
  };

  return jsonEncode(result);
}

void main() {
  globalContext.setProperty(
      'battleDemoListCharacters'.toJS, (() => _listCharactersJson().toJS).toJS);
  globalContext.setProperty(
      'battleDemoListProfiles'.toJS, (() => _listProfilesJson().toJS).toJS);
  globalContext.setProperty(
      'battleDemoSimulate'.toJS,
      ((JSString configJson) => _simulateBattleJson(configJson.toDart).toJS)
          .toJS);
}

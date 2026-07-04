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
final _statusCatalog = StatusEffectCatalog.defaultCatalog;
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
      'trionCapacity': c.baseStats.trionCapacity,
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
/// than looping forever). With the current draft magnitude tuning (100
/// flat max health, damage/heal/cooldown/Attack/Trion Affinity scaled for
/// a 15-20 round conclusion target), battles typically conclude well
/// under this cap - it's a generous safety margin, not the expected case.
Map<String, dynamic> _runBattle({
  required _DraftedTeam teamADraft,
  required _DraftedTeam teamBDraft,
  required ProfileDrivenAi teamAAi,
  required ProfileDrivenAi teamBAi,
  int maxRounds = 60,
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
              'statusEffectsApplied': _statusEffectNames(t.statusEffectsApplied),
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

// --- Interactive play mode: Loadout building + a stateful turn-by-turn
// session, for a human player against an AI-drafted/controlled opponent.
// The batch `_simulateBattleJson` above (AI vs AI, one shot) is unrelated
// and unaffected by any of this.

List<String> _statusEffectNames(List<String> ids) =>
    [for (final id in ids) _statusCatalog[id].name];

Map<String, dynamic> _statusApplicationSummary(StatusEffectApplication a) => {
      'statusEffectId': a.statusEffectId,
      'statusEffectName': _statusCatalog[a.statusEffectId].name,
    };

Map<String, dynamic> _activeTriggerSummary(ActiveTrigger t) => {
      'id': t.id,
      'name': t.name,
      'isPassive': false,
      'category': t.category.name,
      'equipCost': t.equipCost,
      'trionCost': t.trionCost,
      'cooldownTurns': t.cooldownTurns,
      'rangeTag': t.rangeTag.name,
      'attackType': t.attackType.name,
      'attackSubtype': t.attackSubtype.name,
      'targetAffiliation': t.targetAffiliation.name,
      'targetCount': t.targetCount,
      'hitsPerUse': t.hitsPerUse,
      'damageType': t.damageType?.name,
      'damageAvg': t.damage?.average,
      'healAvg': t.healAmount?.average,
      'healsCasterInstead': t.healsCasterInstead,
      'inflictedStatusEffects': [
        for (final a in t.inflictedStatusEffects) _statusApplicationSummary(a)
      ],
    };

Map<String, dynamic> _passiveEffectSummary(PassiveEffect e) => {
      'flatStatModifiers': {
        for (final entry in e.flatStatModifiers.entries)
          entry.key.name: entry.value
      },
      'statusInvulnerabilitiesGranted':
          e.statusInvulnerabilitiesGranted.toList(),
      'damageResistancesGranted':
          e.damageResistancesGranted.map((d) => d.name).toList(),
    };

Map<String, dynamic> _passiveTriggerSummary(PassiveTrigger t) => {
      'id': t.id,
      'name': t.name,
      'isPassive': true,
      'category': t.category.name,
      'equipCost': t.equipCost,
      'effect': _passiveEffectSummary(t.effect),
    };

Map<String, dynamic> _triggerCatalogSummary(Trigger t) => switch (t) {
      ActiveTrigger a => _activeTriggerSummary(a),
      PassiveTrigger p => _passiveTriggerSummary(p),
    };

Map<String, dynamic> _worldAbilitySummary(WorldAbilityEffect w) => {
      'turnTimerSecondsDelta': w.turnTimerSecondsDelta,
      'damagePreventionInstances': w.damagePreventionInstances,
      'surviveLethalDamageOnce': w.surviveLethalDamageOnce,
    };

Map<String, dynamic> _blackTriggerSummary(BlackTrigger bt) => {
      'id': bt.id,
      'name': bt.name,
      'type': bt.type.name,
      'description': bt.description,
      'equipCost': bt.equipCost,
      'activeAbilities': [
        for (final a in bt.activeAbilities) _activeTriggerSummary(a)
      ],
      'passiveAbilities': [
        for (final p in bt.passiveAbilities)
          {
            'id': p.id,
            'name': p.name,
            'effect': _passiveEffectSummary(p.effect),
          }
      ],
      'worldAbility': bt.worldAbility == null
          ? null
          : _worldAbilitySummary(bt.worldAbility!),
    };

String _listTriggersJson() =>
    jsonEncode([for (final t in _triggers.all) _triggerCatalogSummary(t)]);

String _listBlackTriggersJson() =>
    jsonEncode([for (final bt in _blackTriggers.all) _blackTriggerSummary(bt)]);

/// The full Character Type x Black Trigger Type -> grade grid, plus each
/// grade's damage/heal/cooldown/magnitude multiplier, for the Loadout
/// builder UI to show Resonance fit before the player commits.
String _resonanceGridJson() {
  const grid = ResonanceGrid.defaultGrid;
  const multipliers = ResonanceMultipliers.defaults;
  final rows = <String, dynamic>{};
  for (final charType in CharacterType.values) {
    final row = <String, dynamic>{};
    for (final btType in BlackTriggerType.values) {
      final grade = grid.lookup(charType, btType);
      row[btType.name] = {
        'grade': grade.name,
        'multiplier': multipliers.multiplierFor(grade),
      };
    }
    rows[charType.name] = row;
  }
  return jsonEncode(rows);
}

Loadout _loadoutFromRequest(Map<String, dynamic> req) {
  final characterId = req['characterId'] as String;
  final triggerIds = (req['triggerIds'] as List).cast<String>();
  final blackTriggerId = req['blackTriggerId'] as String?;
  return Loadout(
    characterId: characterId,
    triggers: [for (final id in triggerIds) _triggers[id]],
    blackTrigger:
        blackTriggerId == null ? null : _blackTriggers[blackTriggerId],
  );
}

/// [reqJsonString] shape: `{"characterId": "...", "triggerIds": [...],
/// "blackTriggerId": "..." | null}`.
String _validateLoadoutJson(String reqJsonString) {
  final req = jsonDecode(reqJsonString) as Map<String, dynamic>;
  final character = _roster[req['characterId'] as String];
  final loadout = _loadoutFromRequest(req);
  final result = loadout.validateFor(character);
  return jsonEncode({
    'isValid': result.isValid,
    'errors': result.errors,
    'totalCost': loadout.totalEquipCost,
    'budget': character.baseStats.trionCapacity,
    'itemCount': loadout.totalEquippedCount,
    'maxItems': LoadoutRulesConfig.defaults.maxEquippedTriggers,
    'activeCount': loadout.totalActiveAbilityCount,
    'requiredActiveCount':
        LoadoutRulesConfig.defaults.requiredActiveAbilityCount,
  });
}

Map<String, dynamic> _statusInstanceSummary(dynamic instance) => {
      'id': instance.definitionId as String,
      'name': _statusCatalog[instance.definitionId as String].name,
      'remainingTurns': instance.remainingTurns,
    };

Map<String, dynamic> _sessionCharacterSummary(
        CharacterBattleState s, Map<String, List<ActiveTrigger>> equipped) =>
    {
      'id': s.character.id,
      'name': s.character.name,
      'currentHealth': s.currentHealth,
      'maxHealth': s.effectiveStats().maxHealth,
      'alive': s.isAlive,
      'statusEffects': [
        for (final i in s.statusEffects) _statusInstanceSummary(i)
      ],
      'cooldowns': {
        for (final t in equipped[s.character.id] ?? const <ActiveTrigger>[])
          if ((s.cooldowns[t.id] ?? 0) > 0) t.id: s.cooldowns[t.id]
      },
    };

class _Session {
  final Battle battle;
  final Map<String, List<ActiveTrigger>> equippedA;
  final Map<String, List<ActiveTrigger>> equippedB;
  final ProfileDrivenAi aiB;

  _Session({
    required this.battle,
    required this.equippedA,
    required this.equippedB,
    required this.aiB,
  });
}

final Map<int, _Session> _sessions = {};
int _nextSessionId = 1;

Map<String, dynamic> _sessionSnapshot(int sessionId, _Session s) => {
      'sessionId': sessionId,
      'isOver': s.battle.isOver,
      'outcome': s.battle.outcome.name,
      'roundNumber': s.battle.roundNumber,
      'isPlayerTurn': s.battle.isTeamATurn,
      'teamATrion': s.battle.teamA.trionPool.current,
      'teamBTrion': s.battle.teamB.trionPool.current,
      'teamA': [
        for (final c in s.battle.teamA.characters)
          _sessionCharacterSummary(s.battle.states[c.id]!, s.equippedA)
      ],
      'teamB': [
        for (final c in s.battle.teamB.characters)
          _sessionCharacterSummary(s.battle.states[c.id]!, s.equippedB)
      ],
    };

_Session _sessionFor(int id) {
  final s = _sessions[id];
  if (s == null) throw ArgumentError('Unknown session id: $id');
  return s;
}

/// [configJsonString] shape: `{"teamA": {"characterIds": [id,id,id],
/// "loadouts": {"charId": {"triggerIds": [...], "blackTriggerId": ... |
/// null}}}, "teamB": {"characterIds": [id,id,id], "profileId": "..."}}`.
/// Team A (the player) always goes first. If any of Team A's 3 Loadouts
/// is invalid, no session is created - the caller should validate each
/// one first via [_validateLoadoutJson].
String _startSessionJson(String configJsonString) {
  final config = jsonDecode(configJsonString) as Map<String, dynamic>;
  final teamAConfig = config['teamA'] as Map<String, dynamic>;
  final teamACharacterIds =
      (teamAConfig['characterIds'] as List).cast<String>();
  final teamALoadoutReqs = teamAConfig['loadouts'] as Map<String, dynamic>;

  final teamACharacters = teamACharacterIds.map((id) => _roster[id]).toList();
  final teamALoadouts = <String, Loadout>{};
  for (final id in teamACharacterIds) {
    final loadoutReq = teamALoadoutReqs[id] as Map<String, dynamic>;
    final loadout = _loadoutFromRequest({'characterId': id, ...loadoutReq});
    final validation = loadout.validateFor(_roster[id]);
    if (!validation.isValid) {
      return jsonEncode({
        'error': 'Invalid Loadout for $id: ${validation.errors.join('; ')}'
      });
    }
    teamALoadouts[id] = loadout;
  }

  final teamAStates = <String, CharacterBattleState>{};
  final equippedA = <String, List<ActiveTrigger>>{};
  for (final character in teamACharacters) {
    final loadout = teamALoadouts[character.id]!;
    teamAStates[character.id] = _buildBattleState(character, loadout);
    equippedA[character.id] =
        loadout.triggers.whereType<ActiveTrigger>().toList();
  }
  final teamATeam = Team(id: 'player', characters: teamACharacters);

  final teamBConfig = config['teamB'] as Map<String, dynamic>;
  final teamBDraft = _DraftedTeam.draft(
    teamId: 'ai',
    characterIds: (teamBConfig['characterIds'] as List).cast<String>(),
    profile: _profileById(teamBConfig['profileId'] as String),
  );

  final battle = Battle(
    teamA: teamATeam,
    teamB: teamBDraft.team,
    states: {...teamAStates, ...teamBDraft.states},
  );
  battle.startTurn(equippedActiveTriggers: equippedA);

  final session = _Session(
    battle: battle,
    equippedA: equippedA,
    equippedB: teamBDraft.equippedActiveTriggers,
    aiB: ProfileDrivenAi(_profileById(teamBConfig['profileId'] as String)),
  );
  final sessionId = _nextSessionId++;
  _sessions[sessionId] = session;

  return jsonEncode({
    'sessionId': sessionId,
    'teamALoadouts': {
      for (final id in teamACharacterIds)
        id: _loadoutSummary(teamALoadouts[id]!)
    },
    'teamBLoadouts': {
      for (final c in teamBDraft.team.characters)
        c.id: _loadoutSummary(teamBDraft.loadouts[c.id]!)
    },
    'state': _sessionSnapshot(sessionId, session),
  });
}

/// [reqJsonString] shape: `{"sessionId": N, "characterId": "..."}`. Only
/// legal during the player's own turn, for one of their own living
/// characters.
String _legalActionsJson(String reqJsonString) {
  final req = jsonDecode(reqJsonString) as Map<String, dynamic>;
  final session = _sessionFor((req['sessionId'] as num).toInt());
  final battle = session.battle;
  final characterId = req['characterId'] as String;
  final state = battle.states[characterId]!;
  final engine = battle.turnEngine;

  if (!battle.isTeamATurn || !state.isAlive) return jsonEncode([]);

  final actions = <Map<String, dynamic>>[];
  for (final trigger
      in session.equippedA[characterId] ?? const <ActiveTrigger>[]) {
    if (!engine.canUseAbility(state, trigger)) continue;

    List<String> legalTargetIds;
    int maxTargets;
    if (trigger.targetAffiliation == TargetAffiliation.self) {
      legalTargetIds = [characterId];
      maxTargets = 1;
    } else {
      final pool = trigger.targetAffiliation == TargetAffiliation.opponent
          ? battle.teamB.characters.map((c) => battle.states[c.id]!)
          : battle.teamA.characters.map((c) => battle.states[c.id]!);
      final legal = pool
          .where((t) =>
              t.isAlive &&
              (trigger.targetAffiliation != TargetAffiliation.opponent ||
                  engine.canTarget(state, t)))
          .toList();
      legalTargetIds = legal.map((t) => t.character.id).toList();
      maxTargets = trigger.rangeTag == RangeTag.ranged
          ? engine.maxRangedTargets(state, trigger)
          : trigger.targetCount;
    }

    final actualTrionCost =
        (trigger.trionCost * state.trionCostMultiplier()).round();
    actions.add({
      ..._activeTriggerSummary(trigger),
      'legalTargetIds': legalTargetIds,
      'maxTargets': maxTargets,
      'actualTrionCost': actualTrionCost,
      'affordable': actualTrionCost <= battle.teamA.trionPool.current,
    });
  }
  return jsonEncode(actions);
}

/// [reqJsonString] shape: `{"sessionId": N, "characterId": "...",
/// "triggerId": "...", "targetIds": [...]}`.
String _useAbilityJson(String reqJsonString) {
  final req = jsonDecode(reqJsonString) as Map<String, dynamic>;
  final sessionId = (req['sessionId'] as num).toInt();
  final session = _sessionFor(sessionId);
  final battle = session.battle;
  final engine = battle.turnEngine;
  final characterId = req['characterId'] as String;
  final triggerId = req['triggerId'] as String;
  final targetIds = (req['targetIds'] as List).cast<String>();

  final state = battle.states[characterId]!;
  final trigger =
      session.equippedA[characterId]!.firstWhere((t) => t.id == triggerId);

  if (!engine.canUseAbility(state, trigger)) {
    return jsonEncode(
        {'success': false, 'error': 'That ability is not usable right now.'});
  }
  if (!engine.useAbility(state, trigger, battle.teamA.trionPool)) {
    return jsonEncode({'success': false, 'error': 'Not enough Trion.'});
  }

  final targets = [for (final id in targetIds) battle.states[id]!];
  final useResult = engine.resolveAbilityUse(
    attacker: state,
    trigger: trigger,
    targets: targets,
  );

  return jsonEncode({
    'success': true,
    'triggerName': trigger.name,
    'targets': [
      for (final t in useResult.targetResults)
        {
          'targetId': t.targetCharacterId,
          'targetName': battle.states[t.targetCharacterId]!.character.name,
          'hits': t.attackRolls.length,
          'crits': t.attackRolls.where((r) => r.isCriticalHit).length,
          'misses':
              t.attackRolls.where((r) => !r.isHit && !r.isCriticalMiss).length,
          'damage': t.totalDamageDealt,
          'statusEffectsApplied': _statusEffectNames(t.statusEffectsApplied),
          'healthAfter': battle.states[t.targetCharacterId]!.currentHealth,
          'died': !battle.states[t.targetCharacterId]!.isAlive,
        }
    ],
    'state': _sessionSnapshot(sessionId, session),
  });
}

/// [reqJsonString] shape: `{"sessionId": N}`. Ends the player's turn,
/// then automatically plays out the AI's turn (collecting its actions
/// into `aiLog`, same shape as the batch simulator's round log) and
/// starts the player's next turn - unless the battle ends first.
String _endTurnJson(String reqJsonString) {
  final req = jsonDecode(reqJsonString) as Map<String, dynamic>;
  final sessionId = (req['sessionId'] as num).toInt();
  final session = _sessionFor(sessionId);
  final battle = session.battle;

  battle.endTurn();

  final aiLog = <Map<String, dynamic>>[];
  var aiRoundNumber = battle.roundNumber;
  while (!battle.isTeamATurn && !battle.isOver) {
    battle.startTurn(equippedActiveTriggers: session.equippedB);
    aiRoundNumber = battle.roundNumber;
    if (battle.isOver) break;

    final actionResults =
        session.aiB.takeTurn(battle, equippedActiveTriggers: session.equippedB);
    for (final result in actionResults) {
      final trigger = session.equippedB[result.characterId]!
          .firstWhere((t) => t.id == result.triggerId);
      aiLog.add({
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
              'statusEffectsApplied': _statusEffectNames(t.statusEffectsApplied),
              'healthAfter': battle.states[t.targetCharacterId]!.currentHealth,
              'died': !battle.states[t.targetCharacterId]!.isAlive,
            }
        ],
      });
    }

    if (battle.isOver) break;
    battle.endTurn();
  }

  if (!battle.isOver) {
    battle.startTurn(equippedActiveTriggers: session.equippedA);
  }

  return jsonEncode({
    'aiRoundNumber': aiRoundNumber,
    'aiLog': aiLog,
    'state': _sessionSnapshot(sessionId, session),
  });
}

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

  final maxRounds = (config['maxRounds'] as num?)?.toInt() ?? 60;
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

  globalContext.setProperty(
      'battleDemoListTriggers'.toJS, (() => _listTriggersJson().toJS).toJS);
  globalContext.setProperty('battleDemoListBlackTriggers'.toJS,
      (() => _listBlackTriggersJson().toJS).toJS);
  globalContext.setProperty(
      'battleDemoResonanceGrid'.toJS, (() => _resonanceGridJson().toJS).toJS);
  globalContext.setProperty('battleDemoValidateLoadout'.toJS,
      ((JSString reqJson) => _validateLoadoutJson(reqJson.toDart).toJS).toJS);
  globalContext.setProperty(
      'battleDemoStartSession'.toJS,
      ((JSString configJson) => _startSessionJson(configJson.toDart).toJS)
          .toJS);
  globalContext.setProperty('battleDemoLegalActions'.toJS,
      ((JSString reqJson) => _legalActionsJson(reqJson.toDart).toJS).toJS);
  globalContext.setProperty('battleDemoUseAbility'.toJS,
      ((JSString reqJson) => _useAbilityJson(reqJson.toDart).toJS).toJS);
  globalContext.setProperty('battleDemoEndTurn'.toJS,
      ((JSString reqJson) => _endTurnJson(reqJson.toDart).toJS).toJS);
}

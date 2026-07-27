import 'package:battle_engine/battle_engine.dart';

import 'battle_models.dart';

final roster = CharacterRoster.defaultRoster;
final triggerCatalog = TriggerCatalog.defaultCatalog;
final blackTriggerCatalog = BlackTriggerCatalog.defaultCatalog;
final statusCatalog = StatusEffectCatalog.defaultCatalog;
const loadoutBuilder = LoadoutBuilder();

AiProfile profileById(String id) => AiProfile.all.firstWhere((p) => p.id == id);

List<String> statusEffectNames(List<String> ids) => [
  for (final id in ids) statusCatalog[id].name,
];

/// Folds a drafted [Loadout]'s equipped Passive Triggers/Black Trigger
/// passives into [CharacterBattleState.equippedPassiveEffects], its World
/// ability into [CharacterBattleState.worldAbility], and bridges the
/// Loadout's Black Trigger choice into a battle-ready [Character]
/// (`Character.blackTrigger` and `Loadout.blackTrigger` are separate
/// fields today - nothing wires them together automatically).
CharacterBattleState buildBattleState(Character character, Loadout loadout) {
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

/// A team plus everything battle setup derives from its Loadouts.
class DraftedTeam {
  final Team team;
  final Map<String, CharacterBattleState> states;
  final Map<String, List<ActiveTrigger>> equippedActiveTriggers;
  final Map<String, Loadout> loadouts;

  const DraftedTeam(
    this.team,
    this.states,
    this.equippedActiveTriggers,
    this.loadouts,
  );

  /// Drafts via the AI [profile]'s Loadout-building preferences, same as
  /// the engine's own AI opponents draft for themselves.
  factory DraftedTeam.draftWithProfile({
    required String teamId,
    required List<String> characterIds,
    required AiProfile profile,
  }) {
    return DraftedTeam.fromLoadouts(
      teamId: teamId,
      characterIds: characterIds,
      loadouts: {
        for (final id in characterIds)
          id: loadoutBuilder.build(
            roster[id],
            activeTriggerPool: triggerCatalog.activeTriggers,
            passiveTriggerPool: triggerCatalog.passiveTriggers,
            blackTriggerPool: blackTriggerCatalog.all,
            profile: profile,
          ),
      },
    );
  }

  /// Drafts from explicit, already-validated player [loadouts].
  factory DraftedTeam.fromLoadouts({
    required String teamId,
    required List<String> characterIds,
    required Map<String, Loadout> loadouts,
  }) {
    final characters = characterIds.map((id) => roster[id]).toList();
    final team = Team(id: teamId, characters: characters);
    final states = <String, CharacterBattleState>{};
    final equipped = <String, List<ActiveTrigger>>{};

    for (final character in characters) {
      final loadout = loadouts[character.id]!;
      states[character.id] = buildBattleState(character, loadout);
      equipped[character.id] = loadout.triggers
          .whereType<ActiveTrigger>()
          .toList();
    }

    return DraftedTeam(team, states, equipped, loadouts);
  }
}

FighterSnapshot fighterSnapshot(CharacterBattleState s) => FighterSnapshot(
  id: s.character.id,
  name: s.character.name,
  type: s.character.type,
  currentHealth: s.currentHealth,
  maxHealth: s.effectiveStats().maxHealth,
  alive: s.isAlive,
  fatTriggered: s.fatTriggeredThisTurn,
  statusEffects: [
    for (final i in s.statusEffects)
      StatusBadgeInfo(
        id: i.definitionId,
        name: statusCatalog[i.definitionId].name,
        remainingTurns: i.remainingTurns,
      ),
  ],
);

/// The full roll-by-roll breakdown backing one [LogTargetResult] (or
/// Quick Battle's equivalent), zipping each attack roll with the damage
/// it specifically dealt.
List<LogRollBreakdown> rollBreakdownsFor(TargetHitResult t) => [
  for (var i = 0; i < t.attackRolls.length; i++)
    LogRollBreakdown(
      attackerRoll: LogDiceRoll.from(t.attackRolls[i].attackerRoll),
      defenderRoll: LogDiceRoll.from(t.attackRolls[i].defenderRoll),
      isHit: t.attackRolls[i].isHit,
      isCriticalHit: t.attackRolls[i].isCriticalHit,
      isCriticalMiss: t.attackRolls[i].isCriticalMiss,
      damage: t.damagePerHit[i],
    ),
];

/// The per-target log entries for one resolved ability use.
List<LogTargetResult> logTargets(Battle battle, AbilityUseResult useResult) => [
  for (final t in useResult.targetResults)
    LogTargetResult(
      targetId: t.targetCharacterId,
      targetName: battle.states[t.targetCharacterId]!.character.name,
      hits: t.attackRolls.length,
      crits: t.attackRolls.where((r) => r.isCriticalHit).length,
      misses: t.attackRolls.where((r) => !r.isHit && !r.isCriticalMiss).length,
      damage: t.totalDamageDealt,
      statusEffectsApplied: statusEffectNames(t.statusEffectsApplied),
      healthAfter: battle.states[t.targetCharacterId]!.currentHealth,
      died: !battle.states[t.targetCharacterId]!.isAlive,
      rolls: rollBreakdownsFor(t),
    ),
];

LogAction logActionFor(
  Battle battle,
  ActiveTrigger trigger,
  AiActionResult result,
) => LogAction(
  characterId: result.characterId,
  characterName: battle.states[result.characterId]!.character.name,
  triggerId: trigger.id,
  triggerName: trigger.name,
  fatTriggered: battle.states[result.characterId]!.fatTriggeredThisTurn,
  targets: logTargets(battle, result.useResult),
);

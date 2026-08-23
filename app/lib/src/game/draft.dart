import 'dart:math';

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
    // Start where this Loadout can actually operate: a Close Range kit at
    // the Front, a sniper's kit at the Back. Without this everyone would
    // open at Middle, two squads would stand 2 apart, and every Close Range
    // ability in the game would be unusable on turn one.
    position: startingPositionFor(
      loadout.triggers.whereType<ActiveTrigger>().map((t) => t.rangeTag),
    ),
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
      // A Black Trigger's own active abilities count toward the Loadout
      // rule's required active-ability total (Loadout.totalActiveAbilityCount
      // already includes them) and are just as usable in battle as a
      // regular equipped ActiveTrigger - drop them here and a character
      // whose Loadout satisfies the rule only via its Black Trigger ends up
      // with fewer usable abilities in play than the rule requires.
      equipped[character.id] = [
        ...loadout.triggers.whereType<ActiveTrigger>(),
        ...?loadout.blackTrigger?.activeAbilities,
      ];
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
  bailingOut: s.bailOutState == BailOutState.bailingOut,
  fatTriggered: s.fatTriggeredThisTurn,
  position: s.position,
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
      damageDetail: t.damageDetails[i] == null
          ? null
          : LogDamageDetail.from(t.damageDetails[i]!),
    ),
];

/// Who was already Bailing Out, and who had already refused, before an action
/// resolves. Compared against the same states afterwards so the log can say
/// what *this* action did rather than what is merely true now.
BailOutSnapshot bailOutSnapshot(Battle battle) => BailOutSnapshot(
  bailing: {
    for (final s in battle.states.values)
      if (s.bailOutState == BailOutState.bailingOut) s.character.id,
  },
  refused: {
    for (final s in battle.states.values)
      if (s.hasRefusedToBail) s.character.id,
  },
);

/// See [bailOutSnapshot].
class BailOutSnapshot {
  final Set<String> bailing;
  final Set<String> refused;
  const BailOutSnapshot({this.bailing = const {}, this.refused = const {}});
  static const empty = BailOutSnapshot();
}

/// The per-target log entries for one resolved ability use.
///
/// [before] is the Bail Out picture from just before this action resolved; it
/// is what turns "this target is Bailing Out" into "this hit is what put them
/// there". Omit it and the Bail Out fields simply stay false, which is what an
/// older caller with no bodies on the board wants anyway.
List<LogTargetResult> logTargets(
  Battle battle,
  AbilityUseResult useResult, {
  BailOutSnapshot before = BailOutSnapshot.empty,
}) => [
  for (final t in useResult.targetResults)
    () {
      final state = battle.states[t.targetCharacterId]!;
      final id = t.targetCharacterId;
      final wasBailing = before.bailing.contains(id);
      return LogTargetResult(
        targetId: id,
        targetName: state.character.name,
        hits: t.attackRolls.length,
        crits: t.attackRolls.where((r) => r.isCriticalHit).length,
        misses: t.attackRolls.where((r) => !r.isHit && !r.isCriticalMiss).length,
        damage: t.totalDamageDealt,
        statusEffectsApplied: statusEffectNames(t.statusEffectsApplied),
        healthAfter: state.currentHealth,
        // Still in the window is not defeated. Without this clause a later
        // action aimed at a body - even one that missed it - would print
        // DEFEATED, which is both wrong and the opposite of the decision the
        // player still has to make about that body.
        died: !state.isAlive &&
            state.bailOutState != BailOutState.bailingOut,
        startedBailingOut:
            !wasBailing && state.bailOutState == BailOutState.bailingOut,
        bodyDestroyed:
            wasBailing && state.bailOutState == BailOutState.destroyed,
        trionFromBody: wasBailing &&
                state.bailOutState == BailOutState.destroyed
            ? BailOutConfig.defaults
                .attackerGainFor(state.character.baseStats.trionCapacity)
            : 0,
        refusedToBail:
            !before.refused.contains(id) && state.hasRefusedToBail,
        rolls: rollBreakdownsFor(t),
      );
    }(),
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


/// Picks [size] distinct random character ids, avoiding everyone in [taken].
///
/// **A character can only be in a battle once.** Their id is the key to their
/// battle state, their Loadout, their `teammates` wiring, their row in the
/// squad panel and their target id in the interface, so drafting the same
/// character onto both squads gives the two of them one shared state: one
/// health pool, each squad counting them as a teammate, and one of them able
/// to be ordered to attack themselves. A playtest found exactly that with a
/// mirror-matched Ilona Vance.
///
/// `Battle` now refuses to start such a battle at all. This is the other half:
/// the squad drafts share one rule rather than each screen writing its own,
/// which is how the two screens that got it wrong got it wrong.
///
/// [taken] accepts nulls so a screen can pass its slot list straight in.
List<String> randomSquadAvoiding(
  Random random,
  Iterable<String?> taken, {
  int size = 3,
}) {
  final excluded = taken.whereType<String>().toSet();
  final pool = roster.all
      .map((c) => c.id)
      .where((id) => !excluded.contains(id))
      .toList()
    ..shuffle(random);
  return pool.take(size).toList();
}

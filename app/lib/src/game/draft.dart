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
CharacterBattleState buildBattleState(
  Character character,
  Loadout loadout, {
  // The battle-scoped id (see `CombatantIds`). Null keys this state by
  // the character's own id, which is what a harness with one of each
  // character wants; the draft below always supplies one.
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
    perk: character.perk,
  );

  return CharacterBattleState(
    wieldingCharacter,
    combatantId: combatantId,
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

  /// Keyed by **combatant id**, like everything else a battle holds.
  final Map<String, Loadout> loadouts;

  /// The same Loadouts keyed by the **character's own id**, which is what
  /// anything computed about the squad's *build* rather than about the battle
  /// wants: the Team Efficiency Grade is a property of what you drafted, and
  /// it is worked out from character ids.
  final Map<String, Loadout> loadoutsByCharacterId;

  const DraftedTeam(
    this.team,
    this.states,
    this.equippedActiveTriggers,
    this.loadouts,
    this.loadoutsByCharacterId,
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
  /// [loadouts] is keyed by the character's own id, which is what the draft
  /// screens hand over. Everything this returns is keyed by **combatant id**
  /// instead, because from here on the squad is real and two squads may be
  /// fielding the same character (item #14).
  factory DraftedTeam.fromLoadouts({
    required String teamId,
    required List<String> characterIds,
    required Map<String, Loadout> loadouts,
  }) {
    final characters = characterIds.map((id) => roster[id]).toList();
    final team = Team(id: teamId, characters: characters);
    final states = <String, CharacterBattleState>{};
    final equipped = <String, List<ActiveTrigger>>{};
    final scopedLoadouts = <String, Loadout>{};

    for (final character in characters) {
      final loadout = loadouts[character.id]!;
      final combatantId = CombatantIds.of(teamId, character.id);
      scopedLoadouts[combatantId] = loadout;
      states[combatantId] =
          buildBattleState(character, loadout, combatantId: combatantId);
      // A Black Trigger's own active abilities count toward the Loadout
      // rule's required active-ability total (Loadout.totalActiveAbilityCount
      // already includes them) and are just as usable in battle as a
      // regular equipped ActiveTrigger - drop them here and a character
      // whose Loadout satisfies the rule only via its Black Trigger ends up
      // with fewer usable abilities in play than the rule requires.
      equipped[combatantId] = [
        ...loadout.triggers.whereType<ActiveTrigger>(),
        ...?loadout.blackTrigger?.activeAbilities,
      ];
    }

    return DraftedTeam(team, states, equipped, scopedLoadouts, loadouts);
  }
}

/// Display names for every combatant in [battle], disambiguated **only where
/// two squads field the same character** (item #14).
///
/// An ordinary battle reads exactly as it always did: one Ilona Vance is just
/// "Ilona Vance". A mirror match would otherwise print "Ilona Vance uses Twin
/// Fang Strike on Ilona Vance", which tells the player nothing, so there the
/// squad is named too.
Map<String, String> combatantDisplayNames(
  Battle battle, {
  required String teamALabel,
  required String teamBLabel,
}) {
  final counts = <String, int>{};
  for (final team in [battle.teamA, battle.teamB]) {
    for (final state in battle.statesOf(team)) {
      counts[state.character.id] = (counts[state.character.id] ?? 0) + 1;
    }
  }
  return {
    for (final (team, label) in [
      (battle.teamA, teamALabel),
      (battle.teamB, teamBLabel),
    ])
      for (final state in battle.statesOf(team))
        state.combatantId: (counts[state.character.id] ?? 0) > 1
            ? '${state.character.name} ($label)'
            : state.character.name,
  };
}

FighterSnapshot fighterSnapshot(
  CharacterBattleState s, {
  /// Overrides the displayed name, for a mirror match where the character's
  /// own name no longer identifies them. See [combatantDisplayNames].
  String? displayName,
}) =>
    FighterSnapshot(
  id: s.combatantId,
  name: displayName ?? s.character.name,
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
      if (s.bailOutState == BailOutState.bailingOut) s.combatantId,
  },
  refused: {
    for (final s in battle.states.values)
      if (s.hasRefusedToBail) s.combatantId,
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
/// [displayNames] disambiguates a mirror match; omit it and each target is
/// named by their character's own name, which is right for every other battle.
List<LogTargetResult> logTargets(
  Battle battle,
  AbilityUseResult useResult, {
  BailOutSnapshot before = BailOutSnapshot.empty,
  Map<String, String> displayNames = const {},
}) => [
  for (final t in useResult.targetResults)
    () {
      final state = battle.stateById(t.targetCharacterId);
      final id = t.targetCharacterId;
      final wasBailing = before.bailing.contains(id);
      return LogTargetResult(
        targetId: id,
        targetName:
            displayNames[t.targetCharacterId] ?? state.character.name,
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
  characterName: battle.stateById(result.characterId).character.name,
  triggerId: trigger.id,
  triggerName: trigger.name,
  fatTriggered: battle.states[result.characterId]!.fatTriggeredThisTurn,
  targets: logTargets(battle, result.useResult),
);


/// A random squad of [size] distinct characters, avoiding everyone in
/// [taken].
///
/// [taken] is **this squad's** other slots, not the opposing squad's. Both
/// sides may field the same character since item #14: two Ilona Vances on
/// opposite squads are two combatants with their own health, statuses and
/// position, keyed apart by their combatant ids (see `CombatantIds`). One
/// squad still cannot field her twice, which is what this avoids and what
/// `Battle` still refuses outright.
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

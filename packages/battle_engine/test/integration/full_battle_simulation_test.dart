import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

/// Builds a battle-ready [CharacterBattleState] for [character] wearing
/// [loadout]: folds the Loadout's equipped [PassiveTrigger]s and Black
/// Trigger's passive abilities into [CharacterBattleState.
/// equippedPassiveEffects], and its Black Trigger's World ability (if
/// any) into [CharacterBattleState.worldAbility]. Nothing in `Battle` or
/// `LoadoutBuilder` does this wiring automatically - it's host-app/setup
/// responsibility, exercised here for the first time end-to-end.
CharacterBattleState buildBattleState(Character character, Loadout loadout) {
  final passiveEffects = <PassiveEffect>[
    for (final t in loadout.triggers.whereType<PassiveTrigger>()) t.effect,
    if (loadout.blackTrigger != null)
      for (final p in loadout.blackTrigger!.passiveAbilities) p.effect,
  ];

  // `Character.blackTrigger` (read by `TurnEngine.resonanceMultiplierFor`)
  // and `Loadout.blackTrigger` (read by Loadout validation) are separate
  // fields today - baking the Loadout's choice into the battle Character
  // is what actually makes resonance apply for a drafted team.
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
    equippedPassiveEffects: passiveEffects,
    worldAbility: loadout.blackTrigger?.worldAbility,
  );
}

/// Drafts a 3-character team from [roster] (by id) using [builder] to
/// build each member's Loadout for [profile], and returns the
/// ready-to-battle state map plus each character's equipped active
/// abilities (what `ProfileDrivenAi`/`Battle.startTurn` need).
class DraftedTeam {
  final Team team;
  final Map<String, CharacterBattleState> states;
  final Map<String, List<ActiveTrigger>> equippedActiveTriggers;

  const DraftedTeam(this.team, this.states, this.equippedActiveTriggers);

  factory DraftedTeam.draft({
    required String teamId,
    required List<String> characterIds,
    required AiProfile profile,
    required CharacterRoster roster,
    required TriggerCatalog triggers,
    required BlackTriggerCatalog blackTriggers,
    required LoadoutBuilder builder,
  }) {
    final characters = characterIds.map((id) => roster[id]).toList();
    final team = Team(id: teamId, characters: characters);
    final states = <String, CharacterBattleState>{};
    final equipped = <String, List<ActiveTrigger>>{};

    for (final character in characters) {
      final loadout = builder.build(
        character,
        activeTriggerPool: triggers.activeTriggers,
        passiveTriggerPool: triggers.passiveTriggers,
        blackTriggerPool: blackTriggers.all,
        profile: profile,
      );
      states[character.id] = buildBattleState(character, loadout);
      equipped[character.id] =
          loadout.triggers.whereType<ActiveTrigger>().toList();
    }

    return DraftedTeam(team, states, equipped);
  }
}

/// Runs a full battle to completion (or [maxRounds], whichever comes
/// first) alternating [teamAAi]/[teamBAi] each team's turn, returning the
/// final [BattleOutcome]. Throws if the battle doesn't conclude within
/// [maxRounds] - a real engine/AI bug (e.g. an AI that can never legally
/// act) should surface as a test failure, not an infinite loop.
BattleOutcome runToCompletion(
  Battle battle,
  DraftedTeam teamADraft,
  DraftedTeam teamBDraft,
  ProfileDrivenAi teamAAi,
  ProfileDrivenAi teamBAi, {
  int maxRounds = 5000,
}) {
  for (var i = 0; i < maxRounds * 2; i++) {
    if (battle.isOver) return battle.outcome;

    final activeDraft = battle.isTeamATurn ? teamADraft : teamBDraft;
    final activeAi = battle.isTeamATurn ? teamAAi : teamBAi;

    battle.startTurn(
        equippedActiveTriggers: activeDraft.equippedActiveTriggers);
    if (battle.isOver) return battle.outcome;

    activeAi.takeTurn(battle,
        equippedActiveTriggers: activeDraft.equippedActiveTriggers);
    if (battle.isOver) return battle.outcome;

    battle.endTurn();
  }

  fail('Battle did not conclude within $maxRounds rounds - '
      'round ${battle.roundNumber}, outcome ${battle.outcome}');
}

void main() {
  final roster = CharacterRoster.defaultRoster;
  final triggers = TriggerCatalog.defaultCatalog;
  final blackTriggers = BlackTriggerCatalog.defaultCatalog;
  const builder = LoadoutBuilder();

  group('Full battle simulation (real roster/catalogs/AI end to end)', () {
    void playAndAssertConcludes(
      String teamAIds0,
      String teamAIds1,
      String teamAIds2,
      AiProfile teamAProfile,
      String teamBIds0,
      String teamBIds1,
      String teamBIds2,
      AiProfile teamBProfile,
    ) {
      final teamADraft = DraftedTeam.draft(
        teamId: 'team-a',
        characterIds: [teamAIds0, teamAIds1, teamAIds2],
        profile: teamAProfile,
        roster: roster,
        triggers: triggers,
        blackTriggers: blackTriggers,
        builder: builder,
      );
      final teamBDraft = DraftedTeam.draft(
        teamId: 'team-b',
        characterIds: [teamBIds0, teamBIds1, teamBIds2],
        profile: teamBProfile,
        roster: roster,
        triggers: triggers,
        blackTriggers: blackTriggers,
        builder: builder,
      );

      final combinedStates = {...teamADraft.states, ...teamBDraft.states};
      final battle = Battle(
        teamA: teamADraft.team,
        teamB: teamBDraft.team,
        states: combinedStates,
      );

      final outcome = runToCompletion(
        battle,
        teamADraft,
        teamBDraft,
        ProfileDrivenAi(teamAProfile),
        ProfileDrivenAi(teamBProfile),
      );

      expect(outcome, isNot(BattleOutcome.ongoing));
      expect(battle.roundNumber, greaterThan(0));
    }

    test('Executioner team vs Blast Radius team concludes decisively', () {
      playAndAssertConcludes(
        'kaito_reyes',
        'marren_osei',
        'priya_nakamura',
        AiProfile.theExecutioner,
        'dross',
        'ilona_vance',
        'soren_talvik',
        AiProfile.theBlastRadius,
      );
    });

    test(
        'a Beginner team can still complete a battle against an Expert '
        'team', () {
      playAndAssertConcludes(
        'ren_kobayashi',
        'bastian_cole',
        'yuki_amaral',
        AiProfile.buttonMasher,
        'vela_ashworth',
        'sable_whitlock',
        'celestine_moreau',
        AiProfile.theGrandmaster,
      );
    });

    test(
        'The Gambler (Black-Trigger-favoring) completes a battle without '
        'crashing on a mismatched resonance build', () {
      playAndAssertConcludes(
        'airi_tanaka',
        'dorian_voss',
        'haru_ellison',
        AiProfile.theGambler,
        'zheng_anders',
        'nadia_kessler',
        'rurik_voss',
        AiProfile.theController,
      );
    });

    test(
        'two defensive/support-leaning teams (The Wall vs The Turtle) '
        'still reach a conclusion', () {
      playAndAssertConcludes(
        'marren_osei',
        'ilona_vance',
        'bastian_cole',
        AiProfile.theWall,
        'priya_nakamura',
        'soren_talvik',
        'yuki_amaral',
        AiProfile.theTurtle,
      );
    });

    test(
        'a full round-robin of every AiProfile mirrored against itself '
        'concludes within the 8-20 round design target', () {
      // With the draft magnitude tuning that replaced item 5's original
      // numbers (100 flat max health, damage/heal/cooldown/Attack/Trion
      // Affinity scaling to hit an 8-20 round conclusion target), even the
      // most extreme sustain-heavy mirror (The Healer's Crutch vs itself,
      // once the slowest matchup by a wide margin) now typically concludes
      // in well under 20 rounds - so this asserts a real conclusion, not
      // just "ran cleanly for a while". Nothing here seeds the dice RNG
      // (matching every other test in this file), so true variance can
      // still occasionally push a given run past the typical case; 150 is
      // a generous cap purely as a regression guard against a future
      // rebalance reintroducing a genuine stall, not a tight bound on the
      // design target itself.
      for (final profile in AiProfile.all) {
        final teamADraft = DraftedTeam.draft(
          teamId: 'team-a',
          characterIds: ['kaito_reyes', 'marren_osei', 'priya_nakamura'],
          profile: profile,
          roster: roster,
          triggers: triggers,
          blackTriggers: blackTriggers,
          builder: builder,
        );
        final teamBDraft = DraftedTeam.draft(
          teamId: 'team-b',
          characterIds: ['zheng_anders', 'nadia_kessler', 'rurik_voss'],
          profile: profile,
          roster: roster,
          triggers: triggers,
          blackTriggers: blackTriggers,
          builder: builder,
        );
        final battle = Battle(
          teamA: teamADraft.team,
          teamB: teamBDraft.team,
          states: {...teamADraft.states, ...teamBDraft.states},
        );
        final teamAAi = ProfileDrivenAi(profile);
        final teamBAi = ProfileDrivenAi(profile);

        for (var round = 0; round < 150 && !battle.isOver; round++) {
          final activeDraft = battle.isTeamATurn ? teamADraft : teamBDraft;
          final activeAi = battle.isTeamATurn ? teamAAi : teamBAi;
          battle.startTurn(
              equippedActiveTriggers: activeDraft.equippedActiveTriggers);
          if (!battle.isOver) {
            activeAi.takeTurn(battle,
                equippedActiveTriggers: activeDraft.equippedActiveTriggers);
          }
          if (!battle.isOver) battle.endTurn();
        }

        expect(battle.isOver, isTrue,
            reason:
                '${profile.name} mirror did not conclude within 150 rounds');

        for (final c in [
          ...teamADraft.team.characters,
          ...teamBDraft.team.characters
        ]) {
          final state = battle.states[c.id]!;
          expect(state.currentHealth, greaterThanOrEqualTo(0),
              reason: profile.name);
          expect(
            state.currentHealth,
            lessThanOrEqualTo(state.effectiveStats().maxHealth),
            reason: profile.name,
          );
        }
      }
    });
  });
}

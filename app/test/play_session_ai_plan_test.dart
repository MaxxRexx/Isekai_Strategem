import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/loadout_selection.dart';
import 'package:isekai_strategem/src/game/play_session.dart';

/// A3 (AI through the shared path): the AI commits its whole turn as a blind
/// plan (planTurn) and resolves it through the same phase-priority resolver
/// the player's queue uses (resolveAiPlan), spending team B's Trion.
void main() {
  const playerIds = ['marren_osei', 'ilona_vance', 'bastian_cole'];
  const opponentIds = ['kaito_reyes', 'vela_ashworth', 'dross'];

  PlaySession freshSession() {
    final s = PlaySession.start(
      playerCharacterIds: playerIds,
      playerLoadouts: {
        for (final id in playerIds)
          id: defaultLoadoutSelectionFor(id).toLoadout(id),
      },
      opponentCharacterIds: opponentIds,
      opponentProfileId: 'the_tactician',
      firstTurn: 'teamA',
    );
    s.battle.teamA.trionPool.gain(500);
    return s;
  }

  test('the AI plans its whole turn up front without mutating the battle', () {
    final s = freshSession();
    // Move to the AI's turn.
    s.battle.endTurn();
    expect(s.battle.isTeamATurn, isFalse);
    s.battle.startTurn(equippedActiveTriggers: s.equippedB);
    // Guarantee the AI can afford to act, independent of the opening roll.
    s.battle.teamB.trionPool.gain(500);

    final healthBefore = {
      for (final f in s.teamA) f.id: f.currentHealth,
      for (final f in s.teamB) f.id: f.currentHealth,
    };
    final trionBefore = s.teamBTrion;

    final plan = s.aiB.planTurn(s.battle, equippedActiveTriggers: s.equippedB);

    // Planning is pure: no health changed, no Trion spent, nothing recorded.
    expect(plan, isNotEmpty);
    for (final f in [...s.teamA, ...s.teamB]) {
      expect(f.currentHealth, healthBefore[f.id]);
    }
    expect(s.teamBTrion, trionBefore);
    for (final id in opponentIds) {
      expect(s.battle.states[id]!.abilitiesUsedThisTurnCount, 0);
    }
    // Every planned action names a living owner, and either an equipped
    // ability or (for a planned move) a destination line.
    for (final action in plan) {
      expect(opponentIds, contains(action.characterId));
      if (action.isReposition) {
        expect(action.destination, isNotNull);
        expect(action.targetIds, isEmpty);
        continue;
      }
      expect(
        s.equippedB[action.characterId]!.map((t) => t.id),
        contains(action.triggerId),
      );
    }
  });

  test('resolving the AI plan spends team B Trion and applies effects', () {
    final s = freshSession();
    s.battle.endTurn();
    s.battle.startTurn(equippedActiveTriggers: s.equippedB);
    s.battle.teamB.trionPool.gain(500);

    final plan = s.aiB.planTurn(s.battle, equippedActiveTriggers: s.equippedB);
    // Moves are free in Trion, so they do not count towards the spend.
    final expectedSpend = plan.fold<int>(0, (sum, a) {
      if (a.isReposition) return sum;
      final state = s.battle.states[a.characterId]!;
      final trigger = s.equippedB[a.characterId]!.firstWhere(
        (t) => t.id == a.triggerId,
      );
      return sum + (trigger.trionCost * state.trionCostMultiplier()).round();
    });
    final trionBefore = s.teamBTrion;

    final round = s.resolveAiPlan(plan);

    expect(round.team, 'B');
    expect(round.actions.length, plan.length);
    expect(s.teamBTrion, trionBefore - expectedSpend);
    // The uses are now recorded (so end-of-turn cooldowns will be set).
    for (final action in plan) {
      expect(
        s.battle.states[action.characterId]!.abilitiesUsedThisTurnCount,
        greaterThan(0),
      );
    }
  });

  test('endTurn drives a full battle to completion via the AI plan path', () {
    final s = freshSession();
    var guard = 0;
    while (!s.isOver && guard < 200) {
      s.battle.teamA.trionPool.gain(50); // keep the player able to act
      // Queue one legal action for each living player character, if any.
      for (final fighter in s.teamA.where((f) => f.alive)) {
        final legal = s
            .legalActionsFor(fighter.id)
            .where((a) => a.affordable && a.legalTargetIds.isNotEmpty);
        if (legal.isNotEmpty) {
          final action = legal.first;
          s.queue(fighter.id, action.trigger.id, [action.legalTargetIds.first]);
        }
      }
      s.resolveQueue();
      if (s.isOver) break;
      s.endTurn();
      guard++;
    }
    expect(s.isOver, isTrue);
    expect(guard, lessThan(200));
  });
}

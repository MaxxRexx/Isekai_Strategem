import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/loadout_selection.dart';
import 'package:isekai_strategem/src/game/play_session.dart';

import 'support/battle_positions.dart';

/// A1 (turn-queue engine): the queue/unqueue/resolve contract on
/// [PlaySession]. Trion is spent at queue time and refunded on un-queue;
/// effects are applied only when the queue resolves.
void main() {
  const playerIds = ['vela_ashworth', 'kaito_reyes', 'dross'];
  const opponentIds = ['soren_talvik', 'ilona_vance', 'bastian_cole'];

  PlaySession freshSession() {
    final session = PlaySession.start(
      playerCharacterIds: playerIds,
      playerLoadouts: {
        for (final id in playerIds)
          id: defaultLoadoutSelectionFor(id).toLoadout(id),
      },
      opponentCharacterIds: opponentIds,
      opponentProfileId: 'the_tactician',
      // Player goes first so queueing is legal from the start.
      firstTurn: 'teamA',
    );
    // Guarantee affordability so tests do not depend on the opening
    // Trion tier roll.
    session.battle.teamA.trionPool.gain(500);
    spreadForFullRangeCoverage(session);
    return session;
  }

  LegalAction firstLegal(PlaySession s, String characterId) => s
      .legalActionsFor(characterId)
      .firstWhere((a) => a.affordable && a.legalTargetIds.isNotEmpty);

  test('queueing an action spends Trion and un-queueing refunds it', () {
    final session = freshSession();
    const charId = 'vela_ashworth';
    final action = firstLegal(session, charId);
    final before = session.teamATrion;

    final result = session.queue(charId, action.trigger.id, [
      action.legalTargetIds.first,
    ]);

    expect(result.success, isTrue);
    expect(session.queuedActions.length, 1);
    expect(session.teamATrion, before - action.actualTrionCost);

    expect(session.unqueue(0), isTrue);
    expect(session.queuedActions, isEmpty);
    expect(session.teamATrion, before);
  });

  test('the same ability cannot be queued twice in one turn', () {
    final session = freshSession();
    const charId = 'vela_ashworth';
    final action = firstLegal(session, charId);

    expect(
      session.queue(charId, action.trigger.id, [
        action.legalTargetIds.first,
      ]).success,
      isTrue,
    );
    final second = session.queue(charId, action.trigger.id, [
      action.legalTargetIds.first,
    ]);

    expect(second.success, isFalse);
    expect(second.error, contains('already queued'));
    expect(session.queuedCountFor(charId), 1);
  });

  test('per-turn ability limit scales with FAT and blocks the overflow', () {
    final session = freshSession();
    const charId = 'vela_ashworth';
    // Force FAT so the per-turn limit becomes 3.
    session.forceFat(charId);

    var succeeded = 0;
    QueueOutcome? overflow;
    for (final trigger in session.equippedA[charId]!) {
      final legal = session
          .legalActionsFor(charId)
          .where((a) => a.trigger.id == trigger.id);
      if (legal.isEmpty || legal.first.legalTargetIds.isEmpty) continue;
      final result = session.queue(charId, trigger.id, [
        legal.first.legalTargetIds.first,
      ]);
      if (result.success) {
        succeeded++;
      } else {
        overflow = result;
      }
    }

    expect(succeeded, 3);
    expect(session.queuedCountFor(charId), 3);
    expect(overflow, isNotNull);
    expect(overflow!.error, contains('No ability uses left'));
  });

  test('resolveQueue applies the queued actions, clears them, and keeps '
      'Trion spent', () {
    final session = freshSession();
    const charId = 'vela_ashworth';
    final action = firstLegal(session, charId);
    session.queue(charId, action.trigger.id, [action.legalTargetIds.first]);
    final trionAfterQueue = session.teamATrion;

    final round = session.resolveQueue();

    expect(round.team, 'A');
    expect(round.actions.length, 1);
    expect(round.actions.first.triggerId, action.trigger.id);
    expect(session.queuedActions, isEmpty);
    // Resolving consumes the already-spent Trion; it is not refunded.
    expect(session.teamATrion, trionAfterQueue);
  });
}

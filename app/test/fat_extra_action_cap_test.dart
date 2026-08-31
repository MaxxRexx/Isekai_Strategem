import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/loadout_selection.dart';
import 'package:isekai_strategem/src/game/play_session.dart';

import 'support/battle_positions.dart';

/// Item #4's Full Arms Trigger cap: a squad gets one extra action per turn,
/// however many of its members rolled FAT.
///
/// The engine can only see this at resolution, by which point the whole turn
/// is committed, so the queue does the accounting. The claim is derived from
/// what is queued rather than stored, which is what makes un-queueing the
/// second action hand it back.
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
      firstTurn: 'teamA',
    );
    session.battle.teamA.trionPool.gain(500);
    // The extra actions this test is about also cost a typed token (item
    // #15). Wilds pay for any origin, so stocking them keeps the test about
    // the cap and not about the roll.
    session.battle.teamA.typedTrion.gain(TrionTokenType.wild, 20);
    spreadForFullRangeCoverage(session);
    // Everyone rolled FAT, which is the situation the cap exists for.
    for (final state in session.battle.statesOf(session.battle.teamA)) {
      state.fatTriggeredThisTurn = true;
    }
    return session;
  }

  /// Queues [count] of [characterId]'s legal abilities, returning how many
  /// were accepted.
  int queueUpTo(PlaySession session, String characterId, int count) {
    var queued = 0;
    for (final action in session.legalActionsFor(characterId)) {
      if (queued == count) break;
      if (!action.affordable || action.legalTargetIds.isEmpty) continue;
      final result = session.queue(characterId, action.trigger.id, [
        action.legalTargetIds.first,
      ]);
      if (result.success) queued++;
    }
    return queued;
  }

  test('one character can still act twice on a FAT turn', () {
    final session = freshSession();

    expect(queueUpTo(session, 'vela_ashworth', 2), 2);
    expect(session.projectedExtraActionClaimant, contains('vela_ashworth'));
  });

  test('a squadmate cannot take a second extra action in the same turn', () {
    final session = freshSession();
    queueUpTo(session, 'vela_ashworth', 2);

    // The squadmate's first action is untouched: the cap is on the extras.
    expect(queueUpTo(session, 'kaito_reyes', 1), 1);
    // Their second is not, even though they rolled FAT themselves.
    expect(queueUpTo(session, 'kaito_reyes', 1), 0);
  });

  test('un-queueing the second action hands the claim back', () {
    final session = freshSession();
    queueUpTo(session, 'vela_ashworth', 2);
    expect(queueUpTo(session, 'kaito_reyes', 2), 1,
        reason: 'the claim was already taken');

    // Drop Vela's second action.
    final second = session.queuedActions
        .lastIndexWhere((q) => q.characterId.endsWith('vela_ashworth'));
    expect(session.unqueue(second), isTrue);
    expect(session.projectedExtraActionClaimant, isNull);

    expect(queueUpTo(session, 'kaito_reyes', 1), 1,
        reason: 'the freed claim is anyone\'s again');
    expect(session.projectedExtraActionClaimant, contains('kaito_reyes'));
  });

  test('the blocked reason names who holds the extra action', () {
    final session = freshSession();
    queueUpTo(session, 'vela_ashworth', 2);
    queueUpTo(session, 'kaito_reyes', 1);

    final blocked = session
        .abilityDisplaysFor('kaito_reyes')
        .map((d) => d.blockedReason)
        .whereType<String>();

    expect(blocked, anyElement(contains('one extra action')));
    expect(blocked, anyElement(contains('Vela')));
  });

  test('a move counts as the action it costs, cap included', () {
    final session = freshSession();
    // Vela steps and then attacks: two actions, so the claim is hers.
    expect(
      session.queueReposition('vela_ashworth', BattlePosition.middle).success,
      isTrue,
    );
    expect(queueUpTo(session, 'vela_ashworth', 1), 1);
    expect(session.projectedExtraActionClaimant, contains('vela_ashworth'));

    // Dross may still move once, but not move and attack.
    expect(
      session.queueReposition('dross', BattlePosition.middle).success,
      isTrue,
    );
    expect(queueUpTo(session, 'dross', 1), 0);
  });
}

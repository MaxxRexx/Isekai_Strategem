import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/loadout_selection.dart';
import 'package:isekai_strategem/src/game/play_session.dart';

/// Phase F (§10): the clickable-portrait detail panel gates an enemy's
/// loadout behind Mind's Eye. [PlaySession.revealedEnemyIds] is the union of
/// every team-A wielder's reveal set, which the battle UI reads to decide
/// whether to list an opponent's abilities.
void main() {
  const playerIds = ['vela_ashworth', 'kaito_reyes', 'dross'];
  const opponentIds = ['soren_talvik', 'ilona_vance', 'bastian_cole'];

  PlaySession freshSession() => PlaySession.start(
    playerCharacterIds: playerIds,
    playerLoadouts: {
      for (final id in playerIds)
        id: defaultLoadoutSelectionFor(id).toLoadout(id),
    },
    opponentCharacterIds: opponentIds,
    opponentProfileId: 'the_tactician',
    firstTurn: 'teamA',
  );

  test('no enemies are revealed at battle start', () {
    expect(freshSession().revealedEnemyIds, isEmpty);
  });

  test('revealedEnemyIds unions every team-A wielder reveal set', () {
    final session = freshSession();
    // Simulate a Mind's Eye reveal landing on the engine state, the same
    // mutation _resolveMindsEye performs.
    session.battle.stateById(playerIds.first).revealedEnemyIds
        .add(opponentIds.first);
    session.battle.stateById(playerIds[1]).revealedEnemyIds
        .add(opponentIds[1]);

    final revealed = session.revealedEnemyIds;
    expect(revealed, contains(opponentIds.first));
    expect(revealed, contains(opponentIds[1]));
    expect(revealed, isNot(contains(opponentIds[2])));
  });
}

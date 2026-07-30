// A1 manual demo: exercises the new PlaySession turn-queue API and prints a
// readable trace, so the queue-then-resolve behavior can be seen before it
// is wired into the battle UI (that happens in stage A4).
//
// Run from the app/ directory:  dart run tool/queue_demo.dart

import 'package:isekai_strategem/src/game/loadout_selection.dart';
import 'package:isekai_strategem/src/game/play_session.dart';

void main() {
  const playerIds = ['vela_ashworth', 'kaito_reyes', 'dross'];
  const opponentIds = ['soren_talvik', 'ilona_vance', 'bastian_cole'];

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
  // Top up Trion so the demo does not depend on the opening tier roll, and
  // force FAT on Vela so she may queue more than one ability this turn.
  session.battle.teamA.trionPool.gain(500);
  const charId = 'vela_ashworth';
  session.forceFat(charId);

  print('=== A1 turn-queue demo (Vela Ashworth) ===');
  print('Trion at start: ${session.teamATrion}\n');

  final legal = session
      .legalActionsFor(charId)
      .where((a) => a.legalTargetIds.isNotEmpty)
      .toList();
  final first = legal[0];
  final second = legal[1];

  var before = session.teamATrion;
  session.queue(charId, first.trigger.id, [first.legalTargetIds.first]);
  print('Queue  ${first.trigger.name} (cost ${first.actualTrionCost})');
  print('  Trion $before -> ${session.teamATrion}   '
      'queue size ${session.queuedActions.length}\n');

  before = session.teamATrion;
  session.queue(charId, second.trigger.id, [second.legalTargetIds.first]);
  print('Queue  ${second.trigger.name} (cost ${second.actualTrionCost})');
  print('  Trion $before -> ${session.teamATrion}   '
      'queue size ${session.queuedActions.length}\n');

  before = session.teamATrion;
  session.unqueue(1);
  print('Un-queue  ${second.trigger.name}');
  print('  Trion $before -> ${session.teamATrion} (refunded)   '
      'queue size ${session.queuedActions.length}\n');

  print('Opponent HP before resolve:');
  for (final f in session.teamB) {
    print('  ${f.name}: ${f.currentHealth}/${f.maxHealth}');
  }
  print('');

  final round = session.resolveQueue();
  print('resolveQueue() applied ${round.actions.length} action(s):');
  for (final a in round.actions) {
    for (final t in a.targets) {
      print('  ${a.characterName} used ${a.triggerName} on ${t.targetName}'
          ' -> ${t.damage} dmg, HP ${t.healthAfter}');
    }
  }
  print('');
  print('Trion after resolve: ${session.teamATrion} '
      '(unchanged; spent at queue, not refunded on resolve)');
  print('Queue size after resolve: ${session.queuedActions.length}');
}

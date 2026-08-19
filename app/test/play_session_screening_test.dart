import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/draft.dart';
import 'package:isekai_strategem/src/game/play_session.dart';

/// Item 1b, queue side: what screening does to a turn the player has already
/// committed.
///
/// The case this exists for has no equivalent before 1b. Band minimums mean a
/// target can become *too close* to shoot, and killing a screen shortens the
/// distance, so your own squad can walk your own queued shot out the bottom
/// of its band mid-turn. Rather than let it resolve into thin air, the shot is
/// pulled and the Trion handed back, the same bargain un-queueing a
/// Reposition already offers.
void main() {
  Loadout mixed(String id) => Loadout(
        characterId: id,
        triggers: [
          triggerCatalog['twin_fang_strike'], // Close Range
          triggerCatalog['war_chant'], // Close Range, self
          triggerCatalog['charm_whisper'], // Close Range, control
          triggerCatalog['suppressing_fire'], // Long Range, 2 to 4
        ],
      );

  const squad = ['marren_osei', 'ilona_vance', 'bastian_cole'];

  PlaySession session() {
    final s = PlaySession.start(
      playerCharacterIds: squad,
      playerLoadouts: {for (final id in squad) id: mixed(id)},
      opponentCharacterIds: ['kaito_reyes', 'vela_ashworth', 'dross'],
      opponentProfileId: 'the_tactician',
      firstTurn: 'teamA',
    );
    s.battle.teamA.trionPool.gain(500);
    return s;
  }

  test('the ruler-facing distance counts the bodies in the way', () {
    final s = session();
    for (final c in s.battle.teamA.characters) {
      s.battle.states[c.id]!.position = BattlePosition.front;
    }
    final theirs = s.battle.teamB.characters;
    s.battle.states[theirs[0].id]!.position = BattlePosition.front;
    s.battle.states[theirs[1].id]!.position = BattlePosition.front;
    s.battle.states[theirs[2].id]!.position = BattlePosition.back;

    final engine = s.battle.turnEngine;
    final me = s.battle.states['marren_osei']!;
    expect(engine.distanceBetween(me, s.battle.states[theirs[2].id]!), 4,
        reason: '0 + 2 lines, plus the two bodies screening them');
  });

  test('an out-of-range message names screening and how to fix it', () {
    final s = session();
    // Me on my middle line with a Long Range shot (2 to 4). Their front pair
    // sit at 1, under Long Range's minimum. Their sniper is behind both of
    // them at 1 + 2 + 2 = 5, over its maximum, where the bare geometry of 3
    // would have been comfortably inside it. So every target is out of band,
    // and screening is the reason for the only one worth talking about.
    for (final c in s.battle.teamA.characters) {
      s.battle.states[c.id]!.position = BattlePosition.middle;
    }
    final theirs = s.battle.teamB.characters;
    s.battle.states[theirs[0].id]!.position = BattlePosition.front;
    s.battle.states[theirs[1].id]!.position = BattlePosition.front;
    s.battle.states[theirs[2].id]!.position = BattlePosition.back;

    final display = s
        .abilityDisplaysFor('marren_osei')
        .firstWhere((d) => d.trigger.id == 'suppressing_fire');

    expect(display.blockedByRange, isTrue);
    final reason = display.blockedReason!;
    expect(reason, contains('2 to 4'), reason: 'the band and its window');
    expect(reason, contains('Back line is at 5'),
        reason: 'the number the player can see on the ruler');
    expect(reason, contains('screening'),
        reason: 'naming the cause is the point: the fix is not to move');
    expect(reason, contains('break the screen'));
    expect(reason, isNot(contains('nobody is standing there')),
        reason: 'they are plainly standing there, which is the old lie');
  });

  test('a kill that drops a target under the band refunds the queued shot',
      () {
    final s = session();
    // Me on my front line. Their sniper on their middle line with one body in
    // front of it, so 0 + 1 + 1 = 2, which Long Range (2 to 4) just reaches.
    for (final c in s.battle.teamA.characters) {
      s.battle.states[c.id]!.position = BattlePosition.front;
    }
    final theirs = s.battle.teamB.characters;
    final screen = s.battle.states[theirs[0].id]!
      ..position = BattlePosition.front;
    final sniper = s.battle.states[theirs[1].id]!
      ..position = BattlePosition.middle;
    s.battle.states[theirs[2].id]!
      ..position = BattlePosition.middle
      ..currentHealth = 0;

    final engine = s.battle.turnEngine;
    final shooter = s.battle.states['marren_osei']!;
    expect(engine.distanceBetween(shooter, sniper), 2,
        reason: 'one line plus one screen');

    final before = s.battle.teamA.trionPool.current;
    final queued = s.queue(
      'marren_osei',
      'suppressing_fire',
      [sniper.character.id],
    );
    expect(queued.success, isTrue, reason: 'legal when it was queued');
    final spent = before - s.battle.teamA.trionPool.current;
    expect(spent, greaterThan(0), reason: 'Trion leaves the pool at queue time');

    // Now the screen dies before the shot resolves, which is the whole point:
    // the sniper is dragged from 2 down to 1, under Long Range's minimum.
    screen.currentHealth = 0;
    expect(engine.distanceBetween(shooter, sniper), 1);

    final round = s.resolveQueue();

    expect(s.battle.teamA.trionPool.current, before,
        reason: 'the shot was pulled, so every Trion comes back');
    final line = round.actions
        .firstWhere((a) => a.triggerId == 'suppressing_fire');
    expect(line.triggerName, contains('called off'),
        reason: 'the log has to say why, or it reads as nothing happening');
    expect(line.targets, isEmpty);
    expect(sniper.currentHealth, greaterThan(0),
        reason: 'and the shot did not land');
  });

  test('a shot that is still in band resolves as normal', () {
    // The control for the test above: same shape, but nothing moves the
    // target, so the refund path must not fire.
    final s = session();
    for (final c in s.battle.teamA.characters) {
      s.battle.states[c.id]!.position = BattlePosition.front;
    }
    final theirs = s.battle.teamB.characters;
    s.battle.states[theirs[0].id]!.position = BattlePosition.front;
    final sniper = s.battle.states[theirs[1].id]!
      ..position = BattlePosition.middle;
    s.battle.states[theirs[2].id]!
      ..position = BattlePosition.middle
      ..currentHealth = 0;

    final before = s.battle.teamA.trionPool.current;
    expect(
      s
          .queue('marren_osei', 'suppressing_fire',
              [sniper.character.id])
          .success,
      isTrue,
    );
    final round = s.resolveQueue();

    expect(s.battle.teamA.trionPool.current, lessThan(before),
        reason: 'a shot that lands is paid for');
    final line = round.actions
        .firstWhere((a) => a.triggerId == 'suppressing_fire');
    expect(line.triggerName, isNot(contains('called off')));
  });
}

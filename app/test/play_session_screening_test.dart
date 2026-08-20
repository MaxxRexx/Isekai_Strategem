import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/draft.dart';
import 'package:isekai_strategem/src/game/play_session.dart';

/// Item 1b, queue side: what screening does to a turn the player has already
/// committed.
///
/// The case this exists for has no equivalent before 1b. Band minimums mean a
/// target can become *too close* to shoot, and killing a screen shortens the
/// distance, so your own squad can walk your own committed shot out the bottom
/// of its band mid-turn. The shot bends to reach them and lands anyway, and
/// the squad pays for it out of next turn's Trion. Breaking a screen should
/// never cost you the attack it set up.
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

  /// Always rolls the top of the die. A bend depends on an earlier attack
  /// actually killing the screen, so leaving that to chance would make these
  /// tests pass or fail on the shuffle.
  PlaySession session() {
    final s = PlaySession.start(
      playerCharacterIds: squad,
      playerLoadouts: {for (final id in squad) id: mixed(id)},
      opponentCharacterIds: ['kaito_reyes', 'vela_ashworth', 'dross'],
      opponentProfileId: 'the_tactician',
      firstTurn: 'teamA',
      turnEngine: TurnEngine(
        combatEngine:
            CombatEngine(diceRoller: DiceRoller(const _AlwaysMax(19))),
        statusEffectEngine:
            StatusEffectEngine(diceRoller: DiceRoller(const _AlwaysMax(19))),
      ),
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

  /// The real shape of a bend, end to end: my squad on the front line, their
  /// sniper on their middle line behind one body, and both actions committed
  /// in the same turn.
  ///
  /// Marren kills the screen and Ilona shoots the sniper. Marren resolves
  /// first because attacks tie-break on Team Spirit deviation and hers is 5
  /// against Ilona's 0, so the screen is already gone when the shot lands.
  /// That is the whole scenario, rather than killing the screen by hand
  /// between queueing and resolving, which is not something a turn can do.
  ({PlaySession session, CharacterBattleState screen, CharacterBattleState sniper})
      committedBend() {
    final s = session();
    for (final c in s.battle.teamA.characters) {
      s.battle.states[c.id]!.position = BattlePosition.front;
    }
    final theirs = s.battle.teamB.characters;
    final screen = s.battle.states[theirs[0].id]!
      ..position = BattlePosition.front
      ..currentHealth = 1; // so the Close Range hit is certain to finish it
    final sniper = s.battle.states[theirs[1].id]!
      ..position = BattlePosition.middle;
    s.battle.states[theirs[2].id]!
      ..position = BattlePosition.middle
      ..currentHealth = 0;

    expect(s.battle.turnEngine.distanceBetween(
            s.battle.states['ilona_vance']!, sniper), 2,
        reason: 'their middle line, plus the one body screening it');

    expect(
      s.queue('marren_osei', 'twin_fang_strike', [screen.character.id]).success,
      isTrue,
    );
    expect(
      s.queue('ilona_vance', 'suppressing_fire', [sniper.character.id]).success,
      isTrue,
      reason: 'the shot is legal at the moment it is committed',
    );
    return (session: s, screen: screen, sniper: sniper);
  }

  test('a kill that drops a target under the band bends the shot instead of '
      'wasting it', () {
    final f = committedBend();
    final before = f.sniper.currentHealth;
    final round = f.session.resolveQueue();

    expect(f.screen.isAlive, isFalse, reason: 'the screen went down first');
    expect(f.session.battle.turnEngine.distanceBetween(
            f.session.battle.states['ilona_vance']!, f.sniper), 1,
        reason: 'which dragged the sniper under Long Range\'s minimum of 2');

    final line =
        round.actions.firstWhere((a) => a.triggerId == 'suppressing_fire');
    expect(f.sniper.currentHealth, lessThan(before),
        reason: 'the shot bends and lands rather than being wasted');
    expect(line.bend, isNotNull, reason: 'and the log knows it bent');
    expect(f.session.battle.teamA.trionBacklash, isTrue,
        reason: 'the squad carries Trion Backlash into next turn');
  });

  test('the bend explains itself in full', () {
    final f = committedBend();
    final round = f.session.resolveQueue();
    final bend = round.actions
        .firstWhere((a) => a.triggerId == 'suppressing_fire')
        .bend!;

    // Everything the Details panel needs to answer "why was this legal, what
    // changed, and what did it cost" without the player reconstructing it.
    expect(bend.targetName, f.sniper.character.name);
    expect(bend.bandLabel, 'Long Range');
    expect(bend.bandWindow, '2 to 4');
    expect(bend.bandMinimum, 2);
    expect(bend.distanceWhenCommitted, 2);
    expect(bend.distanceNow, 1);
    expect(bend.screensWhenCommitted, 1);
    expect(bend.screensBroken, [f.screen.character.name],
        reason: 'naming the body that opened the lane is the whole story');
    expect(bend.backlashTier, 10);
  });

  test('Trion Backlash caps next turn\'s income at the Low tier, once', () {
    final s = session();
    final team = s.battle.teamA;
    team.trionBacklash = true;
    final before = team.trionPool.current;

    final result = s.battle.turnEngine
        .resolveTeamTrionGain(team, s.battle.states);
    expect(result.tier, TrionTier.low);
    expect(team.trionPool.current - before, 10);
    expect(team.trionBacklash, isFalse,
        reason: 'the price is paid once, not every turn after');
  });

  test('bending is a flag, not a counter, so a combo is not taxed per shot',
      () {
    // Two shots bending in the same turn cost exactly what one does. That is
    // the clause that stops the rule punishing the combo it exists to reward.
    final f = committedBend();
    final s = f.session;
    expect(
      s.queue('bastian_cole', 'suppressing_fire', [f.sniper.character.id])
          .success,
      isTrue,
    );
    final round = s.resolveQueue();

    expect(round.actions.where((a) => a.bend != null), hasLength(2),
        reason: 'both Long Range shots bent');

    final team = s.battle.teamA;
    final before = team.trionPool.current;
    s.battle.turnEngine.resolveTeamTrionGain(team, s.battle.states);
    expect(team.trionPool.current - before, 10,
        reason: 'two bends cost the same as one: the Low tier, not twice over');
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
    expect(line.bend, isNull, reason: 'nothing bent, so nothing to explain');
    expect(s.battle.teamA.trionBacklash, isFalse,
        reason: 'and no Backlash for a shot that never needed to bend');
  });
}

/// A [Random] that always returns the top of the range, so every attack in
/// these tests lands.
class _AlwaysMax implements Random {
  final int value;
  const _AlwaysMax(this.value);
  @override
  int nextInt(int max) => value % max;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

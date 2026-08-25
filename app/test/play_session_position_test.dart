import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/draft.dart';
import 'package:isekai_strategem/src/game/play_session.dart';

/// #1 (range bands), queue side: the player plans against the position they
/// will be standing in once the queue resolves, not the one they are standing
/// in now. Repositions resolve first (the arm phase), so move-then-strike
/// works and range is judged accordingly.
void main() {
  // Close and Long in the same Loadout, which is what makes the fixture
  // below able to test both edges of a band with one squad.
  Loadout mixed(String id) => Loadout(
        characterId: id,
        triggers: [
          triggerCatalog['twin_fang_strike'], // Close Range (0 to 2)
          triggerCatalog['war_chant'], // Close Range, self
          triggerCatalog['charm_whisper'], // Close Range, control
          triggerCatalog['suppressing_fire'], // Long Range (2 to 4)
        ],
      );

  const squad = ['marren_osei', 'ilona_vance', 'bastian_cole'];
  const actor = 'marren_osei';

  /// Team A on the back line, team B on the middle line: enemy distance 3, so
  /// Long Range reaches and Close Range does not (Close is 0 to 2 after 1b).
  /// One step forward makes distance 2 and flips both. Team B stacks on one
  /// line, so nobody screens anybody and these cases stay about the two lines
  /// alone; screening has its own tests.
  PlaySession session() {
    final s = PlaySession.start(
      playerCharacterIds: squad,
      playerLoadouts: {for (final id in squad) id: mixed(id)},
      opponentCharacterIds: ['kaito_reyes', 'vela_ashworth', 'dross'],
      opponentProfileId: 'the_tactician',
      firstTurn: 'teamA',
    );
    s.battle.teamA.trionPool.gain(500);
    for (final c in s.battle.teamA.characters) {
      s.battle.stateById(c.id).position = BattlePosition.back;
    }
    for (final c in s.battle.teamB.characters) {
      s.battle.stateById(c.id).position = BattlePosition.middle;
    }
    return s;
  }

  /// Pulls their squad onto their front line, so a step forward drops the gap
  /// to 1 and Long Range loses its minimum. The shared fixture cannot show
  /// that any more: at Close Range's widened 0 to 2, a squad on the middle
  /// line is still 2 away after one step, which Long Range reaches.
  void pullEnemiesToTheFront(PlaySession s) {
    for (final c in s.battle.teamB.characters) {
      s.battle.stateById(c.id).position = BattlePosition.front;
    }
  }

  List<String> targetsFor(PlaySession s, String triggerId) =>
      s
          .legalActionsFor(actor)
          .where((a) => a.trigger.id == triggerId)
          .map((a) => a.legalTargetIds)
          .firstWhere((_) => true, orElse: () => const []);

  test('the range band decides which abilities have any target at all', () {
    final s = session();
    expect(targetsFor(s, 'twin_fang_strike'), isEmpty,
        reason: 'Close Range cannot reach across a gap of 3');
    expect(targetsFor(s, 'suppressing_fire'), isNotEmpty,
        reason: 'Long Range reaches from 2 to 4');
  });

  test('an out-of-band ability reports why, and is not usable', () {
    final s = session();
    final display = s
        .abilityDisplaysFor(actor)
        .firstWhere((d) => d.trigger.id == 'twin_fang_strike');

    expect(display.usable, isFalse);
    expect(display.blockedByRange, isTrue);
    expect(display.blockedReason, contains('Close Range'));
    expect(display.blockedReason, contains('0 to 2'));
  });

  test('queueing a Reposition moves the projected position, not the live one',
      () {
    final s = session();
    expect(s.queueReposition(actor, BattlePosition.middle).success, isTrue);

    expect(s.projectedPositionOf(actor), BattlePosition.middle);
    expect(s.battle.stateById(actor).position, BattlePosition.back,
        reason: 'nothing moves until the queue resolves');
  });

  test('move then strike: a queued step brings a Close ability into band', () {
    final s = session();
    s.forceFat(actor); // two ability uses, so the move plus a swing fit

    s.queueReposition(actor, BattlePosition.middle);

    final targets = targetsFor(s, 'twin_fang_strike');
    expect(targets, isNotEmpty,
        reason: 'range is judged from where the character will be standing');
    expect(s.queue(actor, 'twin_fang_strike', [targets.first]).success, isTrue);
  });

  test('stepping forward pushes a Long Range ability out of its band', () {
    final s = session();
    pullEnemiesToTheFront(s);
    s.forceFat(actor);
    s.queueReposition(actor, BattlePosition.middle);

    expect(targetsFor(s, 'suppressing_fire'), isEmpty,
        reason: 'Long Range has a minimum: closing in gives up the shot');
  });

  test('queue rejects a target outside the band even when named directly', () {
    final s = session();
    final enemy = s.battle.teamB.characters.first.id;

    final result = s.queue(actor, 'twin_fang_strike', [enemy]);

    expect(result.success, isFalse);
    expect(result.error, contains('Close Range'));
  });

  test('a Reposition spends one of the turn ability uses', () {
    final s = session();
    // Against the character's real limit rather than a hardcoded 1: FAT
    // triggers on its own roll at the start of a turn, so the limit is not
    // fixed across runs.
    final maxUses = s.battle.turnEngine.fatEngine
        .maxAbilitiesThisTurn(s.battle.stateById(actor));

    // Pace back and forth so every step stays adjacent to the last.
    for (var i = 0; i < maxUses; i++) {
      final step = i.isEven ? BattlePosition.middle : BattlePosition.back;
      expect(s.queueReposition(actor, step).success, isTrue);
    }
    expect(s.queuedCountFor(actor), maxUses);

    final overflow = s.queueReposition(actor, BattlePosition.middle);
    expect(overflow.success, isFalse);
    expect(overflow.error, contains('No ability uses left'));
    expect(s.legalRepositionsFor(actor), isEmpty);
  });

  test('only one step per Reposition, measured from the projected position',
      () {
    final s = session();
    s.forceFat(actor);
    expect(s.queueReposition(actor, BattlePosition.front).success, isFalse,
        reason: 'front is two steps from back');

    s.queueReposition(actor, BattlePosition.middle);
    expect(s.legalRepositionsFor(actor), contains(BattlePosition.front));
    expect(s.queueReposition(actor, BattlePosition.front).success, isTrue);
    expect(s.projectedPositionOf(actor), BattlePosition.front);
  });

  test('un-queueing the move drops the strike that depended on it, refunded',
      () {
    final s = session();
    s.forceFat(actor);
    s.queueReposition(actor, BattlePosition.middle);
    final targets = targetsFor(s, 'twin_fang_strike');
    final before = s.teamATrion;
    s.queue(actor, 'twin_fang_strike', [targets.first]);
    expect(s.teamATrion, lessThan(before));

    expect(s.unqueue(0), isTrue); // the Reposition

    expect(s.queuedActions, isEmpty,
        reason: 'the strike can no longer reach, so it does not stay queued');
    expect(s.teamATrion, before, reason: 'its Trion comes back');
  });

  test('resolveQueue moves first, then resolves the abilities', () {
    final s = session();
    s.forceFat(actor);
    final targets = () {
      s.queueReposition(actor, BattlePosition.middle);
      return targetsFor(s, 'twin_fang_strike');
    }();
    s.queue(actor, 'twin_fang_strike', [targets.first]);

    final round = s.resolveQueue();

    expect(round.actions.map((a) => a.triggerId).toList(),
        [repositionActionId, 'twin_fang_strike']);
    expect(s.battle.stateById(actor).position, BattlePosition.middle);
    expect(s.queuedActions, isEmpty);
  });

  test('a zone-locked character cannot queue a move', () {
    final s = session();
    final state = s.battle.stateById(actor);
    state.statusEffects.add(
      StatusEffectInstance(
        definitionId: 'forced_repetition',
        remainingTurns: 2,
        sourceCharacterId: 'kaito_reyes',
      ),
    );

    expect(s.legalRepositionsFor(actor), isEmpty);
    expect(s.queueReposition(actor, BattlePosition.middle).success, isFalse);
  });

  test('an ability the move brings into band is flagged, not just greyed', () {
    final s = session();
    // Pin the limit to one action: FAT rolls on its own at the start of a
    // turn, and with it the move would leave a use spare and the ability
    // would simply be usable.
    s.battle.stateById(actor).fatTriggeredThisTurn = false;
    s.queueReposition(actor, BattlePosition.middle); // spends the only action

    final display = s
        .abilityDisplaysFor(actor)
        .firstWhere((d) => d.trigger.id == 'twin_fang_strike');

    expect(display.reachableAfterMove, isTrue,
        reason: 'the step is what put it in band');
    expect(display.blockedByRange, isFalse, reason: 'range is no longer the problem');
    expect(display.blockedReason, contains('In range once the move resolves'));
    expect(display.blockedReason, contains('Full Arms Trigger'),
        reason: 'names the thing that buys moving and attacking together');
  });

  test('an ability out of band even after the move is not flagged', () {
    final s = session();
    pullEnemiesToTheFront(s);
    s.queueReposition(actor, BattlePosition.middle);

    final display = s
        .abilityDisplaysFor(actor)
        .firstWhere((d) => d.trigger.id == 'suppressing_fire');

    expect(display.reachableAfterMove, isFalse);
    expect(display.blockedByRange, isTrue);
    expect(display.blockedReason, contains('Out of range'));
  });

  test('an ability already in band before the move is not flagged either', () {
    final s = session();
    s.forceFat(actor);
    s.queueReposition(actor, BattlePosition.middle);

    // war_chant is self-targeted, so it reached from either line.
    final display = s
        .abilityDisplaysFor(actor)
        .firstWhere((d) => d.trigger.id == 'war_chant');

    expect(display.reachableAfterMove, isFalse);
    expect(display.usable, isTrue);
  });

  test('the move hint points at the step that brings more abilities to bear',
      () {
    final s = session();
    // Three of the four Triggers are Close Range, so from the back line the
    // hint should be to close the gap.
    expect(s.suggestRepositionFor(actor), BattlePosition.middle);
  });
}

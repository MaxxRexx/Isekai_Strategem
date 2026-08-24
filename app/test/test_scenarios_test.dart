import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/draft.dart';
import 'package:flutter/material.dart';
import 'package:isekai_strategem/src/game/test_scenarios.dart';
import 'package:isekai_strategem/src/screens/play_flow_screen.dart';

/// The Tests tab is only useful if every scenario in it actually loads. These
/// are the checks that a scenario is well-formed, not checks on the rules it
/// exists to exercise: a scenario naming a Trigger that does not exist, or a
/// kit that busts a character's Trion Capacity, would otherwise only be found
/// by tapping it.
void main() {
  test('every scenario has a unique id and names a work item', () {
    final ids = testScenarios.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'duplicate scenario id');
    for (final s in testScenarios) {
      expect(s.name, isNotEmpty);
      expect(s.item, isNotEmpty);
      expect(s.goal, isNotEmpty);
      expect(s.steps, isNotEmpty, reason: '${s.id} says nothing to do');
      expect(s.expect, isNotEmpty,
          reason: '${s.id} says nothing to look for');
    }
  });

  test('every squad is three characters and the two do not overlap', () {
    for (final s in testScenarios) {
      expect(s.playerIds.length, 3, reason: s.id);
      expect(s.enemyIds.length, 3, reason: s.id);
      // The mirror-match stopgap is still in force until item #14, and a
      // scenario that trips it throws at battle construction rather than
      // failing gracefully.
      expect(
        s.playerIds.toSet().intersection(s.enemyIds.toSet()),
        isEmpty,
        reason: '${s.id} drafts the same character onto both squads',
      );
    }
  });

  test('every character has a kit, and every kit is a legal Loadout', () {
    for (final s in testScenarios) {
      for (final id in [...s.playerIds, ...s.enemyIds]) {
        expect(s.kits.containsKey(id), isTrue,
            reason: '${s.id} has no kit for $id');
        for (final triggerId in s.kits[id]!) {
          expect(triggerCatalog.contains(triggerId), isTrue,
              reason: '${s.id}: unknown Trigger $triggerId');
        }
        final validation = s.loadoutFor(id).validateFor(roster[id]);
        expect(validation.isValid, isTrue,
            reason: '${s.id}, $id: ${validation.errors.join('; ')}');
      }
    }
  });

  test('every arranged character is actually in the scenario', () {
    for (final s in testScenarios) {
      final everyone = {...s.playerIds, ...s.enemyIds};
      for (final id in [
        ...s.positions.keys,
        ...s.health.keys,
        ...s.bailingOut,
        ...s.destroyed,
      ]) {
        expect(everyone.contains(id), isTrue,
            reason: '${s.id} arranges $id, who is not in the battle');
      }
      expect(s.bailingOut.intersection(s.destroyed), isEmpty, reason: s.id);
    }
  });

  test('every scenario starts, and starts on the player turn', () {
    for (final s in testScenarios) {
      final session = s.start();
      expect(session.battle.isTeamATurn, isTrue,
          reason: '${s.id} does not open on the player');
      expect(session.openingAiRound, isNull, reason: s.id);
      expect(session.battle.isOver, isFalse,
          reason: '${s.id} is over before it begins');
    }
  });

  test('the board is arranged the way the scenario describes', () {
    for (final s in testScenarios) {
      final session = s.start();
      s.positions.forEach((id, position) {
        expect(session.battle.states[id]!.position, position, reason: s.id);
      });
      for (final id in s.bailingOut) {
        final state = session.battle.states[id]!;
        expect(state.bailOutState, BailOutState.bailingOut, reason: s.id);
        expect(state.isOnBoard, isTrue, reason: s.id);
        expect(state.isAlive, isFalse, reason: s.id);
      }
      for (final id in s.destroyed) {
        expect(session.battle.states[id]!.bailOutState,
            BailOutState.destroyed,
            reason: s.id);
      }
      // Health is set before the opening turn, which then runs a Trion roll
      // and a status tick. Neither touches health on a clean board, so the
      // arranged values should still be standing.
      s.health.forEach((id, value) {
        expect(session.battle.states[id]!.currentHealth, value, reason: s.id);
      });
    }
  });

  test('both squads can afford to act on turn one', () {
    for (final s in testScenarios) {
      final session = s.start();
      // The opening turn has already rolled income on top of the arranged
      // pool, so this is a floor rather than the exact number.
      expect(session.battle.teamA.trionPool.current,
          greaterThanOrEqualTo(s.startingTrion),
          reason: s.id);
      expect(session.battle.teamB.trionPool.current,
          greaterThanOrEqualTo(s.startingTrion),
          reason: s.id);
    }
  });

  group('the scenarios put the board where their briefs claim', () {
    TestScenario byId(String id) =>
        testScenarios.firstWhere((s) => s.id == id);

    test('The screen holds: the enemy back line is out of Close Range', () {
      final s = byId('screen_holds');
      final session = s.start();
      final engine = session.battle.turnEngine;
      final rurik = session.battle.states['rurik_voss']!;
      final nadia = session.battle.states['nadia_kessler']!;

      final distance = engine.distanceBetween(rurik, nadia);
      expect(distance, 4,
          reason: 'step 0 + step 2 + two screening enemies');
      expect(RangeTag.close.reaches(distance), isFalse);
    });

    test('A body still screens: the distance holds until the body goes', () {
      final s = byId('body_screens');
      final session = s.start();
      final engine = session.battle.turnEngine;
      final rurik = session.battle.states['rurik_voss']!;
      final vela = session.battle.states['vela_ashworth']!;
      final nadia = session.battle.states['nadia_kessler']!;

      expect(engine.distanceBetween(rurik, nadia), 3,
          reason: 'one enemy screening the back line');

      // Vela drops but stays on the board as a body.
      vela.currentHealth = 0;
      session.battle.turnEngine.noteHealthChanged(vela);
      expect(vela.bailOutState, BailOutState.bailingOut);
      expect(engine.distanceBetween(rurik, nadia), 3,
          reason: 'the body goes on screening');

      // Cleared, and the lane opens.
      vela.bailOutState = BailOutState.destroyed;
      expect(engine.distanceBetween(rurik, nadia), 2,
          reason: 'the screen is gone');
      expect(RangeTag.close.reaches(2), isTrue);
    });

    test('The bending shot: the target sits exactly on Long Range minimum',
        () {
      final s = byId('bending_shot');
      final session = s.start();
      final engine = session.battle.turnEngine;
      final mireille = session.battle.states['mireille_song']!;
      final ren = session.battle.states['ren_kobayashi']!;
      final vela = session.battle.states['vela_ashworth']!;

      expect(vela.bailOutState, BailOutState.bailingOut,
          reason: 'the body has to be there before turn one');
      final before = engine.distanceBetween(mireille, ren);
      expect(before, 2, reason: 'legal for Long Range, and only just');
      expect(RangeTag.long.reaches(before), isTrue);

      // Clearing the body drags the target under the band's minimum, which
      // is the only thing that makes a shot bend.
      vela.bailOutState = BailOutState.destroyed;
      final after = engine.distanceBetween(mireille, ren);
      expect(after, 1);
      expect(RangeTag.long.reaches(after), isFalse);
    });

    test('The last one does not bail: two are already gone', () {
      final s = byId('last_one_standing');
      final session = s.start();
      final living = session.battle.teamB.characters
          .where((c) => session.battle.states[c.id]!.isAlive)
          .toList();
      expect(living.length, 1);
      expect(living.single.id, 'nadia_kessler');
      expect(session.battle.isTeamDefeated(session.battle.teamB), isFalse);
    });

    test('Refuse to Bail is equipped and the holder is one hit from zero', () {
      final s = byId('refuse_to_bail');
      final session = s.start();
      expect(session.battle.states['rurik_voss']!.currentHealth, 1);
      expect(
        session.equippedA['rurik_voss']!.map((t) => t.id),
        contains('refuse_to_bail'),
      );
    });

    test('Only damage may be aimed at a body: the kit carries both halves',
        () {
      final s = byId('body_targeting');
      final session = s.start();
      final kit = session.equippedA['kaito_reyes']!;
      final charm = kit.firstWhere((t) => t.id == 'charm_whisper');
      final strike = kit.firstWhere((t) => t.id == 'twin_fang_strike');
      expect(charm.damage, isNull, reason: 'the ability that must be refused');
      expect(strike.damage, isNotNull, reason: 'the ability that must work');
      expect(session.battle.states['vela_ashworth']!.bailOutState,
          BailOutState.bailingOut);
    });
  });

  group('a scenario opens the real battle screen', () {
    // The unit tests above build the session directly, which is exactly why
    // they missed the first version of this: the battle screen reads state
    // the scenario path was not setting, and a release web build renders a
    // caught exception as a blank grey page rather than a crash. Pumping the
    // real screen is the only check that catches that class of miss.
    for (final scenario in testScenarios) {
      testWidgets('${scenario.name} renders a battle, not an error', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1400, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(home: PlayFlowScreen(scenario: scenario)),
        );
        await tester.pump();

        expect(tester.takeException(), isNull,
            reason: '${scenario.id} threw while building the battle');
        expect(find.byType(ErrorWidget), findsNothing,
            reason: '${scenario.id} rendered an error widget');

        // The scenario banner is the marker that it went straight to battle
        // rather than stopping at the setup or Loadout step.
        expect(find.text('BRIEF'), findsOneWidget, reason: scenario.id);
        expect(find.text(scenario.name), findsWidgets, reason: scenario.id);
      });
    }

    testWidgets('the brief opens from the battle screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final scenario = testScenarios.first;

      await tester.pumpWidget(
        MaterialApp(home: PlayFlowScreen(scenario: scenario)),
      );
      await tester.pump();

      await tester.tap(find.text('BRIEF'));
      await tester.pumpAndSettle();

      expect(find.text('WHAT TO DO'), findsOneWidget);
      expect(find.text('WHAT SHOULD HAPPEN'), findsOneWidget);
      expect(find.text(scenario.expect.first), findsOneWidget);
    });
  });
}


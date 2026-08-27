import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/draft.dart';
import 'package:flutter/material.dart';
import 'package:isekai_strategem/src/game/play_session.dart';
import 'package:isekai_strategem/src/game/test_scenarios.dart';
import 'package:isekai_strategem/src/screens/play_flow_screen.dart';
import 'package:isekai_strategem/src/screens/test_lab_screen.dart';

/// The Tests tab is only useful if every scenario in it actually loads. These
/// are the checks that a scenario is well-formed, not checks on the rules it
/// exists to exercise: a scenario naming a Trigger that does not exist, or a
/// kit that busts a character's Trion Capacity, would otherwise only be found
/// by tapping it.
/// A battle keys by combatant id (item #14); a test naming a character holds
/// their roster id. One place translates.
CharacterBattleState stateFor(
  TestScenario scenario,
  PlaySession session,
  String characterId,
) =>
    session.battle.stateOf(
      scenario.playerIds.contains(characterId)
          ? session.battle.teamA
          : session.battle.teamB,
      characterId,
    );

void main() {
  // Every scenario ever written stays under test, retired or not: a retired
  // one is still shipped code, it is still what a future round would start
  // from, and its numbers are still quoted in the docs. What retiring changes
  // is only whether the Tests tab offers it.
  group('the Tests tab offers only what still needs playing', () {
    test('retired scenarios are kept, but not listed', () {
      expect(allScenarios, isNotEmpty);
      expect(
        testScenarios,
        allScenarios.where((s) => !s.retired),
        reason: 'the tab lists exactly the unconfirmed cases',
      );
      for (final s in testScenarios) {
        expect(s.retired, isFalse);
      }
    });

    testWidgets('an empty list reads as finished, not broken', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: TestLabScreen()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      if (testScenarios.isEmpty) {
        expect(find.text('Nothing waiting'), findsOneWidget);
        expect(find.text('START SCENARIO'), findsNothing);
      } else {
        expect(find.text('START SCENARIO'), findsOneWidget);
        expect(find.text('Nothing waiting'), findsNothing);
      }
    });
  });

  test('every scenario has a unique id and names a work item', () {
    final ids = allScenarios.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'duplicate scenario id');
    for (final s in allScenarios) {
      expect(s.name, isNotEmpty);
      expect(s.item, isNotEmpty);
      expect(s.goal, isNotEmpty);
      expect(s.orderedSteps, isNotEmpty,
          reason: '${s.id} says nothing to do');
      expect(s.expectations, isNotEmpty,
          reason: '${s.id} says nothing to look for');
    }
  });

  test('every squad is three characters and the two do not overlap', () {
    for (final s in allScenarios) {
      expect(s.playerIds.length, 3, reason: s.id);
      expect(s.enemyIds.length, 3, reason: s.id);
      // Both squads may field the same character since item #14, and one
      // scenario exists to exercise exactly that. What still throws at battle
      // construction is the same character twice on **one** squad, because
      // that really would be one shared state.
      expect(s.playerIds.toSet(), hasLength(3),
          reason: '${s.id} drafts a character twice onto the player squad');
      expect(s.enemyIds.toSet(), hasLength(3),
          reason: '${s.id} drafts a character twice onto the enemy squad');
    }
  });

  test('every character has a kit, and every kit is a legal Loadout', () {
    for (final s in allScenarios) {
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
    for (final s in allScenarios) {
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
    for (final s in allScenarios) {
      final session = s.start();
      expect(session.battle.isTeamATurn, isTrue,
          reason: '${s.id} does not open on the player');
      expect(session.openingAiRound, isNull, reason: s.id);
      expect(session.battle.isOver, isFalse,
          reason: '${s.id} is over before it begins');
    }
  });

  test('the board is arranged the way the scenario describes', () {
    for (final s in allScenarios) {
      final session = s.start();
      s.positions.forEach((id, position) {
        expect(stateFor(s, session, id).position, position, reason: s.id);
      });
      for (final id in s.bailingOut) {
        final state = stateFor(s, session, id);
        expect(state.bailOutState, BailOutState.bailingOut, reason: s.id);
        expect(state.isOnBoard, isTrue, reason: s.id);
        expect(state.isAlive, isFalse, reason: s.id);
      }
      for (final id in s.destroyed) {
        expect(stateFor(s, session, id).bailOutState,
            BailOutState.destroyed,
            reason: s.id);
      }
      // Health is set before the opening turn, which then runs a Trion roll
      // and a status tick. Neither touches health on a clean board, so the
      // arranged values should still be standing.
      s.health.forEach((id, value) {
        expect(stateFor(s, session, id).currentHealth, value, reason: s.id);
      });
    }
  });

  test('both squads can afford to act on turn one', () {
    for (final s in allScenarios) {
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
        allScenarios.firstWhere((s) => s.id == id);

    /// A battle keys by combatant id (item #14); a test naming a character
    /// holds their roster id. One place translates, the same as the scenarios
    /// themselves do.
    CharacterBattleState stateOf(
      TestScenario scenario,
      PlaySession session,
      String characterId,
    ) =>
        session.battle.stateOf(
          scenario.playerIds.contains(characterId)
              ? session.battle.teamA
              : session.battle.teamB,
          characterId,
        );

    List<ActiveTrigger> kitOf(PlaySession session, String characterId) =>
        session.equippedA[CombatantIds.of('player', characterId)]!;

    test('A buff worth the action: the buff catches the line, and says so',
        () {
      // The brief says Rurik and Kaito get it and Mireille does not, because
      // an area ability catches a line. If that stops being true the brief
      // is lying to the tester.
      final s = byId('support_pays_its_way');
      final session = s.start();
      final kaito = stateOf(s, session, 'kaito_reyes');
      final rurik = stateOf(s, session, 'rurik_voss');
      final mireille = stateOf(s, session, 'mireille_song');

      expect(kaito.position, BattlePosition.middle);
      expect(rurik.position, kaito.position,
          reason: 'the brief turns on these two sharing a line');
      expect(mireille.position, isNot(kaito.position));

      final queued = session.queue(
        kaito.combatantId,
        'war_chant',
        [kaito.combatantId, rurik.combatantId],
      );
      expect(queued.success, isTrue, reason: queued.error ?? '');
      session.resolveQueue();

      List<String> statusesOn(CharacterBattleState st) =>
          st.statusEffects.map((i) => i.definitionId).toList();

      expect(statusesOn(kaito), contains('empowered'));
      expect(statusesOn(rurik), contains('empowered'),
          reason: 'he shares the line it was aimed at');
      expect(statusesOn(mireille), isNot(contains('empowered')),
          reason: 'an area ability catches a line, not a squad');
    });

    test('A bleed that piles up: the brief step one is performable and it '
        'really stacks', () {
      final s = byId('stacking_bleed');
      var stacked = false;

      for (var attempt = 0; attempt < 40 && !stacked; attempt++) {
        final session = s.start();
        final rurik = stateOf(s, session, 'rurik_voss');
        final kaito = stateOf(s, session, 'kaito_reyes');
        final vela = stateOf(s, session, 'vela_ashworth');

        for (final actor in [rurik, kaito]) {
          final queued = session.queue(
            actor.combatantId,
            actor == rurik ? 'whirlwind_slash' : 'rapid_fire',
            [vela.combatantId],
          );
          expect(queued.success, isTrue, reason: queued.error ?? '');
        }
        session.resolveQueue();

        final bleeds =
            vela.statusEffects.where((i) => i.definitionId == 'bleeding');
        if (bleeds.isEmpty) continue;

        expect(bleeds, hasLength(1),
            reason: 'however many land, there is one badge and one timer');
        expect(bleeds.single.stacks, lessThanOrEqualTo(3),
            reason: 'three is the cap, and Rapid Fire strikes three times');
        if (bleeds.single.stacks < 2) continue;
        stacked = true;
      }

      expect(stacked, isTrue,
          reason: 'forty turns without two bleeds landing would make this '
              'scenario unplayable');
    });

    test('Freeze then shatter: the chain the brief promises actually runs',
        () {
      // Three dice gates stand in front of this chain: each of the three
      // attacks has to land, and the first Frost Lance has to win the
      // infliction contest for Chilled. None of them is what is under test,
      // so this runs turns until one comes up clean and then holds the chain
      // to the letter. What is under test is that the two reactions are not
      // rolled for at all.
      final s = byId('freeze_and_shatter');
      var ranClean = false;

      for (var attempt = 0; attempt < 60 && !ranClean; attempt++) {
        final session = s.start();
        final vela = stateOf(s, session, 'vela_ashworth');

        for (final actor in ['rurik_voss', 'kaito_reyes', 'mireille_song']) {
          final state = stateOf(s, session, actor);
          final ability =
              actor == 'mireille_song' ? 'thunderclap_round' : 'frost_lance';
          final queued = session.queue(
            state.combatantId,
            ability,
            [vela.combatantId],
          );
          expect(queued.success, isTrue, reason: queued.error ?? '');
        }

        final actions = session.resolveQueue().actions;
        expect(actions.map((a) => a.characterName.split(' ').first).toList(),
            ['Rurik', 'Kaito', 'Mireille'],
            reason: 'the brief tells the tester to read the log in this '
                'order, so the resolver has to produce it');

        bool landed(int i) =>
            actions[i].targets.isNotEmpty &&
            actions[i].targets.first.rolls.any((r) => r.isHit);

        final chilled = landed(0) &&
            actions[0]
                .targets
                .first
                .statusEffectsApplied
                .contains('Chilled');
        if (!chilled || !landed(1) || !landed(2)) continue;

        // A hit can still be turned aside by a ward or a counter after the
        // roll lands, so the freeze is the signal that this attempt got all
        // the way through. Anything short of it is another attempt, not a
        // failure; sixty attempts without one is the failure.
        final froze = actions[1].reactions.where((r) => r.became == 'Frozen');
        if (froze.isEmpty) continue;
        final shatter =
            actions[2].reactions.where((r) => r.reactingName == 'Frozen');
        if (shatter.isEmpty) continue;
        ranClean = true;

        expect(froze.single.consumed, isTrue, reason: 'the chill is spent');
        expect(shatter.single.damageMultiplier, 2.0,
            reason: 'Thunder shatters ice for double');
        expect(shatter.single.consumed, isTrue);
        expect(vela.statusEffects.map((i) => i.definitionId),
            isNot(contains('frozen')),
            reason: 'the ice was spent breaking');
      }

      expect(ranClean, isTrue,
          reason: 'sixty turns without the chain running once would make this '
              'scenario unplayable');
    });

    test('A one-turn lock: the brief step one is actually performable', () {
      // A brief that tells a tester to queue an ability they cannot reach
      // with is worse than no brief. Item #D's scenario turns on Mind
      // Shatter landing on the enemy Front, so that has to be a legal queue
      // from where the scenario stands Kaito.
      final s = byId('one_turn_silence');
      final session = s.start();
      final kaito = stateOf(s, session, 'kaito_reyes');
      final vela = stateOf(s, session, 'vela_ashworth');

      expect(kitOf(session, 'kaito_reyes').map((t) => t.id),
          contains('mind_shatter'));

      final distance =
          session.battle.turnEngine.distanceBetween(kaito, vela);
      expect(RangeTag.mid.reaches(distance), isTrue,
          reason: 'Mid Range has to reach at distance $distance');

      final queued = session.queue(
        kaito.combatantId,
        'mind_shatter',
        [vela.combatantId],
      );
      expect(queued.success, isTrue, reason: queued.error ?? '');
    });

    test('A buff you cast: War Chant reaches the caster and their line', () {
      // Item #5's spot-fix made this a squad buff rather than a self-buff.
      // The scenario still turns on the duration, so what it needs is that
      // the caster can put it on themselves.
      final s = byId('buff_lasts_your_turns');
      final session = s.start();
      final kaito = stateOf(s, session, 'kaito_reyes');

      final warChant = kitOf(session, 'kaito_reyes')
          .firstWhere((t) => t.id == 'war_chant');
      expect(warChant.targetAffiliation, TargetAffiliation.ally);
      expect(warChant.targetCount, 3);
      expect(
        warChant.inflictedStatusEffects.map((a) => a.statusEffectId),
        contains('empowered'),
      );

      final queued = session.queue(
        kaito.combatantId,
        'war_chant',
        [kaito.combatantId],
      );
      expect(queued.success, isTrue, reason: queued.error ?? '');
    });

    test('The screen holds: the enemy back line is out of Close Range', () {
      final s = byId('screen_holds');
      final session = s.start();
      final engine = session.battle.turnEngine;
      final rurik = stateOf(s, session, 'rurik_voss');
      final nadia = stateOf(s, session, 'nadia_kessler');

      final distance = engine.distanceBetween(rurik, nadia);
      expect(distance, 4,
          reason: 'step 0 + step 2 + two screening enemies');
      expect(RangeTag.close.reaches(distance), isFalse);
    });

    test('A body still screens: the distance holds until the body goes', () {
      final s = byId('body_screens');
      final session = s.start();
      final engine = session.battle.turnEngine;
      final rurik = stateOf(s, session, 'rurik_voss');
      final vela = stateOf(s, session, 'vela_ashworth');
      final nadia = stateOf(s, session, 'nadia_kessler');

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
      final mireille = stateOf(s, session, 'mireille_song');
      final ren = stateOf(s, session, 'ren_kobayashi');
      final vela = stateOf(s, session, 'vela_ashworth');

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
          .where((c) => session.battle.stateOf(session.battle.teamB, c.id).isAlive)
          .toList();
      expect(living.length, 1);
      expect(living.single.id, 'nadia_kessler');
      expect(session.battle.isTeamDefeated(session.battle.teamB), isFalse);
    });

    test('Refuse to Bail is equipped and the holder is one hit from zero', () {
      final s = byId('refuse_to_bail');
      final session = s.start();
      expect(stateOf(s, session, 'rurik_voss').currentHealth, 1);
      expect(
        kitOf(session, 'rurik_voss').map((t) => t.id),
        contains('refuse_to_bail'),
      );
    });

    test('Only damage may be aimed at a body: the kit carries both halves',
        () {
      final s = byId('body_targeting');
      final session = s.start();
      final kit = kitOf(session, 'kaito_reyes');
      final charm = kit.firstWhere((t) => t.id == 'charm_whisper');
      final strike = kit.firstWhere((t) => t.id == 'twin_fang_strike');
      expect(charm.damage, isNull, reason: 'the ability that must be refused');
      expect(strike.damage, isNotNull, reason: 'the ability that must work');
      expect(stateOf(s, session, 'vela_ashworth').bailOutState,
          BailOutState.bailingOut);
    });
  });

  group('a scenario opens the real battle screen', () {
    // The unit tests above build the session directly, which is exactly why
    // they missed the first version of this: the battle screen reads state
    // the scenario path was not setting, and a release web build renders a
    // caught exception as a blank grey page rather than a crash. Pumping the
    // real screen is the only check that catches that class of miss.
    for (final scenario in allScenarios) {
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
      final scenario = allScenarios.first;

      await tester.pumpWidget(
        MaterialApp(home: PlayFlowScreen(scenario: scenario)),
      );
      await tester.pump();

      await tester.tap(find.text('BRIEF'));
      await tester.pumpAndSettle();

      expect(find.text('WHAT TO DO'), findsOneWidget);
      expect(find.text('WHAT SHOULD HAPPEN'), findsOneWidget);
      expect(find.text(scenario.expectations.first), findsOneWidget);
    });
  });

  group('a bailing body on YOUR squad reads as bailing, not defeated', () {
    // The playtest found this: the opponent's squad panel is TeamPanel /
    // FighterRow, which had the pill and the no-strike-through rule, but the
    // player's own rows are a separate widget in play_flow_screen.dart that
    // read only `alive`. So your own bailing character was painted exactly
    // like a corpse: faded, struck through, no badge. Every existing test
    // pumped the opponent's widget, so nothing saw it.
    //
    // This scenario exists only for the test. It is not in the picker.
    final ownBodyScenario = TestScenario(
      id: 'test_only_own_body',
      name: 'Own body',
      item: '#2',
      goal: 'One of yours is already a body.',
      steps: (s) => const ['Look at your own squad panel.'],
      expect: (s) =>
          const ['Kaito reads as bailing out, not as defeated.'],
      playerIds: const ['rurik_voss', 'kaito_reyes', 'mireille_song'],
      enemyIds: const ['vela_ashworth', 'ren_kobayashi', 'nadia_kessler'],
      kits: {
        for (final id in const [
          'rurik_voss',
          'kaito_reyes',
          'mireille_song',
          'vela_ashworth',
          'ren_kobayashi',
          'nadia_kessler',
        ])
          id: const [
            'twin_fang_strike',
            'shatterpoint',
            'cleave',
            'guardians_aegis',
          ],
      },
      bailingOut: const {'kaito_reyes'},
    );

    testWidgets('the badge is on the row, and the name is not struck through',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(home: PlayFlowScreen(scenario: ownBodyScenario)),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // One in your squad panel, one on nobody else: the opponent has no
      // body in this scenario.
      expect(find.text('BAILING OUT'), findsOneWidget);

      final name = tester.widget<Text>(
        find.text('Kaito Reyes').first,
      );
      expect(name.style?.decoration, isNot(TextDecoration.lineThrough),
          reason: 'a body has not been struck off the board yet');
      expect(name.style?.color, isNot(Colors.white38),
          reason: 'a body is dimmed less than a defeated character');
    });

    testWidgets('a living squad shows no badge at all', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: PlayFlowScreen(
            scenario: allScenarios.firstWhere((s) => s.id == 'screen_holds'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('BAILING OUT'), findsNothing);
    });
  });

  group('a brief cannot disagree with the game', () {
    // The "Read the board" brief shipped claiming one screening pip and
    // distances of 3 and 5, where the game correctly showed two pips and 4
    // and 6. Nothing caught it, because the numbers in a brief were prose and
    // only some scenarios had a matching assertion. They are computed now,
    // and this is the test that the computation is the engine's own.
    test('every distance a scenario computes matches the live battle', () {
      for (final s in allScenarios) {
        final session = s.start();
        final everyone = [...s.playerIds, ...s.enemyIds];
        for (final from in everyone) {
          for (final to in everyone) {
            if (from == to) continue;
            // A destroyed character has no position worth asking about; the
            // engine leaves them on the board's map but nothing measures to
            // them.
            if (s.destroyed.contains(from) || s.destroyed.contains(to)) {
              continue;
            }
            expect(
              s.distanceBetween(from, to),
              session.battle.turnEngine.distanceBetween(
                stateFor(s, session, from),
                stateFor(s, session, to),
              ),
              reason: '${s.id}: $from to $to',
            );
          }
        }
      }
    });

    test('every screen count a scenario computes matches the live battle', () {
      for (final s in allScenarios) {
        final session = s.start();
        for (final id in [...s.playerIds, ...s.enemyIds]) {
          if (s.destroyed.contains(id)) continue;
          final state = stateFor(s, session, id);
          final live = BattleDistance.screensFor(
            state.position,
            session.battle.turnEngine.screeningLinesFor(state),
          );
          expect(s.screensOn(id), live, reason: '${s.id}: screens on $id');
        }
      }
    });

    test('every position a scenario computes matches the live battle', () {
      for (final s in allScenarios) {
        final session = s.start();
        for (final id in [...s.playerIds, ...s.enemyIds]) {
          expect(s.positionOf(id), stateFor(s, session, id).position,
              reason: '${s.id}: position of $id');
        }
      }
    });

    test('Read the board says two pips, 4 and 6', () {
      // The exact numbers the playtest reported, pinned so the brief that
      // got them wrong can never come back.
      final s = allScenarios.firstWhere((x) => x.id == 'read_the_board');
      expect(s.screensOn('nadia_kessler'), 2);
      expect(s.distanceBetween('rurik_voss', 'nadia_kessler'), 4);
      expect(s.distanceBetween('mireille_song', 'nadia_kessler'), 6);
      expect(s.distanceBetween('rurik_voss', 'vela_ashworth'), 0);

      final brief = s.expectations.join(' ');
      expect(brief, contains('2 screening pips'));
      expect(brief, contains('4: your step 0, their step 2, plus 2 screens'));
      expect(brief, contains('6: your step 2, their step 2, plus 2 screens'));
    });
  });
}


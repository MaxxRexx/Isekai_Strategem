import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/battle_models.dart';
import 'package:isekai_strategem/src/game/report.dart';

/// A playtest pasted a battle report back and asked where things had gone:
/// "some elements do not seem to make it into the report when clicking 'copy
/// full report', like the reactions."
///
/// The report is what leaves the app. Anything the battle log shows on screen
/// and the report drops is a fact that exists only until the session closes,
/// and a reaction is exactly the kind of fact worth keeping: it is the reason
/// a number was double and a badge is gone.
void main() {
  LogTargetResult target({
    String name = 'Vela Ashworth',
    int hits = 1,
    int damage = 40,
    List<String> statuses = const [],
  }) => LogTargetResult(
    targetId: 'b:vela_ashworth',
    targetName: name,
    hits: hits,
    crits: 0,
    misses: 0,
    damage: damage,
    statusEffectsApplied: statuses,
    healthAfter: 60,
    died: false,
  );

  LogAction action({
    String trigger = 'Frost Lance',
    List<LogReaction> reactions = const [],
    List<LogTargetResult>? targets,
  }) => LogAction(
    characterId: 'a:kaito_reyes',
    characterName: 'Kaito Reyes',
    triggerId: 'frost_lance',
    triggerName: trigger,
    fatTriggered: false,
    targets: targets ?? [target()],
    reactions: reactions,
  );

  String reportOf(List<LogRound> rounds) => buildPlayReport(
    playerIds: const ['kaito_reyes'],
    opponentIds: const ['vela_ashworth'],
    opponentProfileId: AiProfile.all.first.id,
    outcome: BattleOutcome.teamAWins,
    roundNumber: rounds.length,
    teamA: const [],
    teamB: const [],
    loadouts: const {},
    rounds: rounds,
  );

  group('a reaction survives the copy', () {
    test('a status turning into another one is written out in full', () {
      const shatter = LogReaction(
        characterName: 'Vela Ashworth',
        reactingName: 'Chilled',
        damageTypeLabel: 'cold',
        became: 'Frozen',
        consumed: true,
        becameStacks: 1,
      );
      final report = reportOf([
        LogRound(roundNumber: 1, team: 'A', actions: [
          action(reactions: const [shatter]),
        ]),
      ]);

      expect(report, contains('REACTION'));
      expect(report, contains('Chilled becomes Frozen'));
      expect(report, contains('cold damage'));
    });

    test('the report says exactly what the log line says', () {
      const arc = LogReaction(
        characterName: 'Vela Ashworth',
        reactingName: 'Wet',
        damageTypeLabel: 'lightning',
        became: 'Electrocuted',
        damageMultiplier: 2.0,
        arcedToName: 'Ren Kobayashi',
        becameStacks: 2,
      );
      final report = reportOf([
        LogRound(roundNumber: 1, team: 'A', actions: [
          action(reactions: const [arc]),
        ]),
      ]);

      // Both surfaces read the same getter, which is the point: the sentence
      // has one home.
      expect(report, contains(arc.sentence));
      expect(arc.sentence, contains('now Electrocuted x2'));
      expect(arc.sentence, contains('double damage on the hit'));
      expect(arc.sentence, contains('arcs to Ren Kobayashi'));
    });

    test('a reaction says the status it spent was already there', () {
      const shatter = LogReaction(
        characterName: 'Vela Ashworth',
        reactingName: 'Chilled',
        damageTypeLabel: 'cold',
        became: 'Frozen',
        consumed: true,
        becameStacks: 1,
      );
      expect(shatter.causeSentence,
          'Vela Ashworth was already Chilled and took cold damage');
    });

    test('a reaction whose status the same attack puts back says so', () {
      // The one a playtest could not resolve: the log said Chilled became
      // Frozen, and Chilled was on the target again next turn.
      const refreeze = LogReaction(
        characterName: 'Vela Ashworth',
        reactingName: 'Chilled',
        damageTypeLabel: 'cold',
        became: 'Frozen',
        consumed: true,
        becameStacks: 1,
        reappliedName: 'Chilled',
        reappliedStacks: 1,
      );

      expect(refreeze.effectDescription,
          'Chilled becomes Frozen (now Frozen x1), and the same attack '
          'applies Chilled again (Chilled x1)');
    });

    test('a reaction nothing re-applied stays as short as it was', () {
      const plain = LogReaction(
        characterName: 'Vela Ashworth',
        reactingName: 'Chilled',
        damageTypeLabel: 'cold',
        became: 'Frozen',
        consumed: true,
        becameStacks: 1,
      );
      expect(plain.effectDescription, isNot(contains('again')));
    });

    test('a status-triggered reaction does not read as "a status damage"', () {
      const fromStatus = LogReaction(
        characterName: 'Vela Ashworth',
        reactingName: 'Wet',
        damageTypeLabel: 'a status',
        became: 'Chilled',
      );
      expect(fromStatus.sentence, isNot(contains('a status damage')));
      expect(fromStatus.sentence, contains('another status landed on them'));
    });

    test('a row that builds a status into itself reads as a stack', () {
      const builds = LogReaction(
        characterName: 'Vela Ashworth',
        reactingName: 'Bleeding',
        damageTypeLabel: 'slashing',
        became: 'Bleeding',
        becameStacks: 2,
      );

      expect(builds.effectDescription, 'the Bleeding builds by one '
          '(now Bleeding x2)');
      expect(builds.effectDescription, isNot(contains('builds into Bleeding')),
          reason: '"Bleeding builds into Bleeding" is what a playtest could '
              'make no sense of');
    });
  });

  group('a Bail Out is written once, whatever else happened that turn', () {
    const recall = LogBailOut(
      characterId: 'b:vela_ashworth',
      characterName: 'Vela Ashworth',
      team: 'B',
      refused: false,
      trionSalvaged: 18,
    );

    test('three actions do not print three recalls', () {
      final report = reportOf([
        LogRound(
          roundNumber: 1,
          team: 'A',
          actions: [action(), action(trigger: 'Cleave'), action()],
          bailOuts: const [recall],
        ),
      ]);

      expect('recall'.allMatches(report.toLowerCase()), hasLength(1));
    });

    test('a turn whose only event is a recall still reports it', () {
      final report = reportOf([
        LogRound(
          roundNumber: 1,
          team: 'B',
          actions: const [],
          bailOuts: const [recall],
        ),
      ]);

      expect(report, contains('Vela Ashworth is recalled'));
      expect(report, contains('+18'));
    });
  });

  group('the rest of the line survives too', () {
    test('a friendly ability reports no hits rather than an empty bracket',
        () {
      final report = reportOf([
        LogRound(roundNumber: 1, team: 'A', actions: [
          action(
            trigger: 'War Chant',
            targets: [
              target(
                name: 'Rurik Voss',
                hits: 0,
                damage: 0,
                statuses: const ['Empowered x1'],
              ),
            ],
          ),
        ]),
      ]);

      expect(report, contains('uses War Chant on Rurik Voss [Empowered x1]'));
      expect(report, isNot(contains('()')));
      expect(report, isNot(contains('1 hit')));
    });

    test('a bent shot is marked', () {
      final report = reportOf([
        LogRound(roundNumber: 1, team: 'A', actions: [
          LogAction(
            characterId: 'a:mireille_song',
            characterName: 'Mireille Song',
            triggerId: 'longshot',
            triggerName: 'Longshot',
            fatTriggered: false,
            targets: [target()],
            bend: const LogBend(
              targetName: 'Vela Ashworth',
              bandLabel: 'Long Range',
              bandWindow: '2 to 4',
              bandMinimum: 2,
              distanceWhenCommitted: 3,
              distanceNow: 1,
              screensWhenCommitted: 0,
              screensBroken: [],
              backlashTier: 10,
            ),
          ),
        ]),
      ]);

      expect(report, contains('[BENT]'));
    });
  });
}

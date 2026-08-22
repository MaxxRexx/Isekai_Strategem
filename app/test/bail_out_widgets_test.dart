import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/battle_models.dart';
import 'package:isekai_strategem/src/widgets/fighter_row.dart';
import 'package:isekai_strategem/src/widgets/log_view.dart';

/// Item #2, the pieces the player actually looks at. The rules have engine
/// tests and the session has its own; this is the copy, and copy that says the
/// wrong thing is the failure mode this item is most exposed to. "Defeated"
/// was the only ending the interface knew how to say, and there are now four.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(width: 900, child: child)),
  );

  FighterSnapshot fighter({bool alive = true, bool bailingOut = false}) =>
      FighterSnapshot(
        id: 'b1',
        name: 'Vela Ashworth',
        type: CharacterType.attack,
        currentHealth: alive ? 100 : 0,
        maxHealth: 100,
        alive: alive,
        bailingOut: bailingOut,
      );

  LogTargetResult target({
    bool died = false,
    bool startedBailingOut = false,
    bool bodyDestroyed = false,
    bool refusedToBail = false,
    int trionFromBody = 0,
  }) => LogTargetResult(
    targetId: 'b1',
    targetName: 'Vela Ashworth',
    hits: 1,
    crits: 0,
    misses: 0,
    damage: bodyDestroyed ? 0 : 40,
    statusEffectsApplied: const [],
    healthAfter: died || bodyDestroyed ? 0 : 60,
    died: died || bodyDestroyed,
    startedBailingOut: startedBailingOut,
    bodyDestroyed: bodyDestroyed,
    trionFromBody: trionFromBody,
    refusedToBail: refusedToBail,
  );

  LogRound round(LogTargetResult t) => LogRound(
    roundNumber: 3,
    team: 'A',
    actions: [
      LogAction(
        characterId: 'a1',
        characterName: 'Ren Kobayashi',
        triggerId: 'twin_fang_strike',
        triggerName: 'Twin Fang Strike',
        fatTriggered: false,
        targets: [t],
      ),
    ],
  );

  group('the squad panel', () {
    testWidgets('a bailing body carries the pill and is not struck off', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(FighterRow(fighter: fighter(alive: false, bailingOut: true))),
      );

      expect(find.text('BAILING'), findsOneWidget);
      final name = tester.widget<Text>(find.text('Vela Ashworth'));
      expect(
        name.style?.decoration,
        isNot(TextDecoration.lineThrough),
        reason: 'they have not been struck off the board yet',
      );
    });

    testWidgets('a defeated character has no pill and is struck through', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(FighterRow(fighter: fighter(alive: false))));

      expect(find.text('BAILING'), findsNothing);
      final name = tester.widget<Text>(find.text('Vela Ashworth'));
      expect(name.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('a living character has neither', (tester) async {
      await tester.pumpWidget(wrap(FighterRow(fighter: fighter())));
      expect(find.text('BAILING'), findsNothing);
    });
  });

  group('the battle log names the right ending', () {
    testWidgets('a drop says bailing out, not defeated', (tester) async {
      await tester.pumpWidget(
        wrap(
          RoundEntry(round: round(target(died: true, startedBailingOut: true))),
        ),
      );

      expect(
        find.textContaining('BAILING OUT', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('DEFEATED', findRichText: true), findsNothing);
    });

    testWidgets('a hit on a body says the body was destroyed', (tester) async {
      await tester.pumpWidget(
        wrap(
          RoundEntry(
            round: round(target(bodyDestroyed: true, trionFromBody: 11)),
          ),
        ),
      );

      expect(
        find.textContaining('BODY DESTROYED', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('DEFEATED', findRichText: true), findsNothing);
    });

    testWidgets('a refusal says so', (tester) async {
      await tester.pumpWidget(
        wrap(RoundEntry(round: round(target(refusedToBail: true)))),
      );

      expect(
        find.textContaining('REFUSES TO BAIL', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('an ordinary defeat still says defeated', (tester) async {
      await tester.pumpWidget(
        wrap(RoundEntry(round: round(target(died: true)))),
      );

      expect(
        find.textContaining('DEFEATED', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('BAILING', findRichText: true), findsNothing);
    });
  });

  group('the turn boundary explains itself', () {
    LogRound settled(LogBailOut entry) => LogRound(
      roundNumber: 4,
      team: 'B',
      actions: const [],
      bailOuts: [entry],
    );

    testWidgets('a recall names the squad and the Trion it banked', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          RoundEntry(
            round: settled(
              const LogBailOut(
                characterId: 'a1',
                characterName: 'Ren Kobayashi',
                team: 'A',
                trionSalvaged: 22,
                refused: false,
              ),
            ),
            teamAName: 'Your Squad',
          ),
        ),
      );

      expect(
        find.textContaining('recalled', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Your Squad banks 22 Trion', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a spent refusal says what it cost', (tester) async {
      await tester.pumpWidget(
        wrap(
          RoundEntry(
            round: settled(
              const LogBailOut(
                characterId: 'a1',
                characterName: 'Ren Kobayashi',
                team: 'A',
                trionSalvaged: 0,
                refused: true,
              ),
            ),
          ),
        ),
      );

      expect(
        find.textContaining('refused to bail', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('no Trion Salvage', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a round that settled nothing renders nothing extra', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          RoundEntry(
            round: const LogRound(roundNumber: 4, team: 'B', actions: []),
          ),
        ),
      );

      expect(find.textContaining('recalled', findRichText: true), findsNothing);
      expect(find.text('(no legal action taken)'), findsOneWidget);
    });
  });
}

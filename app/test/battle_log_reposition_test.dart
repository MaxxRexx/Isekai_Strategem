import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/battle_models.dart';
import 'package:isekai_strategem/src/widgets/log_view.dart';

/// The battle log rendered one line per target, so an action with no target
/// rendered nothing at all and Repositions never appeared.
void main() {
  LogAction move(String name, String line) => LogAction(
        characterId: name.toLowerCase(),
        characterName: name,
        triggerId: repositionActionId,
        triggerName: 'Reposition to the $line line',
        fatTriggered: false,
        targets: const [],
      );

  Widget wrap(List<LogRound> rounds) => MaterialApp(
        home: Scaffold(
          body: BattleLogView(
            rounds: rounds,
            teamAName: 'You',
            teamBName: 'Opponent',
            open: true,
            onToggle: () {},
          ),
        ),
      );

  testWidgets('a move appears in the log as a readable sentence',
      (tester) async {
    await tester.pumpWidget(wrap([
      LogRound(
        roundNumber: 1,
        team: 'A',
        actions: [move('Marren Osei', 'front')],
      ),
    ]));

    // The line is a Text.rich, so match the assembled string.
    expect(
      find.text('Marren Osei moves to the front line', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a round of nothing but moves is not reported as empty',
      (tester) async {
    await tester.pumpWidget(wrap([
      LogRound(
        roundNumber: 2,
        team: 'B',
        actions: [move('Vela Ashworth', 'middle')],
      ),
    ]));

    expect(find.text('(no legal action taken)'), findsNothing);
    expect(
      find.text('Vela Ashworth moves to the middle line', findRichText: true),
      findsOneWidget,
    );
  });
}

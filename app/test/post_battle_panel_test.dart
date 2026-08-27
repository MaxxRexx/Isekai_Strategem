import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/test_scenarios.dart';
import 'package:isekai_strategem/src/screens/play_flow_screen.dart';
import 'package:isekai_strategem/src/widgets/pickers.dart';
import 'package:isekai_strategem/src/widgets/ability_slot.dart';
import 'package:isekai_strategem/src/widgets/portrait_tile.dart';
import 'package:isekai_strategem/src/widgets/tag_chip.dart';

/// A playtest report: "when a battle is complete (victory or defeat),
/// clicking on portraits, abilities, etc do not display the description
/// panel."
///
/// The panel was inside the else-branch of `if (session.isOver)`, along with
/// End Turn and the queued-actions strip, so the outcome banner replaced all
/// three at once. The portraits and ability slots stayed tappable throughout
/// and went on setting the selection; there was simply nothing left on screen
/// drawing it. A finished battle is exactly when a player wants to read back
/// over who was carrying what.
void main() {
  Future<void> pumpFinishedBattle(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: PlayFlowScreen(scenario: allScenarios.first)),
    );
    await tester.pump();

    // Surrender is the one way to end a battle on demand from the interface.
    await tester.tap(find.text('SURRENDER'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SURRENDER').last);
    await tester.pumpAndSettle();
  }

  testWidgets('the battle really is over', (tester) async {
    await pumpFinishedBattle(tester);
    expect(find.text('DEFEAT'), findsOneWidget);
  });

  testWidgets('a portrait tapped after the last hit still explains itself',
      (tester) async {
    await pumpFinishedBattle(tester);

    expect(find.byType(CharacterStatRow), findsNothing,
        reason: 'nothing is being described yet');

    await tester.tap(find.byType(PortraitHealthBar).first);
    await tester.pumpAndSettle();

    // The character panel leads with that character's stat row, which
    // nothing else on a finished battle screen draws.
    expect(find.byType(CharacterStatRow), findsOneWidget,
        reason: 'tapping a portrait after the battle showed no description '
            'panel');
  });

  testWidgets('an ability tapped after the last hit still explains itself',
      (tester) async {
    await pumpFinishedBattle(tester);

    // Every ability is unusable now, which is exactly the path that opens a
    // description rather than a target picker.
    final slots = find.byType(AbilitySlot);
    expect(slots, findsWidgets, reason: 'the ability rows outlive the battle');

    await tester.tap(slots.first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TagChip), findsOneWidget,
        reason: 'an ability description leads with its range band, and only '
            'the description panel draws one');
  });

  testWidgets('the outcome banner and its buttons are still there',
      (tester) async {
    await pumpFinishedBattle(tester);
    expect(find.text('RETURN TO HOME'), findsOneWidget);
    expect(find.text('COPY FULL REPORT'), findsOneWidget);
  });
}

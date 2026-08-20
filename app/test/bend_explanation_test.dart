import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/battle_models.dart';
import 'package:isekai_strategem/src/widgets/log_view.dart';

/// The words a player actually reads when a shot bends.
///
/// Generated copy is where sentences go wrong, so these assert the finished
/// text rather than the fields behind it.
void main() {
  Future<String> render(WidgetTester tester, LogBend bend) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: BendExplanation(bend: bend),
      )),
    ));
    final buffer = StringBuffer();
    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      if (w.data != null) buffer.writeln(w.data);
    }
    for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
      buffer.writeln(w.text.toPlainText());
    }
    return buffer.toString();
  }

  const oneScreen = LogBend(
    targetName: 'Celestine Moreau',
    bandLabel: 'Long Range',
    bandWindow: '2 to 4',
    bandMinimum: 2,
    distanceWhenCommitted: 2,
    distanceNow: 1,
    screensWhenCommitted: 1,
    screensBroken: ['Vela Ashworth'],
    backlashTier: 10,
  );

  testWidgets('one screen broken reads as a sentence', (tester) async {
    final text = await render(tester, oneScreen);
    // ignore: avoid_print
    print('=== ONE SCREEN ===\n$text');
    expect(text, contains('THE SHOT BENT TO REACH THEM'));
    expect(text, contains('Celestine Moreau was at distance 2'));
    expect(text, contains('counting the one body'));
    expect(text, contains('Long Range reaches 2 to 4'));
    expect(text, contains('Vela Ashworth then died'));
    expect(text, contains("under Long Range's minimum of 2"));
    expect(text, contains('Trion Backlash.'));
    expect(text, contains('capped at the Low tier, 10 Trion'));
    expect(text, contains('costs nothing further if other shots bend'));
  });

  testWidgets('two screens broken reads as a sentence', (tester) async {
    final text = await render(
      tester,
      const LogBend(
        targetName: 'Celestine Moreau',
        bandLabel: 'Mid Range',
        bandWindow: '1 to 3',
        bandMinimum: 1,
        distanceWhenCommitted: 2,
        distanceNow: 0,
        screensWhenCommitted: 2,
        screensBroken: ['Vela Ashworth', 'Rurik Voss'],
        backlashTier: 10,
      ),
    );
    // ignore: avoid_print
    print('=== TWO SCREENS ===\n$text');
    expect(text, contains('counting the two bodies'));
    expect(text, contains('Vela Ashworth and Rurik Voss then died'));
    expect(text, contains('those bodies gone'));
  });

  testWidgets('a target who simply closed the gap still reads', (tester) async {
    final text = await render(
      tester,
      const LogBend(
        targetName: 'Celestine Moreau',
        bandLabel: 'Long Range',
        bandWindow: '2 to 4',
        bandMinimum: 2,
        distanceWhenCommitted: 2,
        distanceNow: 1,
        screensWhenCommitted: 0,
        screensBroken: [],
        backlashTier: 10,
      ),
    );
    // ignore: avoid_print
    print('=== NO SCREENS ===\n$text');
    expect(text, contains('then came closer'));
    expect(text, isNot(contains('then died')));
    expect(text, isNot(contains('counting the')));
    expect(text, isNot(contains('Breaking a screen')),
        reason: 'no screen broke here, so the line must not claim one did');
  });
}

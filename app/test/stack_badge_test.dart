import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/data/describe.dart';
import 'package:isekai_strategem/src/widgets/badges.dart';

/// Item 5b: twelve statuses stack, and a stack multiplies everything the
/// status does. Three stacks of Bleeding is three times the damage.
///
/// That makes the count the difference between a scratch and a problem, so it
/// has to be on the badge. A player who can only see "Bleeding" cannot judge
/// what is about to happen to them.
///
/// It was an "x2" in 8-pixel type in the badge's top-left corner until a
/// playtest called it unreadable. The cap is three and the deepest pile ever
/// measured is three, so the count is shown rather than spelled: three pips
/// along the top edge, filled to the count.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  Finder litPips() => find.byWidgetPredicate((w) {
        final key = w.key;
        return key is ValueKey<String> &&
            key.value.startsWith('status-badge-pip-on');
      });

  group('a stack is a count you can see, not a digit you must read', () {
    testWidgets('one stack shows no pips at all', (tester) async {
      // Every badge would carry a single lit pip and none of them would mean
      // anything, which was the same objection the old "x1" answered.
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Bleeding',
        id: 'bleeding',
        remainingTurns: 3,
      )));

      expect(litPips(), findsNothing);
      expect(find.text('x1'), findsNothing);
    });

    testWidgets('two stacks light two pips', (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Bleeding',
        id: 'bleeding',
        remainingTurns: 3,
        stacks: 2,
      )));

      expect(litPips(), findsNWidgets(2));
      expect(find.text('x2'), findsNothing,
          reason: 'the digit is what this replaced');
    });

    testWidgets('three stacks fill the row', (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Inspired',
        id: 'inspired',
        remainingTurns: 2,
        stacks: 3,
      )));

      expect(litPips(), findsNWidgets(3));
    });

    testWidgets('the count and the duration are different marks',
        (tester) async {
      // They used to be two 8-pixel digits in opposite corners of a 19-pixel
      // square, in two colours, with nothing saying which was which.
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Inspired',
        id: 'inspired',
        remainingTurns: 2,
        stacks: 3,
      )));

      expect(litPips(), findsNWidgets(3));
      expect(find.byKey(const Key(StatusBadge.durationKey)), findsOneWidget);
      expect(find.byType(Text), findsNothing,
          reason: 'the resting badge carries no text at all');
    });
  });

  group('the tooltip says what a stack costs', () {
    test('a stacked effect says everything is multiplied', () {
      final text = describeStatusBadge(
        id: 'bleeding',
        name: 'Bleeding',
        remainingTurns: 3,
        onSelf: true,
        stacks: 3,
      );

      expect(text, contains('Bleeding x3'));
      expect(text, contains('multiplied by 3'));
    });

    test('an unstacked one reads exactly as it did before', () {
      final text = describeStatusBadge(
        id: 'bleeding',
        name: 'Bleeding',
        remainingTurns: 3,
        onSelf: true,
      );

      expect(text, isNot(contains('x1')));
      expect(text, isNot(contains('multiplied')));
    });
  });
}

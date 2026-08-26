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
void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  group('the badge shows what it is carrying', () {
    testWidgets('a single stack shows no multiplier at all', (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Bleeding',
        id: 'bleeding',
        remainingTurns: 3,
      )));

      expect(find.text('x1'), findsNothing,
          reason: 'every badge would carry an x1 and none of them would mean '
              'anything');
      expect(find.text('3'), findsOneWidget, reason: 'the duration still');
    });

    testWidgets('two stacks say so', (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Bleeding',
        id: 'bleeding',
        remainingTurns: 3,
        stacks: 2,
      )));

      expect(find.text('x2'), findsOneWidget);
    });

    testWidgets('the count and the duration are different numbers',
        (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Inspired',
        id: 'inspired',
        remainingTurns: 2,
        stacks: 3,
      )));

      expect(find.text('x3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
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

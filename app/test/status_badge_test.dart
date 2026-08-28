import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/ui/palette.dart';
import 'package:isekai_strategem/src/widgets/badges.dart';
import 'package:isekai_strategem/src/widgets/status_role_icons.dart';

/// A playtest called the status badges too small and their numbers
/// "almost impossible to read", and asked for something more considered than
/// making them bigger.
///
/// The measurement said size was not the problem. Ninety-nine characters in a
/// hundred carry three effects or fewer, so the 19-pixel square was small to
/// solve a crowding problem the game does not have. What it lacked was
/// information: all 62 effects drew one icon in one colour, so the two 8-pixel
/// corner digits were the only differentiated pixels on it.
///
/// The same footprint now carries four facts and no text, and tapping it
/// spells them out.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  StatusRoleIcon iconOf(WidgetTester tester) =>
      tester.widget<StatusRoleIcon>(find.byType(StatusRoleIcon).first);

  ShapeDecoration decorationOf(WidgetTester tester, String key) =>
      tester.widget<Container>(find.byKey(Key(key))).decoration
          as ShapeDecoration;

  Color borderOf(WidgetTester tester, String key) =>
      (decorationOf(tester, key).shape as OutlinedBorder).side.color;

  group('the badge says what kind of effect it is', () {
    testWidgets('a bleed and a ward are not the same picture', (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Bleeding',
        id: 'bleeding',
        remainingTurns: 3,
      )));
      final bleed = iconOf(tester).role;

      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Guarded',
        id: 'guarded',
        remainingTurns: 2,
      )));
      final ward = iconOf(tester).role;

      expect(bleed, StatusRole.damageOverTime);
      expect(ward, StatusRole.takesLess);
      expect(bleed, isNot(ward),
          reason: 'one shared icon for all 62 effects is what this replaced');
    });

    testWidgets('an effect with no id falls back rather than guessing',
        (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(name: 'Mystery')));
      expect(iconOf(tester).role, StatusRole.special);
    });
  });

  group('the colour says whose side it is on', () {
    testWidgets('harm is red', (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Bleeding',
        id: 'bleeding',
        remainingTurns: 3,
      )));
      expect(borderOf(tester, StatusBadge.compactKey), Palette.danger);
      expect(iconOf(tester).color, Palette.danger);
    });

    testWidgets('help is green', (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Guarded',
        id: 'guarded',
        remainingTurns: 2,
      )));
      expect(borderOf(tester, StatusBadge.compactKey), Palette.good);
    });

    testWidgets('a trade is violet, because it is genuinely neither',
        (tester) async {
      // Enraged buys damage and Psychic immunity and takes the aiming away.
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Enraged',
        id: 'enraged',
        remainingTurns: 2,
      )));
      expect(borderOf(tester, StatusBadge.compactKey), Palette.bend);
    });
  });

  group('the duration is a length, not a digit', () {
    double ruleWidth(WidgetTester tester) => tester
        .widget<FractionallySizedBox>(
            find.byKey(const Key(StatusBadge.durationKey)))
        .widthFactor!;

    testWidgets('it shortens as the turns run out', (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Bleeding',
        id: 'bleeding',
        remainingTurns: 3,
      )));
      final full = ruleWidth(tester);

      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Bleeding',
        id: 'bleeding',
        remainingTurns: 1,
      )));
      final nearlyGone = ruleWidth(tester);

      expect(full, 1.0);
      expect(nearlyGone, lessThan(full));
    });

    testWidgets('the last turn is amber, whatever the effect is', (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Guarded',
        id: 'guarded',
        remainingTurns: 1,
      )));
      final rule = tester.widget<ColoredBox>(find.descendant(
        of: find.byKey(const Key(StatusBadge.durationKey)),
        matching: find.byType(ColoredBox),
      ));

      expect(rule.color, Palette.warn,
          reason: '"about to expire" is worth seeing from across the board, '
              'and it means the same thing on a buff as on a debuff');
    });

    testWidgets('an effect with no expiry draws no rule', (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Bleeding',
        id: 'bleeding',
      )));
      expect(find.byKey(const Key(StatusBadge.durationKey)), findsNothing);
    });

    testWidgets('a longer duration than the scale simply arrives full',
        (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Bleeding',
        id: 'bleeding',
        remainingTurns: 9,
      )));
      expect(ruleWidth(tester), 1.0);
    });
  });

  group('tapping a badge opens it into a named pill', () {
    testWidgets('it starts closed and carries no text', (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Bleeding',
        id: 'bleeding',
        remainingTurns: 3,
        stacks: 2,
      )));

      expect(find.byKey(const Key(StatusBadge.compactKey)), findsOneWidget);
      expect(find.byKey(const Key(StatusBadge.expandedKey)), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('a tap names it, counts it and times it', (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Bleeding',
        id: 'bleeding',
        remainingTurns: 3,
        stacks: 2,
      )));

      await tester.tap(find.byKey(const Key(StatusBadge.compactKey)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key(StatusBadge.expandedKey)), findsOneWidget);
      expect(find.text('BLEEDING'), findsOneWidget);
      expect(find.text('x2'), findsOneWidget);
      expect(find.text('3t'), findsOneWidget);
    });

    testWidgets('the same tap still shows the full description', (tester) async {
      // Tapping used to open the tooltip and nothing else. Expanding must not
      // cost the player the sentence they used to get.
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Guarded',
        id: 'guarded',
        remainingTurns: 2,
      )));

      await tester.tap(find.byKey(const Key(StatusBadge.compactKey)));
      await tester.pumpAndSettle();

      expect(find.textContaining('25% less damage'), findsOneWidget);
    });

    testWidgets('tapping the open pill closes it again', (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Bleeding',
        id: 'bleeding',
        remainingTurns: 3,
      )));

      await tester.tap(find.byKey(const Key(StatusBadge.compactKey)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key(StatusBadge.expandedKey)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key(StatusBadge.compactKey)), findsOneWidget);
      expect(find.byKey(const Key(StatusBadge.expandedKey)), findsNothing);
    });

    testWidgets('an unstacked effect does not show a count in the pill',
        (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Guarded',
        id: 'guarded',
        remainingTurns: 2,
      )));

      await tester.tap(find.byKey(const Key(StatusBadge.compactKey)));
      await tester.pumpAndSettle();

      expect(find.text('GUARDED'), findsOneWidget);
      expect(find.text('x1'), findsNothing);
    });

    testWidgets('the open pill keeps the badge\'s own colour', (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(
        name: 'Guarded',
        id: 'guarded',
        remainingTurns: 2,
      )));

      await tester.tap(find.byKey(const Key(StatusBadge.compactKey)));
      await tester.pumpAndSettle();

      expect(borderOf(tester, StatusBadge.expandedKey), Palette.good);
    });
  });

  group('every role in the catalogue can be drawn', () {
    testWidgets('nothing throws, at the size it actually ships at',
        (tester) async {
      // Fourteen glyphs, each one hand-drawn for ten pixels. A path that
      // throws on one obscure effect would only surface in a battle where
      // that effect landed.
      for (final def in StatusEffectCatalog.defaultCatalog.all) {
        await tester.pumpWidget(wrap(StatusBadge(
          name: def.name,
          id: def.id,
          remainingTurns: def.defaultDurationTurns,
        )));
        expect(tester.takeException(), isNull, reason: def.id);
      }
    });
  });
}

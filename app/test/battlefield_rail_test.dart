import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/battle_models.dart';
import 'package:isekai_strategem/src/widgets/battlefield_rail.dart';

/// #1 (range bands), UI side: the horizontal lane diagram, its distance ruler,
/// and moving by tapping one of your own lines.
void main() {
  FighterSnapshot fighter(
    String id,
    String name,
    BattlePosition position, {
    bool alive = true,
  }) =>
      FighterSnapshot(
        id: id,
        name: name,
        type: CharacterType.attack,
        currentHealth: alive ? 100 : 0,
        maxHealth: 100,
        alive: alive,
        position: position,
      );

  /// The screen pips are drawn shapes rather than a bullet character, because
  /// the glyph is not in the font the web build loads and rendered as an empty
  /// box. So count circles, not text.
  Finder screenPips() => find.byWidgetPredicate((w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration! as BoxDecoration).shape == BoxShape.circle);

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 900, child: child)),
      );

  testWidgets('the rail names all six lines, your side and theirs',
      (tester) async {
    await tester.pumpWidget(wrap(BattlefieldRail(
      teamA: [fighter('a1', 'Ren Kobayashi', BattlePosition.front)],
      teamB: [fighter('b1', 'Vela Ashworth', BattlePosition.back)],
    )));

    expect(find.text('BATTLEFIELD'), findsOneWidget);
    for (final label in ['YOUR BACK', 'YOUR MIDDLE', 'YOUR FRONT']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final label in ['THEIR FRONT', 'THEIR MIDDLE', 'THEIR BACK']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Ren'), findsOneWidget);
    expect(find.text('Vela'), findsOneWidget);
  });

  testWidgets('a queued move draws the token on its destination, marked',
      (tester) async {
    await tester.pumpWidget(wrap(BattlefieldRail(
      teamA: [fighter('a1', 'Ren Kobayashi', BattlePosition.back)],
      teamB: [fighter('b1', 'Vela Ashworth', BattlePosition.front)],
      projected: const {'a1': BattlePosition.middle},
    )));

    // The arrow prefix marks a token standing where it has not moved to yet.
    expect(find.text('> Ren'), findsOneWidget);
    expect(find.text('Ren'), findsNothing);
  });

  testWidgets('the ruler prints the distance to each enemy line',
      (tester) async {
    await tester.pumpWidget(wrap(BattlefieldRail(
      teamA: [fighter('a1', 'Ren Kobayashi', BattlePosition.front)],
      teamB: [
        fighter('b1', 'Vela Ashworth', BattlePosition.front),
        fighter('b2', 'Dross', BattlePosition.middle),
        fighter('b3', 'Kaito Reyes', BattlePosition.back),
      ],
      focusedId: 'a1',
    )));

    // Standing on your front line (step 0), the two lines add and the bodies
    // in the way add on top: their front is unscreened at 0, their middle has
    // one body in front of it so 1 + 1 = 2, and their back has two so
    // 2 + 2 = 4. The ruler prints the number the bands are compared against,
    // screens included, or it would be lying about who is reachable.
    expect(find.text('0'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('an empty enemy line shows a dash, not a number', (tester) async {
    await tester.pumpWidget(wrap(BattlefieldRail(
      teamA: [fighter('a1', 'Ren Kobayashi', BattlePosition.back)],
      teamB: [
        fighter('b1', 'Vela Ashworth', BattlePosition.front),
        fighter('b2', 'Dross', BattlePosition.front),
        fighter('b3', 'Kaito Reyes', BattlePosition.front),
      ],
      focusedId: 'a1',
    )));

    // All three of theirs are on one line, so their middle and back are empty.
    // Measured as if someone were standing there, their back would compute as
    // 2 + 2 + 3 screens = 7, which is higher than any real target can ever be.
    // Nobody is there, so it is a dash.
    expect(find.text('2'), findsOneWidget, reason: 'their front, occupied');
    expect(find.text('7'), findsNothing);
    expect(find.text('-'), findsNWidgets(2),
        reason: 'their empty middle and back lines');
  });

  testWidgets('a screened enemy carries one pip per body shielding them',
      (tester) async {
    await tester.pumpWidget(wrap(BattlefieldRail(
      teamA: [fighter('a1', 'Ren Kobayashi', BattlePosition.front)],
      teamB: [
        fighter('b1', 'Vela Ashworth', BattlePosition.front),
        fighter('b2', 'Dross', BattlePosition.front),
        fighter('b3', 'Kaito Reyes', BattlePosition.back),
      ],
      focusedId: 'a1',
    )));

    // Their sniper is behind two bodies, so two pips and a distance of 4.
    // The pair screening them are on the front line and screen nobody, so
    // two pips is the total across the whole strip.
    expect(screenPips(), findsNWidgets(2));
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('killing a screen shortens the printed distance',
      (tester) async {
    await tester.pumpWidget(wrap(BattlefieldRail(
      teamA: [fighter('a1', 'Ren Kobayashi', BattlePosition.front)],
      teamB: [
        fighter('b1', 'Vela Ashworth', BattlePosition.front, alive: false),
        fighter('b2', 'Dross', BattlePosition.front),
        fighter('b3', 'Kaito Reyes', BattlePosition.back),
      ],
      focusedId: 'a1',
    )));

    // One screen down: the sniper drops from 4 to 3 and shows a single pip.
    // Only the living get in the way.
    expect(find.text('3'), findsOneWidget);
    expect(screenPips(), findsOneWidget);
  });

  testWidgets('the selected band is named, and measured from the focused line',
      (tester) async {
    await tester.pumpWidget(wrap(BattlefieldRail(
      teamA: [fighter('a1', 'Ren Kobayashi', BattlePosition.front)],
      teamB: [fighter('b1', 'Vela Ashworth', BattlePosition.front)],
      reachFrom: BattlePosition.front,
      reachBand: RangeTag.long,
      focusedId: 'a1',
    )));

    expect(find.text('Long Range reaches 2 to 4'), findsOneWidget);
  });

  testWidgets('tapping one of your lines steps there, when the step is legal',
      (tester) async {
    final tapped = <BattlePosition>[];
    await tester.pumpWidget(wrap(BattlefieldRail(
      teamA: [fighter('a1', 'Ren Kobayashi', BattlePosition.back)],
      teamB: [fighter('b1', 'Vela Ashworth', BattlePosition.front)],
      focusedId: 'a1',
      legalSteps: const {BattlePosition.middle},
      onStep: tapped.add,
    )));

    await tester.tap(find.text('YOUR MIDDLE'));
    await tester.tap(find.text('YOUR FRONT'));
    await tester.pump();

    expect(tapped, [BattlePosition.middle],
        reason: 'Front is two lines from Back, so its cell is inert');
  });

  testWidgets('enemy lines are never step targets', (tester) async {
    final tapped = <BattlePosition>[];
    await tester.pumpWidget(wrap(BattlefieldRail(
      teamA: [fighter('a1', 'Ren Kobayashi', BattlePosition.back)],
      teamB: [fighter('b1', 'Vela Ashworth', BattlePosition.front)],
      focusedId: 'a1',
      legalSteps: const {BattlePosition.middle, BattlePosition.front},
      onStep: tapped.add,
    )));

    await tester.tap(find.text('THEIR FRONT'));
    await tester.pump();

    expect(tapped, isEmpty);
  });
}

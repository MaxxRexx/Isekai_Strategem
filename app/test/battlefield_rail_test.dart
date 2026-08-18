import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/battle_models.dart';
import 'package:isekai_strategem/src/widgets/battlefield_rail.dart';

/// #1 (range bands), UI side: the horizontal lane diagram, its distance ruler,
/// and moving by tapping one of your own lines.
void main() {
  FighterSnapshot fighter(String id, String name, BattlePosition position) =>
      FighterSnapshot(
        id: id,
        name: name,
        type: CharacterType.attack,
        currentHealth: 100,
        maxHealth: 100,
        alive: true,
        position: position,
      );

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

    // Standing on your front line (step 0), the enemy lines are 0, 1 and 2
    // away: distance is the two sides' steps added together.
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
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

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/battle_models.dart';
import 'package:isekai_strategem/src/widgets/battlefield_rail.dart';

/// #1 (range bands), UI side: the lane diagram and the move strip.
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
        home: Scaffold(body: SizedBox(width: 320, child: child)),
      );

  testWidgets('the rail names all six lines, both squads', (tester) async {
    await tester.pumpWidget(wrap(BattlefieldRail(
      teamA: [fighter('a1', 'Ren Kobayashi', BattlePosition.front)],
      teamB: [fighter('b1', 'Vela Ashworth', BattlePosition.back)],
    )));

    expect(find.text('BATTLEFIELD'), findsOneWidget);
    // Three lines per side, so each label appears twice.
    for (final label in ['FRONT', 'MIDDLE', 'BACK']) {
      expect(find.text(label), findsNWidgets(2));
    }
    expect(find.text('RK'), findsOneWidget);
    expect(find.text('VA'), findsOneWidget);
  });

  testWidgets('a queued move draws the token on its destination, marked',
      (tester) async {
    await tester.pumpWidget(wrap(BattlefieldRail(
      teamA: [fighter('a1', 'Ren Kobayashi', BattlePosition.back)],
      teamB: [fighter('b1', 'Vela Ashworth', BattlePosition.front)],
      projected: const {'a1': BattlePosition.middle},
    )));

    // The arrow prefix marks a token standing somewhere it has not moved to
    // yet, so the plan is visible before it resolves.
    expect(find.text('> RK'), findsOneWidget);
    expect(find.text('RK'), findsNothing);
  });

  testWidgets('the selected band is spelled out under the lanes',
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

  testWidgets('the stepper only offers a line one step away', (tester) async {
    final tapped = <BattlePosition>[];
    await tester.pumpWidget(wrap(PositionStepper(
      current: BattlePosition.back,
      legal: const {BattlePosition.middle},
      onStep: tapped.add,
    )));

    await tester.tap(find.text('M'));
    await tester.tap(find.text('F'));
    await tester.pump();

    expect(tapped, [BattlePosition.middle],
        reason: 'Front is two steps from Back, so its pip is inert');
  });

  testWidgets('the stepper flags a move that is queued but not resolved',
      (tester) async {
    await tester.pumpWidget(wrap(const PositionStepper(
      current: BattlePosition.middle,
      legal: {},
      pending: true,
    )));

    expect(find.text('MOVING'), findsOneWidget);
  });
}

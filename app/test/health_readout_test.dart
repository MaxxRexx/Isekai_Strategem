import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/widgets/portrait_tile.dart';

/// Found in the #14 playtest: at 31 of 100 the readout on the health bar could
/// not be read.
///
/// The number sits on top of the whole bar, and the bar is two colours at
/// once: a bright green, amber or red fill on the left, and a near-black empty
/// track on the right. The label was dark, which reads on the fill and
/// disappears on the track, so the more damage a character had taken the less
/// legible their health became. Exactly backwards.
void main() {
  Widget wrap(int current) => MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0B0F14),
          body: Center(
            child: PortraitHealthBar(
              characterId: 'ilona_vance',
              name: 'Ilona Vance',
              type: CharacterType.defense,
              currentHealth: current,
              maxHealth: 100,
              alive: current > 0,
              size: 96,
            ),
          ),
        ),
      );

  TextStyle styleAt(WidgetTester tester, int current) => tester
      .widget<Text>(find.text('$current/100'))
      .style!;

  group('the health readout is legible at any health', () {
    testWidgets('the label is light rather than dark', (tester) async {
      await tester.pumpWidget(wrap(31));
      final style = styleAt(tester, 31);

      expect(style.color, Colors.white,
          reason: 'a dark label vanishes into the empty track');
    });

    testWidgets('it carries an outline, so it also reads on the fill',
        (tester) async {
      await tester.pumpWidget(wrap(100));
      final style = styleAt(tester, 100);

      expect(style.shadows, isNotNull);
      expect(style.shadows, hasLength(greaterThanOrEqualTo(4)),
          reason: 'an outline needs a shadow on each side');
      for (final shadow in style.shadows!) {
        expect(shadow.color.a, greaterThan(0.5),
            reason: 'a faint outline does not separate white from green');
      }
    });

    testWidgets('the treatment does not change with how hurt they are',
        (tester) async {
      // The bug was that legibility tracked health. Whatever the fill is
      // doing, the number is drawn the same way.
      await tester.pumpWidget(wrap(100));
      final full = styleAt(tester, 100);
      await tester.pumpWidget(wrap(31));
      final hurt = styleAt(tester, 31);
      await tester.pumpWidget(wrap(1));
      final nearlyGone = styleAt(tester, 1);

      expect(hurt.color, full.color);
      expect(nearlyGone.color, full.color);
      expect(hurt.shadows, full.shadows);
      expect(nearlyGone.shadows, full.shadows);
    });

    testWidgets('a defeated character still reads', (tester) async {
      await tester.pumpWidget(wrap(0));
      expect(find.text('0/100'), findsOneWidget);
      expect(styleAt(tester, 0).color, Colors.white);
    });
  });
}

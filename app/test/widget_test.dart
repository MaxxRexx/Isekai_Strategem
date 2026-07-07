import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isekai_strategem/src/app.dart';

const _outcomePattern =
    r'SQUAD [AB] WINS|MUTUAL DEFEAT|NO CONCLUSION REACHED|VICTORY|DEFEAT';

/// These screens are long scrollable forms; the default test viewport is
/// small enough that content below the fold is culled by the sliver
/// layout and never built, so finders can't see it without scrolling.
/// Using a tall surface instead keeps the tests simple and readable.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('Home screen shows the title and every entry point', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const IsekaiStrategemApp());

    expect(find.text('ISEKAI STRATEGEM'), findsOneWidget);
    expect(find.text('PLAY (DRAFT YOUR SQUAD)'), findsOneWidget);
    expect(find.text('GUIDED TUTORIAL'), findsOneWidget);
    expect(find.text('SIMULATE (AI VS AI)'), findsOneWidget);
    expect(find.text('QUICK BATTLE (ONE-SHOT)'), findsOneWidget);
    expect(find.text('HOW TO PLAY'), findsOneWidget);
  });

  testWidgets(
    'Quick Battle runs a real battle end to end and shows an outcome',
    (WidgetTester tester) async {
      await tester.pumpWidget(const IsekaiStrategemApp());

      await tester.tap(find.text('QUICK BATTLE (ONE-SHOT)'));
      await tester.pumpAndSettle();

      expect(find.text('Quick Battle'), findsOneWidget);
      expect(find.text('BATTLE LOG'), findsOneWidget);
      expect(find.textContaining(RegExp(_outcomePattern)), findsOneWidget);

      await tester.tap(find.text('RUN ANOTHER BATTLE'));
      await tester.pumpAndSettle();
      expect(find.textContaining(RegExp(_outcomePattern)), findsOneWidget);
    },
  );

  testWidgets('Simulate mode drafts two AI squads and runs a real battle', (
    WidgetTester tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(const IsekaiStrategemApp());

    await tester.tap(find.text('SIMULATE (AI VS AI)'));
    await tester.pumpAndSettle();

    expect(find.text('SQUAD A'), findsOneWidget);
    expect(find.text('SQUAD B'), findsOneWidget);

    await tester.tap(find.text('ENGAGE'));
    await tester.pumpAndSettle();

    expect(find.textContaining(RegExp(_outcomePattern)), findsOneWidget);
    expect(find.text('ENGAGEMENT LOG'), findsOneWidget);
  });

  testWidgets(
    'Play mode drafts a squad, auto-fills Loadouts, and reaches the battle',
    (WidgetTester tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(const IsekaiStrategemApp());

      await tester.tap(find.text('PLAY (DRAFT YOUR SQUAD)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('NEXT: BUILD LOADOUTS'));
      await tester.pumpAndSettle();

      // 3 characters, each needs its Loadout auto-filled and confirmed.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Auto-fill'));
        await tester.pumpAndSettle();

        final confirmButton = i < 2
            ? find.text('CONFIRM LOADOUT')
            : find.text('CONFIRM LOADOUT & ENGAGE');
        expect(confirmButton, findsOneWidget);
        await tester.tap(confirmButton);
        await tester.pumpAndSettle();
      }

      expect(find.text('YOUR SQUAD'), findsOneWidget);
      expect(find.text('OPPONENT SQUAD'), findsOneWidget);
    },
  );

  testWidgets('Guided Tutorial walks through the scripted squad setup steps', (
    WidgetTester tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(const IsekaiStrategemApp());

    await tester.tap(find.text('GUIDED TUTORIAL'));
    await tester.pumpAndSettle();

    expect(find.text('GUIDED TUTORIAL'), findsWidgets);
    expect(find.textContaining('Ren Kobayashi'), findsWidgets);

    // Slot 0 (Agent I) is the only enabled/empty slot at this step. The
    // picker sheet is a tap-to-preview roster grid: tap the tile to focus
    // it, then Draft to actually commit the pick and close the sheet.
    await tester.tap(find.text('Choose a character...').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ren Kobayashi').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Draft'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ilona Vance'), findsWidgets);
  });

  testWidgets('How to Play guide renders the rules reference', (
    WidgetTester tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(const IsekaiStrategemApp());

    await tester.tap(find.text('HOW TO PLAY'));
    await tester.pumpAndSettle();

    // The Rules tab is shown by default.
    expect(find.text('Character Stats'), findsOneWidget);

    // Each catalog now sits behind its own instant sub-tab switcher rather
    // than one long scroll, so switch tabs to reach each one.
    for (final tabLabel in const [
      'Character Perks',
      'Status Effects',
      'Triggers',
      'Black Triggers',
    ]) {
      await tester.tap(find.text(tabLabel));
      await tester.pumpAndSettle();
      if (tabLabel == 'Status Effects') {
        expect(find.textContaining('Poisoned'), findsWidgets);
      }
    }
  });
}

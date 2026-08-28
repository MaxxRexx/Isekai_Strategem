import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/data/describe.dart';
import 'package:isekai_strategem/src/screens/guide_screen.dart';

/// The guide's Status Effects tab ran on a hand-written map of 49 names with
/// its own durations and effect text, beside a catalogue of 62.
///
/// The gap was the predictable one, and every item in it was the rules
/// reference telling a player something untrue: thirteen effects missing
/// outright, Empowered's duration a turn short, Electrocuted claiming a flat 3
/// where it rolls 1d4, Enraged never mentioning the Psychic immunity or the
/// random targeting item 3b gave it, and Radiant Blessing still promising +10
/// maximum health that had been deliberately removed.
///
/// The tab is generated now. These are the checks that it stays that way: a
/// second copy of this data cannot creep back in without failing here.
void main() {
  final catalog = StatusEffectCatalog.defaultCatalog;

  Future<void> openStatusTab(WidgetTester tester) async {
    // Tall enough that the whole list builds in one viewport: a lazy ListView
    // only builds what is on screen, and this test is about what the list
    // contains rather than about scrolling.
    await tester.binding.setSurfaceSize(const Size(900, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: GuideScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Status Effects'));
    await tester.pumpAndSettle();
  }

  testWidgets('every effect in the catalogue is listed', (tester) async {
    await openStatusTab(tester);

    final seen = {
      for (final w in tester.widgetList<Text>(find.byType(Text)))
        if (w.data != null) w.data!,
    };

    final missing = [
      for (final def in catalog.all)
        if (!seen.contains(def.name)) def.name,
    ];
    expect(missing, isEmpty,
        reason: 'the guide is the rules reference, and an effect it does not '
            'list is one a player cannot look up');
  });

  testWidgets('the count in the intro is the real one', (tester) async {
    await openStatusTab(tester);

    expect(find.textContaining('${catalog.all.length} status effects'),
        findsOneWidget,
        reason: 'it said "50" against a catalogue of 62 for an entire wave');
  });

  testWidgets('the durations come from the catalogue', (tester) async {
    await openStatusTab(tester);

    // Empowered is the one that was actually wrong: the guide said two turns
    // and the catalogue says three.
    final empowered = catalog['empowered'];
    expect(empowered.defaultDurationTurns, 3);
    expect(find.text('Empowered'), findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Empowered'),
          matching: find.byType(Row),
        ).first,
        matching: find.text('3 turns'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the body text is the generated description', (tester) async {
    await openStatusTab(tester);

    // Not "a description that looks similar": the same string the badge
    // tooltip and the ability panel use, so the three cannot disagree.
    final expected = describeStatusEffect(
      catalog['empowered'],
      onSelf: true,
      includeDuration: false,
    );
    expect(find.text(expected), findsOneWidget);
  });

  group('the things the hand-written copy got wrong stay fixed', () {
    test('Electrocuted says what it rolls, not what it averages', () {
      final text = describeStatusEffect(
        catalog['electrocuted'],
        onSelf: true,
        includeDuration: false,
      );
      expect(text, contains('1d4'),
          reason: 'rounding 1d4 to 3 says a number the dice do not promise');
      expect(text, contains('Lightning'),
          reason: 'the type decides whether a resistance changes it');
    });

    test('Enraged mentions everything item 3b gave it', () {
      final text = describeStatusEffect(
        catalog['enraged'],
        onSelf: true,
        includeDuration: false,
      );
      expect(text, contains('50% more damage'));
      expect(text, contains('Psychic'));
      expect(text, contains('at random'));
    });

    test('Radiant Blessing no longer promises maximum health', () {
      final text = describeStatusEffect(
        catalog['radiant_blessing'],
        onSelf: true,
        includeDuration: false,
      );
      expect(text, isNot(contains('max')),
          reason: 'raising the ceiling was deliberately taken out, and the '
              'guide went on advertising it');
    });

    test('a roll effect says which rolls', () {
      // Both used to read "You roll at a disadvantage", which is the same
      // sentence for two effects that hurt in completely different ways.
      final poisoned = describeStatusEffect(catalog['poisoned'],
          onSelf: true, includeDuration: false);
      final threatened = describeStatusEffect(catalog['threatened'],
          onSelf: true, includeDuration: false);

      expect(poisoned, contains('attack rolls'));
      expect(threatened, contains('ranged attack rolls'));
      expect(poisoned, isNot(contains('ranged')));
    });

    test('an effect touching every attack roll does not list ranged twice',
        () {
      // Terrified carries both tags. Disadvantage does not stack, so naming
      // both would imply something the dice do not do.
      final text = describeStatusEffect(catalog['terrified'],
          onSelf: true, includeDuration: false);
      expect(text, contains('attack rolls'));
      expect(text, isNot(contains('ranged attack rolls')));
    });
  });
}

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/battle_models.dart';
import 'package:isekai_strategem/src/widgets/fighter_row.dart';
import 'package:isekai_strategem/src/widgets/portrait_tile.dart';

/// A playtest report: "from middle position with Mireille, Longshot did not
/// highlight Nadia, but Frag Grenade did."
///
/// Both are Long Range attacks and both reach exactly the same people. The
/// difference was never reach: the area ability auto-selected its targets, so
/// they were marked, and the single-target one waited for a tap, so nobody
/// was. Reachability had no mark of its own, which meant the board said
/// "nothing here for you" whenever an ability wanted a choice.
///
/// Two states now, and they have to stay visibly different: steady means the
/// ability can reach this portrait, pulsing means it has been aimed there.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(width: 900, child: child)),
  );

  FighterSnapshot fighter(String id, String name) => FighterSnapshot(
    id: id,
    name: name,
    type: CharacterType.attack,
    currentHealth: 100,
    maxHealth: 100,
    alive: true,
  );

  /// Which of the two target-picker overlays a portrait is wearing.
  ({bool ring, bool pulse}) marksOn(WidgetTester tester, String id) {
    final portrait = find.byWidgetPredicate(
      (w) => w is PortraitHealthBar && w.characterId == id,
    );
    expect(portrait, findsOneWidget, reason: 'no portrait found for $id');
    bool has(String key) => find
        .descendant(of: portrait, matching: find.byKey(Key(key)))
        .evaluate()
        .isNotEmpty;
    return (
      ring: has(PortraitHealthBar.eligibleMarkKey),
      pulse: has(PortraitHealthBar.selectedMarkKey),
    );
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    Set<String> eligible = const {},
    Set<String> selected = const {},
  }) => tester.pumpWidget(
    wrap(
      TeamPanel(
        label: 'Opponent Squad',
        color: Colors.red,
        fighters: [
          fighter('opponent:nadia_kessler', 'Nadia Kessler'),
          fighter('opponent:vela_ashworth', 'Vela Ashworth'),
        ],
        eligibleIds: eligible,
        selectedIds: selected,
        onFighterTap: (_) {},
      ),
    ),
  );

  testWidgets('an unselected ability marks nobody', (tester) async {
    await pumpPanel(tester);
    expect(marksOn(tester, 'opponent:nadia_kessler').ring, isFalse);
    expect(marksOn(tester, 'opponent:nadia_kessler').pulse, isFalse);
  });

  testWidgets('a reachable target is marked before anything is picked',
      (tester) async {
    // This is the Longshot case: nothing selected yet, and the player still
    // has to be able to see who the shot can reach.
    await pumpPanel(tester, eligible: {'opponent:nadia_kessler'});

    expect(marksOn(tester, 'opponent:nadia_kessler').ring, isTrue);
    expect(marksOn(tester, 'opponent:nadia_kessler').pulse, isFalse,
        reason: 'reachable is not the same as chosen');
    expect(marksOn(tester, 'opponent:vela_ashworth').ring, isFalse,
        reason: 'an out-of-reach target stays unmarked');
  });

  testWidgets('picking one changes its mark rather than adding to it',
      (tester) async {
    await pumpPanel(
      tester,
      eligible: {'opponent:nadia_kessler', 'opponent:vela_ashworth'},
      selected: {'opponent:nadia_kessler'},
    );

    final picked = marksOn(tester, 'opponent:nadia_kessler');
    final offered = marksOn(tester, 'opponent:vela_ashworth');

    expect(picked.pulse, isTrue);
    expect(picked.ring, isFalse);
    expect(offered.ring, isTrue);
    expect(offered.pulse, isFalse,
        reason: 'if both states pulsed there would be no way to read which '
            'one the ability is actually aimed at');
  });

  testWidgets('the row marks a fighter the same way outside a panel',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        FighterRow(
          fighter: fighter('player:rurik_voss', 'Rurik Voss'),
          eligible: true,
        ),
      ),
    );
    expect(marksOn(tester, 'player:rurik_voss').ring, isTrue);
  });
}

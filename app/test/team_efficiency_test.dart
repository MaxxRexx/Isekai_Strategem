import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/draft.dart';
import 'package:isekai_strategem/src/game/loadout_selection.dart';
import 'package:isekai_strategem/src/game/play_session.dart';
import 'package:isekai_strategem/src/game/team_efficiency.dart';

/// The Team Efficiency Grade scoring model, and its use as earned
/// initiative: the grade weights which squad takes the opening turn, in
/// place of the fair coin flip that used to decide it.
void main() {
  Loadout loadout(String id, List<String> triggerIds) => Loadout(
    characterId: id,
    triggers: [for (final t in triggerIds) triggerCatalog[t]],
  );

  TeamEfficiency gradeOf(String id, List<String> triggerIds) =>
      computeTeamEfficiency(
        characterIds: [id],
        loadouts: {id: loadout(id, triggerIds)},
      );

  test('composite stays in range and maps to a tier monotonically', () {
    final teg = computeTeamEfficiency(
      characterIds: const ['vela_ashworth'],
      loadouts: {
        'vela_ashworth': defaultLoadoutSelectionFor(
          'vela_ashworth',
        ).toLoadout('vela_ashworth'),
      },
    );
    expect(teg.composite, inInclusiveRange(0, 100));
    // Tier thresholds line up with the composite.
    final expected = switch (teg.composite) {
      >= 96 => TegTier.sss,
      >= 89 => TegTier.ss,
      >= 79 => TegTier.s,
      >= 68 => TegTier.a,
      >= 55 => TegTier.b,
      >= 40 => TegTier.c,
      _ => TegTier.d,
    };
    expect(teg.tier, expected);
  });

  test('Team Spirit alignment rewards matching the squad\'s pole', () {
    // Yuki has high Team Spirit (70, the sustain pole). A support loadout is
    // aligned; a pure-offense loadout on the same character is not.
    final aligned = gradeOf('yuki_amaral', [
      'soul_siphon', // heal/siphon (sustain)
      'cleansing_ward', // ally support
      'rally_cry', // ally buff
      'war_chant', // self buff
    ]);
    final mismatched = gradeOf('yuki_amaral', [
      'twin_fang_strike',
      'piercing_thrust',
      'longshot',
      'scattershot',
    ]);
    expect(
      aligned.teamSpiritAlignment,
      greaterThan(mismatched.teamSpiritAlignment),
    );
  });

  test('resonance fit is null without a Black Trigger and set with one', () {
    final noBt = gradeOf('vela_ashworth', [
      'twin_fang_strike',
      'piercing_thrust',
      'longshot',
      'scattershot',
    ]);
    expect(noBt.resonanceFit, isNull);

    final withBt = computeTeamEfficiency(
      characterIds: const ['vela_ashworth'],
      loadouts: {
        'vela_ashworth': Loadout(
          characterId: 'vela_ashworth',
          triggers: [
            triggerCatalog['twin_fang_strike'],
            triggerCatalog['piercing_thrust'],
            triggerCatalog['longshot'],
          ],
          blackTrigger: blackTriggerCatalog['ashbringer'],
        ),
      },
    );
    expect(withBt.resonanceFit, isNotNull);
  });

  test('scoring is deterministic', () {
    final a = gradeOf('dross', [
      'twin_fang_strike',
      'cleave',
      'whirlwind_slash',
      'longshot',
    ]);
    final b = gradeOf('dross', [
      'twin_fang_strike',
      'cleave',
      'whirlwind_slash',
      'longshot',
    ]);
    expect(a.composite, b.composite);
    expect(a.tier, b.tier);
  });

  test('both squads get a grade stored on the session', () {
    const playerIds = ['marren_osei', 'ilona_vance', 'bastian_cole'];
    final session = PlaySession.start(
      playerCharacterIds: playerIds,
      playerLoadouts: {
        for (final id in playerIds)
          id: defaultLoadoutSelectionFor(id).toLoadout(id),
      },
      opponentCharacterIds: const ['kaito_reyes', 'vela_ashworth', 'dross'],
      opponentProfileId: 'the_tactician',
      // The opening turn is a coin flip, independent of the grade; the
      // grades are still computed and stored for later use.
      firstTurn: 'teamA',
    );
    expect(session.teamAEfficiency.composite, inInclusiveRange(0, 100));
    expect(session.teamBEfficiency.composite, inInclusiveRange(0, 100));
    // firstTurn: 'teamA' is honored deterministically, so the AI does not
    // take an opening turn.
    expect(session.openingAiRound, isNull);
  });

  group('earned initiative (the opening turn is weighted by grade)', () {
    test('two evenly graded squads still flip a fair coin', () {
      for (final tier in TegTier.values) {
        expect(openingTurnChanceFor(tier, tier), 0.5,
            reason: '$tier against itself should be even');
      }
    });

    test('each tier of separation is worth five points, capped at 65/35', () {
      expect(openingTurnChanceFor(TegTier.c, TegTier.d), closeTo(0.55, 1e-9));
      expect(openingTurnChanceFor(TegTier.b, TegTier.d), closeTo(0.60, 1e-9));
      expect(openingTurnChanceFor(TegTier.a, TegTier.d), closeTo(0.65, 1e-9));
      // Beyond three tiers the advantage stops growing.
      expect(openingTurnChanceFor(TegTier.sss, TegTier.d), closeTo(0.65, 1e-9));
    });

    test('the underdog always keeps a real chance of moving first', () {
      for (final own in TegTier.values) {
        for (final other in TegTier.values) {
          final chance = openingTurnChanceFor(own, other);
          expect(chance, greaterThanOrEqualTo(0.35));
          expect(chance, lessThanOrEqualTo(0.65));
        }
      }
    });

    test('the two squads\' chances are complementary', () {
      for (final own in TegTier.values) {
        for (final other in TegTier.values) {
          expect(
            openingTurnChanceFor(own, other) +
                openingTurnChanceFor(other, own),
            closeTo(1.0, 1e-9),
          );
        }
      }
    });

    test('rolling it out lands near the stated odds', () {
      final random = Random(20260814);
      var wins = 0;
      const samples = 20000;
      for (var i = 0; i < samples; i++) {
        if (rollsOpeningTurn(TegTier.s, TegTier.c, random: random)) wins++;
      }
      // S over C is three tiers, so the ceiling: 65/35.
      expect(wins / samples, closeTo(0.65, 0.02));
    });
  });
}

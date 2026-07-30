import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/draft.dart';
import 'package:isekai_strategem/src/game/loadout_selection.dart';
import 'package:isekai_strategem/src/game/play_session.dart';
import 'package:isekai_strategem/src/game/team_efficiency.dart';

/// A5: the Team Efficiency Grade scoring model and its use as opening-turn
/// (cross-team) Initiative.
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
      'mending_light', // heal
      'vital_surge', // buff
      'rally_cry', // buff
      'war_chant', // self buff
    ]);
    final mismatched = gradeOf('yuki_amaral', [
      'twin_fang_strike',
      'piercing_thrust',
      'longshot',
      'marksmans_volley',
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
      'marksmans_volley',
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
}

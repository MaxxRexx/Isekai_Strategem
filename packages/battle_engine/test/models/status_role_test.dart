import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

/// A playtest reported the status badges as too small to read. The
/// measurement said size was not the problem: all 62 effects drew one shared
/// icon in one shared colour, so the badge could only be counted, never read,
/// and the two 8-pixel numbers were the only differentiated pixels on it.
///
/// This is the fix's foundation. Every effect answers two questions off its
/// own declared fields: what kind of thing it does, and whose side it is on.
/// Nothing is hand-listed, so an effect written tomorrow classifies itself,
/// and one re-tuned in wave 4 re-classifies itself.
void main() {
  final catalog = StatusEffectCatalog.defaultCatalog;

  Map<StatusRole, List<String>> byRole() {
    final m = <StatusRole, List<String>>{};
    for (final d in catalog.all) {
      m.putIfAbsent(d.role, () => []).add(d.id);
    }
    return m;
  }

  group('the catalogue is narrower than 62', () {
    test('every effect classifies, and every role earns its glyph', () {
      final roles = byRole();
      expect(roles.values.expand((e) => e), hasLength(62));
      for (final role in StatusRole.values) {
        expect(roles[role], isNotNull,
            reason: 'nothing is ${role.name}, so its glyph would never be '
                'drawn and should not be in the set');
        expect(roles[role], isNotEmpty, reason: role.name);
      }
    });

    test('the sixteen roles are the ones the icon set draws', () {
      // Pinned so a re-tune that moves an effect between roles is visible in
      // the diff rather than silently changing what a badge looks like.
      final roles = byRole();
      expect(roles[StatusRole.actionDenied], [
        'stunned',
        'frozen',
        'silenced',
        'petrified',
        'genjutsu_trapped',
      ]);
      expect(roles[StatusRole.damageOverTime], [
        'bleeding',
        'electrocuted',
        'scorched',
        'necrotic_wound',
      ]);
      expect(roles[StatusRole.healOverTime], ['regenerating', 'radiant_blessing']);
      expect(roles[StatusRole.trionDrain], ['sapped']);
      expect(roles[StatusRole.paysLess], ['overcharged']);
      expect(roles[StatusRole.paysMore], ['choked']);
      expect(roles[StatusRole.takesLess], ['guarded', 'untargetable']);
      expect(roles[StatusRole.takesMore], ['exposed', 'marked']);
      expect(roles[StatusRole.dealsMore], ['empowered', 'vow_of_the_duel']);
      expect(roles[StatusRole.dealsLess], ['weakened']);
      // Sealed left this group when it stopped zeroing Trion Affinity and
      // FAT Chance and started sealing an ability type, which is an option
      // closed off rather than a number taken to zero.
      expect(roles[StatusRole.statZeroed],
          ['shattered_guard', 'overwhelmed']);
      expect(roles[StatusRole.statUp], hasLength(8));
      expect(roles[StatusRole.statDown], hasLength(11));
      expect(roles[StatusRole.aimSpoiled], hasLength(7));
      expect(roles[StatusRole.optionDenied], hasLength(7));
    });

    test('only what nothing can read falls through to special', () {
      expect(byRole()[StatusRole.special], [
        // Wet and Sickened change a damage-type relationship, which is its
        // own thing and not one of the sixteen.
        'wet',
        'sickened',
        // Punishes repeating an ability.
        'interdict',
        // Shares what happens to you with a bound enemy.
        'karmic_bind',
        // The two that declare no fields at all, which item 13b left with
        // written sentences. The rule cannot see them, and says so.
        'called_shot_stat_zero',
        'minds_eye_reveal',
      ]);
    });
  });

  group('the role is the thing that changes the turn', () {
    test('losing the turn outright beats anything else on the same effect', () {
      // Petrified also multiplies incoming damage and zeroes Team Spirit.
      expect(catalog['petrified'].role, StatusRole.actionDenied);
    });

    test('losing the choice of target beats hitting harder', () {
      // Enraged buys outgoing damage and takes the aiming away. The
      // catalogue's own note calls the aiming the cost, so that is the role.
      expect(catalog['enraged'].role, StatusRole.aimSpoiled);
    });

    test('a stat taken to zero is not a stat stepped down', () {
      expect(catalog['shattered_guard'].role, StatusRole.statZeroed);
      expect(catalog['acid'].role, StatusRole.statDown);
    });

    test('being untargetable reads as the strongest form of taking less', () {
      expect(catalog['untargetable'].role, StatusRole.takesLess);
    });

    test('what an ability costs is its own thing, split by direction', () {
      // Added after the first pass, where both fell through to `special` and
      // drew the "unusual, tap it" glyph on an effect the rule can read
      // perfectly well. Split rather than one shared Trion-cost glyph, for the
      // same reason takesLess and takesMore are split: the colour already says
      // which way, and the glyph saying it too is the point of encoding it
      // twice. Named for what the holder does about it, like the rest of the
      // enum, and in the same words the description uses ("You pay 50% less
      // Trion").
      expect(catalog['overcharged'].role, StatusRole.paysLess);
      expect(catalog['overcharged'].valence, StatusValence.helpful);
      expect(catalog['choked'].role, StatusRole.paysMore);
      expect(catalog['choked'].valence, StatusValence.harmful);
      expect(catalog['sapped'].role, StatusRole.trionDrain,
          reason: 'losing Trion outright is not the same as paying more');
    });

    test('a roll that got worse reads with the stats that got worse', () {
      // Poisoned has no stat step at all, only disadvantage, and it belongs
      // beside Acid rather than in a glyph of its own.
      expect(catalog['poisoned'].role, StatusRole.statDown);
      expect(catalog['focused'].role, StatusRole.statUp);
    });
  });

  group('valence is counted, not looked up', () {
    test('an effect that only helps is helpful', () {
      expect(catalog['guarded'].valence, StatusValence.helpful);
      expect(catalog['regenerating'].valence, StatusValence.helpful);
      expect(catalog['inspired'].valence, StatusValence.helpful);
    });

    test('an effect that only hurts is harmful', () {
      expect(catalog['bleeding'].valence, StatusValence.harmful);
      expect(catalog['stunned'].valence, StatusValence.harmful);
      expect(catalog['shattered_guard'].valence, StatusValence.harmful);
    });

    test('a trade is neutral, which is the answer rather than a shrug', () {
      // Each of these buys something real and charges something real for it.
      // Painting them green or red would be a claim the effect cannot back.
      expect(catalog['enraged'].valence, StatusValence.neutral,
          reason: 'damage and Psychic immunity, at the cost of aiming');
      expect(catalog['vow_of_the_duel'].valence, StatusValence.neutral,
          reason: 'damage, at the cost of being unhealable');
      expect(catalog['petrified'].valence, StatusValence.neutral,
          reason: 'no turn, but much harder to hurt');
      expect(catalog['wet'].valence, StatusValence.neutral,
          reason: 'Fire-immune and Lightning-vulnerable at once');
    });

    test('an effect the rule cannot read is neutral rather than guessed at',
        () {
      expect(catalog['called_shot_stat_zero'].valence, StatusValence.neutral);
      expect(catalog['minds_eye_reveal'].valence, StatusValence.neutral);
    });

    test('the split is what the badge colours will be', () {
      final counts = <StatusValence, int>{};
      for (final d in catalog.all) {
        counts[d.valence] = (counts[d.valence] ?? 0) + 1;
      }
      expect(counts[StatusValence.helpful], 14);
      expect(counts[StatusValence.harmful], 42);
      expect(counts[StatusValence.neutral], 6);
    });
  });

  group('the classification survives a re-tune', () {
    test('flipping a magnitude flips the answer, with nothing to edit here',
        () {
      // The point of deriving rather than listing. A hostile version of
      // Guarded is a different role and a different colour, and neither this
      // file nor the badge needs to know it exists.
      const helping = StatusEffectDefinition(
        id: 'test_ward',
        name: 'Test Ward',
        allDamageTakenMultiplier: 0.75,
      );
      const hurting = StatusEffectDefinition(
        id: 'test_frailty',
        name: 'Test Frailty',
        allDamageTakenMultiplier: 1.25,
      );

      expect(helping.role, StatusRole.takesLess);
      expect(helping.valence, StatusValence.helpful);
      expect(hurting.role, StatusRole.takesMore);
      expect(hurting.valence, StatusValence.harmful);
    });

    test('an effect with no fields at all does not throw', () {
      const blank = StatusEffectDefinition(id: 'test_blank', name: 'Blank');
      expect(blank.role, StatusRole.special);
      expect(blank.valence, StatusValence.neutral);
    });
  });
}

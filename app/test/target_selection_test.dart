import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/draft.dart';
import 'package:isekai_strategem/src/game/target_selection.dart';

/// Verifies the battle screen's portrait-based target picker behaves
/// correctly for every Active Trigger in the catalog, so no ability type
/// slips through the self / area / manual branching (see
/// [autoSelectedTargets], [awaitingManualTargets] and [lineTargets]).
///
/// **Found in a playtest.** An area ability used to auto-highlight every
/// target it could reach, across every line. The rules do not work that way:
/// an area ability catches one line, and the engine quietly narrowed the
/// list to whichever line the first target stood on. War Chant lit up three
/// characters on three lines, the queue listed all three, and it landed on
/// one of them. The picker aims at a line now.
void main() {
  const caster = 'caster';
  // Stand-in legal-target pools, mirroring how PlaySession.legalActionsFor
  // builds them: three living opponents / three living allies.
  const opponents = ['opp_a', 'opp_b', 'opp_c'];
  const allies = [caster, 'ally_b', 'ally_c'];

  List<String> legalPoolFor(ActiveTrigger t) => switch (t.targetAffiliation) {
    TargetAffiliation.self => const [caster],
    TargetAffiliation.opponent => opponents,
    TargetAffiliation.ally => allies,
  };

  final actives = triggerCatalog.activeTriggers.toList();

  test('catalog actually has the ability types under test', () {
    expect(actives, isNotEmpty);
    // Guard against a regression where one whole branch loses coverage.
    expect(
      actives.any((t) => t.targetAffiliation == TargetAffiliation.self),
      isTrue,
    );
    expect(
      actives.any((t) => t.attackSubtype == AttackSubtype.aoe),
      isTrue,
    );
    expect(
      actives.any((t) => t.attackSubtype == AttackSubtype.burst),
      isTrue,
    );
    expect(
      actives.any((t) => t.targetAffiliation == TargetAffiliation.ally),
      isTrue,
    );
  });

  for (final t in actives) {
    group('${t.id} (${t.attackSubtype.name}/${t.targetAffiliation.name})', () {
      final legal = legalPoolFor(t);
      // Non-blinded target budget, as PlaySession would compute it.
      final maxTargets =
          t.targetAffiliation == TargetAffiliation.self ? 1 : t.targetCount;

      test('target budget is at least one', () {
        expect(maxTargets, greaterThanOrEqualTo(1));
      });

      test('awaiting-manual flag matches the ability shape', () {
        // Everything except a self-cast is a choice, area abilities
        // included: the choice there is which line.
        expect(awaitingManualTargets(t),
            t.targetAffiliation != TargetAffiliation.self);
      });

      test('auto-selection is a valid subset within budget', () {
        final auto = autoSelectedTargets(t, caster, legal, maxTargets);
        expect(auto.length, lessThanOrEqualTo(maxTargets));
        if (t.targetAffiliation == TargetAffiliation.self) {
          expect(auto, [caster]);
        } else {
          // Nothing is pre-selected, so the highlight can never promise a
          // target the resolution will drop.
          expect(auto, isEmpty);
        }
      });
    });
  }

  group('an area ability aims at a line', () {
    // Two on the front line, one at the back: the shape that exposed this.
    const lines = {
      'opp_a': BattlePosition.front,
      'opp_b': BattlePosition.front,
      'opp_c': BattlePosition.back,
    };
    BattlePosition positionOf(String id) => lines[id]!;

    test('tapping one catches everyone on their line', () {
      final caught = lineTargets(
        tappedId: 'opp_a',
        legalTargetIds: opponents,
        positionOf: positionOf,
        maxTargets: 3,
      );
      expect(caught, ['opp_a', 'opp_b']);
    });

    test('and nobody on any other line', () {
      final caught = lineTargets(
        tappedId: 'opp_c',
        legalTargetIds: opponents,
        positionOf: positionOf,
        maxTargets: 3,
      );
      expect(caught, ['opp_c'],
          reason: 'the back line is one character, so that is what it hits');
    });

    test('it never promises more than the ability can affect', () {
      // A blinded ranged area attack has its budget cut below the number
      // standing there, and the highlight has to respect that.
      final caught = lineTargets(
        tappedId: 'opp_a',
        legalTargetIds: opponents,
        positionOf: positionOf,
        maxTargets: 1,
      );
      expect(caught, hasLength(1));
    });

    test('an unreachable character on the line is not caught', () {
      // legalTargetIds is already filtered for range and screening, so
      // anyone missing from it stays missing.
      final caught = lineTargets(
        tappedId: 'opp_a',
        legalTargetIds: const ['opp_a'],
        positionOf: positionOf,
        maxTargets: 3,
      );
      expect(caught, ['opp_a']);
    });
  });
}

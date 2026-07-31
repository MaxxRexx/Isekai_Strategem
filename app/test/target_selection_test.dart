import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/draft.dart';
import 'package:isekai_strategem/src/game/target_selection.dart';

/// Verifies the battle screen's portrait-based target picker behaves
/// correctly for every Active Trigger in the catalog, so no ability type
/// slips through the self / AoE / manual branching (see [autoSelectedTargets]
/// and [awaitingManualTargets]).
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
        final expected =
            t.targetAffiliation != TargetAffiliation.self &&
            t.attackSubtype != AttackSubtype.aoe;
        expect(awaitingManualTargets(t), expected);
      });

      test('auto-selection is a valid subset within budget', () {
        final auto = autoSelectedTargets(t, caster, legal, maxTargets);
        expect(auto.length, lessThanOrEqualTo(maxTargets));
        if (t.targetAffiliation == TargetAffiliation.self) {
          expect(auto, [caster]);
        } else if (t.attackSubtype == AttackSubtype.aoe) {
          // AoE pre-highlights everyone it can hit.
          expect(auto, everyElement(isIn(legal)));
          expect(auto.length, legal.length.clamp(0, maxTargets));
        } else {
          // Single / unique / burst: the player picks, nothing pre-selected.
          expect(auto, isEmpty);
        }
      });
    });
  }

  test('blinded ranged AoE never highlights more than it can hit', () {
    // Regression: a blinded ranged AoE has its target budget cut below the
    // enemy count, so the pre-highlight must clamp to the budget rather than
    // lighting up all three enemies.
    final rangedAoe = actives.firstWhere(
      (t) =>
          t.attackSubtype == AttackSubtype.aoe && t.rangeTag == RangeTag.ranged,
    );
    final auto = autoSelectedTargets(rangedAoe, caster, opponents, 2);
    expect(auto.length, 2);
    expect(auto, everyElement(isIn(opponents)));
  });
}

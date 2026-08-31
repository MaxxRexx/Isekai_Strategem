import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

/// Item #16: origin is an even, independent axis.
///
/// Typed Trion (#15) keys its tokens to origin, so the four origins have to be
/// roughly even. If one of them is thin, its tokens are dead weight for most
/// squads and that origin cannot anchor a build, which is the whole payoff the
/// mechanic is selling. Before the re-tag the split was physical 23, mental 21,
/// energy 11, afflict 6.
///
/// The second half matters just as much. Every psychic ability used to be
/// Mental origin and every Mental ability psychic, a perfect one-to-one, so for
/// those abilities origin carried nothing that ability type did not already
/// say. An axis that duplicates another is not a second axis.
void main() {
  final actives = TriggerCatalog.defaultCatalog.activeTriggers.toList();

  int countOfOrigin(OriginTag o) =>
      actives.where((t) => t.originTag == o).length;

  test('no origin is thin enough to be dead weight', () {
    final counts = {for (final o in OriginTag.values) o: countOfOrigin(o)};

    for (final entry in counts.entries) {
      expect(
        entry.value,
        inInclusiveRange(13, 18),
        reason: 'origin ${entry.key.name} sits at ${entry.value} of '
            '${actives.length}; the four are meant to be near even so each can '
            'anchor a build. Full spread: '
            '${counts.map((k, v) => MapEntry(k.name, v))}',
      );
    }
    expect(counts.values.reduce((a, b) => a + b), actives.length);
  });

  test('origin does not simply restate ability type', () {
    // The failure this guards is the old one: psychic and Mental being the
    // same set. Each needs a real spread across the other axis.
    for (final type in AbilityType.values) {
      final origins = actives
          .where((t) => t.abilityType == type)
          .map((t) => t.originTag)
          .toSet();
      expect(origins.length, greaterThanOrEqualTo(2),
          reason: '${type.name} abilities all share one origin, so origin '
              'tells you nothing ability type has not already said');
    }

    for (final origin in OriginTag.values) {
      final types = actives
          .where((t) => t.originTag == origin)
          .map((t) => t.abilityType)
          .toSet();
      expect(types.length, greaterThanOrEqualTo(2),
          reason: '${origin.name} abilities are all one ability type, which '
              'makes the two tags a single axis wearing two names');
    }
  });
}

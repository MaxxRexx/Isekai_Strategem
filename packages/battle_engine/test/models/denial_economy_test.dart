import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

/// Item #4, decision D5's non-token half: the denial statuses measured against
/// the economy they actually run in.
///
/// The half that drains *typed* Trion is wave 3's, and needs new content. What
/// is pinned here is the relationship these three have to the squad income and
/// the ability costs around them, because that relationship is the whole point
/// of them and it is invisible from any single number.
void main() {
  final magnitudes = const StatusEffectMagnitudes();
  final tiers = TrionTierConfig.defaults;
  final roster = CharacterRoster.defaultRoster;

  final averageCapacity = roster.all
          .map((c) => c.baseStats.trionCapacity)
          .reduce((a, b) => a + b) /
      roster.all.length;

  /// What one stack of Sapped takes from the victim, and hands the causer,
  /// each turn.
  double sappedPerTurn() =>
      averageCapacity * magnitudes.sappedDrainPercentOfTrionCapacity;

  group('Sapped is a sub-game, not a switch', () {
    test('one stack costs about one cheap action, not a turn of income', () {
      // The Close band is the cheap one after D4, averaging about 15 Trion.
      final closeAverage = TriggerCatalog.defaultCatalog.activeTriggers
              .where((t) => t.rangeTag == RangeTag.close)
              .map((t) => t.trionCost)
              .reduce((a, b) => a + b) /
          21;

      expect(sappedPerTurn(), lessThan(closeAverage * 1.2),
          reason: 'a stack should cost the victim about one cheap play');
      expect(sappedPerTurn(), greaterThan(closeAverage * 0.6),
          reason: 'and it should be worth building a kit around');
    });

    test('a full three stacks costs a turn, not the battle', () {
      // The old 25% took 27 a turn per stack against a measured squad income
      // of about 25, so three stacks took 81: more than three turns of income,
      // every turn, handed to the causer. The bound that matters is against
      // what a squad typically earns rather than its luckiest turn, which is
      // the Medium tier.
      const maxStacks = 3;
      expect(sappedPerTurn() * maxStacks,
          lessThanOrEqualTo(tiers.mediumAmount * 2.0),
          reason: 'a full stack should cost about a turn and a half of '
              'ordinary income, not several turns of it');
    });

    test('one stack does not take a whole medium income turn', () {
      expect(sappedPerTurn(), lessThan(tiers.mediumAmount.toDouble()));
    });
  });

  group('Choked and Overcharged read against the new cost spread', () {
    StatusEffectDefinition def(String id) =>
        StatusEffectCatalog.defaultCatalog[id];

    test('Choked doubles, Overcharged halves, and they stay each other\'s '
        'mirror', () {
      final choked = def('choked').trionCostMultiplier!;
      final overcharged = def('overcharged').trionCostMultiplier!;

      expect(choked, 2.0);
      expect(overcharged, 0.5);
      expect(choked * overcharged, 1.0,
          reason: 'one should undo the other exactly');
    });

    test('Choked prices a sniper out of their signature shot', () {
      // This is what D4 bought the denial sub-game for free: with every band
      // priced the same, a cost multiplier was worth the same against anyone.
      // Now it is worth most against the squad banking for a big shot.
      final priciest = TriggerCatalog.defaultCatalog.activeTriggers
          .map((t) => t.trionCost)
          .reduce((a, b) => a > b ? a : b);

      expect(priciest * def('choked').trionCostMultiplier!,
          greaterThan(TrionTierConfig.defaults.highAmount * 2),
          reason: 'choking the big play should take it off the table, not '
              'just tax it');
    });
  });

  test('all three are still unreachable, which is wave 3 content', () {
    // Recorded rather than asserted-away: nothing applies these, so none of
    // the numbers above can be felt in a played battle yet. When the content
    // pass homes them, this test is what says the economy was ready.
    final applied = <String>{
      for (final t in TriggerCatalog.defaultCatalog.activeTriggers)
        for (final a in t.inflictedStatusEffects) a.statusEffectId,
      for (final bt in BlackTriggerCatalog.defaultCatalog.all)
        for (final t in bt.activeAbilities)
          for (final a in t.inflictedStatusEffects) a.statusEffectId,
    };

    expect(applied.intersection({'sapped', 'choked', 'overcharged'}), isEmpty,
        reason: 'if this fails, one of them found a home: good, and the '
            'numbers above are now live rather than theoretical');
  });
}

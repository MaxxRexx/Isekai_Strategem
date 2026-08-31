import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

/// Item #4, decision D4: range is an input to the cost model, so each band
/// has an economic identity and not just a different window.
///
/// Close is cheap and fast but demands you stand in the danger. Long is safe
/// and you pay for it twice over, in Trion at the moment of use and again in
/// what it eats of a Loadout's Trion Capacity. Mid is flexible and pays in
/// tempo.
///
/// These are the band-level shapes, not per-ability values, so re-pricing one
/// ability under SPTV does not fail them; moving a whole band does.
void main() {
  final actives =
      TriggerCatalog.defaultCatalog.all.whereType<ActiveTrigger>().toList();

  List<ActiveTrigger> band(RangeTag tag) =>
      actives.where((t) => t.rangeTag == tag).toList();

  double mean(Iterable<num> xs) =>
      xs.fold<num>(0, (a, b) => a + b) / xs.length;

  int maxOf(Iterable<int> xs) => xs.reduce((a, b) => a > b ? a : b);

  final close = band(RangeTag.close);
  final mid = band(RangeTag.mid);
  final long = band(RangeTag.long);

  test('every band has enough abilities to build around', () {
    for (final ts in [close, mid, long]) {
      expect(ts.length, greaterThanOrEqualTo(15));
    }
  });

  group('Long pays for its safety, twice over', () {
    test('it costs the most Trion to fire, on average', () {
      expect(mean(long.map((t) => t.trionCost)),
          greaterThan(mean(close.map((t) => t.trionCost))));
      expect(mean(long.map((t) => t.trionCost)),
          greaterThan(mean(mid.map((t) => t.trionCost))));
    });

    test('and the most Trion Capacity to carry', () {
      expect(mean(long.map((t) => t.equipCost)),
          greaterThan(mean(close.map((t) => t.equipCost))));
      expect(mean(long.map((t) => t.equipCost)),
          greaterThan(mean(mid.map((t) => t.equipCost))));
    });

    test('its ceiling reaches three times the Close average, and stops there',
        () {
      final closeTrion = mean(close.map((t) => t.trionCost));
      final closeEquip = mean(close.map((t) => t.equipCost));

      expect(maxOf(long.map((t) => t.trionCost)),
          greaterThan(closeTrion * 2.5),
          reason: 'the priciest shot should be a play you bank for');
      expect(maxOf(long.map((t) => t.trionCost)),
          lessThanOrEqualTo((closeTrion * 3).ceil()));
      expect(maxOf(long.map((t) => t.equipCost)),
          lessThanOrEqualTo((closeEquip * 3).ceil()));
    });
  });

  group('Mid pays in tempo', () {
    test('it carries the highest cooldowns, up to the specified 4', () {
      expect(mean(mid.map((t) => t.cooldownTurns)),
          greaterThan(mean(close.map((t) => t.cooldownTurns))));
      expect(mean(mid.map((t) => t.cooldownTurns)),
          greaterThan(mean(long.map((t) => t.cooldownTurns))));
      expect(maxOf(mid.map((t) => t.cooldownTurns)), 4);
    });
  });

  group('Close is cheap and fast', () {
    test('it is the cheapest band to fire and to carry', () {
      expect(mean(close.map((t) => t.trionCost)),
          lessThan(mean(long.map((t) => t.trionCost))));
      expect(mean(close.map((t) => t.equipCost)),
          lessThan(mean(mid.map((t) => t.equipCost))));
    });

    test('nothing in it sits out more than one turn', () {
      expect(close.map((t) => t.cooldownTurns), everyElement(lessThanOrEqualTo(2)));
    });
  });

  test('a Loadout of one band is still buildable, if not a maximal one', () {
    // The Loadout rule needs exactly 4 active abilities inside the
    // character's Trion Capacity, and the smallest Capacity on the roster is
    // 100. A squad should be able to specialise into any band; what Long
    // gives up for its reach is the *pick* of that band, not access to it.
    final smallestCapacity = CharacterRoster.defaultRoster.all
        .map((c) => c.baseStats.trionCapacity)
        .reduce((a, b) => a < b ? a : b);

    for (final ts in [close, mid, long]) {
      final cheapestFour = (ts.map((t) => t.equipCost).toList()..sort())
          .take(4)
          .fold(0, (a, b) => a + b);
      expect(cheapestFour, lessThanOrEqualTo(smallestCapacity),
          reason: '${ts.first.rangeTag.name} cannot fill a Loadout at all');
    }
  });
}

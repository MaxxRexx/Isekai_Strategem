// Derives each active ability's Trion Type requirement (item #15) and prints
// the table for review.
//
//   dart run tool/derive_type_costs.dart
//
// The rule, from the owner's decisions #2A and #3A:
//   * every ability asks for one to four, total;
//   * at least one slot is always the ability's own origin;
//   * the total scales with what the ability is worth, so fillers cost one and
//     the biggest plays cost four;
//   * the slots beyond the first are the ability's own origin again when it
//     leans hard on it, otherwise Random, which is what keeps a squad running
//     one origin able to act.
import 'package:battle_engine/battle_engine.dart';

/// What the ability is worth, in the same damage-equivalent SPTV prices in.
/// Payload alone, before cost: an ability's Raw Trion price is a separate
/// question and this must not simply restate it.
double payloadOf(ActiveTrigger t) {
  final damage = t.damage == null
      ? 0.0
      : t.damage!.average *
          (t.abilitySubtype == AbilitySubtype.burst ? t.hitsPerUse : 1) *
          t.targetCount;
  final heal = t.healAmount == null ? 0.0 : t.healAmount!.average;
  // A rider is worth something even when the ability deals nothing, which is
  // the only reason a pure control ability is not priced at zero.
  final riders = t.inflictedStatusEffects.length * 12.0;
  final reactive = t.armsReactive == null ? 0.0 : 15.0;
  final unique = t.uniqueBehavior == null ? 0.0 : 18.0;
  return damage + heal + riders + reactive + unique;
}

/// The total number of slots, one to four, by where the ability ranks against
/// its own origin's peers.
///
/// By rank rather than by raw value, so every origin gets the same spread:
/// roughly three fifths of an origin at one slot, a quarter at two, and its
/// two or three biggest plays at three and four.
int totalSlots(double payload, List<double> peerPayloads) {
  final sorted = [...peerPayloads]..sort();
  final rank = sorted.indexWhere((p) => p >= payload);
  final position = sorted.length <= 1 ? 0.0 : rank / (sorted.length - 1);
  if (position <= 0.62) return 1;
  if (position <= 0.86) return 2;
  if (position <= 0.94) return 3;
  return 4;
}

TrionTypeCost costFor(ActiveTrigger t, int slots) {
  final own = TrionType.of(t.originTag);
  if (slots == 1) return TrionTypeCost.one(own);
  // A second of its own kind when the ability is squarely that origin's
  // business: a rider whose whole point is the origin's effect, or a unique
  // behaviour. Otherwise the extra slots are Random, so a mixed squad can
  // still field it.
  final leansOwn = t.uniqueBehavior != null || t.inflictedStatusEffects.length >= 2;
  final ownSlots = leansOwn ? 2 : 1;
  return TrionTypeCost({own: ownSlots}, random: slots - ownSlots);
}

void main() {
  final actives =
      TriggerCatalog.defaultCatalog.activeTriggers.toList();

  // Ranked against its own origin's peers, not the whole catalogue.
  //
  // Ranking across all 61 made Physical average 2.00 slots and Mental 1.12,
  // because the payload proxy leans on damage and the damage-dealers are
  // mostly Physical. That would have made Mental the cheapest origin to run
  // twice over, which is not a balance decision anybody took. The Raw Trion
  // cost already prices how strong an ability is; the types answer which kind
  // you drew, so each origin gets the same spread of requirements.
  final rows = <(ActiveTrigger, TrionTypeCost)>[];
  for (final origin in OriginTag.values) {
    final peers = actives.where((t) => t.originTag == origin).toList();
    final peerPayloads = [for (final t in peers) payloadOf(t)];
    for (final t in peers) {
      rows.add((t, costFor(t, totalSlots(payloadOf(t), peerPayloads))));
    }
  }
  rows.sort((a, b) {
    final byTotal = a.$2.total.compareTo(b.$2.total);
    return byTotal != 0 ? byTotal : a.$1.name.compareTo(b.$1.name);
  });

  print('id|name|origin|rawTrion|slots|cost');
  for (final (t, cost) in rows) {
    print('${t.id}|${t.name}|${t.originTag.name}|${t.trionCost}|'
        '${cost.total}|$cost');
  }

  final total = rows.fold<int>(0, (a, r) => a + r.$2.total);
  print('');
  print('MEAN ${(total / rows.length).toStringAsFixed(2)} over ${rows.length}');
  for (var n = 1; n <= 4; n++) {
    final c = rows.where((r) => r.$2.total == n).length;
    print('  $n slot: $c');
  }
}

// Derives each active ability's Trion Type requirement (item #15) and prints
// the table for review.
//
//   dart run tool/derive_type_costs.dart
//
// The shapes come from Naruto-Arena, which our typed Trion is modelled on.
// Its skills cost, in rising order of how demanding they are to hold:
//
//   * one of a kind          Sasuke's Sharingan: 1 Bloodline
//   * one kind plus Random   Rasengan: 1 Ninjutsu + 1 Random
//   * two of one kind        a balance patch: "2 Ninjutsu instead of
//                            1 Taijutsu and 1 Ninjutsu"
//   * two different kinds    Demonic Ice Mirrors: 1 Ninjutsu + 1 Bloodline
//   * Random only            a balance patch: "2 Random"
//
// Two *different* kinds is the shape that carries the most information, and
// the one an earlier pass of this tool could not produce at all. What decides
// it there is what the skill actually is: Demonic Ice Mirrors is a bloodline
// technique performed as ninjutsu, so it costs one of each.
//
// So the rule here reads the ability rather than only its origin:
//
//   * the first slot is always the ability's own origin (decision 2A);
//   * further slots are named by what the ability *does* - the damage it
//     deals, the statuses it inflicts, and how it is delivered - each of
//     which points at an origin of its own;
//   * where that points at the same origin again, the cost doubles up on it;
//     where it points at a different one, the cost names both;
//   * where the ability has nothing distinctive left to say, the slot is
//     Random, which is what keeps a squad running one origin able to act.
import 'package:battle_engine/battle_engine.dart';

/// The origin a damage type speaks for. Force and impact are Physical; the
/// elements and raw energy are Energy; anything that corrodes or festers is
/// Afflict; anything that works on the mind is Mental.
OriginTag? originOfDamage(DamageType? d) => switch (d) {
      null => null,
      DamageType.bludgeoning ||
      DamageType.piercing ||
      DamageType.slashing =>
        OriginTag.physical,
      DamageType.cold ||
      DamageType.fire ||
      DamageType.lightning ||
      DamageType.thunder ||
      DamageType.force ||
      DamageType.radiant =>
        OriginTag.energy,
      DamageType.acid || DamageType.poison || DamageType.necrotic =>
        OriginTag.afflict,
      DamageType.psychic => OriginTag.mental,
    };

/// The origin a status speaks for, by what it does to the holder rather than
/// by its name: shutting a mind down is Mental work, rotting someone is
/// Afflict work, and moving Trion around is Energy work.
OriginTag? originOfStatus(String id) {
  final def = StatusEffectCatalog.defaultCatalog[id];
  return switch (def.role) {
    StatusRole.actionDenied || StatusRole.optionDenied => OriginTag.mental,
    StatusRole.damageOverTime => OriginTag.afflict,
    StatusRole.trionDrain ||
    StatusRole.paysLess ||
    StatusRole.paysMore =>
      OriginTag.energy,
    StatusRole.healOverTime || StatusRole.takesLess => OriginTag.energy,
    _ => null,
  };
}

/// The origin the delivery speaks for: a psychic ability reaches the mind, a
/// melee one reaches with the body.
OriginTag? originOfDelivery(AbilityType type) => switch (type) {
      AbilityType.melee => OriginTag.physical,
      AbilityType.psychic => OriginTag.mental,
      AbilityType.ranged => null,
    };

/// Everything the ability says about itself, after its own origin, most
/// telling first. Nulls are the ability having nothing further to say, and
/// become Random slots.
List<OriginTag?> secondaryVoices(ActiveTrigger t) => [
      originOfDamage(t.damageType),
      for (final s in t.inflictedStatusEffects) originOfStatus(s.statusEffectId),
      originOfDelivery(t.abilityType),
    ];

/// What the ability is worth, in the same damage-equivalent SPTV prices in.
double payloadOf(ActiveTrigger t) {
  final damage = t.damage == null
      ? 0.0
      : t.damage!.average *
          (t.abilitySubtype == AbilitySubtype.burst ? t.hitsPerUse : 1) *
          t.targetCount;
  final heal = t.healAmount == null ? 0.0 : t.healAmount!.average;
  final riders = t.inflictedStatusEffects.length * 12.0;
  final reactive = t.armsReactive == null ? 0.0 : 15.0;
  final unique = t.uniqueBehavior == null ? 0.0 : 18.0;
  return damage + heal + riders + reactive + unique;
}

/// The total number of slots, one to four, by where the ability ranks against
/// its own origin's peers, so every origin gets the same spread.
int totalSlots(double payload, List<double> peerPayloads) {
  final sorted = [...peerPayloads]..sort();
  final rank = sorted.indexWhere((p) => p >= payload);
  final position = sorted.length <= 1 ? 0.0 : rank / (sorted.length - 1);
  if (position <= double.parse(const String.fromEnvironment('b1', defaultValue: '0.62'))) return 1;
  if (position <= double.parse(const String.fromEnvironment('b2', defaultValue: '0.86'))) return 2;
  if (position <= double.parse(const String.fromEnvironment('b3', defaultValue: '0.94'))) return 3;
  return 4;
}

TrionTypeCost costFor(ActiveTrigger t, int slots) {
  final typed = <TrionType, int>{TrionType.of(t.originTag): 1};
  var random = 0;
  final voices = secondaryVoices(t);
  var next = 0;
  for (var filled = 1; filled < slots; filled++) {
    OriginTag? voice;
    while (next < voices.length && voice == null) {
      voice = voices[next++];
    }
    if (voice == null) {
      random++;
    } else {
      final type = TrionType.of(voice);
      typed[type] = (typed[type] ?? 0) + 1;
    }
  }
  return TrionTypeCost(typed, random: random);
}

void main() {
  final actives = TriggerCatalog.defaultCatalog.activeTriggers.toList();

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
    print('  $n slot: ${rows.where((r) => r.$2.total == n).length}');
  }
  final multi = rows.where((r) => r.$2.typed.length >= 2).length;
  final pureRandom = rows.where((r) => r.$2.random > 0).length;
  print('  naming two or more different kinds: $multi');
  print('  carrying at least one Random: $pureRandom');
}

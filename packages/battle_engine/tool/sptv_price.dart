// Prices the whole catalogue with item #3's rule: every status in
// damage-equivalent Status Points, and every ability in Trigger Value with
// the SP term folded in.
//
//   dart run tool/sptv_price.dart [--band 2.0,3.0]
//
// This is the check that the rule is a rule. Nothing here is hand-written:
// every number falls out of a status's own declarative fields and the
// measured baselines in `SptvBaselines`, so re-tuning a magnitude re-prices
// it, and re-measuring the baselines (tool/sptv_baseline.dart) re-prices
// everything. Wave 4 runs the pass; this is what it will run.
import 'package:battle_engine/battle_engine.dart';

String pad(String s, int n) => s.padRight(n);
String padLeft(String s, int n) => s.padLeft(n);
String f(num v, [int places = 2]) => v.toStringAsFixed(places);

void main(List<String> args) {
  var bandLow = 2.0;
  var bandHigh = 3.0;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--band') {
      final parts = args[i + 1].split(',');
      if (parts.length == 2) {
        bandLow = double.parse(parts[0]);
        bandHigh = double.parse(parts[1]);
      }
    }
  }

  final statuses = StatusEffectCatalog.defaultCatalog;
  final triggers = TriggerCatalog.defaultCatalog;
  const b = SptvBaselines.defaults;

  print('== SPTV pricing ==');
  print('');
  print('Baselines: an action buys ${f(b.damagePerDamagingUse, 1)} damage, a '
      'character deals and takes ${f(b.damagePerCharacterTurn, 1)} a turn,');
  print('a Trion buys ${f(b.damagePerTrion)} damage, a rider that hits wins '
      'its contest ${f(b.riderLandsGivenHit * 100, 0)}% of the time.');
  print('Derived: one point of an opposed stat is '
      '${f(Sptv.damagePerOpposedStatPoint(b))} damage a turn, '
      'one of Armor ${f(Sptv.damagePerArmorPoint(b))}, '
      'advantage ${f(Sptv.damagePerAdvantage(b))} '
      '(${f(Sptv.advantageInStatPoints, 1)} points of modifier).');
  print('');

  // ---- statuses -----------------------------------------------------------

  final prices = <StatusPrice>[];
  for (final def in statuses.all) {
    prices.add(Sptv.priceStatus(def, baselines: b));
  }
  prices.sort((x, y) => y.total.compareTo(x.total));

  print('== Status Points, all ${prices.length} effects ==');
  print('  ${pad('status', 26)} ${padLeft('SP', 7)}  '
      '${padLeft('per turn', 8)}  ${padLeft('turns', 5)}  fields');
  for (final p in prices) {
    final fields = p.byField.keys.join(', ');
    final flag = p.isComplete ? '' : '  [unpriced: ${p.unpriced.join(', ')}]';
    print('  ${pad(p.statusId, 26)} ${padLeft(f(p.total, 1), 7)}  '
        '${padLeft(f(p.perTurn, 1), 8)}  ${padLeft(f(p.turns, 0), 5)}  '
        '$fields$flag');
  }
  print('');

  final complete = prices.where((p) => p.isComplete).toList();
  final incomplete = prices.where((p) => !p.isComplete).toList();
  final zero = prices.where((p) => p.total == 0).toList();
  print('Priced in full: ${complete.length} of ${prices.length}. '
      'Carrying an unpriced field: ${incomplete.length}. '
      'Priced at zero: ${zero.length}.');
  if (zero.isNotEmpty) {
    print('At zero (nothing the rule can read yet): '
        '${zero.map((p) => p.statusId).join(', ')}');
  }
  print('');

  // ---- what nothing can apply --------------------------------------------

  final applied = <String>{};
  for (final t in triggers.activeTriggers) {
    for (final a in t.inflictedStatusEffects) {
      applied.add(a.statusEffectId);
    }
  }
  for (final bt in BlackTriggerCatalog.defaultCatalog.all) {
    for (final t in bt.activeAbilities) {
      for (final a in t.inflictedStatusEffects) {
        applied.add(a.statusEffectId);
      }
    }
  }
  // A reaction is a way in too: a status the table turns another status into
  // is reachable without any ability naming it.
  final byReaction = <String>{};
  for (final def in statuses.all) {
    for (final r in def.reactions) {
      if (r.becomes != null) byReaction.add(r.becomes!);
    }
  }

  final unreachable = [
    for (final def in statuses.all)
      if (!applied.contains(def.id) && !byReaction.contains(def.id)) def.id
  ]..sort();
  final onlyByReaction = [
    for (final id in byReaction)
      if (!applied.contains(id)) id
  ]..sort();

  print('== Reachability ==');
  print('Applied by an ability: ${applied.length}');
  print('Reachable only through the reaction table: '
      '${onlyByReaction.length}${onlyByReaction.isEmpty ? '' : ' '
          '(${onlyByReaction.join(', ')})'}');
  print('Nothing can apply: ${unreachable.length}');
  if (unreachable.isNotEmpty) {
    for (final id in unreachable) {
      print('  $id');
    }
  }
  print('');

  // ---- abilities ----------------------------------------------------------

  final values = <(String, double, double, double)>[];
  // An ability whose whole effect is a unique behaviour or a reactive counter
  // has nothing the rule can read: no damage, no heal, no inflicted status.
  // Pricing those at zero and averaging them in would say the catalogue is
  // half broken, when what is true is that the rule cannot see them yet.
  final invisible = <String>[];

  for (final t in triggers.activeTriggers) {
    final tv = Sptv.triggerValue(t, baselines: b);
    if (tv == double.infinity) continue;
    var sp = 0.0;
    for (final a in t.inflictedStatusEffects) {
      if (!statuses.contains(a.statusEffectId)) continue;
      sp += Sptv.priceStatus(
        statuses[a.statusEffectId],
        baselines: b,
        durationTurns: a.durationTurnsOverride,
        targets: t.targetCount,
      ).total;
    }
    final payload = (t.damage?.average ?? 0) * t.targetCount * t.hitsPerUse +
        (t.healAmount?.average ?? 0) * t.targetCount;
    if (payload == 0 && sp == 0) {
      final why = t.uniqueBehavior != null
          ? 'unique behaviour'
          : t.armsReactive != null
              ? 'reactive counter'
              : 'nothing the rule can read';
      invisible.add('${pad(t.id, 24)} $why');
      continue;
    }
    values.add((t.id, payload, sp, tv));
  }
  values.sort((x, y) => x.$4.compareTo(y.$4));

  print('== Trigger Value, band ${f(bandLow, 1)} to ${f(bandHigh, 1)} ==');
  print('  ${pad('trigger', 24)} ${padLeft('payload', 8)} '
      '${padLeft('SP', 7)} ${padLeft('TV', 6)}');
  for (final (id, payload, sp, tv) in values) {
    final mark = tv < bandLow
        ? ' <- under'
        : tv > bandHigh
            ? ' <- over'
            : '';
    print('  ${pad(id, 24)} ${padLeft(f(payload, 1), 8)} '
        '${padLeft(f(sp, 1), 7)} ${padLeft(f(tv), 6)}$mark');
  }
  print('');

  final tvs = values.map((v) => v.$4).toList()..sort();
  final inBand = tvs.where((v) => v >= bandLow && v <= bandHigh).length;
  print('TV: min ${f(tvs.first)}, median ${f(tvs[tvs.length ~/ 2])}, '
      'max ${f(tvs.last)}');
  print('In band: $inBand of ${tvs.length} '
      '(${f(100 * inBand / tvs.length, 0)}%)');

  final riderCarrying = values.where((v) => v.$3 > 0).toList();
  if (riderCarrying.isNotEmpty) {
    final withoutSp = riderCarrying
        .map((v) => v.$2 == 0 ? 0.0 : v.$4 * v.$2 / (v.$2 + v.$3 * b.riderLandsGivenHit))
        .toList();
    final liftedIn = riderCarrying
        .where((v) => v.$4 >= bandLow)
        .length;
    final wouldBeIn = withoutSp.where((v) => v >= bandLow).length;
    print('Abilities carrying a status: ${riderCarrying.length}. '
        'In band with the SP term: $liftedIn. Without it: $wouldBeIn.');
  }
  print('');

  if (invisible.isNotEmpty) {
    print('== ${invisible.length} abilities the rule cannot see ==');
    print('Their whole effect is a unique behaviour or a reactive counter, '
        'neither of which has a conversion yet.');
    for (final line in invisible) {
      print('  $line');
    }
  }
}

// Phase I5 (optional): a DESIGN-TIME proposer for Layer-2 signature combos.
// It never runs at runtime - it reads the trigger catalog and prints candidate
// `ComboDefinition`s (using the identity primitives) for a human to review,
// edit, and paste into `ComboCatalog.signature`. The engine only ever matches
// combos a human approved; this tool just does the busywork of surfacing
// thematically-plausible pairings from the content data.
//
// Run from the package root:
//   dart run tool/propose_signature_combos.dart
//
// Heuristics (all tunable): a "setup" that chills/freezes or deals Cold pairs
// with a Fire "payoff" (elemental detonation); an affliction-applier pairs with
// an Energy payoff (affliction exploit); a control-applier pairs with a heavy
// single-target hit (control finisher). Output is capped per category so it
// stays reviewable.

import 'package:battle_engine/battle_engine.dart';

const int _maxPerCategory = 6;

bool _appliesAny(ActiveTrigger t, Set<String> ids) =>
    t.inflictedStatusEffects.any((a) => ids.contains(a.statusEffectId));

bool _isOffensive(ActiveTrigger t) =>
    t.targetAffiliation == TargetAffiliation.opponent;

String _snippet({
  required String id,
  required String name,
  required String flavor,
  required int strength,
  required bool setupPayoff,
  required String setupId,
  required String payoffId,
}) =>
    "ComboDefinition(\n"
    "  id: '$id',\n"
    "  name: '$name',\n"
    "  flavor: '$flavor',\n"
    "  strength: $strength,\n"
    "${setupPayoff ? "  isSetupPayoff: true,\n" : ""}"
    "  condition: AllOf([\n"
    "    PayoffIsOffensive(),\n"
    "    PayoffUsesTrigger({'$payoffId'}),\n"
    "    AllyUsedTriggerOnTarget({'$setupId'}),\n"
    "  ]),\n"
    "),";

void main() {
  final triggers =
      TriggerCatalog.defaultCatalog.all.whereType<ActiveTrigger>().toList();

  final coldSetups = triggers.where((t) =>
      _appliesAny(t, {'chilled', 'frozen'}) || t.damageType == DamageType.cold);
  final firePayoffs = triggers
      .where((t) => _isOffensive(t) && t.damageType == DamageType.fire);
  final afflictionSetups =
      triggers.where((t) => _appliesAny(t, ComboCatalog.afflictionStatuses));
  final energyPayoffs = triggers
      .where((t) => _isOffensive(t) && t.originTag == OriginTag.energy);
  final controlSetups =
      triggers.where((t) => _appliesAny(t, ComboCatalog.controlStatuses));
  final heavyHits = triggers.where((t) =>
      _isOffensive(t) &&
      t.damageType != null &&
      t.attackSubtype == AttackSubtype.single);

  final existing = {for (final c in ComboCatalog.all) c.id};
  final out = StringBuffer();
  var total = 0;

  void propose(
    String category,
    Iterable<ActiveTrigger> setups,
    Iterable<ActiveTrigger> payoffs, {
    required int strength,
    required bool setupPayoff,
    required String suffix,
  }) {
    var n = 0;
    for (final s in setups) {
      for (final p in payoffs) {
        if (s.id == p.id) continue;
        if (n >= _maxPerCategory) return;
        final id = '${p.id}_${suffix.toLowerCase()}';
        if (existing.contains(id)) continue;
        n++;
        total++;
        out.writeln('// [$category] ${s.name} -> ${p.name}');
        out.writeln(_snippet(
          id: id,
          name: '${p.name} $suffix',
          flavor: '${s.name} sets the target up; '
              '${p.name} follows through for the payoff.',
          strength: strength,
          setupPayoff: setupPayoff,
          setupId: s.id,
          payoffId: p.id,
        ));
        out.writeln();
      }
    }
  }

  propose('elemental detonation', coldSetups, firePayoffs,
      strength: 4, setupPayoff: true, suffix: 'Detonation');
  propose('affliction exploit', afflictionSetups, energyPayoffs,
      strength: 3, setupPayoff: true, suffix: 'Exploit');
  propose('control finisher', controlSetups, heavyHits,
      strength: 4, setupPayoff: true, suffix: 'Finisher');

  print('// Phase I4 signature-combo PROPOSALS (design-time; review before use).');
  print('// $total candidate(s). Edit ids/names/flavor/strength, drop the');
  print('// nonsense, then paste the keepers into ComboCatalog.signature.');
  print('');
  print(out.toString());
}

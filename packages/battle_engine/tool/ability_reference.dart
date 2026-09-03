// Everything needed to price one ability's Trion Types by hand: what it does,
// what its riders do, and what SPTV says it is worth.
//
//   dart run tool/ability_reference.dart
import 'package:battle_engine/battle_engine.dart';

void main() {
  final catalog = TriggerCatalog.defaultCatalog;
  final statuses = StatusEffectCatalog.defaultCatalog;
  final actives = catalog.activeTriggers.toList()
    ..sort((a, b) {
      final o = a.originTag.index.compareTo(b.originTag.index);
      return o != 0 ? o : a.name.compareTo(b.name);
    });

  for (final t in actives) {
    final tv = Sptv.triggerValue(t, statuses: statuses, triggers: catalog);
    final reach = t.targetCount * t.hitsPerUse;
    final payload =
        (t.damage?.average ?? 0) * reach + (t.healAmount?.average ?? 0);
    print('=== ${t.name} [${t.id}] ===');
    print('  origin ${t.originTag.name} | ${t.rangeTag.name} | '
        '${t.abilityType.name}/${t.abilitySubtype.name} | '
        '${t.category.name} | aimed at ${t.targetAffiliation.name}');
    print('  raw ${t.trionCost} Trion | cooldown ${t.cooldownTurns} | '
        'equip ${t.equipCost}');
    print('  targets ${t.targetCount} x ${t.hitsPerUse} hits'
        '${t.damageType == null ? '' : ' | ${t.damageType!.name}'}'
        '${t.damage == null ? '' : ' avg ${t.damage!.average.round()}'}'
        '${t.healAmount == null ? '' : ' | heals ${t.healAmount!.average.round()}'}');
    print('  payload ${payload.round()} | SPTV value '
        '${tv.isInfinite ? 'infinite (free)' : tv.toStringAsFixed(2)}');
    for (final a in t.inflictedStatusEffects) {
      final def = statuses[a.statusEffectId];
      final price = Sptv.priceStatus(def,
          baselines: SptvBaselines.defaults,
          targets: t.targetCount,
          triggers: catalog);
      print('  RIDER ${def.name} (role ${def.role.name}, '
          '${def.defaultDurationTurns ?? 0} turns, SP ${price.total.round()})');
    }
    if (t.armsReactive != null) print('  COUNTER ${t.armsReactive!.name}');
    if (t.uniqueBehavior != null) print('  UNIQUE ${t.uniqueBehavior!.name}');
    print('  CURRENT ${t.trionTypeCost}');
    print('');
  }
}

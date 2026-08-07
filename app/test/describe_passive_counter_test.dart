import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/data/describe.dart';

/// Phase F (F2): passive counters are behaviours, not flat stat mods, so the
/// loadout panel used to show "No stat effect." for them. describeTrigger now
/// gives each a real description.
void main() {
  test('every passive counter gets a real description, not "No stat effect"',
      () {
    final passives = TriggerCatalog.defaultCatalog.all
        .whereType<PassiveTrigger>()
        .where((p) => p.counterKind != null)
        .toList();
    expect(passives, isNotEmpty);
    for (final p in passives) {
      final desc = describeTrigger(p);
      expect(desc, isNot('No stat effect.'),
          reason: '${p.counterKind} should describe its behaviour');
      expect(desc.length, greaterThan(40));
    }
  });

  test('Draegor description mentions its Enmity/Regret mechanic', () {
    final draegor = TriggerCatalog.defaultCatalog.all
        .whereType<PassiveTrigger>()
        .firstWhere((p) => p.counterKind == PassiveCounterKind.draegor);
    expect(describeTrigger(draegor).toLowerCase(), contains('enmity'));
  });
}

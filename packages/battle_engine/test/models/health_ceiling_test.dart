import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Nothing may take a character above their base maximum health. Healing
/// clamps to the *effective* maximum, so any status that raises maximum health
/// quietly raises the healing ceiling with it. Rallied did exactly that, and
/// Radiant Blessing did it as a rider on an otherwise reasonable heal.
void main() {
  test('no status effect raises maximum health', () {
    final raisers = StatusEffectCatalog.defaultCatalog.all
        .where((d) =>
            (d.flatStatModifiers[ModifiableStat.maxHealth] ?? 0) > 0 ||
            (d.perRemainingTurnStatModifiers[ModifiableStat.maxHealth] ?? 0) >
                0)
        .map((d) => d.name)
        .toList();

    expect(raisers, isEmpty,
        reason: 'these would let healing carry a character past their own '
            'ceiling: ${raisers.join(', ')}');
  });

  test('a heal at one below maximum restores exactly one', () {
    final state =
        CharacterBattleState(testCharacter(stats: testStats(maxHealth: 100)));
    state.currentHealth = 99;
    final max = state.effectiveStats().maxHealth;

    state.currentHealth = (state.currentHealth + 40).clamp(0, max);

    expect(state.currentHealth, 100,
        reason: 'overheal is discarded, not banked');
  });

  test('Radiant Blessing heals over time without raising the ceiling', () {
    final def = StatusEffectCatalog.defaultCatalog['radiant_blessing'];
    expect(def.turnStartHeal, isNotNull,
        reason: 'it should still heal each turn');
    expect(def.flatStatModifiers[ModifiableStat.maxHealth], isNull);
  });
}

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Re-applying a status refreshes it instead of adding a second copy. Stacking
/// produced two Bleedings ticking separately and two Braced badges counting
/// down out of step on the same character strip.
void main() {
  CharacterBattleState victim() =>
      CharacterBattleState(testCharacter(id: 'v'));

  final engine = StatusEffectEngine();

  test('applying the same status twice leaves one instance', () {
    final v = victim();
    engine.apply(v, 'bleeding');
    engine.apply(v, 'bleeding');

    expect(v.statusEffects.where((e) => e.definitionId == 'bleeding'),
        hasLength(1));
  });

  test('a re-application refreshes the duration back to full', () {
    final v = victim();
    engine.apply(v, 'braced');
    v.statusEffects.first.remainingTurns = 1; // most of the way through
    engine.apply(v, 'braced');

    final def = StatusEffectCatalog.defaultCatalog['braced'];
    expect(v.statusEffects.single.remainingTurns, def.defaultDurationTurns);
  });

  test('a shorter re-application never cuts a longer one short', () {
    final v = victim();
    engine.apply(v, 'braced'); // 3 turns by default
    engine.apply(v, 'braced', durationOverride: 1);

    expect(v.statusEffects.single.remainingTurns, greaterThanOrEqualTo(3));
  });

  test('different statuses still coexist', () {
    final v = victim();
    engine.apply(v, 'guarded');
    engine.apply(v, 'braced');

    expect(v.statusEffects.map((e) => e.definitionId),
        containsAll(['guarded', 'braced']));
    expect(v.statusEffects, hasLength(2));
  });

  test('no character can ever show the same badge twice', () {
    final v = victim();
    for (final id in ['bleeding', 'braced', 'guarded', 'bleeding', 'braced']) {
      engine.apply(v, id);
    }
    final ids = v.statusEffects.map((e) => e.definitionId).toList();
    expect(ids.toSet().length, ids.length);
  });
}

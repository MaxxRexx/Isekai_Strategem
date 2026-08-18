import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// A heal, a ward or a buff aimed at your own side is not an attack and is not
/// inflicted. It was being run through the full hostile pipeline: rolled to
/// hit against the recipient's own Defense, then contested against their own
/// Status Effect Resistance. In practice that meant a character resisted their
/// own War Chant roughly three times in four.
void main() {
  Battle newBattle() {
    final battle = Battle(
      teamA: Team(id: 'a', characters: [
        testCharacter(id: 'a1'),
        testCharacter(id: 'a2'),
        testCharacter(id: 'a3'),
      ]),
      teamB: Team(id: 'b', characters: [
        testCharacter(id: 'b1'),
        testCharacter(id: 'b2'),
        testCharacter(id: 'b3'),
      ]),
    );
    battle.teamA.trionPool.gain(1000);
    for (final c in [...battle.teamA.characters, ...battle.teamB.characters]) {
      battle.states[c.id]!.position = BattlePosition.front;
    }
    return battle;
  }

  ActiveTrigger buff({
    TargetAffiliation affiliation = TargetAffiliation.self,
    String statusId = 'empowered',
  }) =>
      testTrigger(
        id: 'buff',
        rangeTag: RangeTag.close,
        targetAffiliation: affiliation,
        includeDamage: false,
        inflictedStatusEffects: [StatusEffectApplication(statusId)],
      );

  test('a self-buff lands every single time', () {
    final battle = newBattle();
    final me = battle.states['a1']!;
    final trigger = buff();

    for (var i = 0; i < 60; i++) {
      me.statusEffects.clear();
      battle.turnEngine
          .resolveAbilityUse(attacker: me, trigger: trigger, targets: [me]);
      expect(me.statusEffects.map((e) => e.definitionId), contains('empowered'),
          reason: 'run $i: a buff on yourself is granted, never contested');
    }
  });

  test('an ally-targeted buff lands every single time', () {
    final battle = newBattle();
    final me = battle.states['a1']!;
    final ally = battle.states['a2']!;
    final trigger = buff(affiliation: TargetAffiliation.ally);

    for (var i = 0; i < 60; i++) {
      ally.statusEffects.clear();
      battle.turnEngine
          .resolveAbilityUse(attacker: me, trigger: trigger, targets: [ally]);
      expect(
          ally.statusEffects.map((e) => e.definitionId), contains('empowered'),
          reason: 'run $i');
    }
  });

  test('a heal on an ally is never rolled against their own Defense', () {
    final battle = newBattle();
    final me = battle.states['a1']!;
    final ally = battle.states['a2']!;
    final heal = testTrigger(
      id: 'mend',
      rangeTag: RangeTag.close,
      targetAffiliation: TargetAffiliation.ally,
      includeDamage: false,
      healAmount: const DiceExpression(2, 4, flatBonus: 4),
    );

    for (var i = 0; i < 60; i++) {
      ally.currentHealth = 40;
      battle.turnEngine
          .resolveAbilityUse(attacker: me, trigger: heal, targets: [ally]);
      expect(ally.currentHealth, greaterThan(40), reason: 'run $i: healing a '
          'teammate cannot miss');
    }
  });

  test('a hostile status is still contested, so this is not a blanket bypass',
      () {
    final battle = newBattle();
    final me = battle.states['a1']!;
    final foe = battle.states['b1']!;
    final hostile = buff(affiliation: TargetAffiliation.opponent);

    var landed = 0;
    for (var i = 0; i < 80; i++) {
      foe.statusEffects.clear();
      battle.turnEngine
          .resolveAbilityUse(attacker: me, trigger: hostile, targets: [foe]);
      if (foe.statusEffects.isNotEmpty) landed++;
    }
    expect(landed, greaterThan(0), reason: 'some should land');
    expect(landed, lessThan(80),
        reason: 'an enemy still gets to resist; only friendly is automatic');
  });

  test('the whole catalogue: every friendly rider lands, every time', () {
    final battle = newBattle();
    final me = battle.states['a1']!;
    final ally = battle.states['a2']!;

    final friendly = TriggerCatalog.defaultCatalog.all
        .whereType<ActiveTrigger>()
        .where((t) =>
            t.targetAffiliation != TargetAffiliation.opponent &&
            (t.inflictedStatusEffects.isNotEmpty || t.healAmount != null))
        .toList();
    expect(friendly, isNotEmpty, reason: 'fixture should find some');

    for (final trigger in friendly) {
      final onSelf = trigger.targetAffiliation == TargetAffiliation.self;
      final target = onSelf ? me : ally;
      // Stand where the band reaches, or the range gate filters the target
      // out and the result is a false failure.
      me.position = switch (trigger.rangeTag) {
        RangeTag.close => BattlePosition.front,
        RangeTag.mid => BattlePosition.middle,
        RangeTag.long => BattlePosition.back,
      };
      ally.position = me.position;

      for (var i = 0; i < 12; i++) {
        target.statusEffects.clear();
        target.currentHealth = 50;
        me.currentHealth = 50;
        battle.turnEngine.resolveAbilityUse(
            attacker: me, trigger: trigger, targets: [target]);
        if (trigger.inflictedStatusEffects.isNotEmpty) {
          expect(target.statusEffects, isNotEmpty,
              reason: '${trigger.id} failed to apply its status on run $i');
        }
        if (trigger.healAmount != null) {
          final healed = trigger.healsCasterInstead ? me : target;
          expect(healed.currentHealth, greaterThan(50),
              reason: '${trigger.id} failed to heal on run $i');
        }
      }
    }
  });
}

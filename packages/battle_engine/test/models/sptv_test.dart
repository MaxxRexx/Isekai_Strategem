import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

/// Item #3's rule: SPTV.
///
/// One Status Point is one point of damage, with no conversion constant
/// between them (decision #A). A status is priced from its own declarative
/// fields (decision #B), each conversion derived from a measured baseline, so
/// nothing carries a hand-written price and a price cannot drift from the
/// content it prices.
///
/// These tests check the rule, not the catalogue's current numbers. The pass
/// that moves those is wave 4's.
void main() {
  final catalog = StatusEffectCatalog.defaultCatalog;
  const b = SptvBaselines.defaults;

  group('the conversions come off the dice, not off a hunch', () {
    test('one point of an opposed stat is worth about 4.5 percentage points',
        () {
      // A property of two d20s with ties to the attacker, computed rather
      // than asserted.
      expect(Sptv.opposedStatPointWinChance, closeTo(0.0475, 0.005));
    });

    test('advantage is worth about four points of flat modifier', () {
      expect(Sptv.advantageInStatPoints, closeTo(4.0, 0.5));
    });

    test('a stat point is worth its own share of a landed roll', () {
      final expected = Sptv.opposedStatPointWinChance *
          b.attackRollsPerCharacterTurn *
          b.damagePerLandedRoll;
      expect(Sptv.damagePerOpposedStatPoint(b), closeTo(expected, 0.0001));
    });

    test('a point of Armor is worth one subtraction per landed hit', () {
      expect(Sptv.damagePerArmorPoint(b),
          closeTo(b.attackRollsPerCharacterTurn * b.attackLandRate, 0.0001));
    });
  });

  group('a status is priced from its own fields', () {
    test('a damage tick is priced at the damage it ticks', () {
      final price = Sptv.priceStatus(catalog['bleeding'], baselines: b);
      final tick = catalog['bleeding'].turnStartDamage!.average;

      expect(price.byField['turnStartDamage'], closeTo(tick, 0.001),
          reason: 'a tick cannot miss, so it is worth its face value');
      expect(price.total, closeTo(price.perTurn * price.turns, 0.001));
    });

    test('denying an action is worth an action', () {
      final price = Sptv.priceStatus(catalog['silenced'], baselines: b);
      expect(price.byField['preventsActions'],
          closeTo(b.damagePerDamagingUse, 0.001));
    });

    test('a duration multiplies, and so do targets', () {
      final one = Sptv.priceStatus(catalog['bleeding'],
          baselines: b, durationTurns: 1);
      final three = Sptv.priceStatus(catalog['bleeding'],
          baselines: b, durationTurns: 3);
      final threeTargets = Sptv.priceStatus(catalog['bleeding'],
          baselines: b, durationTurns: 1, targets: 3);

      expect(three.total, closeTo(one.total * 3, 0.001));
      expect(threeTargets.total, closeTo(one.total * 3, 0.001));
    });

    test('a stack multiplies the price, exactly as it multiplies the effect',
        () {
      // Decision #F: magnitudes and SP both multiply by the count.
      final one = Sptv.priceStatus(catalog['bleeding'], baselines: b);
      final three =
          Sptv.priceStatus(catalog['bleeding'], baselines: b, stacks: 3);

      expect(three.total, closeTo(one.total * 3, 0.001));
    });

    test('a stat step is priced by the stat, not by the number', () {
      // Armor and Attack are both "one point" and are not worth the same.
      final armor = Sptv.priceStatus(catalog['acid'], baselines: b);
      final attack = Sptv.priceStatus(catalog['fatigued'], baselines: b);

      expect(armor.perTurn, isNot(closeTo(attack.perTurn, 0.001)));
    });

    test('an effect with nothing priceable says so rather than reading zero',
        () {
      final price = Sptv.priceStatus(catalog['misfire'], baselines: b);

      expect(price.total, 0);
      expect(price.isComplete, isFalse,
          reason: 'a zero that is really an unpriced field has to be visible');
      expect(price.unpriced, contains('misfireChance'));
    });

    test('every one of the 62 can be priced without throwing', () {
      for (final def in catalog.all) {
        expect(() => Sptv.priceStatus(def, baselines: b), returnsNormally,
            reason: def.id);
      }
    });

    test('a price re-derives itself when the baseline moves', () {
      // The reason prices are formulas: item #4 moves the economy, and wave 4
      // re-measures rather than re-authoring 62 numbers.
      const richer = SptvBaselines(damagePerDamagingUse: 24.0);
      final normal = Sptv.priceStatus(catalog['silenced'], baselines: b);
      final doubled = Sptv.priceStatus(catalog['silenced'], baselines: richer);

      expect(doubled.total, closeTo(normal.total * 2, 0.001));
    });
  });

  group('Trigger Value counts the rider', () {
    ActiveTrigger byId(String id) =>
        TriggerCatalog.defaultCatalog[id] as ActiveTrigger;

    test('an ability carrying a status is worth more than its damage alone',
        () {
      final t = byId('mind_shatter');
      final damageOnly = t.damage!.average * t.targetCount * t.hitsPerUse /
          t.trionCost *
          Sptv.cooldownFactor(t.cooldownTurns);

      expect(Sptv.triggerValue(t), greaterThan(damageOnly),
          reason: 'an ability whose real payload is a status used to price at '
              'half what it is worth');
    });

    test('a rider aimed at an opponent is discounted, one on yourself is not',
        () {
      // The infliction contest is the difference, and it is measured.
      final hostile = byId('mind_shatter');
      final withoutContest = Sptv.triggerValue(
        hostile,
        baselines: const SptvBaselines(riderLandsGivenHit: 1.0),
      );

      expect(Sptv.triggerValue(hostile), lessThan(withoutContest));
      expect(b.riderLandsGivenHit, lessThan(1.0));
    });

    test('a shorter cooldown is worth more of the same payload', () {
      expect(Sptv.cooldownFactor(1), greaterThan(Sptv.cooldownFactor(2)));
      expect(Sptv.cooldownFactor(2), greaterThan(Sptv.cooldownFactor(3)));
      expect(Sptv.cooldownFactor(4), lessThan(Sptv.cooldownFactor(3)));
    });

    test('a free ability is not divided by zero', () {
      final free = ActiveTrigger(
        id: 'free',
        name: 'Free',
        category: TriggerCategory.attacker,
        equipCost: 10,
        trionCost: 0,
        cooldownTurns: 1,
        originTag: OriginTag.physical,
        rangeTag: RangeTag.close,
        attackType: AttackType.melee,
        attackSubtype: AttackSubtype.single,
        damageType: DamageType.slashing,
        damage: const DiceExpression(1, 6),
      );
      expect(Sptv.triggerValue(free), double.infinity);
    });

    test('a heal counts as payload, because a tick of healing does', () {
      // The conversion table prices turnStartHeal as damage undone. A direct
      // heal that counted as nothing would contradict it.
      final ward = byId('cleansing_ward');
      expect(Sptv.triggerValue(ward), greaterThan(0));
    });
  });

  group('what the rule cannot price, it names', () {
    test('the unpriced list is the one the review approved, plus 3b', () {
      expect(Sptv.unpricedFields, containsAll(<String>[
        'misfireChance',
        'preventsTargeting',
        'cannotTargetSource',
        'locksRandomAbilityEachTurn',
      ]));
      expect(Sptv.unpricedFields, contains('reactions'),
          reason: 'a status that sets up a reaction is worth more, and how '
              'much more has not been derived');
    });

    test('preventing healing is priced now that healing is measured', () {
      final price = Sptv.priceStatus(catalog['cursed'], baselines: b);
      expect(price.byField.containsKey('preventsHealing'), isTrue);
    });

    test('an unpriced field never silently contributes zero to a full price',
        () {
      // Every status that carries an unpriced field has to say so, or its
      // price reads as an answer when it is a floor.
      for (final def in catalog.all) {
        final price = Sptv.priceStatus(def, baselines: b);
        if (def.misfireChance != null || def.preventsTargeting) {
          expect(price.isComplete, isFalse, reason: def.id);
        }
      }
    });
  });

  group('reachability, so nothing is priced that nothing can apply', () {
    test('the statuses nothing applies are a known list', () {
      final applied = <String>{};
      for (final t in TriggerCatalog.defaultCatalog.activeTriggers) {
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
      final byReaction = <String>{
        for (final def in catalog.all)
          for (final r in def.reactions)
            if (r.becomes != null) r.becomes!
      };

      final unreachable = [
        for (final def in catalog.all)
          if (!applied.contains(def.id) && !byReaction.contains(def.id))
            def.id
      ];

      // The count is the thing under watch: wave 3's content pass is meant to
      // shrink it, and nothing should ever grow it silently.
      expect(unreachable.length, lessThanOrEqualTo(34),
          reason: 'a new status nothing can apply is a status nobody will '
              'ever see: $unreachable');
    });

    test('the reaction table homes four statuses for free', () {
      // Decision #E counted on this: Wet, Frozen, Electrocuted and Sickened
      // become reachable through the table without any ability naming them.
      final applied = <String>{
        for (final t in TriggerCatalog.defaultCatalog.activeTriggers)
          for (final a in t.inflictedStatusEffects) a.statusEffectId
      };
      final byReaction = <String>{
        for (final def in catalog.all)
          for (final r in def.reactions)
            if (r.becomes != null) r.becomes!
      };

      final homedByTable = byReaction.difference(applied);
      expect(homedByTable, containsAll(<String>['wet', 'frozen']));
      expect(homedByTable.length, greaterThanOrEqualTo(4));
    });
  });
}

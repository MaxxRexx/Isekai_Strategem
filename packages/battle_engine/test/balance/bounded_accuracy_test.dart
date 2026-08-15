import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

/// Locks in the properties the P0 balance pass was for. These are not
/// arbitrary numbers to keep green: each one is a rule about the shape of
/// the combat math, and breaking one means the d20 has stopped mattering
/// again. Content may move freely inside these bounds.
///
/// If a change here is deliberate, widen the bound and say why - do not
/// delete the check.
void main() {
  final roster = CharacterRoster.defaultRoster;
  final catalog = TriggerCatalog.defaultCatalog;
  final blackTriggers = BlackTriggerCatalog.defaultCatalog;

  /// Every damaging ability in the game, base Triggers and Black Trigger
  /// abilities alike.
  Iterable<ActiveTrigger> allDamagingAbilities() sync* {
    yield* catalog.activeTriggers.where((t) => t.damage != null);
    for (final bt in blackTriggers.all) {
      yield* bt.activeAbilities.where((t) => t.damage != null);
    }
  }

  double diceAverage(DiceExpression d) => d.count * (d.sides + 1) / 2;

  /// Chance the attacker wins the opposed d20 contest at a given modifier
  /// gap, ties going to the attacker.
  double hitChance(int gap) {
    var wins = 0;
    for (var a = 1; a <= 20; a++) {
      for (var d = 1; d <= 20; d++) {
        if (a + gap >= d) wins++;
      }
    }
    return wins / 400;
  }

  group('accuracy band', () {
    test('Attack stays within 4-14 and Defense within 2-12', () {
      for (final c in roster.all) {
        expect(c.baseStats.attack, inInclusiveRange(4, 14),
            reason: '${c.name} Attack is outside the band');
        expect(c.baseStats.defense, inInclusiveRange(2, 12),
            reason: '${c.name} Defense is outside the band');
      }
    });

    test('even the most lopsided matchup leaves the die deciding', () {
      final attacks = roster.all.map((c) => c.baseStats.attack);
      final defenses = roster.all.map((c) => c.baseStats.defense);
      final widest = attacks.reduce((a, b) => a > b ? a : b) -
          defenses.reduce((a, b) => a < b ? a : b);
      final narrowest = attacks.reduce((a, b) => a < b ? a : b) -
          defenses.reduce((a, b) => a > b ? a : b);

      // Nobody is ever a sure thing and nobody is ever hopeless: the whole
      // roster fits between roughly a fifth and roughly four fifths.
      expect(hitChance(widest), lessThan(0.95));
      expect(hitChance(narrowest), greaterThan(0.15));
    });

    test('an evenly matched pair is close to a coin flip', () {
      expect(hitChance(0), closeTo(0.53, 0.02));
    });
  });

  group('damage is mostly dice', () {
    test('every damaging ability rolls at least a third of its damage', () {
      for (final t in allDamagingAbilities()) {
        final share = diceAverage(t.damage!) / t.damage!.average;
        expect(share, greaterThanOrEqualTo(0.35),
            reason: '${t.id} (${t.damage}) is mostly a flat bonus, so its '
                'damage roll barely swings');
        expect(share, lessThanOrEqualTo(0.70),
            reason: '${t.id} (${t.damage}) is almost all dice, which is as '
                'swingy as a flat bonus is flat');
      }
    });
  });

  group('single-hit lethality', () {
    // Every character in the roster starts at 100 health.
    final maxHealth = roster.all.first.baseStats.maxHealth;

    test('no single hit can take a full-health character out', () {
      for (final t in allDamagingAbilities()) {
        final ceiling = t.damage!.count * t.damage!.sides + t.damage!.flatBonus;
        expect(ceiling, lessThan(maxHealth),
            reason: '${t.id} tops out at $ceiling against $maxHealth health, '
                'so a lucky roll deletes someone outright');
      }
    });

    test('an average critical hit still leaves someone standing', () {
      for (final t in allDamagingAbilities()) {
        // A crit rolls the damage dice a second time.
        final averageCrit = t.damage!.average + diceAverage(t.damage!);
        expect(averageCrit, lessThan(maxHealth),
            reason: '${t.id} averages $averageCrit on a crit, which is a '
                'one-shot on a full-health character');
      }
    });
  });

  group('range bands', () {
    test('the catalog is split evenly across the three bands', () {
      final byBand = <RangeTag, int>{};
      for (final t in catalog.activeTriggers) {
        byBand[t.rangeTag] = (byBand[t.rangeTag] ?? 0) + 1;
      }
      expect(byBand[RangeTag.close], 20);
      expect(byBand[RangeTag.mid], 20);
      expect(byBand[RangeTag.long], 20);
    });

    test('a melee-type Trigger is always Close Range', () {
      for (final t in catalog.activeTriggers) {
        if (t.attackType != AttackType.melee) continue;
        expect(t.rangeTag, RangeTag.close,
            reason: '${t.id} is a melee attack, so it has to be in contact');
      }
    });

    test('the band is not just a restatement of the attack type', () {
      // This is the failure the band was rescued from: when every non-melee
      // Trigger sat in one bucket, the tag was perfectly derivable from the
      // attack type and carried nothing of its own. Both ranged and psychic
      // must therefore straddle mid and long.
      for (final type in [AttackType.ranged, AttackType.psychic]) {
        final bands = catalog.activeTriggers
            .where((t) => t.attackType == type)
            .map((t) => t.rangeTag)
            .toSet();
        expect(bands.length, greaterThan(1),
            reason: 'every $type Trigger sits in the same band, which makes '
                'the band redundant with the attack type');
      }
    });

    test('everything but Close Range counts as being at a distance', () {
      expect(RangeTag.close.isAtRange, isFalse);
      expect(RangeTag.mid.isAtRange, isTrue);
      expect(RangeTag.long.isAtRange, isTrue);
    });
  });

  group('critical hits', () {
    test('the crit threshold never drops below a natural 17', () {
      final engine = CombatEngine();
      for (var chance = 0.0; chance <= 200; chance += 1) {
        expect(engine.criticalHitThreshold(chance), greaterThanOrEqualTo(17));
      }
    });

    test('a crit doubles the dice and leaves the flat bonus alone', () {
      final engine = CombatEngine();
      final target = CharacterBattleState(Character(
        id: 't',
        name: 'Target',
        type: CharacterType.defense,
        baseStats: const Stats(
          trionCapacity: 100,
          trionAffinity: 10,
          teamSpirit: 50,
          criticalChance: 0,
          fatChance: 0,
          armor: 0,
          maxHealth: 100,
          attack: 5,
          defense: 5,
          statusEffectInfliction: 5,
          statusEffectResistance: 5,
        ),
      ));

      // Twin Fang Strike's shape: 6d6+23, here rolled as 21 dice + 23 flat.
      final crit = engine.resolveDamage(
        baseDamage: 44,
        damageType: DamageType.slashing,
        isCriticalHit: true,
        target: target,
        criticalDiceComponent: 21,
      );
      expect(crit, 65);
      expect(crit, lessThan(88), reason: 'the old rule doubled everything');
    });
  });
}

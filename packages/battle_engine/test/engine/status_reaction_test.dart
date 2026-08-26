import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Item 3b: status reactions.
///
/// Sixty-two status effects existed and none of them talked to each other. A
/// status was a modifier you applied and forgot. The table gives twelve of
/// them something to say to a damage type, which is where combinatorial depth
/// comes from without writing more content.
///
/// Every row below is one entry in the approved table, checked against the
/// catalogue rather than against a copy of it.
void main() {
  final catalog = StatusEffectCatalog.defaultCatalog;

  /// A battle whose dice always roll high, so an attack lands when a test
  /// needs it to.
  Battle twoSquads() {
    final roster = CharacterRoster.defaultRoster;
    return Battle(
      turnEngine: TurnEngine(
        combatEngine:
            CombatEngine(diceRoller: DiceRoller(const FixedRandom(19))),
        statusEffectEngine:
            StatusEffectEngine(diceRoller: DiceRoller(const FixedRandom(19))),
      ),
      teamA: Team(
        id: 'a',
        characters: [
          roster['kaito_reyes'],
          roster['vela_ashworth'],
          roster['dross'],
        ],
        trionPool: TrionPool(current: 300, cap: 500),
      ),
      teamB: Team(
        id: 'b',
        characters: [
          roster['marren_osei'],
          roster['ilona_vance'],
          roster['bastian_cole'],
        ],
        trionPool: TrionPool(current: 300, cap: 500),
      ),
    );
  }

  /// Hits [target] with a real attack of [type], resolved through the ordinary
  /// path, and returns what the resolution reported firing.
  ///
  /// Going through a real ability rather than poking damage in is the point:
  /// the reaction has to fire where a hit actually lands, and the reacting
  /// status has to still be on the target while the damage is worked out.
  List<StatusReactionEvent> hit(
    Battle battle,
    CharacterBattleState target,
    DamageType type, {
    int damage = 10,
  }) {
    final attacker = battle.states['kaito_reyes']!;
    attacker.position = BattlePosition.front;
    if (target.position != BattlePosition.front) {
      target.position = BattlePosition.front;
    }
    final result = battle.turnEngine.resolveAbilityUse(
      attacker: attacker,
      trigger: testTrigger(
        id: 'test_${type.name}',
        rangeTag: RangeTag.close,
        damageType: type,
        damage: DiceExpression(1, 2, flatBonus: damage),
      ),
      targets: [target],
    );
    return result.reactions;
  }

  ActiveTrigger attack(String id) =>
      TriggerCatalog.defaultCatalog[id] as ActiveTrigger;

  bool has(CharacterBattleState s, String id) =>
      s.statusEffects.any((i) => i.definitionId == id);

  group('the table is data, not code', () {
    test('the twelve rows are on the definitions themselves', () {
      // If a row is ever moved into a switch statement in the engine, this
      // is the test that notices.
      final rows = <String, int>{};
      for (final def in catalog.all) {
        if (def.reactions.isNotEmpty) rows[def.id] = def.reactions.length;
      }

      expect(rows, {
        'wet': 3,
        'poisoned': 1,
        'frozen': 2,
        'bleeding': 1,
        'electrocuted': 1,
        'scorched': 2,
        'chilled': 2,
        'corroded': 1,
      });
      expect(rows.values.reduce((a, b) => a + b), 13,
          reason: 'twelve table rows, with the Frozen shatter written once '
              'per damage type that shatters it');
    });

    test('every reaction names a status that exists', () {
      for (final def in catalog.all) {
        for (final r in def.reactions) {
          if (r.becomes != null) {
            expect(catalog.contains(r.becomes!), isTrue,
                reason: '${def.id} turns into ${r.becomes}, which is not a '
                    'catalogued status');
          }
          if (r.alsoRemoves != null) {
            expect(catalog.contains(r.alsoRemoves!), isTrue);
          }
        }
      }
    });

    test('a reaction has something to react to', () {
      for (final def in catalog.all) {
        for (final r in def.reactions) {
          expect(r.onDamageType != null || r.onStatusApplied != null, isTrue,
              reason: '${def.id} has a reaction that can never fire');
        }
      }
    });
  });

  group('water', () {
    test('Wet plus Cold freezes, and the water is spent', () {
      final battle = twoSquads();
      final target = battle.states['marren_osei']!;
      battle.turnEngine.statusEffectEngine.apply(target, 'wet');

      hit(battle, target, DamageType.cold);

      expect(has(target, 'frozen'), isTrue);
      expect(has(target, 'wet'), isFalse);
    });

    test('Wet plus Lightning electrocutes, and the water is spent', () {
      final battle = twoSquads();
      final target = battle.states['marren_osei']!;
      battle.turnEngine.statusEffectEngine.apply(target, 'wet');

      hit(battle, target, DamageType.lightning);

      expect(has(target, 'electrocuted'), isTrue);
      expect(has(target, 'wet'), isFalse);
    });

    test('Wet plus Fire boils the water off and the fire does nothing', () {
      final battle = twoSquads();
      final target = battle.states['marren_osei']!;
      battle.turnEngine.statusEffectEngine.apply(target, 'wet');
      final health = target.currentHealth;

      hit(battle, target, DamageType.fire, damage: 30);

      expect(has(target, 'wet'), isFalse, reason: 'the water boils off');
      expect(target.currentHealth, health,
          reason: 'Wet is Fire-immune, so the hit that removes it deals '
              'nothing');
    });
  });

  group('fire and ice', () {
    test('Scorched plus Cold quenches to Chilled', () {
      final battle = twoSquads();
      final target = battle.states['marren_osei']!;
      battle.turnEngine.statusEffectEngine.apply(target, 'scorched');

      hit(battle, target, DamageType.cold);

      expect(has(target, 'chilled'), isTrue);
      expect(has(target, 'scorched'), isFalse);
    });

    test('Scorched plus Fire is the burn build paying off', () {
      final battle = twoSquads();
      final target = battle.states['marren_osei']!;
      battle.turnEngine.statusEffectEngine.apply(target, 'scorched');

      hit(battle, target, DamageType.fire);

      expect(has(target, 'scorched'), isTrue,
          reason: 'this row builds rather than transforms');
    });

    test('Chilled plus Cold freezes', () {
      final battle = twoSquads();
      final target = battle.states['marren_osei']!;
      battle.turnEngine.statusEffectEngine.apply(target, 'chilled');

      hit(battle, target, DamageType.cold);

      expect(has(target, 'frozen'), isTrue);
      expect(has(target, 'chilled'), isFalse);
    });

    test('Chilled plus Fire melts back to Wet, which sets up the next hit',
        () {
      final battle = twoSquads();
      final target = battle.states['marren_osei']!;
      battle.turnEngine.statusEffectEngine.apply(target, 'chilled');

      hit(battle, target, DamageType.fire);
      expect(has(target, 'wet'), isTrue);
      expect(has(target, 'chilled'), isFalse);

      // And the loop closes: the water freezes again.
      hit(battle, target, DamageType.cold);
      expect(has(target, 'frozen'), isTrue);
    });
  });

  group('the shatter', () {
    test('Frozen plus Bludgeoning doubles the hit and breaks the ice', () {
      final battle = twoSquads();
      final plain = battle.states['marren_osei']!;
      final frozen = battle.states['ilona_vance']!;
      battle.turnEngine.statusEffectEngine.apply(frozen, 'frozen');

      final plainBefore = plain.currentHealth;
      hit(battle, plain, DamageType.bludgeoning, damage: 20);
      final plainDamage = plainBefore - plain.currentHealth;

      final frozenBefore = frozen.currentHealth;
      hit(battle, frozen, DamageType.bludgeoning, damage: 20);
      final frozenDamage = frozenBefore - frozen.currentHealth;

      expect(has(frozen, 'frozen'), isFalse, reason: 'the ice is gone');
      expect(frozenDamage, greaterThan(plainDamage),
          reason: 'shattering has to be worth aiming for');
    });

    test('Thunder shatters too', () {
      final battle = twoSquads();
      final target = battle.states['marren_osei']!;
      battle.turnEngine.statusEffectEngine.apply(target, 'frozen');

      hit(battle, target, DamageType.thunder);

      expect(has(target, 'frozen'), isFalse);
    });

    test('an ordinary damage type leaves the ice alone', () {
      final battle = twoSquads();
      final target = battle.states['marren_osei']!;
      battle.turnEngine.statusEffectEngine.apply(target, 'frozen');

      hit(battle, target, DamageType.piercing);

      expect(has(target, 'frozen'), isTrue);
    });
  });

  group('the rest of the table', () {
    test('Corroded plus Acid takes another coat', () {
      final battle = twoSquads();
      final target = battle.states['marren_osei']!;
      battle.turnEngine.statusEffectEngine.apply(target, 'corroded');

      hit(battle, target, DamageType.acid);

      expect(has(target, 'acid'), isTrue);
      expect(has(target, 'corroded'), isTrue,
          reason: 'the corrosion deepens rather than transforming');
    });

    test('Bleeding plus Slashing builds the bleed', () {
      final battle = twoSquads();
      final target = battle.states['marren_osei']!;
      battle.turnEngine.statusEffectEngine.apply(target, 'bleeding');

      hit(battle, target, DamageType.slashing);

      expect(has(target, 'bleeding'), isTrue);
    });

    test('Poisoned plus Poison sickens', () {
      final battle = twoSquads();
      final target = battle.states['marren_osei']!;
      battle.turnEngine.statusEffectEngine.apply(target, 'poisoned');

      hit(battle, target, DamageType.poison);

      expect(has(target, 'sickened'), isTrue);
      expect(has(target, 'poisoned'), isFalse);
    });

    test('Electrocuted plus Thunder arcs down the line', () {
      final battle = twoSquads();
      final target = battle.states['marren_osei']!;
      final neighbour = battle.states['ilona_vance']!;
      target.position = BattlePosition.front;
      neighbour.position = BattlePosition.front;
      battle.states['bastian_cole']!.position = BattlePosition.back;
      battle.turnEngine.statusEffectEngine.apply(target, 'electrocuted');

      hit(battle, target, DamageType.thunder);

      expect(has(neighbour, 'electrocuted'), isTrue,
          reason: 'it arcs to someone standing on the same line');
      expect(has(battle.states['bastian_cole']!, 'electrocuted'), isFalse,
          reason: 'and not to the back line');
    });
  });

  group('a bleed does not feed itself', () {
    test('a status ticking its own damage type fires nothing', () {
      // Bleeding ticks Slashing, and Slashing is what Bleeding reacts to.
      // Reactions are about being hit, so a tick must not count, or a bleed
      // refreshes itself forever and never expires.
      final battle = twoSquads();
      final target = battle.states['marren_osei']!;
      battle.startTurn();
      battle.turnEngine.statusEffectEngine
          .apply(target, 'bleeding', durationOverride: 3);
      battle.endTurn();

      var turns = 0;
      while (has(target, 'bleeding') && turns < 12) {
        battle.startTurn();
        battle.endTurn();
        turns++;
      }

      expect(has(target, 'bleeding'), isFalse,
          reason: 'a bleed that renews itself never ends');
    });
  });

  group('Enraged, redesigned', () {
    test('it is immune to Psychic, the answer a psychic squad had none of',
        () {
      final battle = twoSquads();
      final target = battle.states['marren_osei']!;
      final health = target.currentHealth;
      battle.turnEngine.statusEffectEngine.apply(target, 'enraged');

      hit(battle, target, DamageType.psychic, damage: 40);

      expect(target.currentHealth, health);
    });

    test('it still hits harder and defends worse', () {
      final def = catalog['enraged'];
      expect(def.outgoingDamageMultiplier, greaterThan(1.0));
      expect(def.flatStatModifiers[ModifiableStat.defense], lessThan(0));
    });

    test('it takes the choice of target away', () {
      expect(catalog['enraged'].randomizesOwnTargeting, isTrue);
    });

    test('the holder targeting is drawn from the pool, not from their aim',
        () {
      final roster = CharacterRoster.defaultRoster;
      final battle = Battle(
        turnEngine: TurnEngine(
          combatEngine: CombatEngine(diceRoller: DiceRoller(Random(3))),
          statusEffectEngine:
              StatusEffectEngine(diceRoller: DiceRoller(Random(3))),
        ),
        teamA: Team(
          id: 'a',
          characters: [
            roster['kaito_reyes'],
            roster['vela_ashworth'],
            roster['dross'],
          ],
          trionPool: TrionPool(current: 500, cap: 500),
        ),
        teamB: Team(
          id: 'b',
          characters: [
            roster['marren_osei'],
            roster['ilona_vance'],
            roster['bastian_cole'],
          ],
          trionPool: TrionPool(current: 500, cap: 500),
        ),
      );
      final attacker = battle.states['kaito_reyes']!;
      final pool = battle.statesOf(battle.teamB).toList();
      for (final s in [attacker, ...pool]) {
        s.position = BattlePosition.front;
      }
      battle.turnEngine.statusEffectEngine.apply(attacker, 'enraged');

      final trigger = attack('twin_fang_strike');
      final struck = <String>{};
      for (var i = 0; i < 20; i++) {
        for (final s in pool) {
          s.currentHealth = s.effectiveStats().maxHealth;
        }
        final result = battle.turnEngine.resolveAbilityUse(
          attacker: attacker,
          trigger: trigger,
          targets: [pool.first],
          targetPool: pool,
        );
        struck.addAll(result.targetResults.map((r) => r.targetCharacterId));
      }

      expect(struck.length, greaterThan(1),
          reason: 'an enraged character who always hits who they aimed at is '
              'not enraged');
    });

    test('without a pool to choose from, the aim stands', () {
      final battle = twoSquads();
      final attacker = battle.states['kaito_reyes']!;
      final target = battle.states['marren_osei']!;
      attacker.position = BattlePosition.front;
      target.position = BattlePosition.front;
      battle.turnEngine.statusEffectEngine.apply(attacker, 'enraged');

      final result = battle.turnEngine.resolveAbilityUse(
        attacker: attacker,
        trigger: attack('twin_fang_strike'),
        targets: [target],
      );

      expect(result.targetResults.single.targetCharacterId,
          target.combatantId);
    });
  });

  group('what fired is reported, so the log can say it', () {
    test('an ability that sets off a reaction says so on its result', () {
      final battle = twoSquads();
      final attacker = battle.states['kaito_reyes']!;
      final target = battle.states['marren_osei']!;
      attacker.position = BattlePosition.front;
      target.position = BattlePosition.front;
      battle.turnEngine.statusEffectEngine.apply(target, 'frozen');

      final result = battle.turnEngine.resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(
          id: 'test_hammer',
          rangeTag: RangeTag.close,
          damageType: DamageType.bludgeoning,
          damage: const DiceExpression(1, 2, flatBonus: 10),
        ),
        targets: [target],
      );

      // The dice are fixed high, so the attack lands and the shatter is not
      // conditional on luck.
      final shatter =
          result.reactions.where((r) => r.reactingStatusId == 'frozen');
      expect(shatter, hasLength(1));
      expect(shatter.single.consumed, isTrue);
      expect(shatter.single.damageMultiplier, 2.0);
      expect(shatter.single.characterId, target.combatantId);
      expect(shatter.single.damageType, DamageType.bludgeoning,
          reason: 'the log has to be able to say what set the reaction off');
    });

    test('an ordinary hit reports nothing', () {
      final battle = twoSquads();
      final attacker = battle.states['kaito_reyes']!;
      final target = battle.states['marren_osei']!;
      attacker.position = BattlePosition.front;
      target.position = BattlePosition.front;

      final result = battle.turnEngine.resolveAbilityUse(
        attacker: attacker,
        trigger: attack('twin_fang_strike'),
        targets: [target],
      );

      expect(result.reactions, isEmpty);
    });
  });
}

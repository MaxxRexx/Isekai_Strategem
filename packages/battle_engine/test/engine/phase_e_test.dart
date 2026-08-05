import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

Team _team(String id, List<String> ids) =>
    Team(id: id, characters: [for (final c in ids) testCharacter(id: c)]);

ActiveTrigger get _illusoryDouble =>
    TriggerCatalog.defaultCatalog['illusory_double'] as ActiveTrigger;

void main() {
  group('Phase E: Illusory Double charges (Battle wiring)', () {
    test('initialize grants the starting charge to holders only', () {
      final battle = Battle(
        teamA: _team('A', ['a1', 'a2', 'a3']),
        teamB: _team('B', ['b1', 'b2', 'b3']),
      );

      battle.initializeIllusoryDoubleCharges({
        'a1': [_illusoryDouble],
      });

      expect(battle.states['a1']!.illusoryDoubleCharges, 1);
      expect(battle.states['a2']!.illusoryDoubleCharges, 0);
      expect(battle.states['b1']!.illusoryDoubleCharges, 0);
    });

    test('a defeated ally grants a holder one extra charge', () {
      final battle = Battle(
        teamA: _team('A', ['a1', 'a2', 'a3']),
        teamB: _team('B', ['b1', 'b2', 'b3']),
      );
      battle.initializeIllusoryDoubleCharges({
        'a1': [_illusoryDouble],
      });

      // a2 falls.
      battle.states['a2']!.currentHealth = 0;
      battle.checkForDefeats();

      expect(battle.states['a1']!.illusoryDoubleCharges, 2);
    });

    test('the grant is idempotent per defeat', () {
      final battle = Battle(
        teamA: _team('A', ['a1', 'a2', 'a3']),
        teamB: _team('B', ['b1', 'b2', 'b3']),
      );
      battle.initializeIllusoryDoubleCharges({
        'a1': [_illusoryDouble],
      });

      battle.states['a2']!.currentHealth = 0;
      battle.checkForDefeats();
      battle.checkForDefeats();
      battle.checkForDefeats();

      expect(battle.states['a1']!.illusoryDoubleCharges, 2,
          reason: 'one death grants exactly one charge, not one per call');

      // A second ally falls: another +1.
      battle.states['a3']!.currentHealth = 0;
      battle.checkForDefeats();
      expect(battle.states['a1']!.illusoryDoubleCharges, 3);
    });

    test('non-holders never gain charges, and enemy deaths do not count', () {
      final battle = Battle(
        teamA: _team('A', ['a1', 'a2', 'a3']),
        teamB: _team('B', ['b1', 'b2', 'b3']),
      );
      battle.initializeIllusoryDoubleCharges({
        'a1': [_illusoryDouble],
      });

      // An enemy falls - no charge for a1 (different team).
      battle.states['b1']!.currentHealth = 0;
      battle.checkForDefeats();
      expect(battle.states['a1']!.illusoryDoubleCharges, 1);

      // a2 (a non-holder) is alive; it should never accrue charges even as
      // its own ally falls.
      battle.states['a3']!.currentHealth = 0;
      battle.checkForDefeats();
      expect(battle.states['a2']!.illusoryDoubleCharges, 0);
      expect(battle.states['a1']!.illusoryDoubleCharges, 2);
    });

    test('a dead holder does not gain charges from a later ally defeat', () {
      final battle = Battle(
        teamA: _team('A', ['a1', 'a2', 'a3']),
        teamB: _team('B', ['b1', 'b2', 'b3']),
      );
      battle.initializeIllusoryDoubleCharges({
        'a1': [_illusoryDouble],
      });

      // The holder itself falls first.
      battle.states['a1']!.currentHealth = 0;
      battle.checkForDefeats();

      // Then another ally falls - the dead holder gains nothing.
      battle.states['a2']!.currentHealth = 0;
      battle.checkForDefeats();

      expect(battle.states['a1']!.illusoryDoubleCharges, 1,
          reason: 'still just the starting charge; dead holders do not accrue');
    });
  });

  group('Phase E: Karmic Bind live link (Punish, one-way)', () {
    TurnEngine engineWith(
      Map<String, CharacterBattleState> registry, {
      Random random = const FixedRandom(15),
    }) {
      final e = TurnEngine(combatEngine: CombatEngine(diceRoller: DiceRoller(random)));
      e.characterRegistry = registry;
      return e;
    }

    CharacterBattleState boundCaster(String enemyId,
        {double fraction = 0.5, int hp = 100}) {
      final c = CharacterBattleState(testCharacter(
        id: 'caster',
        stats: testStats(maxHealth: 100, armor: 0, teamSpirit: 50),
      ));
      c.currentHealth = hp;
      c.karmicBindTargetId = enemyId;
      c.statusEffects.add(StatusEffectInstance(
        definitionId: 'karmic_bind',
        remainingTurns: 3,
        data: {'karmicBindFraction': fraction},
      ));
      return c;
    }

    CharacterBattleState enemy() => CharacterBattleState(testCharacter(
          id: 'bound',
          stats: testStats(maxHealth: 100, armor: 0, defense: 0),
        ));

    CharacterBattleState attacker() => CharacterBattleState(testCharacter(
          id: 'atk',
          stats: testStats(attack: 1000, teamSpirit: 50),
        ));

    final flat10 = const DiceExpression(0, 1, flatBonus: 10);

    test('damage taken by the caster strikes the bound enemy for a fraction',
        () {
      final bound = enemy();
      final caster = boundCaster('bound');
      final atk = attacker();
      final engine = engineWith({'caster': caster, 'bound': bound});

      engine.resolveAbilityUse(
        attacker: atk,
        trigger: testTrigger(damage: flat10),
        targets: [caster],
      );

      expect(caster.currentHealth, 90, reason: 'caster took 10');
      expect(bound.currentHealth, 95, reason: 'round(10 * 0.5) = 5 propagated');
    });

    test('healing the caster also strikes the bound enemy', () {
      final bound = enemy();
      final caster = boundCaster('bound', hp: 50);
      final engine = engineWith({'caster': caster, 'bound': bound},
          random: const FixedRandom(19));

      engine.resolveAbilityUse(
        attacker: caster,
        trigger: testTrigger(
          targetAffiliation: TargetAffiliation.ally,
          includeDamage: false,
          healAmount: const DiceExpression(0, 1, flatBonus: 20),
        ),
        targets: [caster],
      );

      expect(caster.currentHealth, 70, reason: 'caster healed 20');
      expect(bound.currentHealth, 90, reason: 'round(20 * 0.5) = 10 propagated');
    });

    test('the link is one-way: damaging the bound enemy never hits the caster',
        () {
      final bound = enemy();
      final caster = boundCaster('bound');
      final atk = attacker();
      final engine = engineWith({'caster': caster, 'bound': bound});

      engine.resolveAbilityUse(
        attacker: atk,
        trigger: testTrigger(damage: flat10),
        targets: [bound],
      );

      expect(bound.currentHealth, 90, reason: 'enemy took 10');
      expect(caster.currentHealth, 100,
          reason: 'enemy carries no bind back to the caster');
    });

    test('no propagation once the karmic_bind status has expired', () {
      final bound = enemy();
      final caster = boundCaster('bound')
        ..statusEffects.removeWhere((i) => i.definitionId == 'karmic_bind');
      final atk = attacker();
      final engine = engineWith({'caster': caster, 'bound': bound});

      engine.resolveAbilityUse(
        attacker: atk,
        trigger: testTrigger(damage: flat10),
        targets: [caster],
      );

      expect(caster.currentHealth, 90);
      expect(bound.currentHealth, 100,
          reason: 'the link is gone once its status expires');
    });

    test('no crash and no propagation without a registry (standalone engine)',
        () {
      final bound = enemy();
      final caster = boundCaster('bound');
      final atk = attacker();
      // No characterRegistry set: cross-team effect is simply disabled.
      final engine =
          TurnEngine(combatEngine: CombatEngine(diceRoller: DiceRoller(const FixedRandom(15))));

      engine.resolveAbilityUse(
        attacker: atk,
        trigger: testTrigger(damage: flat10),
        targets: [caster],
      );

      expect(caster.currentHealth, 90);
      expect(bound.currentHealth, 100);
    });
  });
}

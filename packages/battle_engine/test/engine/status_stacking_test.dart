import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Item 5b: twelve status effects stack, capped at three. The other fifty
/// refresh and nothing else.
///
/// Stacking used to be the accidental default: applying an effect twice made
/// two instances, ticking separately and counting down out of step, which is
/// unreadable on a character strip and doubles a magnitude nobody priced. It
/// is a declared property now, with a maximum, and it is still **one
/// instance**: one badge, one duration, a bigger effect.
void main() {
  final catalog = StatusEffectCatalog.defaultCatalog;
  StatusEffectEngine engine() =>
      StatusEffectEngine(diceRoller: DiceRoller(Random(1)));

  StatusEffectInstance only(CharacterBattleState s) => s.statusEffects.single;

  group('what stacks, and what does not', () {
    test('exactly twelve effects stack', () {
      final stacking = [
        for (final d in catalog.all)
          if (d.stacks) d.id
      ]..sort();

      expect(stacking, [
        'acid',
        'adrenaline_rush',
        'battle_trance',
        'bleeding',
        'electrocuted',
        'fatigued',
        'hexed',
        'inspired',
        'regenerating',
        'sapped',
        'suppressed',
        'warded',
      ]);
    });

    test('none of them stacks past three', () {
      for (final d in catalog.all) {
        expect(d.maxStacks, lessThanOrEqualTo(3), reason: d.id);
        expect(d.maxStacks, greaterThanOrEqualTo(1), reason: d.id);
      }
    });

    test('the other fifty only refresh', () {
      final plain = catalog.all.where((d) => !d.stacks).toList();
      expect(plain, hasLength(50));
      for (final d in plain) {
        expect(d.maxStacks, 1, reason: d.id);
      }
    });
  });

  group('a stack is one instance, not two', () {
    test('re-applying counts a stack and leaves one badge', () {
      final e = engine();
      final state = CharacterBattleState(testCharacter());

      e.apply(state, 'bleeding');
      expect(state.statusEffects, hasLength(1));
      expect(only(state).stacks, 1);

      e.apply(state, 'bleeding');
      expect(state.statusEffects, hasLength(1),
          reason: 'two badges for one effect is the thing this replaced');
      expect(only(state).stacks, 2);
    });

    test('it stops at the cap', () {
      final e = engine();
      final state = CharacterBattleState(testCharacter());
      for (var i = 0; i < 6; i++) {
        e.apply(state, 'bleeding');
      }
      expect(only(state).stacks, 3);
    });

    test('a non-stacking effect never counts past one', () {
      final e = engine();
      final state = CharacterBattleState(testCharacter());
      e.apply(state, 'stunned');
      e.apply(state, 'stunned');
      e.apply(state, 'stunned');

      expect(state.statusEffects, hasLength(1));
      expect(only(state).stacks, 1);
    });

    test('the stacks share one duration, refreshed on re-application', () {
      final e = engine();
      final state = CharacterBattleState(testCharacter());
      e.apply(state, 'bleeding', durationOverride: 3);
      e.tickEndOfTurn(state); // 3 -> 2
      expect(only(state).remainingTurns, 2);

      e.apply(state, 'bleeding', durationOverride: 3);
      expect(only(state).stacks, 2);
      expect(only(state).remainingTurns, 3,
          reason: 'one timer for the pile, and a fresh application refreshes '
              'it');
    });
  });

  group('a stack multiplies the magnitude', () {
    test('a stat step is multiplied', () {
      final e = engine();
      final state =
          CharacterBattleState(testCharacter(stats: testStats(attack: 20)));

      e.apply(state, 'inspired');
      final one = state.effectiveStats().attack;
      e.apply(state, 'inspired');
      final two = state.effectiveStats().attack;
      e.apply(state, 'inspired');
      final three = state.effectiveStats().attack;

      expect(one, 22, reason: 'Inspired is +2 Attack');
      expect(two, 24);
      expect(three, 26);

      e.apply(state, 'inspired');
      expect(state.effectiveStats().attack, 26, reason: 'capped at three');
    });

    test('a damage tick is multiplied', () {
      final e = engine();
      final state = CharacterBattleState(testCharacter());

      e.apply(state, 'bleeding');
      final one = e.tickStartOfTurn(state).damageEvents.single.amount;
      e.apply(state, 'bleeding');
      final two = e.tickStartOfTurn(state).damageEvents.single.amount;

      expect(two, one * 2);
    });

    test('a heal tick is multiplied', () {
      final e = engine();
      final state = CharacterBattleState(testCharacter());

      e.apply(state, 'regenerating');
      final one = e.tickStartOfTurn(state).healEvents.single.amount;
      e.apply(state, 'regenerating');
      final two = e.tickStartOfTurn(state).healEvents.single.amount;

      expect(two, one * 2);
    });

    test('a Trion drain is multiplied', () {
      final e = engine();
      final state =
          CharacterBattleState(testCharacter(stats: testStats(trionCapacity: 100)));

      e.apply(state, 'sapped', sourceCharacterId: 'causer');
      final one = e.tickStartOfTurn(state).trionDrainEvents.single.amount;
      e.apply(state, 'sapped', sourceCharacterId: 'causer');
      final two = e.tickStartOfTurn(state).trionDrainEvents.single.amount;

      expect(two, one * 2);
    });

    test('a negative step goes the right way', () {
      final e = engine();
      final state =
          CharacterBattleState(testCharacter(stats: testStats(armor: 20)));

      e.apply(state, 'acid');
      final one = state.effectiveStats().armor;
      e.apply(state, 'acid');
      final two = state.effectiveStats().armor;

      expect(one, lessThan(20));
      expect(two, lessThan(one), reason: 'a second coat bites deeper');
      expect(20 - two, (20 - one) * 2);
    });

    test('a single stack changes nothing about the old numbers', () {
      // Everything below three stacks has to behave exactly as it did before
      // item 5b, or this quietly re-balanced fifty effects.
      final e = engine();
      final state =
          CharacterBattleState(testCharacter(stats: testStats(attack: 20)));
      e.apply(state, 'inspired');
      expect(state.effectiveStats().attack, 22);
    });
  });

  group('stacks and the reaction table meet', () {
    test('a reaction that names its own status stacks it', () {
      // Item 3b's "builds rather than transforms" rows (Bleeding hit by
      // Slashing, Scorched hit by Fire, Corroded taking more Acid) were
      // written as a refresh until 5b gave them somewhere to go.
      final roster = CharacterRoster.defaultRoster;
      final battle = Battle(
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
      final attacker = battle.states['kaito_reyes']!;
      final target = battle.states['marren_osei']!;
      attacker.position = BattlePosition.front;
      target.position = BattlePosition.front;
      battle.turnEngine.statusEffectEngine.apply(target, 'bleeding');
      expect(only(target).stacks, 1);

      battle.turnEngine.resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(
          id: 'test_slash',
          rangeTag: RangeTag.close,
          damageType: DamageType.slashing,
          damage: const DiceExpression(1, 2, flatBonus: 5),
        ),
        targets: [target],
      );

      final bleed = target.statusEffects
          .where((i) => i.definitionId == 'bleeding')
          .single;
      expect(bleed.stacks, 2, reason: 'the row says Bleeding builds');
    });
  });
}

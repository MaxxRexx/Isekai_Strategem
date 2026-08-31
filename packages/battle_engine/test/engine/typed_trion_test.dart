import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// A [Random] with a scripted `nextDouble`, which is what the typed-Trion roll
/// actually consumes: one draw for the Wild check, one for the weighted origin
/// pick. `nextInt` is unused here and returns 0.
class _Doubles implements Random {
  final List<double> _values;
  int _i = 0;
  _Doubles(this._values);

  @override
  double nextDouble() => _values[_i++ % _values.length];

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}

/// Item #15: typed Trion, a second resource laid over the Trion pool.
///
/// The pool answers how much a squad can do; these tokens answer what kind.
/// The design that matters is in the gate: an ordinary turn runs on the pool
/// alone, so a roll that goes against you never stops you acting. Tokens buy
/// the big plays, and only those.
void main() {
  Team teamOf(String id, {List<Character>? characters}) => Team(
        id: id,
        characters: characters ??
            [
              testCharacter(id: '$id-1'),
              testCharacter(id: '$id-2'),
              testCharacter(id: '$id-3'),
            ],
      );

  group('earning tokens', () {
    test('pays one token per living squad member, per turn', () {
      final team = teamOf('a');
      final states = [
        for (final c in team.characters) CharacterBattleState(c),
      ];
      // Every draw lands above the Wild chance, so each token is an origin.
      final engine = TurnEngine(
        combatEngine: CombatEngine(diceRoller: DiceRoller(_Doubles([0.9]))),
      );

      final gained = engine.resolveTypedTrionGain(team, states, const {});

      expect(gained, hasLength(3));
      expect(team.typedTrion.total, 3);
    });

    test('a fallen member earns nothing', () {
      final team = teamOf('a');
      final states = [
        for (final c in team.characters) CharacterBattleState(c),
      ];
      states.first.currentHealth = 0;
      final engine = TurnEngine(
        combatEngine: CombatEngine(diceRoller: DiceRoller(_Doubles([0.9]))),
      );

      expect(engine.resolveTypedTrionGain(team, states, const {}), hasLength(2));
    });

    test('a low draw pays a Wild, which is the valve', () {
      final team = teamOf('a');
      final states = [
        for (final c in team.characters) CharacterBattleState(c),
      ];
      // 0.0 is below the default 0.20 Wild chance every time.
      final engine = TurnEngine(
        combatEngine: CombatEngine(diceRoller: DiceRoller(_Doubles([0.0]))),
      );

      final gained = engine.resolveTypedTrionGain(team, states, const {});

      expect(gained, everyElement(TrionTokenType.wild));
    });

    test('the roll leans toward the origins the squad actually runs', () {
      final team = teamOf('a');
      final states = [
        for (final c in team.characters) CharacterBattleState(c),
      ];
      // A squad built entirely out of Afflict abilities. With the uniform
      // floor at 1 per origin and 9 Afflict abilities, Afflict holds 12 of the
      // 16 weight, so a draw at 60% of the way through lands there and not on
      // physical, which sits first and would win an unweighted roll.
      final equipped = {
        for (final s in states)
          s.combatantId: [
            for (var i = 0; i < 3; i++)
              testTrigger(id: '${s.combatantId}-$i', originTag: OriginTag.afflict),
          ],
      };
      final engine = TurnEngine(
        combatEngine: CombatEngine(diceRoller: DiceRoller(_Doubles([0.9, 0.6]))),
      );

      final gained = engine.resolveTypedTrionGain(team, states, equipped);

      expect(gained, everyElement(TrionTokenType.afflict));
    });
  });

  group('the reserve', () {
    test('Wild pays for any origin, but an exact match is spent first', () {
      final reserve = TypedTrionReserve({
        TrionTokenType.mental: 1,
        TrionTokenType.wild: 1,
      });

      expect(reserve.canPay(OriginTag.mental), isTrue);
      expect(reserve.spend(OriginTag.mental), isTrue);
      // The Wild survived, because the exact token went first.
      expect(reserve[TrionTokenType.wild], 1);
      expect(reserve[TrionTokenType.mental], 0);

      // Now only the Wild is left, and it covers an origin it does not match.
      expect(reserve.spend(OriginTag.physical), isTrue);
      expect(reserve.total, 0);
      expect(reserve.spend(OriginTag.physical), isFalse);
    });
  });

  group('the signature gate', () {
    late Battle battle;
    late CharacterBattleState actor;

    setUp(() {
      final teamA = teamOf('a');
      battle = Battle(teamA: teamA, teamB: teamOf('b'));
      actor = battle.statesOf(battle.teamA).first;
      battle.teamA.trionPool.gain(1000);
      // A second action in one turn is only possible at all on a Full Arms
      // Trigger turn, so that is the turn the gate is about.
      actor.fatTriggeredThisTurn = true;
    });

    test('an ordinary first ability costs no token', () {
      expect(battle.teamA.typedTrion.total, 0);

      expect(
        battle.turnEngine.canUseAbility(actor, testTrigger(id: 'plain')),
        isTrue,
        reason: 'an empty reserve must never stop a squad acting at all',
      );
    });

    test('a second action in a turn costs a token', () {
      final first = testTrigger(id: 'first');
      expect(battle.turnEngine.useAbility(actor, first, battle.teamA.trionPool),
          isTrue);

      final second = testTrigger(id: 'second', originTag: OriginTag.energy);
      expect(battle.turnEngine.requiresTypedTrion(actor, second), isTrue);
      expect(battle.turnEngine.canUseAbility(actor, second), isFalse);

      battle.teamA.typedTrion.gain(TrionTokenType.energy);
      expect(battle.turnEngine.canUseAbility(actor, second), isTrue);
    });

    test('paying for the extra action spends the token', () {
      battle.turnEngine
          .useAbility(actor, testTrigger(id: 'first'), battle.teamA.trionPool);
      battle.teamA.typedTrion.gain(TrionTokenType.wild);

      final second = testTrigger(id: 'second', originTag: OriginTag.afflict);
      expect(
          battle.turnEngine
              .useAbility(actor, second, battle.teamA.trionPool),
          isTrue);

      expect(battle.teamA.typedTrion.total, 0);
    });

    test('a use it cannot pay for spends no Trion either', () {
      battle.turnEngine
          .useAbility(actor, testTrigger(id: 'first'), battle.teamA.trionPool);
      final before = battle.teamA.trionPool.current;

      final second = testTrigger(id: 'second', trionCost: 5);
      expect(
          battle.turnEngine
              .useAbility(actor, second, battle.teamA.trionPool),
          isFalse);

      expect(battle.teamA.trionPool.current, before,
          reason: 'a use that cannot afford both must spend neither');
    });
  });
}

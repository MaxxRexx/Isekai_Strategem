import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Item #1: positions and the distance rules underneath the range bands.
///
/// The rules these lock in are the whole reason position is a decision: the
/// two squads face each other across a gap, so distance to an enemy adds and
/// distance to an ally subtracts, and each band is a window with a minimum
/// as well as a maximum.
void main() {
  group('distance', () {
    test('enemies add, because you face each other across the gap', () {
      expect(
        BattleDistance.betweenEnemies(BattlePosition.front, BattlePosition.front),
        0,
        reason: 'both pressed all the way forward is a knife fight',
      );
      expect(
        BattleDistance.betweenEnemies(BattlePosition.front, BattlePosition.back),
        2,
        reason: 'a front attacker cannot reach a back sniper with a Close hit',
      );
      expect(
        BattleDistance.betweenEnemies(BattlePosition.back, BattlePosition.back),
        4,
        reason: 'both hanging all the way back is a sniper duel',
      );
    });

    test('allies subtract, because you are on the same side', () {
      expect(
        BattleDistance.betweenAllies(BattlePosition.front, BattlePosition.front),
        0,
      );
      expect(
        BattleDistance.betweenAllies(BattlePosition.front, BattlePosition.back),
        2,
        reason: 'opposite ends of your own formation',
      );
      expect(
        BattleDistance.betweenAllies(BattlePosition.back, BattlePosition.front),
        2,
        reason: 'symmetric',
      );
    });

    test('hanging back moves you away from the enemy but towards your own '
        'back line, which is the tension the whole system rests on', () {
      // Stepping from Front to Back widens the gap to an enemy...
      final nearEnemy = BattleDistance.betweenEnemies(
          BattlePosition.front, BattlePosition.middle);
      final farEnemy = BattleDistance.betweenEnemies(
          BattlePosition.back, BattlePosition.middle);
      expect(farEnemy, greaterThan(nearEnemy));

      // ...while closing it to an ally who is already at the back.
      final nearAlly =
          BattleDistance.betweenAllies(BattlePosition.back, BattlePosition.back);
      final farAlly = BattleDistance.betweenAllies(
          BattlePosition.front, BattlePosition.back);
      expect(nearAlly, lessThan(farAlly));
    });
  });

  group('reach windows', () {
    test('each band has a minimum as well as a maximum', () {
      expect(RangeTag.close.minDistance, 0);
      expect(RangeTag.close.maxDistance, 1);
      expect(RangeTag.mid.minDistance, 1);
      expect(RangeTag.mid.maxDistance, 3);
      expect(RangeTag.long.minDistance, 2);
      expect(RangeTag.long.maxDistance, 4);
    });

    test('a sniper caught in a scrum has no shot', () {
      expect(RangeTag.long.reaches(0), isFalse);
      expect(RangeTag.long.reaches(1), isFalse);
      expect(RangeTag.long.reaches(2), isTrue);
    });

    test('a knife cannot cross the field', () {
      expect(RangeTag.close.reaches(1), isTrue);
      expect(RangeTag.close.reaches(2), isFalse);
      expect(RangeTag.close.reaches(4), isFalse);
    });

    test('every distance leaves at least one band available', () {
      for (var d = 0; d <= BattleDistance.maxEnemyDistance; d++) {
        expect(RangeTag.values.any((b) => b.reaches(d)), isTrue,
            reason: 'distance $d is a dead zone, which would strand a squad');
      }
    });

    test('the extremes commit you to one band, the middle gives a choice', () {
      List<RangeTag> at(int d) =>
          RangeTag.values.where((b) => b.reaches(d)).toList();
      expect(at(0), [RangeTag.close]);
      expect(at(1), [RangeTag.close, RangeTag.mid]);
      expect(at(2), [RangeTag.mid, RangeTag.long]);
      expect(at(3), [RangeTag.mid, RangeTag.long]);
      expect(at(4), [RangeTag.long]);
    });
  });

  group('stepping between positions', () {
    test('Reposition moves exactly one step', () {
      expect(BattlePosition.front.adjacent, [BattlePosition.middle]);
      expect(BattlePosition.middle.adjacent,
          [BattlePosition.front, BattlePosition.back]);
      expect(BattlePosition.back.adjacent, [BattlePosition.middle]);
    });

    test('the ends of the line have nowhere further to go', () {
      expect(BattlePosition.front.forward, isNull);
      expect(BattlePosition.back.backward, isNull);
    });
  });

  group('the engine reads positions', () {
    CharacterBattleState stateAt(String id, BattlePosition position) =>
        CharacterBattleState(testCharacter(id: id), position: position);

    test('a character defaults to Middle so older setups still work', () {
      expect(CharacterBattleState(testCharacter()).position,
          BattlePosition.middle);
    });

    test('canReach gates an ability on the distance to its target', () {
      final engine = TurnEngine();
      final attacker = stateAt('a', BattlePosition.front);
      final enemy = stateAt('b', BattlePosition.back);
      // Not teammates, so they are enemies: 0 + 2 = 2.
      expect(engine.distanceBetween(attacker, enemy), 2);

      final closeHit = testTrigger(id: 'close', rangeTag: RangeTag.close);
      final longHit = testTrigger(id: 'long', rangeTag: RangeTag.long);
      expect(engine.canReach(attacker, enemy, closeHit), isFalse,
          reason: 'a Close ability cannot reach the enemy back line');
      expect(engine.canReach(attacker, enemy, longHit), isTrue,
          reason: 'a Long ability is exactly how you reach it');
    });

    test('a self-targeted ability always reaches, whatever band it carries',
        () {
      final engine = TurnEngine();
      final self = stateAt('a', BattlePosition.back);
      final selfBuff = testTrigger(
        id: 'buff',
        rangeTag: RangeTag.long,
        targetAffiliation: TargetAffiliation.self,
      );
      expect(engine.canReach(self, self, selfBuff), isTrue);
    });

    test('canTarget applies the range band only when given the ability', () {
      final engine = TurnEngine();
      final attacker = stateAt('a', BattlePosition.front);
      final enemy = stateAt('b', BattlePosition.back);
      final closeHit = testTrigger(id: 'close', rangeTag: RangeTag.close);

      expect(engine.canTarget(attacker, enemy), isTrue,
          reason: 'with no ability in mind the answer stays range-agnostic');
      expect(engine.canTarget(attacker, enemy, trigger: closeHit), isFalse,
          reason: 'given the ability, the band applies');
    });
  });

  group('area attacks catch a position, not any three bodies', () {
    // Both squads need real teammate wiring for the ally/enemy split, so
    // these go through a Battle rather than bare states.
    Battle twoSquads() {
      final roster = CharacterRoster.defaultRoster;
      return Battle(
        teamA: Team(id: 'a', characters: [
          roster['kaito_reyes'],
          roster['vela_ashworth'],
          roster['dross'],
        ]),
        teamB: Team(id: 'b', characters: [
          roster['marren_osei'],
          roster['ilona_vance'],
          roster['bastian_cole'],
        ]),
      );
    }

    test('only enemies standing with the aimed-at target are caught', () {
      final battle = twoSquads();
      final attacker = battle.states['kaito_reyes']!
        ..position = BattlePosition.front;
      final together1 = battle.states['marren_osei']!
        ..position = BattlePosition.front;
      final together2 = battle.states['ilona_vance']!
        ..position = BattlePosition.front;
      final apart = battle.states['bastian_cole']!
        ..position = BattlePosition.back;

      final blast = testTrigger(
        id: 'blast',
        rangeTag: RangeTag.close,
        attackSubtype: AttackSubtype.aoe,
        targetCount: 3,
        damage: const DiceExpression(1, 4, flatBonus: 40),
      );

      final result = battle.turnEngine.resolveAbilityUse(
        attacker: attacker,
        trigger: blast,
        targets: [together1, together2, apart],
      );

      final hit = result.targetResults.map((r) => r.targetCharacterId).toSet();
      expect(hit, containsAll(['marren_osei', 'ilona_vance']));
      expect(hit, isNot(contains('bastian_cole')),
          reason: 'someone standing somewhere else is not in the blast');
    });

    test('spreading out is a real defence against area damage', () {
      final clumped = twoSquads();
      final spread = twoSquads();
      final blast = testTrigger(
        id: 'blast',
        rangeTag: RangeTag.close,
        attackSubtype: AttackSubtype.aoe,
        targetCount: 3,
        damage: const DiceExpression(1, 4, flatBonus: 40),
      );

      int caught(Battle battle, List<BattlePosition> enemyPositions) {
        final attacker = battle.states['kaito_reyes']!
          ..position = BattlePosition.front;
        final enemies = ['marren_osei', 'ilona_vance', 'bastian_cole'];
        for (var i = 0; i < enemies.length; i++) {
          battle.states[enemies[i]]!.position = enemyPositions[i];
        }
        return battle.turnEngine
            .resolveAbilityUse(
              attacker: attacker,
              trigger: blast,
              targets: enemies.map((e) => battle.states[e]!).toList(),
            )
            .targetResults
            .length;
      }

      final clumpedCount = caught(clumped, [
        BattlePosition.front,
        BattlePosition.front,
        BattlePosition.front,
      ]);
      final spreadCount = caught(spread, [
        BattlePosition.front,
        BattlePosition.middle,
        BattlePosition.back,
      ]);
      expect(clumpedCount, 3);
      expect(spreadCount, 1);
      expect(spreadCount, lessThan(clumpedCount));
    });
  });

  group('protection needs proximity', () {
    test('a guardian too far away cannot step in front of an ally', () {
      final roster = CharacterRoster.defaultRoster;
      final battle = Battle(
        teamA: Team(id: 'a', characters: [
          roster['kaito_reyes'],
          roster['vela_ashworth'],
          roster['dross'],
        ]),
        teamB: Team(id: 'b', characters: [
          roster['sable_whitlock'],
          roster['marren_osei'],
          roster['ilona_vance'],
        ]),
      );
      final attacker = battle.states['kaito_reyes']!
        ..position = BattlePosition.front;
      final guardian = battle.states['sable_whitlock']!
        ..position = BattlePosition.back;
      final protectee = battle.states['marren_osei']!
        ..position = BattlePosition.front;

      // Close Range, because attacker and protectee are both at Front and
      // that is distance 0, which only Close reaches.
      final hit = testTrigger(
        id: 'hit',
        rangeTag: RangeTag.close,
        damage: const DiceExpression(1, 4, flatBonus: 30),
      );
      battle.turnEngine.resolveAbilityUse(
        attacker: attacker,
        trigger: hit,
        targets: [protectee],
      );

      expect(guardian.currentHealth, guardian.character.baseStats.maxHealth,
          reason: 'Sable is two positions away and cannot intercept');
      expect(protectee.currentHealth,
          lessThan(protectee.character.baseStats.maxHealth));
      expect(guardian.perkChargeUsed, isFalse,
          reason: 'a redirect that cannot happen must not burn the charge');
    });

    test('a guardian standing with the ally does intercept', () {
      final roster = CharacterRoster.defaultRoster;
      final battle = Battle(
        teamA: Team(id: 'a', characters: [
          roster['kaito_reyes'],
          roster['vela_ashworth'],
          roster['dross'],
        ]),
        teamB: Team(id: 'b', characters: [
          roster['sable_whitlock'],
          roster['marren_osei'],
          roster['ilona_vance'],
        ]),
      );
      final attacker = battle.states['kaito_reyes']!
        ..position = BattlePosition.front;
      final guardian = battle.states['sable_whitlock']!
        ..position = BattlePosition.front;
      final protectee = battle.states['marren_osei']!
        ..position = BattlePosition.front;

      final hit = testTrigger(
        id: 'hit',
        rangeTag: RangeTag.close,
        damage: const DiceExpression(1, 4, flatBonus: 30),
      );
      battle.turnEngine.resolveAbilityUse(
        attacker: attacker,
        trigger: hit,
        targets: [protectee],
      );

      expect(guardian.currentHealth,
          lessThan(guardian.character.baseStats.maxHealth),
          reason: 'Sable is standing right there and takes it instead');
      expect(protectee.currentHealth, protectee.character.baseStats.maxHealth);
    });
  });
}

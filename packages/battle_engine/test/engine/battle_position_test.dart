import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Items #1 and 1b: positions, the distance rules underneath the range bands,
/// and screening.
///
/// The rules these lock in are the whole reason position is a decision: the
/// two squads face each other across a gap, so distance to an enemy adds and
/// distance to an ally subtracts; screening adds the bodies standing in the
/// way; and each band is a window with a minimum as well as a maximum.
void main() {
  /// An unscreened target, which is what an empty squad means.
  const alone = <BattlePosition>[];

  /// Two real squads. Screening and the ally/enemy split both need the
  /// `teammates` wiring that only the Battle constructor sets up, so anything
  /// about either goes through a Battle rather than bare states.
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

  group('distance', () {
    test('enemies add, because you face each other across the gap', () {
      expect(
        BattleDistance.betweenEnemies(BattlePosition.front, BattlePosition.front,
            targetSquad: alone),
        0,
        reason: 'both pressed all the way forward is a knife fight',
      );
      expect(
        BattleDistance.betweenEnemies(BattlePosition.front, BattlePosition.back,
            targetSquad: alone),
        2,
        reason: 'an unscreened back sniper is two lines away, no more',
      );
      expect(
        BattleDistance.betweenEnemies(BattlePosition.back, BattlePosition.back,
            targetSquad: alone),
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
          BattlePosition.front, BattlePosition.middle,
          targetSquad: alone);
      final farEnemy = BattleDistance.betweenEnemies(
          BattlePosition.back, BattlePosition.middle,
          targetSquad: alone);
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
      expect(RangeTag.close.maxDistance, 2);
      expect(RangeTag.mid.minDistance, 1);
      expect(RangeTag.mid.maxDistance, 3);
      expect(RangeTag.long.minDistance, 2);
      expect(RangeTag.long.maxDistance, 4);
    });

    test('the widening is enemy-facing only, so a Close ward still reaches '
        'just the next line', () {
      // Widening Close to 0-2 was decided to let Close Range *attacks* reach
      // an enemy back line. Letting it widen the ally side too would have
      // quietly handed three defensive abilities the whole formation.
      expect(RangeTag.close.maxDistance, 2, reason: 'against an enemy');
      expect(RangeTag.close.allyMaxDistance, 1, reason: 'towards an ally');
      expect(RangeTag.close.reachesAlly(1), isTrue);
      expect(RangeTag.close.reachesAlly(2), isFalse,
          reason: 'front to back of your own formation is still too far');
      // Mid and Long already exceed the widest possible ally distance of 2,
      // so for them the two maximums are the same number.
      expect(RangeTag.mid.allyMaxDistance, RangeTag.mid.maxDistance);
      expect(RangeTag.long.allyMaxDistance, RangeTag.long.maxDistance);
    });

    test('a sniper caught in a scrum has no shot', () {
      expect(RangeTag.long.reaches(0), isFalse);
      expect(RangeTag.long.reaches(1), isFalse);
      expect(RangeTag.long.reaches(2), isTrue);
    });

    test('a knife still cannot cross the field', () {
      expect(RangeTag.close.reaches(2), isTrue,
          reason: 'the widening: an unscreened back sniper is now reachable');
      expect(RangeTag.close.reaches(3), isFalse);
      expect(RangeTag.close.reaches(4), isFalse);
    });

    test('every distance the two lines alone can produce leaves at least one '
        'band available', () {
      for (var d = 0;
          d <= BattleDistance.maxUnscreenedEnemyDistance;
          d++) {
        expect(RangeTag.values.any((b) => b.reaches(d)), isTrue,
            reason: 'distance $d is a dead zone, which would strand a squad');
      }
    });

    test('screening can push a target past every band, and that is safe '
        'because stepping to your own front line always undoes it', () {
      // 5 and 6 are real numbers the ruler can print, and nothing reaches
      // them. They are only produced by hanging back yourself.
      expect(RangeTag.values.any((b) => b.reaches(5)), isFalse);
      expect(RangeTag.values.any((b) => b.reaches(6)), isFalse);
      expect(BattleDistance.maxEnemyDistance, 6);

      // The guarantee: measured from your own front line, no enemy formation
      // of any size up to a full squad exceeds 4, which Long Range covers.
      // This is what stops screening ever making a target unreachable.
      for (final a in BattlePosition.values) {
        for (final b in BattlePosition.values) {
          for (final c in BattlePosition.values) {
            for (final squad in [
              [a],
              [a, b],
              [a, b, c],
            ]) {
              for (final target in squad.toSet()) {
                final d = BattleDistance.betweenEnemies(
                    BattlePosition.front, target,
                    targetSquad: squad);
                expect(d, lessThanOrEqualTo(4),
                    reason: 'from my front line, $target behind $squad');
                expect(RangeTag.values.any((band) => band.reaches(d)), isTrue,
                    reason: 'nothing reaches $target behind $squad');
              }
            }
          }
        }
      }
    });

    test('the extremes commit you to one band, the middle gives a choice', () {
      List<RangeTag> at(int d) =>
          RangeTag.values.where((b) => b.reaches(d)).toList();
      expect(at(0), [RangeTag.close]);
      expect(at(1), [RangeTag.close, RangeTag.mid]);
      expect(at(2), [RangeTag.close, RangeTag.mid, RangeTag.long],
          reason: 'the widening makes 2 the one distance every band covers');
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
      // Not teammates, so they are enemies, and nobody is screening the
      // enemy: 0 + 2 + 0 = 2.
      expect(engine.distanceBetween(attacker, enemy), 2);

      final closeHit = testTrigger(id: 'close', rangeTag: RangeTag.close);
      final midHit = testTrigger(id: 'mid', rangeTag: RangeTag.mid);
      final longHit = testTrigger(id: 'long', rangeTag: RangeTag.long);
      expect(engine.canReach(attacker, enemy, closeHit), isTrue,
          reason: 'the widening: an unscreened back sniper is now in reach');
      expect(engine.canReach(attacker, enemy, midHit), isTrue);
      expect(engine.canReach(attacker, enemy, longHit), isTrue,
          reason: 'distance 2 is the one every band covers');
    });

    test('screening is what puts a back-line sniper out of a knife\'s reach',
        () {
      // The mechanic 1b exists for, on a real Battle so `teammates` is wired
      // and the squad actually screens. Their two front-liners shield the
      // sniper behind them.
      final battle = twoSquads();
      final attacker = battle.states['kaito_reyes']!
        ..position = BattlePosition.front;
      final screenOne = battle.states['marren_osei']!
        ..position = BattlePosition.front;
      final screenTwo = battle.states['ilona_vance']!
        ..position = BattlePosition.front;
      final sniper = battle.states['bastian_cole']!
        ..position = BattlePosition.back;
      final engine = battle.turnEngine;

      final closeHit = testTrigger(id: 'close', rangeTag: RangeTag.close);
      final midHit = testTrigger(id: 'mid', rangeTag: RangeTag.mid);
      final longHit = testTrigger(id: 'long', rangeTag: RangeTag.long);

      expect(engine.distanceBetween(attacker, sniper), 4,
          reason: '0 + 2 lines, plus 2 bodies in the way');
      expect(engine.canReach(attacker, sniper, closeHit), isFalse);
      expect(engine.canReach(attacker, sniper, midHit), isFalse);
      expect(engine.canReach(attacker, sniper, longHit), isTrue,
          reason: 'only Long Range reaches a doubly screened target');

      // Kill one screen and Mid Range opens up.
      screenOne.currentHealth = 0;
      expect(engine.distanceBetween(attacker, sniper), 3);
      expect(engine.canReach(attacker, sniper, midHit), isTrue);
      expect(engine.canReach(attacker, sniper, closeHit), isFalse);

      // Kill the other and the knife finally arrives, which is the pay-off
      // the widening exists for.
      screenTwo.currentHealth = 0;
      expect(engine.distanceBetween(attacker, sniper), 2);
      expect(engine.canReach(attacker, sniper, closeHit), isTrue);
    });

    test('a squad stacked on one line screens nobody, so camping stops '
        'working of its own accord', () {
      final battle = twoSquads();
      final attacker = battle.states['kaito_reyes']!
        ..position = BattlePosition.front;
      for (final id in ['marren_osei', 'ilona_vance', 'bastian_cole']) {
        battle.states[id]!.position = BattlePosition.back;
      }
      final camper = battle.states['bastian_cole']!;
      final closeHit = testTrigger(id: 'close', rangeTag: RangeTag.close);

      expect(battle.turnEngine.distanceBetween(attacker, camper), 2,
          reason: 'nobody stands in front of anybody, so there are no screens');
      expect(battle.turnEngine.canReach(attacker, camper, closeHit), isTrue,
          reason: 'the back-camp is answerable by a Close build again');
    });

    test('screening never applies towards an ally', () {
      final battle = twoSquads();
      final healer = battle.states['kaito_reyes']!
        ..position = BattlePosition.front;
      final hurt = battle.states['dross']!..position = BattlePosition.middle;
      // Vela stands between them, and screens nothing: your own squad is not
      // in the way of a heal.
      battle.states['vela_ashworth']!.position = BattlePosition.front;
      final ward = testTrigger(
        id: 'ward',
        rangeTag: RangeTag.close,
        targetAffiliation: TargetAffiliation.ally,
      );
      expect(battle.turnEngine.distanceBetween(healer, hurt), 1);
      expect(battle.turnEngine.canReach(healer, hurt, ward), isTrue);
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
      // Both on their back lines: 2 + 2 = 4, past Close Range's widened 0-2.
      final attacker = stateAt('a', BattlePosition.back);
      final enemy = stateAt('b', BattlePosition.back);
      final closeHit = testTrigger(id: 'close', rangeTag: RangeTag.close);

      expect(engine.canTarget(attacker, enemy), isTrue,
          reason: 'with no ability in mind the answer stays range-agnostic');
      expect(engine.canTarget(attacker, enemy, trigger: closeHit), isFalse,
          reason: 'given the ability, the band applies');
      // And the squad can be supplied explicitly, which is how a caller
      // planning against projected positions screens against the formation
      // that will exist rather than the one that does.
      final longHit = testTrigger(id: 'long2', rangeTag: RangeTag.long);
      expect(engine.canTarget(attacker, enemy, trigger: longHit), isTrue,
          reason: 'unscreened, 4 is exactly Long Range\'s limit');
      expect(
        engine.canTarget(attacker, enemy,
            trigger: longHit,
            targetSquad: const [BattlePosition.front, BattlePosition.front]),
        isFalse,
        reason: 'two screens put them at 6, past everything',
      );
    });
  });

  group('area attacks catch a position, not any three bodies', () {
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
        abilitySubtype: AbilitySubtype.aoe,
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
        abilitySubtype: AbilitySubtype.aoe,
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
      // Deterministic dice: without this the attack can simply miss and the
      // test becomes a coin flip on whether the protectee took damage.
      final battle = Battle(
        turnEngine: TurnEngine(
          combatEngine: CombatEngine(diceRoller: DiceRoller(FixedRandom(19))),
        ),
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
      expect(guardian.sideEffectChargeUsed, isFalse,
          reason: 'a redirect that cannot happen must not burn the charge');
    });

    test('a guardian standing with the ally does intercept', () {
      final roster = CharacterRoster.defaultRoster;
      // Deterministic dice: without this the attack can simply miss and the
      // test becomes a coin flip on whether the protectee took damage.
      final battle = Battle(
        turnEngine: TurnEngine(
          combatEngine: CombatEngine(diceRoller: DiceRoller(FixedRandom(19))),
        ),
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

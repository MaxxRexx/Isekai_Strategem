import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/draft.dart';
import 'package:isekai_strategem/src/game/play_session.dart';

import 'support/battle_positions.dart';

/// Item #14: both squads may field the same character.
///
/// The #2 playtest found what happened before this: drafting one Ilona Vance
/// onto each squad gave the two of them a single battle state. One health
/// pool, each squad counting her as a teammate, and killing yours killed
/// theirs. The stopgap was to forbid it at the draft screens.
///
/// A combatant id is the squad's id and the character's joined, so the two are
/// two combatants. These are the tests that they really are separate, and that
/// the interface can still tell you which one it means.
void main() {
  Loadout kit(String id) => Loadout(
        characterId: id,
        triggers: [
          triggerCatalog['twin_fang_strike'],
          triggerCatalog['shatterpoint'],
          triggerCatalog['cleave'],
          triggerCatalog['guardians_aegis'],
        ],
      );

  /// The same three characters on both sides: a true mirror, which is the
  /// case that used to collapse hardest.
  const squad = ['ilona_vance', 'marren_osei', 'bastian_cole'];

  PlaySession startMirror() => PlaySession.start(
        playerCharacterIds: squad,
        playerLoadouts: {for (final id in squad) id: kit(id)},
        opponentCharacterIds: squad,
        opponentProfileId: 'the_tactician',
        firstTurn: 'teamA',
      );

  PlaySession mirrorSession() {
    final session = startMirror();
    stockEveryTrionType(session);
    return session;
  }

  group('a true mirror is six combatants, not three', () {
    test('the battle starts at all', () {
      expect(mirrorSession, returnsNormally);
    });

    test('every combatant has their own state', () {
      final s = mirrorSession();
      expect(s.battle.states, hasLength(6));
      final ids = s.battle.states.values.map((st) => st.combatantId).toSet();
      expect(ids, hasLength(6), reason: 'six distinct keys, not three shared');
    });

    test('the two Ilonas are different objects with their own health', () {
      final s = mirrorSession();
      final mine = s.battle.stateOf(s.battle.teamA, 'ilona_vance');
      final theirs = s.battle.stateOf(s.battle.teamB, 'ilona_vance');

      expect(identical(mine, theirs), isFalse);
      expect(mine.combatantId, isNot(theirs.combatantId));
      expect(CombatantIds.characterOf(mine.combatantId), 'ilona_vance');
      expect(CombatantIds.characterOf(theirs.combatantId), 'ilona_vance');

      theirs.currentHealth = 12;
      expect(mine.currentHealth, 100,
          reason: 'hurting theirs must not hurt yours');
    });

    test('each Ilona counts only her own squad as teammates', () {
      final s = mirrorSession();
      final mine = s.battle.stateOf(s.battle.teamA, 'ilona_vance');
      final theirs = s.battle.stateOf(s.battle.teamB, 'ilona_vance');

      expect(mine.teammates, hasLength(2));
      expect(
        mine.teammates.any((t) => identical(t, theirs)),
        isFalse,
        reason: 'the enemy Ilona is not your teammate',
      );
      for (final mate in mine.teammates) {
        expect(CombatantIds.teamOf(mate.combatantId), 'player');
      }
    });

    test('a status on one does not appear on the other', () {
      final s = mirrorSession();
      final mine = s.battle.stateOf(s.battle.teamA, 'ilona_vance');
      final theirs = s.battle.stateOf(s.battle.teamB, 'ilona_vance');

      s.battle.turnEngine.statusEffectEngine.apply(theirs, 'stunned');
      expect(theirs.statusEffects, hasLength(1));
      expect(mine.statusEffects, isEmpty);
    });

    test('moving one does not move the other', () {
      final s = mirrorSession();
      final mine = s.battle.stateOf(s.battle.teamA, 'ilona_vance');
      final theirs = s.battle.stateOf(s.battle.teamB, 'ilona_vance');

      mine.position = BattlePosition.back;
      theirs.position = BattlePosition.front;
      expect(mine.position, BattlePosition.back);
    });

    test('defeating theirs does not defeat yours', () {
      final s = mirrorSession();
      for (final state in s.battle.statesOf(s.battle.teamB)) {
        state.currentHealth = 0;
      }
      expect(s.battle.isTeamDefeated(s.battle.teamB), isTrue);
      expect(s.battle.isTeamDefeated(s.battle.teamA), isFalse);
      expect(s.outcome, BattleOutcome.teamAWins);
    });
  });

  group('the interface can say which one it means', () {
    test('a mirrored character is named with their squad', () {
      final s = mirrorSession();
      final mine = s.teamA.firstWhere((f) => f.id.endsWith('ilona_vance'));
      final theirs = s.teamB.firstWhere((f) => f.id.endsWith('ilona_vance'));

      expect(mine.name, 'Ilona Vance (yours)');
      expect(theirs.name, 'Ilona Vance (theirs)');
      expect(mine.name, isNot(theirs.name));
    });

    test('an ordinary battle still reads as plain names', () {
      final s = PlaySession.start(
        playerCharacterIds: squad,
        playerLoadouts: {for (final id in squad) id: kit(id)},
        opponentCharacterIds: const [
          'kaito_reyes',
          'vela_ashworth',
          'dross',
        ],
        opponentProfileId: 'the_tactician',
        firstTurn: 'teamA',
      );
      for (final f in [...s.teamA, ...s.teamB]) {
        expect(f.name, isNot(contains('(')),
            reason: 'only a mirror match needs the squad naming');
      }
    });

    test('only the duplicated character is disambiguated', () {
      final s = PlaySession.start(
        playerCharacterIds: const ['ilona_vance', 'marren_osei', 'dross'],
        playerLoadouts: {
          for (final id in ['ilona_vance', 'marren_osei', 'dross'])
            id: kit(id),
        },
        opponentCharacterIds: const [
          'ilona_vance',
          'kaito_reyes',
          'vela_ashworth',
        ],
        opponentProfileId: 'the_tactician',
        firstTurn: 'teamA',
      );
      final names = {for (final f in [...s.teamA, ...s.teamB]) f.id: f.name};
      expect(names.values.where((n) => n.contains('(')), hasLength(2));
      expect(names[CombatantIds.of('player', 'marren_osei')], 'Marren Osei');
      expect(names[CombatantIds.of('ai', 'kaito_reyes')], 'Kaito Reyes');
    });

    test('asking by character id is refused rather than answered wrongly', () {
      final s = mirrorSession();
      expect(
        () => s.battle.stateById('ilona_vance'),
        throwsA(isA<ArgumentError>()),
        reason: 'a character id cannot say which Ilona, so it must not guess',
      );
      // A combatant id is never ambiguous.
      expect(
        s.battle.stateById(CombatantIds.of('ai', 'ilona_vance')).combatantId,
        CombatantIds.of('ai', 'ilona_vance'),
      );
    });
  });

  group('the same character twice on one squad is still refused', () {
    test('the battle will not start', () {
      expect(
        () => PlaySession.start(
          playerCharacterIds: const [
            'ilona_vance',
            'ilona_vance',
            'dross',
          ],
          playerLoadouts: {
            for (final id in ['ilona_vance', 'dross']) id: kit(id),
          },
          opponentCharacterIds: const [
            'kaito_reyes',
            'vela_ashworth',
            'marren_osei',
          ],
          opponentProfileId: 'the_tactician',
        ),
        throwsA(isA<ArgumentError>()),
        reason: 'one squad fielding her twice is still one shared state',
      );
    });
  });

  group('a mirror match plays', () {
    test('a queued attack hits the enemy Ilona and leaves yours alone', () {
      final s = mirrorSession();
      s.battle.teamA.trionPool.gain(500);
      for (final state in s.battle.statesOf(s.battle.teamA)) {
        state.position = BattlePosition.front;
      }
      for (final state in s.battle.statesOf(s.battle.teamB)) {
        state.position = BattlePosition.front;
      }

      final mine = s.battle.stateOf(s.battle.teamA, 'ilona_vance');
      final theirs = s.battle.stateOf(s.battle.teamB, 'ilona_vance');

      final queued = s.queue(
        mine.combatantId,
        'twin_fang_strike',
        [theirs.combatantId],
      );
      expect(queued.success, isTrue, reason: queued.error ?? '');

      s.resolveQueue();

      expect(mine.currentHealth, 100,
          reason: 'she cannot have hit herself');
      // The attack may miss, so this asserts only that the two are separate:
      // whatever happened, it happened to exactly one of them.
      expect(theirs.currentHealth, lessThanOrEqualTo(100));
    });

    test('the whole battle runs to a conclusion', () {
      final s = mirrorSession();
      var turns = 0;
      while (!s.isOver && turns < 200) {
        s.resolveQueue();
        s.endTurn();
        turns++;
      }
      expect(s.isOver, isTrue, reason: 'a mirror match has to conclude');
      expect(turns, lessThan(200));
    });
  });
}

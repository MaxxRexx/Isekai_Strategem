import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Item #2: Bail Out, contested.
///
/// An operator reduced to zero does not die on the spot. Their body stays on
/// the board for one contested turn: left alone the operator is recalled and
/// the squad banks Trion Salvage, hit once the body is destroyed and the
/// Salvage is gone. Both halves are decisions, which is the whole point of the
/// item and the reason the first draft of it was thrown away.
void main() {
  /// Two real squads with deterministic dice, because half of these tests turn
  /// on an attack actually landing.
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
        trionPool: TrionPool(current: 100, cap: 500),
      ),
      teamB: Team(
        id: 'b',
        characters: [
          roster['marren_osei'],
          roster['ilona_vance'],
          roster['bastian_cole'],
        ],
        trionPool: TrionPool(current: 100, cap: 500),
      ),
    );
  }

  /// Drops [id] to zero the way an attack would, so the Bail Out rules run.
  CharacterBattleState drop(Battle battle, String id) {
    final state = battle.states[id]!;
    state.currentHealth = 0;
    battle.turnEngine.noteHealthChanged(state);
    return state;
  }

  group('entering the window', () {
    test('a drop opens a window rather than ending the character', () {
      final battle = twoSquads();
      final body = drop(battle, 'marren_osei');

      expect(body.bailOutState, BailOutState.bailingOut);
      expect(body.isAlive, isFalse,
          reason: 'the operator is leaving: they do not act, they do not '
              'count for income, and nothing about them is alive');
      expect(body.isOnBoard, isTrue,
          reason: 'but the body is still standing on its line');
    });

    test('the last body of a squad does not bail', () {
      final battle = twoSquads();
      drop(battle, 'marren_osei');
      drop(battle, 'ilona_vance');
      final last = drop(battle, 'bastian_cole');

      expect(last.bailOutState, BailOutState.none,
          reason: 'their squad is defeated the moment they fall, so a window '
              'would only hold a finished battle open');
      expect(battle.isTeamDefeated(battle.teamB), isTrue);
      expect(battle.outcome, BattleOutcome.teamAWins);
    });

    test('a wreck does not parry: the body loses its own armed counters', () {
      final battle = twoSquads();
      final target = battle.states['marren_osei']!;
      target.reactiveEffects
          .add(ReactiveEffect(kind: ReactiveKind.reflectNonAoe));

      drop(battle, 'marren_osei');
      expect(target.reactiveEffects, isEmpty);
    });
  });

  group('the body is still in the way', () {
    test('a killed screen keeps screening until it leaves the board', () {
      final battle = twoSquads();
      battle.states['marren_osei']!.position = BattlePosition.front;
      battle.states['ilona_vance']!.position = BattlePosition.middle;
      battle.states['bastian_cole']!.position = BattlePosition.back;
      final attacker = battle.states['kaito_reyes']!
        ..position = BattlePosition.front;
      final sniper = battle.states['bastian_cole']!;
      final engine = battle.turnEngine;

      // 0 + 2 lines, plus the two squadmates in front of the sniper.
      expect(engine.distanceBetween(attacker, sniper), 4);

      drop(battle, 'marren_osei');
      expect(engine.distanceBetween(attacker, sniper), 4,
          reason: 'the body has not gone anywhere, so neither has the '
              'distance: this is what makes clearing it a real choice');

      battle.states['marren_osei']!.bailOutState = BailOutState.destroyed;
      expect(engine.distanceBetween(attacker, sniper), 3,
          reason: 'destroying the body is what opens the lane');
    });

    test('a recalled body stops screening', () {
      final battle = twoSquads();
      battle.states['marren_osei']!.position = BattlePosition.front;
      battle.states['bastian_cole']!.position = BattlePosition.middle;
      battle.states['ilona_vance']!.position = BattlePosition.back;
      final attacker = battle.states['kaito_reyes']!
        ..position = BattlePosition.front;
      final engine = battle.turnEngine;
      final target = battle.states['bastian_cole']!;

      drop(battle, 'marren_osei');
      final screened = engine.distanceBetween(attacker, target);

      battle.states['marren_osei']!.bailOutState = BailOutState.recalled;
      expect(engine.distanceBetween(attacker, target), screened - 1);
    });
  });

  group('the window closes at a turn boundary', () {
    test('the enemy gets exactly one full turn, then the squad banks the '
        'Salvage', () {
      final battle = twoSquads();
      // Team A is active and has just killed one of team B's squad.
      final body = drop(battle, 'marren_osei');

      battle.endTurn(); // A's turn ends: the turn they killed in does not count
      expect(body.bailOutState, BailOutState.bailingOut,
          reason: 'A committed that turn before the kill landed, so it was '
              'never a decision');

      battle.startTurn(); // B's own turn
      final duringOwnTurn = battle.endTurn();
      expect(duringOwnTurn.bailOuts, isEmpty,
          reason: 'their own turn is not the contested one');
      expect(body.bailOutState, BailOutState.bailingOut);

      battle.startTurn(); // A's turn: this is the window
      // Measured across the settling itself: a turn start also rolls income,
      // which is not what this test is about.
      final poolBefore = battle.teamB.trionPool.current;
      final settled = battle.endTurn();

      expect(body.bailOutState, BailOutState.recalled);
      expect(settled.bailOuts, hasLength(1));
      expect(settled.bailOuts.single.characterId, 'marren_osei');
      expect(settled.bailOuts.single.refused, isFalse);

      final capacity =
          battle.states['marren_osei']!.character.baseStats.trionCapacity;
      final expected = BailOutConfig.defaults.salvageFor(capacity);
      expect(settled.bailOuts.single.trionSalvaged, expected);
      expect(battle.teamB.trionPool.current - poolBefore, expected,
          reason: 'the Salvage goes to the bailing squad, not the attacker');
    });

    test('a body dropped on its own turn still gets the enemy exactly one '
        'turn', () {
      final battle = twoSquads();
      battle.endTurn();
      battle.startTurn(); // team B is active

      final body = drop(battle, 'marren_osei'); // e.g. a reflected hit
      expect(battle.endTurn().bailOuts, isEmpty,
          reason: 'the rest of their own turn is not the enemy deciding');

      battle.startTurn(); // team A: the window
      final settled = battle.endTurn();
      expect(body.bailOutState, BailOutState.recalled);
      expect(settled.bailOuts, hasLength(1));
    });
  });

  group('destroying the body', () {
    /// Puts [attacker] and [target] on the front lines so a Close Range
    /// attack certainly reaches, and returns a plain damaging trigger.
    ActiveTrigger closeAttack() => testTrigger(
          id: 'test_slash',
          rangeTag: RangeTag.close,
          damageType: DamageType.slashing,
          damage: DiceExpression(1, 6, flatBonus: 4),
        );

    test('any landed hit destroys it, denies the Salvage, and pays the '
        'attacker', () {
      final battle = twoSquads();
      final attacker = battle.states['kaito_reyes']!
        ..position = BattlePosition.front;
      final body = drop(battle, 'marren_osei');
      body.position = BattlePosition.front;

      final gainBefore = battle.teamA.trionPool.current;

      battle.turnEngine.resolveAbilityUse(
        attacker: attacker,
        trigger: closeAttack(),
        targets: [body],
      );

      expect(body.bailOutState, BailOutState.destroyed);

      final capacity = body.character.baseStats.trionCapacity;
      expect(battle.teamA.trionPool.current - gainBefore,
          BailOutConfig.defaults.attackerGainFor(capacity),
          reason: 'the smaller gain, paid for spending the action');

      // And the window can no longer pay out.
      battle.endTurn();
      battle.startTurn();
      battle.endTurn();
      battle.startTurn();
      final theirPoolBefore = battle.teamB.trionPool.current;
      final settled = battle.endTurn();
      expect(settled.bailOuts, isEmpty);
      expect(battle.teamB.trionPool.current, theirPoolBefore,
          reason: 'no Salvage: that is what destroying it denied');
    });

    test('the body takes no damage and gains no statuses from the hit that '
        'clears it', () {
      final battle = twoSquads();
      final attacker = battle.states['kaito_reyes']!
        ..position = BattlePosition.front;
      final body = drop(battle, 'marren_osei');
      body.position = BattlePosition.front;

      final result = battle.turnEngine.resolveAbilityUse(
        attacker: attacker,
        trigger: testTrigger(
          id: 'test_slash_bleed',
          rangeTag: RangeTag.close,
          damageType: DamageType.slashing,
          damage: DiceExpression(1, 6, flatBonus: 4),
          inflictedStatusEffects: const [StatusEffectApplication('bleeding')],
        ),
        targets: [body],
      );

      expect(body.currentHealth, 0);
      expect(body.statusEffects, isEmpty,
          reason: 'there is nothing left to afflict');
      expect(result.targetResults.single.statusEffectsApplied, isEmpty);
    });

    test('a miss leaves the body standing', () {
      final battle = Battle(
        // A natural 1 against a real defender never lands.
        turnEngine: TurnEngine(
          combatEngine:
              CombatEngine(diceRoller: DiceRoller(const FixedRandom(0))),
        ),
        teamA: Team(
          id: 'a',
          characters: [
            testCharacter(id: 'a1'),
            testCharacter(id: 'a2'),
            testCharacter(id: 'a3'),
          ],
        ),
        teamB: Team(
          id: 'b',
          characters: [
            testCharacter(id: 'b1'),
            testCharacter(id: 'b2', stats: testStats(defense: 20)),
            testCharacter(id: 'b3'),
          ],
        ),
      );
      final attacker = battle.states['a1']!..position = BattlePosition.front;
      final body = drop(battle, 'b2')..position = BattlePosition.front;

      battle.turnEngine.resolveAbilityUse(
        attacker: attacker,
        trigger: closeAttack(),
        targets: [body],
      );

      expect(body.bailOutState, BailOutState.bailingOut,
          reason: 'a landed hit ends it; a miss is still a miss');
    });

    test('nobody steps in front of a body', () {
      final battle = twoSquads();
      // Sable's Guardian's Instinct would redirect a hit aimed at an ally.
      final guardian = battle.states.values.firstWhere(
        (s) =>
            s.character.sideEffect?.canRedirectAllyAttackOncePerBattle == true,
        orElse: () => battle.states['ilona_vance']!,
      );
      final body = drop(battle, 'marren_osei');
      body.position = guardian.position;

      final attacker = battle.states['kaito_reyes']!
        ..position = BattlePosition.front;
      battle.turnEngine.resolveAbilityUse(
        attacker: attacker,
        trigger: closeAttack(),
        targets: [body],
      );

      expect(guardian.sideEffectChargeUsed, isFalse,
          reason: 'spending a once-per-battle charge to save a wreck would be '
              'the worst trade in the game');
      expect(body.bailOutState, BailOutState.destroyed);
    });
  });

  group('Refuse to Bail', () {
    ActiveTrigger refuseToBail() =>
        TriggerCatalog.defaultCatalog['refuse_to_bail'] as ActiveTrigger;

    test('it is in the catalog, self-targeted, and arms its own counter', () {
      final trigger = refuseToBail();
      expect(trigger.targetAffiliation, TargetAffiliation.self);
      expect(trigger.armsReactive, ReactiveKind.refuseToBail);
      expect(trigger.armsReactiveDefaultTurns, isNull,
          reason: 'it stands until it fires, like the other untimed wards');
    });

    test('the drop does not happen: they stay on 1 health', () {
      final battle = twoSquads();
      final holder = battle.states['marren_osei']!;
      holder.reactiveEffects
          .add(ReactiveEffect(kind: ReactiveKind.refuseToBail));

      drop(battle, 'marren_osei');

      expect(holder.currentHealth, 1);
      expect(holder.isAlive, isTrue, reason: 'they are still fighting');
      expect(holder.bailOutState, BailOutState.none);
      expect(holder.hasRefusedToBail, isTrue);
      expect(holder.reactiveEffects, isEmpty, reason: 'consumed on firing');
    });

    test('they get one turn of their own, then are gone with no Salvage', () {
      final battle = twoSquads();
      final holder = battle.states['marren_osei']!;
      holder.reactiveEffects
          .add(ReactiveEffect(kind: ReactiveKind.refuseToBail));
      drop(battle, 'marren_osei');

      battle.endTurn(); // team A's turn ends
      battle.startTurn(); // team B's turn: the one they bought
      expect(holder.isAlive, isTrue,
          reason: 'this is the turn they paid for, and they can act in it');

      final poolBefore = battle.teamB.trionPool.current;
      final settled = battle.endTurn();
      expect(holder.isAlive, isFalse);
      expect(holder.bailOutState, BailOutState.none,
          reason: 'no body is left to recall');
      expect(settled.bailOuts, hasLength(1));
      expect(settled.bailOuts.single.refused, isTrue);
      expect(settled.bailOuts.single.trionSalvaged, 0);
      expect(battle.teamB.trionPool.current, poolBefore,
          reason: 'refusing costs the Salvage, and that is the whole gamble');
    });

    test('having refused once, a second drop opens no window', () {
      final battle = twoSquads();
      final holder = battle.states['marren_osei']!;
      holder.reactiveEffects
          .add(ReactiveEffect(kind: ReactiveKind.refuseToBail));
      drop(battle, 'marren_osei');
      expect(holder.currentHealth, 1);

      drop(battle, 'marren_osei');
      expect(holder.isAlive, isFalse);
      expect(holder.bailOutState, BailOutState.none);
    });
  });

  group('a character can only be in a battle once', () {
    // Found in a playtest: a mirror-matched Ilona Vance on both squads shared
    // one battle state, so killing the player's killed the opponent's, both
    // squads counted her as a teammate, and she could be ordered to attack
    // herself. The map is keyed by character id; a duplicate silently
    // collapses two characters into one.
    test('the same character on both squads is refused, not collapsed', () {
      final roster = CharacterRoster.defaultRoster;
      expect(
        () => Battle(
          teamA: Team(id: 'a', characters: [
            roster['sable_whitlock'],
            roster['marren_osei'],
            roster['ilona_vance'],
          ]),
          teamB: Team(id: 'b', characters: [
            roster['ilona_vance'],
            roster['rurik_voss'],
            roster['haru_ellison'],
          ]),
        ),
        throwsArgumentError,
        reason: 'six characters cannot share five battle states',
      );
    });

    test('two squads with no overlap build normally', () {
      expect(twoSquads().states, hasLength(6));
    });
  });

  group('the numbers', () {
    test('Salvage is 20% of base Trion Capacity and the attacker gets half of '
        'that', () {
      const config = BailOutConfig.defaults;
      expect(config.salvageFor(100), 20);
      expect(config.salvageFor(130), 26);
      expect(config.attackerGainFor(100), 10);
      expect(config.attackerGainFor(130), 13);
      for (final capacity in [100, 105, 110, 115, 120, 130]) {
        expect(config.attackerGainFor(capacity) * 2,
            closeTo(config.salvageFor(capacity), 1),
            reason: 'the two are tied to one base, so #3 can re-price either '
                'without them drifting apart');
      }
    });
  });
}

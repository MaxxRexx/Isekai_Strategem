import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/data/describe.dart';
import 'package:isekai_strategem/src/game/draft.dart';
import 'package:isekai_strategem/src/game/play_session.dart';

/// Item #2, the session side: what a Bailing Out body does to the interface.
///
/// The engine rules have their own tests. These are the four things a player
/// touches: which abilities may be pointed at a body, what the ruler and the
/// out-of-range copy count, what the log says happened, and whether the
/// opponent understands any of it.
void main() {
  Loadout mixed(String id) => Loadout(
        characterId: id,
        triggers: [
          triggerCatalog['twin_fang_strike'], // Close Range attack
          triggerCatalog['war_chant'], // Close Range, self buff
          triggerCatalog['charm_whisper'], // Close Range, control, no damage
          triggerCatalog['cleansing_ward'], // ally-targeted ward
        ],
      );

  const squad = ['marren_osei', 'ilona_vance', 'bastian_cole'];

  /// Deterministic dice: every one of these turns on an attack landing.
  PlaySession session() {
    final s = PlaySession.start(
      playerCharacterIds: squad,
      playerLoadouts: {for (final id in squad) id: mixed(id)},
      opponentCharacterIds: ['kaito_reyes', 'vela_ashworth', 'dross'],
      opponentProfileId: 'the_tactician',
      firstTurn: 'teamA',
      turnEngine: TurnEngine(
        combatEngine:
            CombatEngine(diceRoller: DiceRoller(const _AlwaysMax(19))),
        statusEffectEngine:
            StatusEffectEngine(diceRoller: DiceRoller(const _AlwaysMax(19))),
      ),
    );
    s.battle.teamA.trionPool.gain(500);
    for (final c in [...s.battle.teamA.characters, ...s.battle.teamB.characters]) {
      s.battle.stateById(c.id).position = BattlePosition.front;
    }
    return s;
  }

  /// Puts one of their squad into the Bail Out window and returns it.
  CharacterBattleState body(PlaySession s, String id) {
    final state = s.battle.stateById(id);
    state.currentHealth = 0;
    s.battle.turnEngine.noteHealthChanged(state);
    expect(state.bailOutState, BailOutState.bailingOut);
    return state;
  }

  group('what may be aimed at a body', () {
    test('an attack may; a heal, a buff and a debuff may not', () {
      final s = session();
      final corpse = body(s, 'kaito_reyes');
      final actions = s.legalActionsFor('marren_osei');

      final attack =
          actions.firstWhere((a) => a.trigger.id == 'twin_fang_strike');
      expect(attack.legalTargetIds, contains(corpse.combatantId),
          reason: 'clearing a body is a real choice, so it has to be offered');

      final control = actions.firstWhere((a) => a.trigger.id == 'charm_whisper');
      expect(control.legalTargetIds, isNot(contains(corpse.combatantId)),
          reason: 'there is nothing left to charm');

      // Ally-targeted abilities never see the other squad at all, so the
      // case that matters is a body on your *own* side.
      final ownBody = body(s, 'ilona_vance');
      final ward = s
          .legalActionsFor('marren_osei')
          .firstWhere((a) => a.trigger.id == 'cleansing_ward');
      expect(ward.legalTargetIds, isNot(contains(ownBody.combatantId)),
          reason: 'Bail Out is not a revive, and the interface should never '
              'suggest otherwise');
    });

    test('a queued attack on a body resolves and destroys it', () {
      final s = session();
      final corpse = body(s, 'kaito_reyes');
      final poolBefore = s.battle.teamA.trionPool.current;

      expect(
        s.queue('marren_osei', 'twin_fang_strike', [corpse.combatantId])
            .success,
        isTrue,
      );
      final round = s.resolveQueue();

      expect(corpse.bailOutState, BailOutState.destroyed);
      final target = round.actions
          .firstWhere((a) => a.triggerId == 'twin_fang_strike')
          .targets
          .single;
      expect(target.bodyDestroyed, isTrue);
      expect(target.trionFromBody, greaterThan(0));
      expect(target.died, isTrue);
      final cost =
          (triggerCatalog['twin_fang_strike'] as ActiveTrigger).trionCost;
      expect(s.battle.teamA.trionPool.current,
          poolBefore - cost + target.trionFromBody,
          reason: 'the ability was paid for and the body paid back');
    });
  });

  group('the log says which of the endings happened', () {
    test('a drop reads as bailing out, not as defeated', () {
      final s = session();
      final victim = s.battle.stateById('kaito_reyes')..currentHealth = 1;

      expect(
        s.queue('marren_osei', 'twin_fang_strike', [victim.combatantId])
            .success,
        isTrue,
      );
      final round = s.resolveQueue();
      final target = round.actions
          .firstWhere((a) => a.triggerId == 'twin_fang_strike')
          .targets
          .single;

      expect(target.startedBailingOut, isTrue);
      expect(target.died, isFalse,
          reason: 'bailing out is not defeated, and the log must not say it '
              'is: the body is still a decision');
      expect(target.bodyDestroyed, isFalse);
      expect(victim.bailOutState, BailOutState.bailingOut);
    });

    test('the recall is logged with the Trion it banked', () {
      final s = session();
      // One of the player's own squad bails, so the window is settled at the
      // end of the opponent's turn, which is where the player will read it.
      final own = body(s, 'ilona_vance');
      // The window is armed when the opponent's turn begins and settled when
      // it ends, so it closes inside the very next opponent turn.
      final round = s.endTurn();

      final recall = round.bailOuts
          .where((b) => b.characterId == own.combatantId)
          .toList();
      expect(recall, hasLength(1), reason: 'the recall has to appear once');
      expect(recall.single.refused, isFalse);
      expect(recall.single.team, 'A');
      expect(
        recall.single.trionSalvaged,
        BailOutConfig.defaults
            .salvageFor(own.character.baseStats.trionCapacity),
      );
      expect(own.bailOutState, BailOutState.recalled);
    });
  });

  group('the opponent understands bodies', () {
    test('the AI clears a body when nothing living is in its band', () {
      final s = session();
      // The board this needs: nothing alive inside any band the opponent
      // carries, no step that fixes it, and a body they can reach. Two of the
      // player's squad are bodies on the near lines, screening the survivor
      // out to distance 4; the opponent is pressed to their own front line
      // with Close Range work only, which reaches 0 to 2.
      for (final c in s.battle.teamB.characters) {
        s.battle.stateById(c.id).position = BattlePosition.front;
        s.equippedB[s.battle.stateById(c.id).combatantId] = [triggerCatalog['twin_fang_strike'] as ActiveTrigger];
      }
      s.battle.stateById('marren_osei').position = BattlePosition.front;
      s.battle.stateById('ilona_vance').position = BattlePosition.middle;
      s.battle.stateById('bastian_cole').position = BattlePosition.back;
      final front = body(s, 'marren_osei');
      body(s, 'ilona_vance');
      s.battle.teamB.trionPool.gain(500);

      final engine = s.battle.turnEngine;
      expect(
        engine.distanceBetween(
            s.battle.stateById('kaito_reyes'), s.battle.stateById('bastian_cole')),
        4,
        reason: 'the survivor is screened right out of Close Range',
      );

      s.endTurn();

      expect(front.bailOutState, BailOutState.destroyed,
          reason: 'a body it can reach is worth an action it has nothing else '
              'to spend on');
    });

    test('the AI does not trade a live shot for a body', () {
      final s = session();
      // Everyone on the front lines and the opponent carrying Close Range
      // work, so every one of their actions has a living target inside its
      // band. Pinning the band matters: at distance 0 a Mid or Long ability
      // has no living target either, and reaching for the body would then be
      // the rule working rather than failing.
      for (final c in s.battle.teamB.characters) {
        s.equippedB[s.battle.stateById(c.id).combatantId] = [triggerCatalog['twin_fang_strike'] as ActiveTrigger];
      }
      final corpse = body(s, 'marren_osei');
      s.battle.teamB.trionPool.gain(500);

      s.endTurn();

      expect(corpse.bailOutState, isNot(BailOutState.destroyed),
          reason: 'shooting a wreck while somebody can still shoot back is '
              'never the trade');
    });
  });

  group('a body is not defeated', () {
    test('a later action aimed at a body never reads as a defeat', () {
      final s = session();
      final corpse = body(s, 'kaito_reyes');

      // Charm Whisper cannot be aimed at a body, so use the attack: the point
      // is what the *second* action against the same target says.
      expect(
        s.queue('marren_osei', 'twin_fang_strike', [corpse.combatantId])
            .success,
        isTrue,
      );
      final round = s.resolveQueue();
      final target = round.actions
          .firstWhere((a) => a.triggerId == 'twin_fang_strike')
          .targets
          .single;

      expect(target.bodyDestroyed, isTrue);
      expect(target.died, isTrue, reason: 'the body really is gone now');
    });

    test('while the window is open, died stays false', () {
      final s = session();
      final victim = s.battle.stateById('kaito_reyes')..currentHealth = 1;
      expect(
        s.queue('marren_osei', 'twin_fang_strike', [victim.combatantId])
            .success,
        isTrue,
      );
      final round = s.resolveQueue();
      final target = round.actions
          .firstWhere((a) => a.triggerId == 'twin_fang_strike')
          .targets
          .single;

      expect(target.startedBailingOut, isTrue);
      expect(target.died, isFalse,
          reason: 'they are bailing out, which is not the same as defeated, '
              'and the player still has a decision to make about the body');
    });
  });

  group('a character can only be in a battle once', () {
    // The playtest bug: a mirror-matched Ilona Vance on both squads shared one
    // battle state, so killing the player's killed the opponent's. The engine
    // now refuses such a battle; this is the draft rule that stops one being
    // built, checked over enough draws that a rare overlap cannot hide.
    test('a randomised squad never overlaps the one it is drafted against',
        () {
      final random = Random(7);
      const theirs = ['ilona_vance', 'rurik_voss', 'haru_ellison'];
      for (var i = 0; i < 2000; i++) {
        final mine = randomSquadAvoiding(random, theirs);
        expect(mine, hasLength(3));
        expect(mine.toSet(), hasLength(3), reason: 'and no repeats within it');
        expect(mine.toSet().intersection(theirs.toSet()), isEmpty,
            reason: 'draw $i put ${mine.toSet().intersection(theirs.toSet())} '
                'on both squads');
      }
    });

    test('empty slots on the other squad exclude nobody', () {
      final picked = randomSquadAvoiding(Random(1), [null, null, null]);
      expect(picked, hasLength(3));
    });
  });

  test('Refuse to Bail explains itself in the Loadout', () {
    final trigger = triggerCatalog['refuse_to_bail'];
    final text = describeTrigger(trigger);
    expect(text, contains('0 health'));
    expect(text, contains('1 health'));
    expect(text, contains('Trion Salvage'),
        reason: 'the price is the point, so it has to be in the copy');
    expect(text, contains('until it fires'));
  });
}

/// Always rolls the top of the die.
class _AlwaysMax implements Random {
  final int value;
  const _AlwaysMax(this.value);
  @override
  int nextInt(int max) => value % max;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

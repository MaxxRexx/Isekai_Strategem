import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Item #D: what a duration means.
///
/// The countdown used to run at the *start* of the holder's turn, next to the
/// damage ticks, and that made one word mean three different things. A 1-turn
/// Stun put on an enemy was decremented to zero and removed at the start of
/// their turn, before they acted, so it did nothing whatsoever. A debuff of N
/// turns delivered N damage ticks but only N-1 afflicted turns. A self-buff of
/// N covered N of the opponent's turns but only N-1 of your own.
///
/// The countdown now runs at the end of the holder's turn and sits out the
/// turn the effect was applied on. N means the same thing for every effect:
/// **the holder's next N turns**.
///
/// These tests drive real turns through [Battle] rather than calling the
/// status engine directly, because the whole question is about turn
/// boundaries and only [Battle] has them.
void main() {
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

  /// Plays one whole turn for whichever team is active, running [during] in
  /// the window where a real caller would be using abilities.
  void playTurn(Battle battle, {void Function()? during}) {
    battle.startTurn();
    during?.call();
    battle.endTurn();
  }

  StatusEffectInstance? instanceOn(CharacterBattleState state, String id) {
    for (final i in state.statusEffects) {
      if (i.definitionId == id) return i;
    }
    return null;
  }

  group('a hostile effect afflicts exactly the turns it says', () {
    test('a 1-turn Stun costs the enemy their action, which is the bug', () {
      final battle = twoSquads();
      final victim = battle.states['marren_osei']!;

      // Team A's turn: stun someone on team B for one turn.
      battle.startTurn();
      battle.turnEngine.statusEffectEngine
          .apply(victim, 'stunned', durationOverride: 1);
      battle.endTurn();

      // Team B's turn. This is the turn the Stun was meant to take away, and
      // before item #D it was already gone by now.
      battle.startTurn();
      expect(victim.isActionPrevented(), isTrue,
          reason: 'a 1-turn Stun that expires before its victim acts is not '
              'a Stun at all');
      battle.endTurn();

      expect(victim.isActionPrevented(), isFalse);
      expect(instanceOn(victim, 'stunned'), isNull,
          reason: 'and it is spent afterwards, not carried on');
    });

    test('a 2-turn Stun costs them two actions, not one', () {
      final battle = twoSquads();
      final victim = battle.states['marren_osei']!;

      battle.startTurn();
      battle.turnEngine.statusEffectEngine
          .apply(victim, 'stunned', durationOverride: 2);
      battle.endTurn();

      playTurn(battle); // theirs, stunned
      expect(instanceOn(victim, 'stunned')?.remainingTurns, 1);
      playTurn(battle); // ours

      battle.startTurn();
      expect(victim.isActionPrevented(), isTrue);
      battle.endTurn();

      expect(instanceOn(victim, 'stunned'), isNull);
    });

    test('damage over time still ticks exactly N times', () {
      final battle = twoSquads();
      final victim = battle.states['marren_osei']!;
      victim.currentHealth = 100;

      battle.startTurn();
      battle.turnEngine.statusEffectEngine
          .apply(victim, 'bleeding', durationOverride: 3);
      battle.endTurn();

      var ticks = 0;
      for (var i = 0; i < 8 && instanceOn(victim, 'bleeding') != null; i++) {
        final before = victim.currentHealth;
        battle.startTurn();
        if (victim.currentHealth < before) ticks++;
        battle.endTurn();
      }

      expect(ticks, 3,
          reason: 'splitting the countdown from the ticks is what keeps '
              'damage over time untouched');
    });
  });

  group('an effect applied on the holder own turn sits that turn out', () {
    test('a self-buff lasts for N of your own turns', () {
      // This is the one thing #D changes about your own side, and it was the
      // decision: a buff you cast reads 2 and gives you two of your turns,
      // where it used to give you one plus the remainder of the turn you
      // cast it on.
      final battle = twoSquads();
      final self = battle.states['kaito_reyes']!;

      battle.startTurn();
      battle.turnEngine.statusEffectEngine
          .apply(self, 'empowered', durationOverride: 2);
      expect(instanceOn(self, 'empowered')?.skipsNextCountdown, isTrue);
      battle.endTurn();

      expect(instanceOn(self, 'empowered')?.remainingTurns, 2,
          reason: 'the turn it was cast on is not one of the turns it buys');

      // Count the holder's own turns the buff is actually live for, which is
      // what a buff of this kind is bought for.
      var ownTurnsBuffed = 0;
      for (var i = 0; i < 8; i++) {
        battle.startTurn();
        final ourTurn = identical(battle.activeTeam, battle.teamA);
        if (ourTurn && instanceOn(self, 'empowered') != null) ownTurnsBuffed++;
        battle.endTurn();
      }

      expect(ownTurnsBuffed, 2,
          reason: 'two turns means two of your turns, for every effect');
      expect(instanceOn(self, 'empowered'), isNull);
    });

    test('a ward still covers the same answers it always did', () {
      // Guarded's value is realised on the opponent's turn, and this is the
      // case #D had to not break: 2 turns still means two of their turns.
      final battle = twoSquads();
      final self = battle.states['kaito_reyes']!;

      battle.startTurn();
      battle.turnEngine.statusEffectEngine
          .apply(self, 'guarded', durationOverride: 2);
      battle.endTurn();

      var covered = 0;
      for (var i = 0; i < 6; i++) {
        battle.startTurn();
        final theirTurn = !identical(battle.activeTeam, battle.teamA);
        if (theirTurn && instanceOn(self, 'guarded') != null) covered++;
        battle.endTurn();
      }

      expect(covered, 2,
          reason: 'a ward that stops covering the opponent answer is not a '
              'ward');
    });

    test('heal over time on yourself still heals N times', () {
      final battle = twoSquads();
      final self = battle.states['kaito_reyes']!;
      self.currentHealth = 40;

      battle.startTurn();
      battle.turnEngine.statusEffectEngine
          .apply(self, 'regenerating', durationOverride: 3);
      battle.endTurn();

      var heals = 0;
      for (var i = 0; i < 10 && instanceOn(self, 'regenerating') != null; i++) {
        final before = self.currentHealth;
        battle.startTurn();
        if (self.currentHealth > before) heals++;
        battle.endTurn();
      }

      expect(heals, 3);
    });

    test('a counter Stun on the attacker survives to their next turn', () {
      // The case that decided the shape of the fix: a reactive counter lands
      // a Stun on whoever is attacking, and they are attacking on their own
      // turn. Counting that turn would spend the Stun on a turn its victim
      // had already taken.
      final battle = twoSquads();
      final attacker = battle.states['kaito_reyes']!;

      battle.startTurn();
      battle.turnEngine.statusEffectEngine
          .apply(attacker, 'stunned', durationOverride: 1);
      battle.endTurn();

      playTurn(battle); // theirs

      battle.startTurn();
      expect(attacker.isActionPrevented(), isTrue,
          reason: 'the Stun has to cost them a turn they have not had yet');
      battle.endTurn();
    });

    test('re-applying on your own turn does not spend that turn either', () {
      final battle = twoSquads();
      final self = battle.states['kaito_reyes']!;
      final engine = battle.turnEngine.statusEffectEngine;

      battle.startTurn();
      engine.apply(self, 'focused', durationOverride: 2);
      battle.endTurn();

      playTurn(battle); // theirs
      battle.startTurn();
      engine.apply(self, 'focused', durationOverride: 2); // refreshed
      battle.endTurn();

      expect(instanceOn(self, 'focused')?.remainingTurns, 2,
          reason: 'a refresh is an application, and follows the same rule');
    });
  });

  group('the rules that must not have moved', () {
    test('an untimed effect never expires on its own', () {
      final battle = twoSquads();
      final self = battle.states['kaito_reyes']!;

      battle.startTurn();
      battle.turnEngine.statusEffectEngine
          .apply(self, 'stunned', durationOverride: null);
      // stunned carries a default, so pin an untimed instance directly.
      self.statusEffects.clear();
      self.statusEffects.add(StatusEffectInstance(definitionId: 'stunned'));
      battle.endTurn();

      for (var i = 0; i < 6; i++) {
        playTurn(battle);
      }
      expect(instanceOn(self, 'stunned'), isNotNull);
      expect(instanceOn(self, 'stunned')?.remainingTurns, isNull);
    });

    test('the turn end reports what ran out', () {
      final battle = twoSquads();
      final self = battle.states['kaito_reyes']!;

      battle.startTurn();
      battle.turnEngine.statusEffectEngine
          .apply(self, 'empowered', durationOverride: 1);
      battle.endTurn();

      playTurn(battle); // theirs

      battle.startTurn();
      final result = battle.endTurn();

      expect(result.statusesExpired[self.combatantId]?.single.definitionId,
          'empowered');
    });

    test('a body on the board is not counted down', () {
      final battle = twoSquads();
      final self = battle.states['kaito_reyes']!;

      battle.startTurn();
      battle.turnEngine.statusEffectEngine
          .apply(self, 'empowered', durationOverride: 2);
      battle.endTurn();

      self.currentHealth = 0;
      battle.turnEngine.noteHealthChanged(self);

      playTurn(battle); // theirs
      playTurn(battle); // ours, but they are not alive to spend it

      expect(instanceOn(self, 'empowered')?.remainingTurns, 2,
          reason: 'only a living holder spends a turn of a duration');
    });
  });
}

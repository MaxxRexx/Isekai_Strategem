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
}

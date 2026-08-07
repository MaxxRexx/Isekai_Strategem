import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Combat-v2 Phase I: the Combo Recognition subsystem (action ledger +
/// condition primitives + recognizer + Layer-1 generic catalog).
void main() {
  const recognizer = ComboCatalog.defaultRecognizer;

  ComboLedgerEntry setup(
    ComboLedger ledger, {
    required String team,
    required String actor,
    required List<String> statuses,
    required String target,
    bool damage = true,
    String id = 'setup',
    OriginTag origin = OriginTag.physical,
    TargetAffiliation affiliation = TargetAffiliation.opponent,
  }) =>
      ledger.record(
        actorId: actor,
        teamId: team,
        trigger: testTrigger(id: id, originTag: origin, targetAffiliation: affiliation),
        targetIds: [target],
        statusesApplied: statuses,
        dealtDamage: damage,
      );

  group('ComboRecognizer (Phase I)', () {
    test('focus fire: a second attacker into an already-struck enemy', () {
      final ledger = ComboLedger();
      setup(ledger, team: 'A', actor: 'a1', statuses: [], target: 'x');
      final payoff =
          setup(ledger, team: 'A', actor: 'a2', statuses: [], target: 'x', id: 'hit');

      final ids = recognizer.recognize(ledger.contextFor(payoff)).map((c) => c.id);
      expect(ids, contains('focus_fire'));
    });

    test('control then strike is recognized and outranks focus fire', () {
      final ledger = ComboLedger();
      setup(ledger, team: 'A', actor: 'a1', statuses: ['stunned'], target: 'x');
      final payoff =
          setup(ledger, team: 'A', actor: 'a2', statuses: [], target: 'x', id: 'hit');

      final best = recognizer.best(ledger.contextFor(payoff));
      expect(best?.id, 'control_then_strike');
      expect(best?.strength, 3);
    });

    test('affliction detonate: energy payoff into an afflicted target', () {
      final target = CharacterBattleState(testCharacter(id: 'x'))
        ..statusEffects
            .add(StatusEffectInstance(definitionId: 'poisoned', remainingTurns: 3));

      final ledger = ComboLedger();
      final payoff = setup(ledger,
          team: 'A', actor: 'a1', statuses: [], target: 'x', id: 'blast', origin: OriginTag.energy);
      final ids = recognizer
          .recognize(ledger.contextFor(payoff, targetState: target))
          .map((c) => c.id);
      expect(ids, contains('affliction_detonate'));

      // A physical payoff into the same afflicted target does not detonate.
      final ledger2 = ComboLedger();
      final payoff2 = setup(ledger2,
          team: 'A', actor: 'a1', statuses: [], target: 'x', id: 'slash', origin: OriginTag.physical);
      final ids2 = recognizer
          .recognize(ledger2.contextFor(payoff2, targetState: target))
          .map((c) => c.id);
      expect(ids2, isNot(contains('affliction_detonate')));
    });

    test('setup exploit fires on an ally-applied vulnerability', () {
      final ledger = ComboLedger();
      setup(ledger, team: 'A', actor: 'a1', statuses: ['exposed'], target: 'x', damage: false);
      final payoff =
          setup(ledger, team: 'A', actor: 'a2', statuses: [], target: 'x', id: 'hit');

      final ids = recognizer.recognize(ledger.contextFor(payoff)).map((c) => c.id);
      expect(ids, contains('setup_exploit'));
    });

    test('an enemy-applied setup is not your combo', () {
      final ledger = ComboLedger();
      // Enemy (team B) stuns and strikes x, then team A hits x.
      setup(ledger, team: 'B', actor: 'b1', statuses: ['stunned'], target: 'x');
      final payoff =
          setup(ledger, team: 'A', actor: 'a1', statuses: [], target: 'x', id: 'hit');

      final ids = recognizer.recognize(ledger.contextFor(payoff)).map((c) => c.id);
      expect(ids, isNot(contains('control_then_strike')));
      expect(ids, isNot(contains('focus_fire')),
          reason: 'the prior strike belonged to the enemy team');
    });

    test('a non-offensive payoff recognizes nothing', () {
      final ledger = ComboLedger();
      setup(ledger, team: 'A', actor: 'a1', statuses: ['stunned'], target: 'x');
      final payoff = ledger.record(
        actorId: 'a2',
        teamId: 'A',
        trigger: testTrigger(id: 'selfbuff', targetAffiliation: TargetAffiliation.self),
        targetIds: ['a2'],
        statusesApplied: [],
        dealtDamage: false,
      );

      expect(recognizer.recognize(ledger.contextFor(payoff)), isEmpty);
    });

    test('clearTurn empties the ledger and restarts sequencing', () {
      final ledger = ComboLedger();
      setup(ledger, team: 'A', actor: 'a1', statuses: [], target: 'x');
      expect(ledger.entries, hasLength(1));

      ledger.clearTurn();
      expect(ledger.entries, isEmpty);

      final e = setup(ledger, team: 'A', actor: 'a1', statuses: [], target: 'x');
      expect(e.sequence, 0, reason: 'sequence restarts after a turn boundary');
    });
  });

  group('Signature combos (Phase I4)', () {
    test('frozen detonation: Frost Lance setup then Cinderburst payoff', () {
      final ledger = ComboLedger();
      setup(ledger, team: 'A', actor: 'a1', statuses: [], target: 'x', id: 'frost_lance');
      final payoff =
          setup(ledger, team: 'A', actor: 'a2', statuses: [], target: 'x', id: 'cinderburst');
      final best = recognizer.best(ledger.contextFor(payoff));
      expect(best?.id, 'frozen_detonation');
      expect(best?.strength, 4);
      expect(best?.isSetupPayoff, isTrue);
    });

    test('terror cascade: Nightmare Pulse then Dread Gaze', () {
      final ledger = ComboLedger();
      setup(ledger, team: 'A', actor: 'a1', statuses: [], target: 'x', id: 'nightmare_pulse');
      final payoff =
          setup(ledger, team: 'A', actor: 'a2', statuses: [], target: 'x', id: 'dread_gaze');
      expect(recognizer.recognize(ledger.contextFor(payoff)).map((c) => c.id),
          contains('terror_cascade'));
    });

    test('shatterpoint execution: a Shatterpoint finisher on a softened target',
        () {
      final ledger = ComboLedger();
      setup(ledger, team: 'A', actor: 'a1', statuses: [], target: 'x', id: 'longshot');
      final payoff =
          setup(ledger, team: 'A', actor: 'a2', statuses: [], target: 'x', id: 'shatterpoint');
      final best = recognizer.best(ledger.contextFor(payoff));
      expect(best?.id, 'shatterpoint_execution');
      expect(best?.strength, 5);
    });

    test('a signature payoff without its setup falls back to the generic combo',
        () {
      final ledger = ComboLedger();
      setup(ledger, team: 'A', actor: 'a1', statuses: [], target: 'x', id: 'longshot');
      final payoff =
          setup(ledger, team: 'A', actor: 'a2', statuses: [], target: 'x', id: 'cinderburst');
      final ids = recognizer.recognize(ledger.contextFor(payoff)).map((c) => c.id);
      expect(ids, isNot(contains('frozen_detonation')),
          reason: 'no Frost Lance setup was played');
      expect(ids, contains('focus_fire'));
    });
  });
}

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/data/describe.dart';

/// Descriptions have to answer three questions a player cannot work out by
/// looking: what a named status actually does, how long it lasts, and whether
/// it is still there when they next act.
void main() {
  final catalog = StatusEffectCatalog.defaultCatalog;

  group('duration wording', () {
    test('a 1-turn effect says outright that it is gone before you act again',
        () {
      final text = describeStatusDuration(1, onSelf: true);
      expect(text, contains('this turn only'));
      expect(text, contains('wears off when your next turn begins'));
    });

    test('a 2-turn effect covers this turn and one more of yours', () {
      expect(describeStatusDuration(2, onSelf: true),
          'Active this turn and your next turn.');
    });

    test('longer effects count the remaining turns', () {
      expect(describeStatusDuration(3, onSelf: true),
          'Active this turn and your next 2 turns.');
    });

    test('the turns counted belong to whoever holds the effect', () {
      expect(describeStatusDuration(2, onSelf: false), contains('their next'));
    });

    test('an effect with no expiry says so instead of naming a number', () {
      expect(describeStatusDuration(null, onSelf: true),
          contains('until it is removed'));
    });
  });

  group('what a status does', () {
    test('Empowered states the damage bonus rather than just its name', () {
      final text = describeStatusEffect(catalog['empowered'], onSelf: true);
      expect(text, contains('25% more damage'));
      expect(text, contains('your next turn'));
    });

    test('Stunned states the lockout and the stat it zeroes', () {
      final text = describeStatusEffect(catalog['stunned'], onSelf: false);
      expect(text, contains('cannot act'));
      expect(text, contains('Team Spirit'));
    });

    test('a damage-over-time effect says when the damage lands', () {
      final text = describeStatusEffect(catalog['bleeding'], onSelf: false);
      expect(text, contains('at the start of each of their turns'));
    });

    test('the subject and verb agree for both sides', () {
      expect(describeStatusEffect(catalog['empowered'], onSelf: true),
          startsWith('You deal '));
      expect(describeStatusEffect(catalog['empowered'], onSelf: false),
          startsWith('They deal '));
    });

    test('every catalogued effect produces a sentence, not a bare name', () {
      for (final def in catalog.all) {
        final text = describeStatusEffect(def, onSelf: true);
        expect(text.endsWith('.'), isTrue, reason: '${def.id}: "$text"');
        expect(text.length, greaterThan(def.name.length + 10),
            reason: '${def.id} says almost nothing: "$text"');
      }
    });
  });

  group('an ability that inflicts a status explains it', () {
    test('War Chant answers what, how long, and when', () {
      final trigger =
          TriggerCatalog.defaultCatalog['war_chant'] as ActiveTrigger;
      final text = describeActiveTrigger(trigger);

      expect(text, contains('Empowered'));
      expect(text, contains('25% more damage'),
          reason: 'what the status does');
      expect(text, contains('your next turn'), reason: 'how long it lasts');
      expect(text, contains('still up on your next turn'),
          reason: 'when the bonus actually pays, on an ordinary turn');
      expect(text, isNot(contains('Full Arms Trigger turn an attack')),
          reason: 'no ability should read as needing FAT to be useful');
      expect(text, contains('Costs 10 Trion'));
    });

    test('an enemy-targeted status is described against them, not you', () {
      final trigger =
          TriggerCatalog.defaultCatalog['charm_whisper'] as ActiveTrigger;
      final text = describeActiveTrigger(trigger);

      expect(text, contains('Leaves the target'));
      expect(text, contains('their next'));
      expect(text, isNot(contains('sets up the attack you make then')));
    });
  });

  group('the badge tooltip counts what is actually left', () {
    test('one turn remaining says it wears off before their next turn', () {
      final text = describeStatusBadge(
        id: 'empowered',
        name: 'Empowered',
        remainingTurns: 1,
        onSelf: false,
      );
      expect(text, contains('25% more damage'));
      expect(text, contains('Wears off when their next turn begins'));
    });

    test('the live counter is used, not the effect default', () {
      final text = describeStatusBadge(
        id: 'bleeding',
        name: 'Bleeding',
        remainingTurns: 3,
        onSelf: true,
      );
      expect(text, contains('your next 2 turns'));
    });
  });
}

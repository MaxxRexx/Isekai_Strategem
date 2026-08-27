import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/data/describe.dart';

/// Descriptions have to answer three questions a player cannot work out by
/// looking: what a named status actually does, how long it lasts, and whether
/// it is still there when they next act.
void main() {
  final catalog = StatusEffectCatalog.defaultCatalog;

  group('duration wording', () {
    test('a 1-turn effect covers a whole turn, which is item #D', () {
      // The old wording had to warn that a 1-turn effect was gone before its
      // holder acted again, because it was. It is not any more: one turn is
      // one of the holder's turns.
      expect(describeStatusDuration(1, onSelf: true),
          'Lasts through your next turn.');
    });

    test('a 2-turn effect covers two of the holder turns', () {
      expect(describeStatusDuration(2, onSelf: true),
          'Lasts through your next 2 turns.');
    });

    test('the number in the sentence is the number on the effect', () {
      // The point of #D: no arithmetic between what an effect says and what
      // the player is told.
      for (final turns in [1, 2, 3, 4]) {
        final text = describeStatusDuration(turns, onSelf: true);
        expect(text, contains(turns == 1 ? 'next turn' : 'next $turns turns'),
            reason: 'a duration of $turns must read as $turns');
      }
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
      expect(text, contains('your next 3 turns'));
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

  group('every status says what it does (item 13b)', () {
    // Sixteen of the 62 used to introduce themselves by name and say nothing
    // else, because the engine read a field the description did not. The
    // standing rule is that a status says what it does and how long it lasts
    // in the player's own turns, never just its name.
    test('not one of the 62 falls back to its own name', () {
      final unexplained = [
        for (final def in catalog.all)
          if (describeStatusEffect(def, onSelf: true)
              .contains('are affected by'))
            def.id
      ];

      expect(unexplained, isEmpty,
          reason: 'these say nothing a player can act on: $unexplained');
    });

    test('a description is computed from the definition, not written down',
        () {
      // Two exceptions are allowed and named: what they are worth is
      // information rather than a magnitude. Everything else has to come off
      // a field, so a re-priced magnitude updates its own text.
      var written = 0;
      for (final def in catalog.all) {
        final text = describeStatusEffect(def, onSelf: true);
        if (def.id == 'minds_eye_reveal' ||
            def.id == 'called_shot_stat_zero') {
          written++;
          continue;
        }
        expect(text, isNotEmpty);
      }
      expect(written, 2);
    });

    test('a per-remaining-turn effect says that it fades', () {
      final text = describeStatusEffect(catalog['braced'], onSelf: true);
      expect(text, contains('Defense +1'));
      expect(text, contains('every turn still left'));
    });

    test('a damage-type interaction names the type and the multiplier', () {
      final text = describeStatusEffect(catalog['wet'], onSelf: false);
      expect(text, contains('no Fire damage'));
      expect(text, contains('2x damage from Lightning'));
    });

    test('a Trion drain says who gets it and when', () {
      final text = describeStatusEffect(catalog['sapped'], onSelf: false);
      expect(text, contains('25%'));
      expect(text, contains('whoever applied this'));
    });

    test('Enraged states all three of its clauses', () {
      final text = describeStatusEffect(catalog['enraged'], onSelf: true);
      expect(text, contains('50% more damage'));
      expect(text, contains('no Psychic damage'));
      expect(text, contains('targets at random'));
    });

    test('the two written ones read as sentences, not as fields', () {
      for (final id in ['minds_eye_reveal', 'called_shot_stat_zero']) {
        final text = describeStatusEffect(catalog[id], onSelf: false);
        expect(text, isNot(contains('are affected by')));
        expect(text.split(' ').length, greaterThan(8), reason: id);
      }
    });
  });

  group('the badge tooltip counts what is actually left', () {
    test('one turn remaining still buys a whole turn', () {
      final text = describeStatusBadge(
        id: 'empowered',
        name: 'Empowered',
        remainingTurns: 1,
        onSelf: false,
      );
      expect(text, contains('25% more damage'));
      expect(text, contains('wears off at the end of their next turn'));
    });

    test('the live counter is used, not the effect default', () {
      final text = describeStatusBadge(
        id: 'bleeding',
        name: 'Bleeding',
        remainingTurns: 3,
        onSelf: true,
      );
      expect(text, contains('3 turns left'));
      expect(text, isNot(contains('Lasts through')),
          reason: 'the default duration is the wrong number on a live badge, '
              'and printing both is what the old string-splitting did');
    });

    test('the tooltip is one clean sentence per part', () {
      final text = describeStatusBadge(
        id: 'empowered',
        name: 'Empowered',
        remainingTurns: 2,
        onSelf: true,
      );
      expect(text, isNot(contains('..')));
    });
  });
}

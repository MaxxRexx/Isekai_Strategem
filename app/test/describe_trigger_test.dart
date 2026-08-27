import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/data/describe.dart';

/// A playtest read Guardian's Aegis and found a description that was wrong in
/// three separate ways at once: it called a squad buff an "attack", it said it
/// hit "all 3 targets", and it never mentioned that those 3 have to be
/// standing on the same line. Every area ability in the catalogue said the
/// same thing, because the description was written off the subtype alone and
/// never looked at who the ability was aimed at.
///
/// These tests are the catalogue-wide version of that report: not "does Aegis
/// read correctly" but "can any ability in the game misdescribe itself in
/// these ways again".
void main() {
  final triggers = TriggerCatalog.defaultCatalog.activeTriggers;
  final blackTriggerAbilities = [
    for (final bt in BlackTriggerCatalog.defaultCatalog.all) ...bt.activeAbilities,
  ];
  final all = [...triggers, ...blackTriggerAbilities];

  /// The opening clause: the sentence that says what kind of ability this is
  /// and what it reaches. Later sentences may legitimately mention attacking
  /// ("this turn sets up the attack you make then"), so the claim under test
  /// is what the ability calls *itself*.
  String opening(ActiveTrigger t) => describeActiveTrigger(t).split('. ').first;

  group('an ability only calls itself an attack if it attacks somebody', () {
    test('nothing aimed at your own side is described as an attack', () {
      final wrong = <String>[];
      for (final t in all) {
        if (t.targetAffiliation == TargetAffiliation.opponent) continue;
        final text = opening(t);
        if (text.contains('attack')) wrong.add('${t.id}: $text');
      }
      expect(wrong, isEmpty,
          reason: 'Guardian\'s Aegis is not an attack, and neither is any '
              'other ability aimed at yourself or an ally');
    });

    test('Guardian\'s Aegis reads as the line buff it is', () {
      final aegis = triggers.firstWhere((t) => t.id == 'guardians_aegis');
      final text = describeActiveTrigger(aegis);

      expect(opening(aegis), isNot(contains('attack')));
      expect(text, contains('one of your own lines'));
      expect(text, contains('Guarded'));
      expect(text, isNot(contains('Makes you')),
          reason: 'the Aegis is cast on a line, not on the caster');
    });
  });

  group('an area ability says it catches a line', () {
    test('every area ability names the line and the cap together', () {
      for (final t in all) {
        if (t.attackSubtype != AttackSubtype.aoe) continue;
        if (t.targetAffiliation == TargetAffiliation.self) continue;
        final text = describeActiveTrigger(t);
        expect(text, contains('line'), reason: t.id);
        expect(text, contains('nobody on any other line'), reason: t.id);
        expect(text, contains('${t.targetCount}'), reason: t.id);
      }
    });

    test('no ability anywhere claims to hit its targets "at once"', () {
      // The old sentence. It is the claim that broke: three targets at once
      // is exactly what an area ability cannot do across three lines.
      final wrong = [
        for (final t in all)
          if (describeActiveTrigger(t).contains('at once')) t.id,
      ];
      expect(wrong, isEmpty);
    });

    test('Cleave says two on one line, not two anywhere', () {
      final cleave = triggers.firstWhere((t) => t.id == 'cleave');
      final text = describeActiveTrigger(cleave);

      expect(text, contains('one enemy line'));
      expect(text, contains('2'));
      expect(text, contains('nobody on any other line'));
    });

    test('an area ability aimed at your side points at your lines', () {
      for (final t in all) {
        if (t.attackSubtype != AttackSubtype.aoe) continue;
        if (t.targetAffiliation != TargetAffiliation.ally) continue;
        expect(describeActiveTrigger(t), contains('one of your own lines'),
            reason: t.id);
      }
    });
  });

  group('a status rider is attributed to whoever actually receives it', () {
    test('a line buff does not say it happens to you', () {
      for (final t in all) {
        if (t.targetAffiliation != TargetAffiliation.ally) continue;
        if (t.inflictedStatusEffects.isEmpty) continue;
        final text = describeActiveTrigger(t);
        expect(text, isNot(contains('Makes you')), reason: t.id);
      }
    });

    test('a self-cast does say it happens to you', () {
      for (final t in all) {
        if (t.targetAffiliation != TargetAffiliation.self) continue;
        if (t.inflictedStatusEffects.isEmpty) continue;
        final text = describeActiveTrigger(t);
        expect(text, contains('Makes you'), reason: t.id);
        expect(text, contains('yourself'), reason: t.id);
      }
    });

    test('an area attack leaves everyone it catches, not "the target"', () {
      for (final t in all) {
        if (t.attackSubtype != AttackSubtype.aoe) continue;
        if (t.targetAffiliation != TargetAffiliation.opponent) continue;
        if (t.inflictedStatusEffects.isEmpty) continue;
        expect(describeActiveTrigger(t), contains('Leaves everyone it catches'),
            reason: t.id);
      }
    });

    test('a single-target ally ability names the ally', () {
      for (final t in all) {
        if (t.targetAffiliation != TargetAffiliation.ally) continue;
        if (t.attackSubtype == AttackSubtype.aoe) continue;
        if (t.inflictedStatusEffects.isEmpty) continue;
        expect(describeActiveTrigger(t), contains('Makes the ally'),
            reason: t.id);
      }
    });
  });

  group('every description in the catalogue is well-formed English', () {
    test('nothing is empty, doubled-up or left dangling', () {
      for (final t in all) {
        final text = describeActiveTrigger(t);
        expect(text.trim(), isNotEmpty, reason: t.id);
        expect(text, isNot(contains('..')), reason: t.id);
        expect(text, isNot(contains('  ')), reason: t.id);
        expect(text, isNot(contains(' .')), reason: t.id);
        expect(text, isNot(contains('one your')), reason: t.id);
      }
    });

    test('no description uses an em dash', () {
      for (final t in all) {
        expect(describeActiveTrigger(t), isNot(contains('—')),
            reason: t.id);
      }
    });
  });
}

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

void main() {
  group('AiProfile.all', () {
    test('has exactly 20 profiles', () {
      expect(AiProfile.all, hasLength(20));
    });

    test('has exactly 4 profiles per skill class', () {
      for (final skillClass in AiSkillClass.values) {
        expect(
          AiProfile.all.where((p) => p.skillClass == skillClass),
          hasLength(4),
          reason: '$skillClass',
        );
      }
    });

    test('every profile has a unique id', () {
      final ids = AiProfile.all.map((p) => p.id);
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('the Intermediate 4 match the confirmed archetypes', () {
      final intermediate =
          AiProfile.all.where((p) => p.skillClass == AiSkillClass.intermediate);
      expect(intermediate.map((p) => p.id).toSet(), {
        'the_executioner',
        'the_afflictor',
        'the_blast_radius',
        'the_gambler',
      });
    });

    test('The Gambler has maximum Black Trigger bias', () {
      expect(AiProfile.theGambler.blackTriggerBias, 1.0);
    });
  });

  group('AiSkillClassConfig.defaults', () {
    test('mistake chance strictly decreases from Beginner to Expert', () {
      final ordered = [
        AiSkillClass.beginner,
        AiSkillClass.amateur,
        AiSkillClass.intermediate,
        AiSkillClass.professional,
        AiSkillClass.expert,
      ];
      for (var i = 1; i < ordered.length; i++) {
        final prev = AiSkillClassConfig.defaults[ordered[i - 1]]!;
        final curr = AiSkillClassConfig.defaults[ordered[i]]!;
        expect(curr.mistakeChance, lessThan(prev.mistakeChance),
            reason: '${ordered[i - 1]} -> ${ordered[i]}');
      }
    });

    test('only Expert uses lookahead', () {
      for (final skillClass in AiSkillClass.values) {
        final config = AiSkillClassConfig.defaults[skillClass]!;
        expect(config.usesLookahead, skillClass == AiSkillClass.expert,
            reason: '$skillClass');
      }
    });

    test(
        'Beginner and Amateur are not matchup-aware; Intermediate and up '
        'are', () {
      for (final skillClass in AiSkillClass.values) {
        final config = AiSkillClassConfig.defaults[skillClass]!;
        final expected = skillClass != AiSkillClass.beginner &&
            skillClass != AiSkillClass.amateur;
        expect(config.matchupAwareEvaluation, expected, reason: '$skillClass');
      }
    });
  });
}

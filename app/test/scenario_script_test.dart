import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/scenario_script.dart';
import 'package:isekai_strategem/src/game/test_scenarios.dart';

/// The Tests tab, played by a machine.
///
/// The owner's objection, and it is a fair one: "having to test manually is
/// not efficient for me, I am very busy." Every scenario in the tab has only
/// ever been checked by a person reading its brief and following it by hand,
/// which costs an evening every time a wave lands and only happens when they
/// have an evening.
///
/// A scenario now carries a `script` beside its prose: the same run, written
/// so it can be executed. This plays every live one fifty times over fixed
/// dice and prints what held. Run it with:
///
///     flutter test test/scenario_script_test.dart --reporter expanded
///
/// Read the report as three verdicts. **PASSED** held on every seed.
/// **DICE 31/50** held on some, which is the honest answer for anything
/// sitting behind an attack roll or an infliction contest. **FAILED** never
/// held once in fifty tries, and that is a real problem: the thing under
/// test is not happening.
///
/// What this does not replace is judgement. "Does spending a turn on this
/// buff feel like it bought something" is not a question a runner can answer,
/// and those stay in the prose for a person to read and decide.
void main() {
  group('every live scenario is playable by machine', () {
    test('a scenario still in the tab carries a script', () {
      final unscripted = [
        for (final s in testScenarios)
          if (s.script == null) s.name,
      ];
      expect(unscripted, isEmpty,
          reason: 'a scenario in the tab that nothing can play is one only '
              'an evening of the owner\'s time will ever check');
    });

    test('a retired scenario needs no script', () {
      // Retired cases have been confirmed by a person already. Writing
      // scripts for them would be work with nothing waiting on it.
      final retired = allScenarios.where((s) => s.retired);
      expect(retired, isNotEmpty);
    });
  });

  group('the scripts run', () {
    for (final scenario in testScenarios) {
      test('${scenario.name}: every check holds at least once in fifty runs',
          () {
        final run = runScenarioScript(scenario);
        // ignore: avoid_print
        print(run.report);

        expect(run.blockedBy, isNull,
            reason: 'the brief tells the tester to do this, so it has to be '
                'possible from the board the scenario sets up');

        final never = run.checks.where((c) => c.isFailure).toList();
        expect(
          never.map((c) => c.check.describe).toList(),
          isEmpty,
          reason: 'these never held in fifty runs, so they are not the dice',
        );
      });
    }
  });

  group('the runner reports honestly', () {
    test('a check behind a dice gate comes back as dice, not as a pass', () {
      // Bleed's second and third stacks need strikes to land and then win an
      // infliction contest. A runner that called that PASSED would be lying
      // by rounding, and one that called it FAILED would cry wolf every run.
      final bleed = testScenarios.firstWhere((s) => s.name == 'Bleed');
      final run = runScenarioScript(bleed);
      final stacked = run.checks.where((c) => c.check.describe.contains('3 stacks'));

      expect(stacked, isNotEmpty);
      expect(stacked.single.verdict, startsWith('DICE'),
          reason: 'three stacks in one turn needs three contested strikes to '
              'land, so it is neither guaranteed nor broken');
    });

    test('a scenario with no script reports that rather than passing', () {
      final retired = allScenarios.firstWhere((s) => s.retired);
      final run = runScenarioScript(retired);

      expect(run.passed, isFalse);
      expect(run.blockedBy, 'no script');
    });
  });
}

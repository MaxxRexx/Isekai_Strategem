import 'dart:math';

import 'package:battle_engine/battle_engine.dart';

import 'battle_models.dart';
import 'play_session.dart';
import 'test_scenarios.dart';

/// A Tests tab scenario, written so a machine can play it.
///
/// The scenarios have always carried `steps` and `expectations`: prose for a
/// person, telling them what to queue and what should happen. Following them
/// by hand is the only way anything in the tab ever got checked, and it costs
/// the owner an evening every time a wave lands.
///
/// A script is the same run, written as instructions instead of English. The
/// prose stays: it is what a human reads in the brief, and it says *why*. The
/// script says *what*, exactly enough to execute, and a test drives it. What
/// the two cannot do is silently disagree, because `scenario_script_test`
/// refuses a live scenario that has no script.
///
/// This does not replace judgement. "Does spending a turn on this buff feel
/// like it bought something" is not a thing a runner can answer, and those
/// stay in the prose for a person. What it replaces is the mechanical half:
/// did the buff land on the right line, did the bleed stack, did the chain
/// fire, is the ability even queueable from where the scenario stands you.
sealed class ScenarioStep {
  const ScenarioStep();

  /// What this step is, for the run report.
  String get describe;
}

/// Queue one ability, by roster id, at other characters by roster id.
///
/// A queue the game refuses is a hard failure rather than a failed check: the
/// brief told the tester to do something they cannot do, which is worse than
/// the thing under test not working.
class QueueAbility extends ScenarioStep {
  final String actor;
  final String ability;
  final List<String> targets;

  const QueueAbility(this.actor, this.ability, {this.targets = const []});

  @override
  String get describe => targets.isEmpty
      ? '$actor queues $ability'
      : '$actor queues $ability at ${targets.join(', ')}';
}

/// Resolve everything queued, then let the enemy take their turn.
///
/// One step, because that is one press of End Turn.
class EndTurn extends ScenarioStep {
  const EndTurn();

  @override
  String get describe => 'end the turn';
}

/// Resolve what is queued without handing the turn over, for a check that
/// has to read the board before the enemy answers.
class ResolveOnly extends ScenarioStep {
  const ResolveOnly();

  @override
  String get describe => 'resolve the queue';
}

/// Something that has to be true at this point in the run.
sealed class ScenarioCheck extends ScenarioStep {
  const ScenarioCheck();

  /// True when the board says what this check says it should, false when it
  /// does not, and **null when the question no longer applies** on this seed.
  ///
  /// The third answer earns its place. A check on how many turns are left of
  /// a buff is not failed by the character carrying it being defeated three
  /// turns into a real battle: it is unanswerable, and counting it as a
  /// failure would report a bug that is not there. The first version of this
  /// runner did exactly that.
  bool? holds(ScenarioBoard board);

  /// What the board actually said, for the report. "FAILED" tells you
  /// something is wrong; "FAILED (saw 3 turns left)" tells you what, which
  /// is the difference between a report you can act on and one you have to
  /// go and investigate.
  String actual(ScenarioBoard board);
}

/// What a check is allowed to look at: the live battle, plus the log this run
/// has produced so far.
class ScenarioBoard {
  final PlaySession session;
  final TestScenario scenario;
  final List<LogRound> rounds;

  const ScenarioBoard(this.session, this.scenario, this.rounds);

  CharacterBattleState stateOf(String characterId) => session.battle.stateOf(
        scenario.playerIds.contains(characterId)
            ? session.battle.teamA
            : session.battle.teamB,
        characterId,
      );

  Iterable<LogAction> get actions => rounds.expand((r) => r.actions);

  StatusEffectInstance? statusOn(String characterId, String statusId) =>
      stateOf(characterId)
          .statusEffects
          .where((i) => i.definitionId == statusId)
          .firstOrNull;
}

/// The named character is carrying the named effect, optionally at a given
/// depth or with a given number of turns left.
class Carries extends ScenarioCheck {
  final String who;
  final String status;
  final int? stacks;
  final int? turnsLeft;

  const Carries(this.who, this.status, {this.stacks, this.turnsLeft});

  @override
  bool? holds(ScenarioBoard board) {
    if (!board.stateOf(who).isAlive) return null;
    final instance = board.statusOn(who, status);
    if (instance == null) return false;
    if (stacks != null && instance.stacks != stacks) return false;
    if (turnsLeft != null && instance.remainingTurns != turnsLeft) return false;
    return true;
  }

  @override
  String actual(ScenarioBoard board) {
    final instance = board.statusOn(who, status);
    if (instance == null) return '$who is not carrying $status';
    return '$status at ${instance.stacks} stack'
        '${instance.stacks == 1 ? '' : 's'}, '
        '${instance.remainingTurns} turn(s) left';
  }

  @override
  String get describe => [
        '$who carries $status',
        if (stacks != null) 'at $stacks stack${stacks == 1 ? '' : 's'}',
        if (turnsLeft != null) 'with $turnsLeft turn(s) left',
      ].join(' ');
}

/// The named character is not carrying the named effect. The check behind
/// "an area ability catches a line, not a squad".
class DoesNotCarry extends ScenarioCheck {
  final String who;
  final String status;

  const DoesNotCarry(this.who, this.status);

  @override
  bool? holds(ScenarioBoard board) =>
      board.stateOf(who).isAlive ? board.statusOn(who, status) == null : null;

  @override
  String actual(ScenarioBoard board) =>
      '$who carries ${board.stateOf(who).statusEffects.map((i) => i.definitionId).join(', ')}';

  @override
  String get describe => '$who does not carry $status';
}

/// A status reaction fired, by display name. Null [became] means "any
/// reaction on this status".
class ReactionFired extends ScenarioCheck {
  final String reacting;
  final String? became;

  const ReactionFired(this.reacting, {this.became});

  @override
  bool? holds(ScenarioBoard board) => board.actions.any((a) => a.reactions.any(
        (r) =>
            r.reactingName == reacting && (became == null || r.became == became),
      ));

  @override
  String actual(ScenarioBoard board) {
    final fired = board.actions
        .expand((a) => a.reactions)
        .map((r) => r.became == null
            ? r.reactingName
            : '${r.reactingName}->${r.became}')
        .toList();
    return fired.isEmpty ? 'nothing reacted' : 'reactions: ${fired.join(', ')}';
  }

  @override
  String get describe =>
      became == null ? '$reacting reacted' : '$reacting became $became';
}

/// The named character's health is at or below a number: the check for "the
/// damage went up visibly" without pinning an exact roll.
class HealthAtMost extends ScenarioCheck {
  final String who;
  final int health;

  const HealthAtMost(this.who, this.health);

  @override
  bool? holds(ScenarioBoard board) =>
      board.stateOf(who).currentHealth <= health;

  @override
  String actual(ScenarioBoard board) =>
      '$who is at ${board.stateOf(who).currentHealth}';

  @override
  String get describe => '$who is at $health health or less';
}

/// The log said something. Deliberately a substring: the check is that the
/// player was told, not how the sentence was punctuated.
class LogSays extends ScenarioCheck {
  final String text;

  const LogSays(this.text);

  @override
  bool? holds(ScenarioBoard board) => board.actions.any((a) =>
      a.reactions.any((r) => r.sentence.contains(text)) ||
      a.targets.any((t) => t.statusEffectsApplied.any((s) => s.contains(text))));

  @override
  String actual(ScenarioBoard board) {
    final lines = board.actions.expand((a) => a.reactions).map((r) => r.sentence);
    return lines.isEmpty ? 'the log said nothing of the kind' : lines.join(' | ');
  }

  @override
  String get describe => 'the log says "$text"';
}

/// How one check fared across the run's seeds.
class CheckResult {
  final ScenarioCheck check;
  final int passed;
  final int evaluated;

  /// What the board said on a seed where this check did not hold.
  final String? sawInstead;

  const CheckResult(this.check, this.passed, this.evaluated, {this.sawInstead});

  /// Nothing to be dice about: a check that never passed is a failure, one
  /// that always passed is a pass, and anything between is the dice, which
  /// is the honest answer for a check sitting behind an attack roll.
  String get verdict {
    if (evaluated == 0) return 'NOT REACHED';
    if (passed == 0) return 'FAILED';
    if (passed == evaluated) return 'PASSED';
    return 'DICE $passed/$evaluated';
  }

  bool get isFailure => evaluated == 0 || passed == 0;
}

/// What one scripted scenario did.
class ScenarioRun {
  final TestScenario scenario;
  final List<CheckResult> checks;

  /// The queue the game refused, if it refused one on every seed. A brief
  /// that tells the tester to do something impossible is its own failure.
  final String? blockedBy;

  const ScenarioRun(this.scenario, this.checks, {this.blockedBy});

  bool get passed => blockedBy == null && !checks.any((c) => c.isFailure);

  String get report {
    final buf = StringBuffer()
      ..writeln('${passed ? 'PASS' : 'FAIL'}  ${scenario.name}  '
          '(${scenario.item})');
    if (blockedBy != null) {
      buf.writeln('      BLOCKED: $blockedBy');
    }
    for (final c in checks) {
      buf.writeln('      ${c.verdict.padRight(12)} ${c.check.describe}');
      if (c.isFailure && c.sawInstead != null) {
        buf.writeln('                   saw: ${c.sawInstead}');
      }
    }
    return buf.toString();
  }
}

/// Plays [scenario]'s script [seeds] times over fixed dice and reports what
/// held.
///
/// Every seed is its own battle from the same starting board, so a check that
/// depends on an attack landing comes back as "DICE 31/50" rather than as a
/// pass or a failure decided by one lucky stream. The seeds are fixed, so two
/// runs of this agree.
ScenarioRun runScenarioScript(TestScenario scenario, {int seeds = 50}) {
  final script = scenario.script;
  if (script == null) {
    return ScenarioRun(scenario, const [], blockedBy: 'no script');
  }
  final checks = script.whereType<ScenarioCheck>().toList();
  final passes = List<int>.filled(checks.length, 0);
  final evaluated = List<int>.filled(checks.length, 0);
  final sawInstead = List<String?>.filled(checks.length, null);
  String? blocked;
  var anySeedRan = false;

  for (var seed = 0; seed < seeds; seed++) {
    final session = scenario.start(turnEngine: _seeded(seed));
    final rounds = <LogRound>[];
    final board = ScenarioBoard(session, scenario, rounds);
    var checkIndex = 0;
    var refused = false;

    for (final step in script) {
      switch (step) {
        case QueueAbility(:final actor, :final ability, :final targets):
          final outcome = session.queue(
            board.stateOf(actor).combatantId,
            ability,
            [for (final t in targets) board.stateOf(t).combatantId],
          );
          if (!outcome.success) {
            blocked ??= '${step.describe}: ${outcome.error}';
            refused = true;
          }
        case ResolveOnly():
          rounds.add(session.resolveQueue());
        case EndTurn():
          rounds.add(session.resolveQueue());
          if (!session.isOver) rounds.add(session.endTurn());
        case ScenarioCheck():
          final answer = step.holds(board);
          if (answer != null) {
            evaluated[checkIndex] += 1;
            if (answer) {
              passes[checkIndex] += 1;
            } else {
              sawInstead[checkIndex] ??= step.actual(board);
            }
          }
          checkIndex += 1;
      }
      if (refused) break;
    }
    if (!refused) anySeedRan = true;
  }

  return ScenarioRun(
    scenario,
    [
      for (var i = 0; i < checks.length; i++)
        CheckResult(checks[i], passes[i], evaluated[i],
            sawInstead: sawInstead[i]),
    ],
    // Only a blocker if it blocked *every* seed. A queue refused on some
    // seeds and not others is the battle having moved on, not a bad brief.
    blockedBy: anySeedRan ? null : blocked,
  );
}

TurnEngine _seeded(int seed) => TurnEngine(
      combatEngine: CombatEngine(diceRoller: DiceRoller(Random(9000 + seed))),
      statusEffectEngine:
          StatusEffectEngine(diceRoller: DiceRoller(Random(4000 + seed))),
      trionGainEngine:
          TrionGainEngine(diceRoller: DiceRoller(Random(2000 + seed))),
      fatEngine: FatEngine(diceRoller: DiceRoller(Random(600 + seed))),
    );

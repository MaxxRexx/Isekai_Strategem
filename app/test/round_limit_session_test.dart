import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/loadout_selection.dart';
import 'package:isekai_strategem/src/game/play_session.dart';
import 'package:isekai_strategem/src/game/simulate.dart';
import 'package:isekai_strategem/src/widgets/outcome_banner.dart';

/// Item #4's round limit, from the player's side. The rule lives in the
/// engine (see `round_limit_test.dart`); what is pinned here is that a real
/// session is subject to it, since a played battle had no cap at all before
/// this and only the simulator ever stopped.
void main() {
  const playerIds = ['vela_ashworth', 'kaito_reyes', 'dross'];
  const opponentIds = ['soren_talvik', 'ilona_vance', 'bastian_cole'];

  PlaySession freshSession() => PlaySession.start(
        playerCharacterIds: playerIds,
        playerLoadouts: {
          for (final id in playerIds)
            id: defaultLoadoutSelectionFor(id).toLoadout(id),
        },
        opponentCharacterIds: opponentIds,
        opponentProfileId: 'the_tactician',
        firstTurn: 'teamA',
      );

  test('a played battle is subject to the limit, and says so', () {
    final session = freshSession();
    expect(session.roundLimit, 30);
    expect(session.isOver, isFalse);

    session.battle.roundNumber = 31;
    // Put the player ahead by a point, which is all the tiebreak needs.
    session.battle.statesOf(session.battle.teamB).first.currentHealth -= 1;

    expect(session.isOver, isTrue);
    expect(session.outcome, BattleOutcome.teamAWins);
    expect(session.endedOnRoundLimit, isTrue);
    expect(session.teamAHealth, greaterThan(session.teamBHealth));
  });

  test('a squad still standing but level is a stalemate, not a mutual defeat',
      () {
    final session = freshSession();
    session.battle.roundNumber = 31;

    expect(session.outcome, BattleOutcome.draw);
    expect(session.endedOnRoundLimit, isTrue);
    final (text, _) = outcomeCopy(session.outcome, onRoundLimit: true);
    expect(text, 'STALEMATE',
        reason: 'nobody was defeated, so calling it a mutual defeat is untrue');
  });

  test('the simulator runs the game rule by default, and reports the timeout',
      () {
    expect(const SimulationConfig(
      teamAIds: playerIds,
      teamBIds: opponentIds,
      teamAProfileId: 'the_tactician',
      teamBProfileId: 'the_tactician',
    ).maxRounds, 30);

    // A limit short enough that no draft can finish inside it, so the run
    // has to come back decided by the rule rather than unresolved.
    final result = runSimulation(const SimulationConfig(
      teamAIds: playerIds,
      teamBIds: opponentIds,
      teamAProfileId: 'the_tactician',
      teamBProfileId: 'the_berserker',
      maxRounds: 2,
    ));

    expect(result.concluded, isTrue,
        reason: 'the limit decides it, so the run is not left hanging');
    expect(result.endedOnRoundLimit, isTrue);
    expect(result.outcome, isNot(BattleOutcome.ongoing));
  });
}

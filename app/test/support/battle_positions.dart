import 'package:battle_engine/battle_engine.dart';
import 'package:isekai_strategem/src/game/play_session.dart';

/// Pins both squads to fixed squares so a test that is not about range does
/// not have to care about it.
///
/// Team A stacks on the front line and team B spreads front/middle/back, which
/// puts an enemy at distance 0, 1 and 2 from every player character. That
/// covers all three bands at once: Close reaches 0 to 1, Mid 1 to 3, Long 2 to
/// 4. Any ability in any band therefore has at least one legal target, which is
/// what tests about queueing, resolution order and passives actually need.
///
/// Tests that are about range should place characters themselves rather than
/// call this.
void spreadForFullRangeCoverage(PlaySession session) {
  final battle = session.battle;
  for (final state in battle.statesOf(battle.teamA)) {
    state.position = BattlePosition.front;
  }
  const spread = [
    BattlePosition.front,
    BattlePosition.middle,
    BattlePosition.back,
  ];
  final teamB = battle.statesOf(battle.teamB);
  for (var i = 0; i < teamB.length; i++) {
    teamB[i].position = spread[i % spread.length];
  }
}

/// Fills the player squad's reserve with [amount] of every Trion Type.
///
/// Every ability asks for Trion Types now (item #15), and the roll that
/// supplies them is random, so a test about anything else would otherwise
/// intermittently measure the reserve instead of what it is about.
void stockEveryTrionType(PlaySession session, [int amount = 20]) {
  for (final type in TrionType.values) {
    session.battle.teamA.trionTypes.gain(type, amount);
    session.battle.teamB.trionTypes.gain(type, amount);
  }
}

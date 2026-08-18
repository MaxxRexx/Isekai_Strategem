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
  for (final character in session.battle.teamA.characters) {
    session.battle.states[character.id]!.position = BattlePosition.front;
  }
  const spread = [
    BattlePosition.front,
    BattlePosition.middle,
    BattlePosition.back,
  ];
  final teamB = session.battle.teamB.characters;
  for (var i = 0; i < teamB.length; i++) {
    session.battle.states[teamB[i].id]!.position = spread[i % spread.length];
  }
}

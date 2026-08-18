import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/draft.dart';
import 'package:isekai_strategem/src/game/play_session.dart';

import 'support/battle_positions.dart';

/// A2 (phase-priority resolution): resolveQueue orders actions by phase
/// (buffs/control before attacks, heals after), then by Team Spirit
/// deviation from the midpoint, then by queue order - independent of the
/// order the player queued them.
void main() {
  // Controlled loadout spanning three phases: two attacks (phase 4), one
  // self-buff (phase 2), one no-damage opponent control (phase 3).
  Loadout controlled(String id) => Loadout(
    characterId: id,
    triggers: [
      triggerCatalog['twin_fang_strike'], // attack
      triggerCatalog['war_chant'], // self buff
      triggerCatalog['charm_whisper'], // control (no damage)
      triggerCatalog['suppressing_fire'], // attack
    ],
  );

  // Defense trio: high Trion Capacity (fits the loadout) and known Team
  // Spirit values - Marren 55 (deviation 5), Ilona 50 (0), Bastian 50 (0).
  const squad = ['marren_osei', 'ilona_vance', 'bastian_cole'];

  PlaySession session() {
    final s = PlaySession.start(
      playerCharacterIds: squad,
      playerLoadouts: {for (final id in squad) id: controlled(id)},
      opponentCharacterIds: ['kaito_reyes', 'vela_ashworth', 'dross'],
      opponentProfileId: 'the_tactician',
      firstTurn: 'teamA',
    );
    s.battle.teamA.trionPool.gain(500);
    spreadForFullRangeCoverage(s);
    return s;
  }

  String opponentTargetFor(PlaySession s, String charId, String triggerId) => s
      .legalActionsFor(charId)
      .firstWhere((a) => a.trigger.id == triggerId)
      .legalTargetIds
      .first;

  test('a self-buff resolves before an attack queued earlier', () {
    final s = session();
    const id = 'marren_osei';
    s.forceFat(id); // allow two abilities this turn

    s.queue(id, 'twin_fang_strike', [
      opponentTargetFor(s, id, 'twin_fang_strike'),
    ]);
    s.queue(id, 'war_chant', [id]); // self target

    final round = s.resolveQueue();
    expect(round.actions.map((a) => a.triggerId).toList(), [
      'war_chant', // buffs (phase 2)
      'twin_fang_strike', // attacks (phase 4)
    ]);
  });

  test('a no-damage control resolves before an attack queued earlier', () {
    final s = session();
    const id = 'marren_osei';
    s.forceFat(id);

    s.queue(id, 'suppressing_fire', [
      opponentTargetFor(s, id, 'suppressing_fire'),
    ]);
    s.queue(id, 'charm_whisper', [opponentTargetFor(s, id, 'charm_whisper')]);

    final round = s.resolveQueue();
    expect(round.actions.map((a) => a.triggerId).toList(), [
      'charm_whisper', // control (phase 3)
      'suppressing_fire', // attacks (phase 4)
    ]);
  });

  test('within a phase, higher Team Spirit deviation resolves first', () {
    final s = session();
    // Queue Ilona (deviation 0) first, then Marren (deviation 5). Both are
    // attacks (same phase), so Marren should resolve first despite being
    // queued second.
    s.queue('ilona_vance', 'twin_fang_strike', [
      opponentTargetFor(s, 'ilona_vance', 'twin_fang_strike'),
    ]);
    s.queue('marren_osei', 'twin_fang_strike', [
      opponentTargetFor(s, 'marren_osei', 'twin_fang_strike'),
    ]);

    final round = s.resolveQueue();
    expect(round.actions.map((a) => a.characterId).toList(), [
      'marren_osei',
      'ilona_vance',
    ]);
  });

  test('equal phase and deviation fall back to queue order', () {
    final s = session();
    // Ilona and Bastian both have Team Spirit 50 (deviation 0) and both
    // queue an attack, so they resolve in the order queued.
    s.queue('bastian_cole', 'twin_fang_strike', [
      opponentTargetFor(s, 'bastian_cole', 'twin_fang_strike'),
    ]);
    s.queue('ilona_vance', 'twin_fang_strike', [
      opponentTargetFor(s, 'ilona_vance', 'twin_fang_strike'),
    ]);

    final round = s.resolveQueue();
    expect(round.actions.map((a) => a.characterId).toList(), [
      'bastian_cole',
      'ilona_vance',
    ]);
  });
}

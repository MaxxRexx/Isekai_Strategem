import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/draft.dart';
import 'package:isekai_strategem/src/game/play_session.dart';

/// Phase A (passive-counter integration): the app's resolution loop now
/// feeds the engine's passive-counter hooks, so the six counters actually
/// advance in-game. Before this wiring `notifyAbilityResolved` /
/// `recordDamageDealt` had zero runtime call sites (design 13.1), leaving
/// every passive counter inert or misbehaving.
void main() {
  Loadout attacker(String id) => Loadout(
        characterId: id,
        triggers: [
          triggerCatalog['twin_fang_strike'], // attack
          triggerCatalog['war_chant'], // self buff
          triggerCatalog['charm_whisper'], // control
          triggerCatalog['suppressing_fire'], // attack
        ],
      );

  const squad = ['marren_osei', 'ilona_vance', 'bastian_cole'];

  PlaySession session() {
    final s = PlaySession.start(
      playerCharacterIds: squad,
      playerLoadouts: {for (final id in squad) id: attacker(id)},
      opponentCharacterIds: ['kaito_reyes', 'vela_ashworth', 'dross'],
      opponentProfileId: 'the_tactician',
      firstTurn: 'teamA',
    );
    s.battle.teamA.trionPool.gain(500);
    return s;
  }

  String oppTarget(PlaySession s, String charId, String triggerId) => s
      .legalActionsFor(charId)
      .firstWhere((a) => a.trigger.id == triggerId)
      .legalTargetIds
      .first;

  test('resolving a queued ability advances Draegor Enmity in-game', () {
    final s = session();
    const id = 'marren_osei';
    s.battle.states[id]!.passiveCounters[PassiveCounterKind.draegor] =
        PassiveCounterState(PassiveCounterKind.draegor);

    s.queue(id, 'twin_fang_strike', [oppTarget(s, id, 'twin_fang_strike')]);
    s.resolveQueue();

    expect(
      s.battle.states[id]!.passiveCounters[PassiveCounterKind.draegor]!.counter,
      1,
      reason: 'notifyAbilityResolved now fires from the resolution loop',
    );
  });

  test('an attack of the sanctioned type consumes an Ironvow strike in-game',
      () {
    final s = session();
    const id = 'marren_osei';
    final ironvow = PassiveCounterState(PassiveCounterKind.ironvow);
    ironvow.sanctionedType =
        (triggerCatalog['twin_fang_strike'] as ActiveTrigger).attackType;
    s.battle.states[id]!.passiveCounters[PassiveCounterKind.ironvow] = ironvow;

    s.queue(id, 'twin_fang_strike', [oppTarget(s, id, 'twin_fang_strike')]);
    s.resolveQueue();

    expect(
      s.battle.states[id]!
          .passiveCounters[PassiveCounterKind.ironvow]!.chargesUsed,
      1,
      reason: 'checkSanctionedStrike now fires from the resolution loop',
    );
  });
}

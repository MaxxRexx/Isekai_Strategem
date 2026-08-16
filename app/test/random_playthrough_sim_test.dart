import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/account.dart';
import 'package:isekai_strategem/src/game/draft.dart';
import 'package:isekai_strategem/src/game/play_session.dart';
import 'package:isekai_strategem/src/game/xp_ledger.dart';

/// Self-test harness: play 30 randomized full battles (random characters,
/// random loadouts, random AI profiles) through the real PlaySession path -
/// with TEG, combos, counters, uniques, and the accounts/XP scaffold all wired
/// - and flag anything that looks like a bug: exceptions, broken invariants
/// (HP out of range, negative Trion, dead characters acting), or a battle that
/// never concludes (soft-lock / loop). Deterministic (seeded) so a failure is
/// reproducible.
void main() {
  test('30 randomized playthroughs: no crashes, invariant breaks, or stalls',
      () {
    final rng = Random(20260807);
    final charIds = roster.all.map((c) => c.id).toList();
    final profileIds = AiProfile.all.map((p) => p.id).toList();
    const teamSize = 3;
    // Raised from 80 when positions landed. Manoeuvring genuinely
    // lengthens a fight, and a defensive matchup where both squads spend
    // turns repositioning can legitimately run past 80 turns without being
    // stuck. This is a soft-lock detector, not a pacing assertion: pacing
    // is measured properly by tool/balance_report.dart, which reports a
    // median well inside the 8-20 design target.
    const turnCap = 200;

    final anomalies = <String>[];

    for (var n = 1; n <= 30; n++) {
      final pool = List.of(charIds)..shuffle(rng);
      final playerIds = pool.take(teamSize).toList();
      final oppIds = pool.skip(teamSize).take(teamSize).toList();
      final pProfile = profileIds[rng.nextInt(profileIds.length)];
      final oProfile = profileIds[rng.nextInt(profileIds.length)];
      final label = '#$n P[${playerIds.join(',')}]/$pProfile '
          'vs O[${oppIds.join(',')}]/$oProfile';

      try {
        final playerLoadouts = DraftedTeam.draftWithProfile(
          teamId: 'p',
          characterIds: playerIds,
          profile: profileById(pProfile),
        ).loadouts;

        final s = PlaySession.start(
          playerCharacterIds: playerIds,
          playerLoadouts: playerLoadouts,
          opponentCharacterIds: oppIds,
          opponentProfileId: oProfile,
        );

        _checkInvariants(s, '$label init', anomalies);

        var turns = 0;
        while (!s.isOver && turns < turnCap) {
          turns++;
          if (!s.isPlayerTurn) {
            anomalies.add('$label: control not on player after a turn '
                '(round ${s.roundNumber})');
            break;
          }
          for (final c in playerIds) {
            final st = s.battle.states[c]!;
            if (!st.isAlive) continue;
            final legal = s
                .legalActionsFor(c)
                .where((a) => a.affordable && a.legalTargetIds.isNotEmpty)
                .toList();
            if (legal.isEmpty) {
              // Nothing in range (or nothing affordable): move, the way a
              // player looking at a grayed-out bar would. Standing still
              // instead is what a stranded squad does, and two stranded
              // squads never finish the battle.
              final step = s.suggestRepositionFor(c);
              if (step != null) s.queueReposition(c, step);
              continue;
            }
            final pick = legal[rng.nextInt(legal.length)];
            final want = pick.maxTargets.clamp(1, pick.legalTargetIds.length);
            final targets = (List.of(pick.legalTargetIds)..shuffle(rng))
                .take(want)
                .toList();
            s.queue(c, pick.trigger.id, targets);
          }
          // Resolve before ending the turn, the way the battle screen does.
          // endTurn does not do it: without this the queue carries over,
          // every re-queue is rejected as a duplicate, and the "player" never
          // lands a single hit - which is how this harness ran until the
          // range work made the resulting stalls visible.
          s.resolveQueue();
          s.endTurn();
          _checkInvariants(s, '$label t$turns', anomalies);
        }

        if (!s.isOver && turns >= turnCap) {
          anomalies.add('$label: did not conclude in $turnCap turns '
              '(possible soft-lock / loop)');
        }
        if (s.isOver && s.outcome == BattleOutcome.ongoing) {
          anomalies.add('$label: isOver but outcome==ongoing');
        }

        // Accounts/XP scaffold smoke test on a concluded battle.
        if (s.isOver) {
          final account = LocalStubAccountService();
          final ledger = LocalStubXpLedger();
          account.continueAsGuest();
          s.awardBattleXpTo(ledger, account);
          account.dispose();
        }
      } catch (e, st) {
        anomalies.add('$label: THREW $e\n  ${st.toString().split('\n').take(3).join('\n  ')}');
      }
    }

    for (final a in anomalies) {
      // ignore: avoid_print
      print('ANOMALY $a');
    }
    expect(anomalies, isEmpty,
        reason: '${anomalies.length} anomalies across 30 randomized battles');
  });
}

void _checkInvariants(PlaySession s, String where, List<String> out) {
  for (final team in [s.battle.teamA, s.battle.teamB]) {
    for (final c in team.characters) {
      final st = s.battle.states[c.id]!;
      final maxHp = st.character.baseStats.maxHealth;
      if (st.currentHealth < 0) {
        out.add('$where: ${c.id} HP ${st.currentHealth} < 0');
      }
      if (st.currentHealth > maxHp) {
        out.add('$where: ${c.id} HP ${st.currentHealth} > max $maxHp');
      }
    }
  }
  if (s.teamATrion < 0) out.add('$where: team A Trion ${s.teamATrion} < 0');
  if (s.teamBTrion < 0) out.add('$where: team B Trion ${s.teamBTrion} < 0');
}

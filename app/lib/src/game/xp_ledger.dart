import 'package:battle_engine/battle_engine.dart';

import 'battle_xp.dart';
import 'team_efficiency.dart';

/// Combat-v2 section 5.2 / 15 (player XP) - CLIENT SCAFFOLD.
///
/// The [XpLedger] owns a player's XP. The REAL implementation MUST be
/// server-authoritative: it re-validates the reported result and applies the
/// inverse-TEG multiplier ([awardBattleXp]) server-side, never trusting a
/// client-sent number. The interface is async precisely so the in-memory
/// [LocalStubXpLedger] and a future network-backed ledger are drop-in
/// interchangeable behind the same call sites.

/// What the client reports at battle end for the ledger to score.
class BattleResultReport {
  final String playerId;

  /// Pre-multiplier base XP for the battle (win/participation/etc.). The
  /// inverse-TEG multiplier is applied on top by the ledger.
  final int baseXp;

  /// The player's squad grade this battle (drives the inverse-TEG multiplier).
  final TegTier tier;

  final bool won;
  final DateTime endedAt;

  const BattleResultReport({
    required this.playerId,
    required this.baseXp,
    required this.tier,
    required this.won,
    required this.endedAt,
  });

  /// Builds a report from a battle [outcome]; [playerIsTeamA] says which side
  /// the player controlled.
  factory BattleResultReport.fromOutcome({
    required String playerId,
    required int baseXp,
    required TegTier tier,
    required BattleOutcome outcome,
    required bool playerIsTeamA,
    DateTime? endedAt,
  }) {
    final won = playerIsTeamA
        ? outcome == BattleOutcome.teamAWins
        : outcome == BattleOutcome.teamBWins;
    return BattleResultReport(
      playerId: playerId,
      baseXp: baseXp,
      tier: tier,
      won: won,
      endedAt: endedAt ?? DateTime.now(),
    );
  }
}

/// The outcome of recording a battle: what was added and the new total.
class XpAward {
  final int baseXp;
  final int awardedXp;
  final int totalXp;

  const XpAward({
    required this.baseXp,
    required this.awardedXp,
    required this.totalXp,
  });
}

abstract class XpLedger {
  Future<int> currentXp(String playerId);

  /// Records a finished battle and returns the resulting [XpAward]. The real
  /// impl validates [report] server-side before trusting it.
  Future<XpAward> recordBattleResult(BattleResultReport report);
}

/// In-memory stand-in so XP works before the backend exists. Applies the
/// shared [awardBattleXp] formula. NOT authoritative - a real player's XP must
/// be owned by the server.
class LocalStubXpLedger implements XpLedger {
  final Map<String, int> _xpByPlayer = {};

  @override
  Future<int> currentXp(String playerId) async => _xpByPlayer[playerId] ?? 0;

  @override
  Future<XpAward> recordBattleResult(BattleResultReport report) async {
    final awarded = awardBattleXp(report.baseXp, report.tier);
    final total = (_xpByPlayer[report.playerId] ?? 0) + awarded;
    _xpByPlayer[report.playerId] = total;
    return XpAward(
      baseXp: report.baseXp,
      awardedXp: awarded,
      totalXp: total,
    );
  }
}

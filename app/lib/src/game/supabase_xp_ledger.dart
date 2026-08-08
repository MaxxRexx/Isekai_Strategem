import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'team_efficiency.dart';
import 'xp_ledger.dart';

/// Real [XpLedger] backed by Supabase (combat-v2 §5.2 / §15). Authoritative:
/// the client reports the battle result and the server (award_battle_xp in
/// supabase/schema.sql) recomputes the inverse-TEG multiplier and owns the
/// running total. The client never sends, and cannot set, an XP number.
class SupabaseXpLedger implements XpLedger {
  final sb.SupabaseClient _client;
  const SupabaseXpLedger(this._client);

  @override
  Future<int> currentXp(String playerId) async {
    final row = await _client
        .from('accounts')
        .select('total_xp')
        .eq('id', playerId)
        .maybeSingle();
    final value = row?['total_xp'];
    return value is int ? value : (value as num?)?.toInt() ?? 0;
  }

  @override
  Future<XpAward> recordBattleResult(BattleResultReport report) async {
    final rows = await _client.rpc(
      'award_battle_xp',
      params: {
        'p_base_xp': report.baseXp,
        'p_tier': report.tier.label,
        'p_won': report.won,
        'p_ended_at': report.endedAt.toUtc().toIso8601String(),
      },
    );
    // The function returns a single row: (base_xp, awarded_xp, total_xp).
    final row = (rows is List && rows.isNotEmpty) ? rows.first : rows;
    int asInt(Object? v) => v is int ? v : (v as num?)?.toInt() ?? 0;
    if (row is Map) {
      return XpAward(
        baseXp: asInt(row['base_xp']),
        awardedXp: asInt(row['awarded_xp']),
        totalXp: asInt(row['total_xp']),
      );
    }
    // Fallback: the RPC returned nothing usable.
    return XpAward(baseXp: report.baseXp, awardedXp: 0, totalXp: 0);
  }
}

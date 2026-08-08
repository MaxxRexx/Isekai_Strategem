import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'account.dart';
import 'supabase_account_service.dart';
import 'supabase_config.dart';
import 'supabase_xp_ledger.dart';
import 'xp_ledger.dart';

/// App-wide access to the accounts / XP services (combat-v2 §15). Picks the
/// real Supabase backend when it's configured and reachable, and falls back to
/// the in-memory stubs otherwise, so the game always runs even if the backend
/// is down or not yet set up. Call [Services.init] once at startup.
class Services {
  final AccountService accountService;
  final XpLedger xpLedger;

  /// True when the real Supabase backend is wired in (vs the local stubs).
  final bool backendLive;

  Services._({
    required this.accountService,
    required this.xpLedger,
    required this.backendLive,
  });

  static Services? _instance;

  /// The initialised services. Falls back to stubs if [init] hasn't run yet.
  static Services get instance =>
      _instance ??= Services._(
        accountService: LocalStubAccountService(),
        xpLedger: LocalStubXpLedger(),
        backendLive: false,
      );

  static Future<Services> init() async {
    if (_instance != null) return _instance!;
    if (SupabaseConfig.isConfigured) {
      try {
        await sb.Supabase.initialize(
          url: SupabaseConfig.url,
          anonKey: SupabaseConfig.anonKey,
        );
        final client = sb.Supabase.instance.client;
        return _instance = Services._(
          accountService: SupabaseAccountService(client),
          xpLedger: SupabaseXpLedger(client),
          backendLive: true,
        );
      } catch (_) {
        // Backend unreachable / not configured yet: fall back to stubs so the
        // game still runs. Sign-in and XP simply stay local until it's up.
      }
    }
    return _instance = Services._(
      accountService: LocalStubAccountService(),
      xpLedger: LocalStubXpLedger(),
      backendLive: false,
    );
  }
}

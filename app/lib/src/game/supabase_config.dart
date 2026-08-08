/// Supabase connection config for the accounts / XP backend (combat-v2 §15).
///
/// These two values are the PUBLIC client credentials and are safe to ship in
/// the app and commit to a public repo: the URL is public, and the publishable
/// key is designed to be exposed client-side. Row Level Security (see
/// supabase/schema.sql) is what actually protects player data, so the key on
/// its own grants no access beyond a signed-in user's own rows.
///
/// NEVER put the `service_role` / secret key, the database password, or the
/// Postgres connection string in the client. Those stay server-side only.
///
/// Overridable at build time with --dart-define for staging/other projects,
/// e.g. `flutter build web --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zzsjkanssxhejhotbrca.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_bccvU0Np263wOjd2FbBGYw_Zo_hRGyr',
  );

  /// True when both values are present (they always are, given the defaults),
  /// so app startup can decide between the real backend and the local stubs.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}

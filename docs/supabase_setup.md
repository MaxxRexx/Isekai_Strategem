# Supabase setup (accounts + XP backend)

This is the one-time dashboard setup for the combat-v2 section 15 accounts / XP
backend. The app talks to Supabase only through the `AccountService` and
`XpLedger` interfaces (`app/lib/src/game/account.dart`, `xp_ledger.dart`), so
once this is done the real backend drops in behind the same call sites.

Project: `https://zzsjkanssxhejhotbrca.supabase.co`

## 1. Create the tables and the XP function

Dashboard -> SQL Editor -> New query -> paste the full contents of
[`supabase/schema.sql`](../supabase/schema.sql) -> Run. It is idempotent, so
re-running is safe. This creates:

- `public.accounts` (one row per user, holds the authoritative `total_xp`),
- `public.xp_ledger` (append-only award history),
- Row Level Security so a user only ever touches their own rows,
- a new-user trigger that creates the account row on sign-up,
- `award_battle_xp(...)`, which recomputes the inverse-TEG multiplier
  server-side so the client can never set its own XP.

## 2. Enable the sign-in methods (stress-free onboarding)

Dashboard -> Authentication -> Sign In / Providers:

- **Anonymous sign-ins**: turn ON. This powers "Play as Guest" (zero-friction
  entry). A guest is a real user with a stable id, so their progress is kept
  and can be upgraded later without loss.
- **Email**: ON by default. We use a magic link / one-time code (passwordless),
  so nothing to remember or leak.
- **Google**: turn ON, then provide a Google OAuth client:
  1. Google Cloud Console -> APIs & Services -> Credentials -> Create
     Credentials -> OAuth client ID -> Web application.
  2. Under "Authorized redirect URIs" add:
     `https://zzsjkanssxhejhotbrca.supabase.co/auth/v1/callback`
  3. Copy the generated Client ID and Client secret into the Google provider
     fields in Supabase and save.
- **Apple** (optional, later): same idea; needs an Apple Developer account.

## 3. Set the redirect URLs

Dashboard -> Authentication -> URL Configuration:

- **Site URL**: `https://maxxrexx.github.io/Isekai_Strategem/`
- **Redirect URLs** (add both): 
  - `https://maxxrexx.github.io/Isekai_Strategem/`
  - `http://localhost:*` (for local dev runs)

These let OAuth and the email magic link return to the app.

## 4. Add the keep-alive GitHub secrets

The free tier pauses after ~7 days of no activity. The
[`supabase-keepalive`](../.github/workflows/supabase-keepalive.yml) workflow
pings the project once a day so it never pauses. It needs two repo secrets:

GitHub repo -> Settings -> Secrets and variables -> Actions -> New repository
secret:

- `SUPABASE_URL` = `https://zzsjkanssxhejhotbrca.supabase.co`
- `SUPABASE_ANON_KEY` = the publishable key (`sb_publishable_...`)

You can also run the workflow once manually (Actions tab -> Supabase keep-alive
-> Run workflow) to confirm it returns an HTTP code.

## 5. Verifying

- After the SQL runs, Dashboard -> Table Editor should show `accounts` and
  `xp_ledger` with the shield (RLS) icon enabled.
- After a test sign-in from the app, `accounts` should gain a row for that user.
- After a finished battle, `xp_ledger` should gain a row and the account's
  `total_xp` should increase by the awarded amount.

## Notes on trust

`award_battle_xp` clamps `base_xp` and owns the multiplier and running total,
so a client cannot directly set its XP. It still trusts the reported base XP and
squad grade for now; full anti-cheat (the server replaying the battle) is a
later phase and does not change these interfaces.

# Isekai Strategem

A turn-based 3v3 tactical squad battler built in Flutter and Dart. You draft a
team of three characters, build each one a Loadout of abilities (Triggers), and
fight another squad through a queue-and-resolve turn system until one side is
wiped out. Its design borrows from World Trigger (Trion, Triggers, Black
Triggers, and the Attacker / Shooter / Sniper / Trapper roles), Naruto (energy
resource play and status effects), and tabletop Dungeons and Dragons (the
20-sided-die to-hit engine, advantage and disadvantage, critical hits, and a
large library of status conditions).

A visual-novel story mode is planned but not yet built. This repository is the
battle game plus its accounts and XP backend.

## What is in the game right now

- **Draft and Loadout building.** Pick 3 of 20 characters and equip each with
  Triggers under a Trion budget (8 slots, exactly 4 active abilities).
- **Full turn-based play.** Queue your actions, choose targets, and end the turn;
  actions resolve through a fixed six-phase order. A rule-based AI opponent (five
  skill classes) plays through the same system.
- **A real battlefield.** Every character stands at Front, Middle or Back.
  Distance to an enemy is the two positions added, and each range band reaches a
  different window of it (Close 0-1, Mid 1-3, Long 2-4), so where you stand
  decides what you can use. Repositioning costs a character their action, and the
  battlefield strip under both squads shows the whole board with its distance
  ruler and the move controls in one place.
- **Deep combat systems:** 60 Triggers, 10 Black Triggers, 62 status effects, a
  reactive and passive counter system, 17 unique abilities, an 18-entry combo
  recognizer, Full Arms Trigger burst turns, and a Team Efficiency Grade that
  scores your build, grants dice advantages, and inversely scales your XP.
- **Accounts and XP (online).** A Supabase backend provides stress-free sign-in
  (guest, passwordless email, or Google) and server-authoritative XP, with a
  local-only fallback so the game always runs.
- **A readable battle log** with plain-English breakdowns and clickable
  character and ability details.

## Documentation

- **[Complete Game Design Document](docs/game_design.md)** is the single, current,
  plain-language explanation of every system and every piece of content (each
  Trigger, Black Trigger ability, status effect, perk, counter, unique ability,
  and combo), with all the numbers. A rendered PDF sits next to it at
  [`docs/Isekai_Strategem_Game_Design_Document.pdf`](docs/Isekai_Strategem_Game_Design_Document.pdf).
- **[Current Development Status](docs/current_development_status.md)** shows what
  is done, in progress, and still to do (with a status board at the top),
  followed by the detailed combat-rework design and build tracker. It also holds
  the numbered work queue that everything else refers to by number.
- [`docs/working_agreement.md`](docs/working_agreement.md) is how the project is
  run: the design-approve-build-playtest loop, and the standing design rules that
  apply to every item without being restated.
- [`docs/next_session_1b.md`](docs/next_session_1b.md) is the handoff for the
  next item (screening / RPP): the spec, where the code lives, and what to watch
  for.
- [`docs/reviews/`](docs/reviews) holds four player-persona design reviews and a
  design-director synthesis of the game's balance.
- [`docs/supabase_setup.md`](docs/supabase_setup.md) documents the accounts/XP
  backend, and [`supabase/schema.sql`](supabase/schema.sql) is its database
  schema.

Note: the Game Design Document is the single source of truth for the game's
rules and content. The older per-topic reference files that used to sit under
`packages/battle_engine/doc/` predated the combat rework, had drifted badly out
of date, and have been removed; everything they covered now lives in
`docs/game_design.md`.

## Architecture

Two layers, kept separate:

- **Battle engine** (`packages/battle_engine`): pure Dart, no Flutter dependency,
  fully unit tested. Data models, dice and roll utilities, and the rules engine
  (Trion income, Full Arms Trigger, combat resolution, status effects, counters,
  unique abilities, combo recognition, and turn orchestration).
- **Flutter app** (`app/`): the playable game. It owns the queue-and-resolve
  orchestration (`lib/src/game/play_session.dart`), the Team Efficiency Grade
  (`lib/src/game/team_efficiency.dart`), draft, Loadout building, target
  selection, all screens and widgets, and the Supabase accounts/XP integration
  (`lib/src/game/services.dart` and friends). It depends on the battle engine as
  a path dependency.

## Development

The battle engine (standalone Dart package):

```
cd packages/battle_engine
dart pub get
dart test
```

Design questions get answered by measurement rather than by guesswork. The
engine package carries a set of standalone analysis tools in
[`packages/battle_engine/tool/`](packages/battle_engine/tool), each runnable
with `dart run tool/<name>.dart`:

| Tool | Answers |
|---|---|
| `balance_report.dart` | Accuracy, dice share, Trigger value, and 200 simulated battles against the 8-20 round pacing target. |
| `position_matrix.dart` | Position against ability range, across the live catalogue. |
| `formation_matrix.dart` | Formation versus formation, and archetype viability with `--kits`. |
| `screening_model.dart` | The proposed screening rule per formation, against the current one. |
| `stall_finder.dart` | Every board state in which neither side can reach the other, and whether it can be escaped. |
| `reach_check.dart` | Specific reach claims, plus the maximum-health invariant. |
| `stackable_statuses.dart` | Which status effects should stack, and why. |

The Flutter app:

```
cd app
flutter pub get
flutter test
flutter run -d chrome   # or another connected device
```

No local machine is required to try the app. Every push to `main` or a
`claude/**` branch that touches `app/` or `packages/` runs
[`deploy-web.yml`](.github/workflows/deploy-web.yml), which runs the tests,
builds the web app, and publishes it to GitHub Pages at
<https://maxxrexx.github.io/Isekai_Strategem/>.

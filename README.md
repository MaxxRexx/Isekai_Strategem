# Isekai Strategem

A turn-based 3v3 tactical combat game with a visual novel story mode, built in
Flutter/Dart. Single-player only: rule-based AI opponent, no server, no
network play.

## Architecture

Two top-level modules, kept separate but sharing a save/state layer:

- **Battle module** (`packages/battle_engine`): the combat engine - data
  models, dice/roll utilities, and the rules engine (Trion gain, Full Arms
  Trigger, combat resolution, status effects, turn orchestration). Pure Dart,
  no Flutter dependency, fully unit tested. No UI.
- **Story module**: dialogue, sprites, backgrounds, and choice-driven scene
  scripts. Not yet scaffolded (comes after the battle engine).

A story scene will be able to trigger a battle encounter (handing off which
characters/teams are involved) and receive the outcome back to branch the
story, via a simple event/callback interface - the two modules are not
tightly coupled.

## Packages

- `packages/battle_engine` - the combat engine described above. See its
  source for design notes on rules that were underspecified and required an
  explicit (documented) interpretation.

## App

`app/` is the real Flutter application (currently web-enabled; other
platforms can be added later with `flutter create --platforms=... .`). It
depends on `packages/battle_engine` as a path dependency and calls it
directly, no JSON/JS interop boundary like the browser demo below. So far it
only has a Quick Battle screen (drafts two random AI-controlled squads and
runs a full battle through the real engine) to prove the wiring end to end;
squad drafting, a real Loadout builder UI, playing your own turns, and the
Story module UI are still ahead.

## Playing / rules

See [`packages/battle_engine/doc`](packages/battle_engine/doc) for the
player-facing guide (how to play, the character roster, Triggers/Black
Triggers, status effects, and the 20 AI opponents), and
[`packages/battle_engine/tool/web_demo`](packages/battle_engine/tool/web_demo)
for a browser-playable Engagement Simulator built on the real engine (a
standalone HTML demo, separate from the `app/` Flutter application above).

## Development

The battle engine is a standalone Dart package:

```
cd packages/battle_engine
dart pub get
dart test
```

The Flutter app:

```
cd app
flutter pub get
flutter test
flutter run -d chrome   # or another connected device
```

No local machine is required to try the app, though. Every push to `main`
or a `claude/**` branch that touches `app/` or `packages/` runs
[`deploy-web.yml`](.github/workflows/deploy-web.yml), which tests, builds,
and publishes the web app to GitHub Pages at
<https://maxxrexx.github.io/Isekai_Strategem/>.

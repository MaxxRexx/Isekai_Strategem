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

## Development

The battle engine is a standalone Dart package:

```
cd packages/battle_engine
dart pub get
dart test
```

# Active development

Before starting any work, read `docs/current_development_status.md` (the work
queue, every decision taken, and the specs for the queued items) and
`docs/working_agreement.md` (how this project is run, plus the standing design
rules). `docs/game_design.md` describes the game as it stands on `main` and is
the single source of truth for its rules and content; re-render the PDF beside
it whenever it changes.

Where the work stands is in **one place**: the "Where we are" section at the
top of `current_development_status.md`, three bullets long. It is not repeated
here, because a second copy is a second thing to keep true and the first one to
go stale.

The app's **Tests tab** (a fourth mode beside Play, Simulate and Guided
Tutorial) holds pre-arranged boards for cases that are hard to reach in an
ordinary battle. A scenario is **retired** once its case has been played and
confirmed, so the tab only ever offers what still needs a look, and an empty
tab is the finished state of a testing round rather than a fault. Each
scenario has a one-word name, because the playtest shorthand in the working
agreement addresses them by it.

A scenario also carries a **script**: the same run written so a machine can
play it. `flutter test test/scenario_script_test.dart --reporter expanded`
plays every scripted scenario (retired or not) fifty times over fixed dice and
prints what held, so the mechanical half of a playtest costs a command rather
than an evening. The judgement half ("did that buff feel worth the turn")
still needs a person.

# Session setup and handoffs

Both are automatic; this section exists so you know they are there.

- **The toolchain installs itself.** `.claude/hooks/session-start.sh` installs
  Flutter (pinned to the version the deploy workflow uses) and fetches both
  packages' dependencies before the session starts, so `dart test` in
  `packages/battle_engine` and `flutter test` in `app` work immediately. It is
  remote-only, so a local machine keeps its own toolchain.
- **Starting or finishing an item?** Use the `handoff` skill in
  `.claude/skills/handoff/`. It covers what to read and verify when picking
  work up, and what to record when putting it down, including the rule that
  matters most here: keep what was verified by running it separate from what
  was verified only by tests, and both separate from what was not checked.

# Communication style

Never use the em dash ("—") in chat responses, commit messages, code comments, or any other written output. Use a period, comma, parentheses, or a regular hyphen instead.

# Decisions requiring user input

If a task needs a decision from the user and the AskUserQuestion tool fails (or is otherwise unavailable), do not proceed on an assumed default. Stop, do not implement the decision-dependent work, and report to the user exactly what question(s) you needed answered so they can respond in plain chat instead.

# Shorthand commands

When the user writes "pif" on its own, treat it as "port into Flutter": port the most recently approved HTML/artifact mockup changes (visual design, layout, interaction pattern) into the real Flutter app in `app/`, matching existing code conventions. Always verify with `dart analyze` and `flutter test` and commit/push the result immediately after, per the workflow already established in this repo.

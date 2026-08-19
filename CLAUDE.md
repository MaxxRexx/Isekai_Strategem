# Active development

Before starting any work, read `docs/current_development_status.md` (the work
queue, every decision taken, and the specs for the queued items) and
`docs/working_agreement.md` (how this project is run, plus the standing design
rules). `docs/game_design.md` describes the game as it stands on `main` and is
the single source of truth for its rules and content; re-render the PDF beside
it whenever it changes.

Items #1 (range bands as a real battlefield) and 1b (screening, also called
RPP) are built. The next item is whatever `current_development_status.md` names
as the current priority.

# Communication style

Never use the em dash ("—") in chat responses, commit messages, code comments, or any other written output. Use a period, comma, parentheses, or a regular hyphen instead.

# Decisions requiring user input

If a task needs a decision from the user and the AskUserQuestion tool fails (or is otherwise unavailable), do not proceed on an assumed default. Stop, do not implement the decision-dependent work, and report to the user exactly what question(s) you needed answered so they can respond in plain chat instead.

# Shorthand commands

When the user writes "pif" on its own, treat it as "port into Flutter": port the most recently approved HTML/artifact mockup changes (visual design, layout, interaction pattern) into the real Flutter app in `app/`, matching existing code conventions. Always verify with `dart analyze` and `flutter test` and commit/push the result immediately after, per the workflow already established in this repo.

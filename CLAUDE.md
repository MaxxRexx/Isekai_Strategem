# Active development

While combat v2 is in progress, read docs/combat_v2_design.md before starting engine work.

# Communication style

Never use the em dash ("—") in chat responses, commit messages, code comments, or any other written output. Use a period, comma, parentheses, or a regular hyphen instead.

# Decisions requiring user input

If a task needs a decision from the user and the AskUserQuestion tool fails (or is otherwise unavailable), do not proceed on an assumed default. Stop, do not implement the decision-dependent work, and report to the user exactly what question(s) you needed answered so they can respond in plain chat instead.

# Shorthand commands

When the user writes "pif" on its own, treat it as "port into Flutter": port the most recently approved HTML/artifact mockup changes (visual design, layout, interaction pattern) into the real Flutter app in `app/`, matching existing code conventions. Always verify with `dart analyze` and `flutter test` and commit/push the result immediately after, per the workflow already established in this repo.

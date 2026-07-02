# Communication style

Never use the em dash ("—") in chat responses, commit messages, code comments, or any other written output. Use a period, comma, parentheses, or a regular hyphen instead.

# Decisions requiring user input

If a task needs a decision from the user and the AskUserQuestion tool fails (or is otherwise unavailable), do not proceed on an assumed default. Stop, do not implement the decision-dependent work, and report to the user exactly what question(s) you needed answered so they can respond in plain chat instead.

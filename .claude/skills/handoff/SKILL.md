---
name: handoff
description: Close out a work item and write the handoff a fresh session needs, or open a session by reading one. Use when finishing an item from the work queue, when the user says they are starting a new session, when they ask for a handoff or a summary of where things stand, or at the start of a session picking up someone else's work. Covers what to record, what to verify before claiming it, and what to leave behind.
---

# Handoff

A fresh session starts knowing nothing. This project runs on a queue of
numbered items and a working agreement, and every item ends with a session
boundary, so the handoff is not paperwork: it is the only thing carrying
context across the gap.

Two directions. **Arriving** is the common one, and it is short.
**Departing** is the one that takes care.

## Arriving: picking up

1. Read, in this order: `docs/working_agreement.md` (how the project is run
   and the standing design rules), `docs/current_development_status.md` (the
   queue, every decision taken, and the specs for queued items), then
   `docs/game_design.md` (the game as it stands on `main`). If a
   `docs/next_session_*.md` exists, read it after the working agreement, and
   treat it as the most specific and the most likely to be stale.
2. **Check the handoff against the code before trusting it.** The working
   agreement requires auditing before designing, and handoffs are exactly
   where an unchecked claim gets copied forward. A real example: a handoff
   stated that traps inherited a new distance rule "for free". They did not.
   The one place in the codebase doing its own distance arithmetic was a trap.
3. **Verify the state the handoff claims**, because it goes stale first:

   ```bash
   git branch --show-current
   git fetch origin main && git rev-list --count main..origin/main   # is local main behind?
   git log --oneline -5
   ```

   Local `main` has been 35 commits stale before now, which made the project's
   own tools look like they did not exist.
4. Establish the baseline before changing anything, so a failure later is
   known to be yours:

   ```bash
   cd packages/battle_engine && dart test && dart analyze
   cd ../../app && flutter test && flutter analyze
   ```

   Record the numbers. Pre-existing analyzer warnings are not yours to fix
   inside another item's diff.

## Departing: writing the handoff

Write it when an item is finishing, not when the session is ending. The two
are rarely the same moment.

### 1. Land the record where it belongs

`docs/current_development_status.md` is the durable one and outlives any
handoff file. Update, in this order:

- The **queue row** for the item: what was actually built, in specifics, not
  "done". State plainly if it has not been playtested.
- The **decisions taken**, each with the reasoning, so the next session cannot
  reopen them by accident. Include decisions made mid-build, not just the ones
  from the design review.
- The **branch table**, the **current priority**, and the **progress bars**.
- Anything the item *found* but did not fix: those become new queue items with
  the evidence attached, not sentences in a chat log.

### 2. Separate what is verified from what is claimed

The single most valuable thing a handoff carries. Three buckets, and never
blur them:

- **Verified by running it.** Give the command and the number. "938 engine
  tests, 279 app tests" beats "tests pass".
- **Verified only by tests.** The working agreement is explicit that tests
  passing and the feature being right are different claims. Say which.
- **Not checked.** Say so. Anything not driven in the real app belongs here,
  and so does anything built after the design review was approved.

### 3. Say what the next session will trip over

Only the things that cost this session real time. Be specific enough to act
on:

- The toolchain, if it is not obvious. (A `SessionStart` hook now installs
  Flutter; see `.claude/hooks/session-start.sh`.)
- Commands with non-obvious flags. The web build needs
  `flutter build web --no-web-resources-cdn` to run without a CDN, and the
  design PDF is re-rendered with `python3 docs/render_pdf.py`.
- Which tool answers which question, in `packages/battle_engine/tool/`. These
  exist so nobody guesses at a number: `stall_finder` for unreachable board
  states, `balance_report` for pacing, `long_battle_diagnosis` for why a
  battle ran as long as it did, `reach_check` and `formation_matrix`
  for reach, `screening_model` and `trap_screening_sim` for the screening
  rules, `stackable_statuses` and `doc_facts` for catalogue questions,
  `sptv_baseline` for what an action, a stat point and a Trion are actually
  worth in a played battle, and `sptv_price` for what every status and every
  ability is worth under item #3's rule. Check
  the directory rather than trusting this list: a previous handoff cited a
  `position_matrix` tool that is not in the repo, which is this section in
  miniature.
- Links to any design-review artifacts, since decisions and their options live
  there and cannot be recovered from the repo.

### 4. Retire the previous handoff

A stale handoff is worse than none, because it is written with authority. When
an item ships, delete its `docs/next_session_*.md` and clear every reference to
it (`CLAUDE.md`, `README.md`, the status document). Only write a new one if the
next item genuinely needs more than the status document already says.

### 5. Leave the tree clean

```bash
git status --short          # nothing uncommitted
git rev-list --count origin/<branch>..HEAD    # nothing unpushed
```

Merge, and delete the merged branch, **only when asked**. The working
agreement is explicit: a merge happens when the owner asks for one, after they
have playtested.

## The honesty rules that matter most here

Carried from the working agreement, because a handoff is where they get
quietly broken:

- Do not describe a feature as working when only its tests have been run.
- Distinguish a bug from a design change; they carry different urgency.
- Do not invent numbers. An unpriced first-pass value is labelled as one.
- No em dashes, anywhere, including in the handoff itself.

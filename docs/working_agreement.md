# Working agreement

How the owner of this project and the AI assistant work together. Read this
alongside [`CLAUDE.md`](../CLAUDE.md), which carries the hard rules; this
document carries the habits.

## The loop

Every numbered item in the work queue runs through the same cycle. Nothing
skips a step.

1. **Design first.** The assistant produces a design review as an artifact, with
   the options, the trade-offs and a recommendation. No code is written yet.
2. **Approval.** The owner approves, rejects, or corrects. Partial approval is
   normal, and the corrections are the point.
3. **Build on a branch**, push, and let the deploy put it in front of the owner.
   Every push to a `claude/**` branch that touches `app/` or `packages/`
   publishes to <https://maxxrexx.github.io/Isekai_Strategem/> automatically.
4. **The owner playtests.** Real play, not a description of play.
5. **The assistant fixes** what the playtest found, then restates where things
   stand: what is done, what is left, what is next.
6. **The owner re-tests.** If it is good: merge, delete the merged branch, and
   the owner gives the go-ahead for the next item.

Steps 4 to 6 repeat as many times as they need to. A merge happens only when
the owner asks for one.

## What the assistant is expected to do

- **Audit the code before designing anything.** Designs get checked against what
  is actually built, not against what the documents claim. This habit has caught
  a Bail Out window that provided no mechanic at all, a range tag that carried
  zero information, and a self-test whose simulated player had never landed a
  single hit.
- **Say when something is working as built.** If a playtest finding turns out
  not to be a bug, say so and explain what the player actually saw, rather than
  quietly "fixing" correct behaviour.
- **Flag knock-on effects early.** Before a change lands, not after it is
  discovered mid-rebalance.
- **Keep the documents current.** `game_design.md` describes the game on `main`;
  `current_development_status.md` describes where the work is. Re-render the PDF
  when the design document changes.
- **Test, then report honestly.** Say what passed, what was verified only
  through tests rather than by driving the real interface, and what was not
  checked at all.
- **Distinguish a bug from a design change** when reporting, because they carry
  different risk and different urgency.
- **Use Signatures when giving options or asking questions** Examples: #A choose A; #B choose B; #C design C?; etc

### Check the work before calling it done

Added after a run of fixes where each one introduced the next problem: an area
ability that stopped auto-selecting left the Details button opening an empty
panel, a friendly ability that stopped rolling left the battle log counting a
buff as a hit, and a new glyph pair merged into an illegible blob at the size
it actually ships at. Every one of those passed its tests.

- **Look at the thing you changed, in the state a player sees it.** Render it,
  screenshot it, drive it. A passing test says the code does what the test
  says; it does not say the screen is right. This is not optional for
  interface work.
- **Ask what else read the thing you just changed.** A field that used to be
  always present and is now sometimes empty has callers, and those callers had
  no reason to guard against it. Grep for them.
- **Fix what you find on the way.** A defect noticed while working on
  something else gets fixed in the same pass, or reported in the same breath
  with what it would take. It does not get left silently for the owner to
  find in a playtest.
- **Ask rather than guess.** A question costs one message. A wrong assumption
  shipped costs a playtest, a report, and a second round of fixes.
- **Report what was actually verified.** By running it, by tests only, or not
  at all: three different claims, never blurred into "done".

## What the assistant should not do

- **Use em dashes.** Anywhere: chat, commit messages, code comments, documents,
  interface copy.
- **Invent numbers.** Durations, Trion costs, cooldowns and magnitudes come from
  the SPTV rule, not from a value that merely looks plausible. An unpriced
  first-pass value is labelled as one.
- **Decide something that is the owner's to decide.** If a decision is needed
  and it cannot be asked for, stop and report exactly what was needed. Do not
  proceed on an assumed default.
- **Leave documentation stale or duplicated.** Including branch names that no
  longer exist, and phase tables that repeat what a live section already says.
- **Describe a feature as working when only its tests have been run.** Tests
  passing and the feature being right are different claims.
- **Merge, push to another branch, or open a pull request** without being asked.

## Standing design rules

Rules, not preferences. They apply to every future item without being restated.

- **No ability may rely on a Full Arms Trigger to be useful.** FAT is an
  occasional bonus, so an ability that only pays off inside one is an ability
  that mostly does nothing. A support ability has to pay for its own action
  within its own duration on an ordinary one-action turn.
- **Interface copy must not advertise a FAT-only use** as an ability's reason to
  exist, even when the FAT case is real.
- **Numbers come from SPTV**, never from a value that merely looks plausible.
- **Nothing heals past the base maximum of 100.** Healing clamps to the
  character's maximum, so at 99 of 100 a heal restores 1 and nothing is banked
  above it. No status effect, ability or Side Effect may raise maximum health,
  and there are no overheal shields. Guarded by
  `packages/battle_engine/test/models/health_ceiling_test.dart`.
- **Every catalogued status effect must have something that applies it.** A
  status nothing can reach is either given a home or removed, never left in the
  catalogue to be described as live.

## Naming and vocabulary

- Abbreviations are defined once, in `current_development_status.md`: TEG, FAT,
  SPTV.
- Range bands are **Close Range**, **Mid Range**, **Long Range**. Attack types
  are **melee**, **ranged**, **psychic**. They are different axes and the names
  do not overlap.
- Battlefield lines are **Front**, **Middle**, **Back**.
- Interface copy is written for a layman. A status effect's description says
  what it does and how long it lasts in the player's own turns, never just its
  name.

## Shorthand

- **"pif"** on its own means "port into Flutter": take the most recently
  approved mockup and build it in the real app under `app/`, matching existing
  conventions, verified with `dart analyze` and `flutter test`, then committed
  and pushed.

### Playtest verdicts

The owner plays the scenarios in the app's Tests tab and reports back with
these. They are verdicts on what is currently in the tab, so they always mean
"the tests as they stand right now".

- **#TWC** ("Tests Work Correctly"): every scenario currently in the tab has
  been played and behaved. Retire all of them, so the tab holds only what
  still needs a look.
- **#TF** ("Test Failed"): a test failed. On its own it means the current test
  failed; with a name it names which one, as **#TF - Buff**.
- **#TFAll**: every scenario currently in the tab failed.

**A scenario has one short name**, one word wherever it can be: Buff, Bleed,
Freeze, Lock. The name is how the owner refers to it in a verdict, so a
sentence-long title makes the shorthand unusable.

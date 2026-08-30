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
- **Keep the documents current.** All of them, not the two named here:
  `game_design.md` describes the game on `main`, `current_development_status.md`
  describes where the work is, and `README.md`, `app/README.md` and `CLAUDE.md`
  all make claims that a change can falsify. Re-render the PDF when the design
  document changes. "Update the docs" means every document that says something
  about what moved, and the check for that is its own section below.
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

### Fix it, do not hand it back

Added after a run of reports that each ended with a new thing the owner had to
approve. Approve one, and the next report ends with another. That loop is the
assistant offloading calls it is equipped to make, and it costs the owner a
round trip every time.

- **A fix that is clearly right gets made, not offered.** The assistant has the
  whole context of the game. If a defect is found and the correct fix follows
  from what is already built, it goes in the same pass. "I found X, shall I fix
  it" is not a question when the answer can only be yes.
- **Escalate a decision, never a chore.** Something is the owner's call when
  two directions are both defensible, when a balance number or a mechanic is at
  stake, or when the fix rewrites something they own. Everything else is work.
- **Every choice put to the owner is a Signature, never a hint or a paragraph
  of loose prose.** Any time options are offered, even mid-discussion, label
  them #A / #B / #C (and #D onward as needed), each with what it means and a
  recommendation, so the reply can be a single token. "Say the word", "let me
  know", "if you want", and a wall of unlabelled alternatives are all
  unanswerable. One decision per letter set; when there are several decisions,
  use several sets (#1A/#1B, #2A/#2B, and so on).
- **One report, one state of the world.** Say what changed, what it cost, and
  what is genuinely still open. A finding with no decision in it belongs in the
  work in progress, not in a queue of things for the owner to bless.

### A search that finds nothing has proved nothing

Added after the owner asked for the docs to be updated and the README was left
untouched. It had been checked, with one grep for the words the change used
("tests tab", "scenario", "wave 1", "wave 2"). The README contains none of
those words and never did, so the search could not have matched however stale
the file was. It was stale: Close Range was still written as 0-1 two waves
after item 1b widened it to 0-2, the distance rule still had no screening in
it, and the tool table listed a `position_matrix` tool that is not in the
repository. The search was then reported as if it were a reading.

- **An empty result is evidence about the search, not about the document.**
  Terms taken from the change can only match documents that already use the
  change's vocabulary, which are the documents least likely to be wrong. A
  document that is stale is usually stale in the old words.
- **Read the documents that make claims about what moved.** Open them. A rule
  restated in prose (a range band, a distance formula, a cost, a count) is
  where drift hides, because nothing compiles it and no test reads it.
- **Run the three checks that are mechanical**, from the repository root:

  ```bash
  # every file a document names exists
  grep -rhoE '`[a-zA-Z0-9_./-]+\.(dart|md|yml|yaml|sql|py)`' --include=*.md . \
    | tr -d '`' | sort -u \
    | while read f; do find . -name "$(basename $f)" | grep -q . || echo "MISSING: $f"; done

  # no document names a branch that is gone (the [^.a-z] skips .claude/ paths)
  git ls-remote --heads origin
  grep -rnE '(^|[^.a-z])claude/[a-z0-9-]+' --include=*.md . | grep -v 'claude/\*\*'

  # every relative link resolves from its own directory, not from the root
  for f in $(find . -name "*.md" -not -path "./.git/*"); do d=$(dirname "$f"); \
    grep -ohE '\]\(([^)#]+)\)' "$f" | sed -E 's/\]\(|\)//g' | grep -v '^http' \
    | while read t; do [ -e "$d/$t" ] || echo "BROKEN in $f -> $t"; done; done
  ```

- **Name the documents that were opened**, in the report. "The docs are
  updated" is not checkable. "I read README, game_design and the working
  agreement; the first was wrong about the range bands" is.

### Complicated is bad. Complex but simple is good

Added after "Status at a glance" grew into a three-column table whose middle
cell was a 250-word paragraph, and the owner asked the obvious question: how
does this tell me what to work on? It did not. The document had been kept
accurate by adding a sentence every time something changed, which is how a
summary stops being one.

The rule is one sentence and it applies to everything in this project: the
game's mechanics, how the work is run, how it is reported, how it is tested,
how options are offered, and how it is written down.

- **A low floor and a high ceiling.** Someone should understand the thing in
  one look, and still find depth in it on the tenth. That is the target for a
  status section and for a status effect alike. Range bands are the example
  that works: three words (Close, Mid, Long) that a player gets immediately,
  sitting on a distance rule with screening in it that takes a while to master.
- **Complexity belongs in the system, never in the surface.** A deep mechanic
  explained in one line is the goal. A shallow one explained in five is the
  failure, and so is a deep one that never gets its line.
- **A summary that grew is no longer a summary.** When something is added to a
  short thing, something else comes out, or it stops being short. Detail goes
  below, in a section of its own, linked to.
- **Say it once.** A fact repeated in two places is two places to be wrong, and
  it is the same failure wearing a different hat.

### When the owner asks where things are

Three bullets. Not four, not a table.

```
- We have done #a to #b.
- We are on #c now. Done: #c1 to #c3. Next: #c4 to #c5.
- After #c: #d to #g, in that order.
```

Item numbers and one clause each. Anything that does not fit that shape is
detail, and detail is what `current_development_status.md` is for. If something
genuinely needs deciding, it is a Signature underneath, not a fourth bullet.

### Cleaning up

"Clean up" is a command with a definite end state, not a nudge to tidy. When
the owner asks for it:

- **Get the work genuinely clean first.** A clean working tree, the tests and
  analyzers green, and the documents updated to match what actually shipped: no
  stale merge status, no branch named that is gone, no rule left in prose that
  the code has outgrown. Everything under "Check the work before calling it
  done" applies. This is the substance of a clean-up; the branch list below is
  the last line of it, not the point.
- **Then say which branches are safe to delete, once.** One list, each entry
  with why it is safe (its work is merged, or it was abandoned). The owner
  deletes branches; the assistant does not, and cannot anyway (a session's
  attempt is refused with an HTTP 403).
- **Never turn it into a standing reminder.** Say it the once and stop. A
  branch-deletion note repeated at the end of every session is nagging, and the
  owner has already heard it.

### Polishing

"Polish" is a request for a researched, finished design, not a tidy of wording.
When the owner says polish, of a mechanic, a feature, or an idea they have
sketched:

- **Research it properly first.** How the best and most relevant games have
  handled the same mechanic, current industry practice, and, where it matters,
  how the game's own lore and existing systems fit. Use real sources, not memory
  alone.
- **Fit it to this game.** Show how it synergises with what already exists,
  where it improves the current design, and what it would cost or complicate.
  Name the trade-offs honestly.
- **Present a highly polished version, or a few.** Concrete options worked
  through to the point of being buildable, each with its reasoning, and a
  recommendation. Not a menu of vague directions.

It is a design deliverable for the owner to approve, not a licence to build.
Nothing is built off a polish until the owner picks a direction.

## What the assistant should not do

- **Use em dashes.** Anywhere: chat, commit messages, code comments, documents,
  interface copy. The repo half is enforced, not trusted:
  `packages/battle_engine/test/no_em_dash_test.dart` fails if one lands in any
  tracked `.md` or `.dart` file. No check can see chat or commit messages, so
  those stay on the author.
- **Invent numbers.** Durations, Trion costs, cooldowns and magnitudes come from
  the SPTV rule, not from a value that merely looks plausible. An unpriced
  first-pass value is labelled as one.
- **Decide something that is the owner's to decide.** If a decision is needed
  and it cannot be asked for, stop and report exactly what was needed. Do not
  proceed on an assumed default.
- **Leave documentation stale or duplicated.** Including branch names that no
  longer exist, phase tables that repeat what a live section already says, and
  a rule written in prose that the code has since changed underneath it.
- **Describe a feature as working when only its tests have been run.** Tests
  passing and the feature being right are different claims.
- **Merge, push to another branch, or open a pull request** without being asked.
- **Delete a branch.** Deleting branches is the owner's, and a session cannot do
  it anyway (the attempt is refused with an HTTP 403). When work is merged, say
  so and, on a clean-up, list the branch as safe to delete; do not try to remove
  it. See "Cleaning up".

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

- **Never introduce a term the owner has not used or approved.** In chat, in
  commit messages, in the documents, and in code comments, use plain English,
  and reach for the owner's own words before any specialist one. `cds` is fine,
  because the owner uses it. Words like "tail" or "seam" are not: they were
  never introduced, and they read as jargon to anyone who has not already met
  them. When a new idea genuinely needs a short name, say it in plain language
  first, then propose the name and let the owner approve it before it goes into
  the documents. A term already sitting in the documents that fails this test
  is flagged for a plain-English replacement, not quietly kept.
- Every approved abbreviation and piece of shorthand lives in one place, the
  next section. Nothing else is approved, so spell it out.
- Range bands are **Close Range**, **Mid Range**, **Long Range**. Attack types
  are **melee**, **ranged**, **psychic**. They are different axes and the names
  do not overlap.
- Battlefield lines are **Front**, **Middle**, **Back**.
- Interface copy is written for a layman. A status effect's description says
  what it does and how long it lasts in the player's own turns, never just its
  name.

## Approved abbreviations and shorthand

The whole list, in one place. Anything not here has not been approved, so spell
it out rather than coin a new short form. The game-design terms are defined in
full in the cds (`current_development_status.md`); the expansions below are the
roster, not a second definition to keep in step.

| Short | Stands for | What it means |
|---|---|---|
| **cds** | `current_development_status.md` | The status document: where the work stands, the wave plan, the work queue, and every decision taken. |
| **TEG** | Team Efficiency Grade | The D-to-SSS score for how well a squad is put together. |
| **FAT** | Full Arms Trigger | The burst turn that grants up to three ability uses instead of one. |
| **SE** | Side Effect | A character's one innate, always-on trait. Called a "perk" until item 5c renamed it. |
| **SPTV** | Status Points and Trigger Value | The two-part pricing rule from item #3: SP prices an effect, TV prices a whole ability, and SP feeds into TV. |
| **pif** | "port into Flutter" | Take the most recently approved mockup and build it in the real app under `app/`, matching existing conventions, verified with `dart analyze` and `flutter test`, then committed and pushed. |

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

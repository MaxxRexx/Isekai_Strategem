# Handoff: starting item 1b (screening / RPP)

Written at the end of the session that built and merged **#1 (range bands)**, so
a fresh session can pick 1b up without re-deriving anything.

Read these three first, in order:

1. [`working_agreement.md`](working_agreement.md) - how this project is run, and
   the standing design rules. Non-negotiable.
2. [`current_development_status.md`](current_development_status.md) - the work
   queue, every decision taken, and the specs for 1b, 1c and 3b.
3. [`game_design.md`](game_design.md) - the game as it stands on `main`.

## Where things stand

**#1 is merged to main and green**: 926 engine tests, 266 app tests, no analyzer
errors. The battlefield exists, characters move, range is enforced at queue time
and at resolution, and the interface draws it.

**Nothing is in progress.** There is no work branch. Create one named for 1b.

## What 1b is

One change to how distance is computed, plus one number.

```
effective distance to an enemy =
    my line's step + their line's step + screens

screens = living members of the target's squad standing on a line
          strictly in front of the target, on the target's own side
```

No subtraction: an unscreened target sits at its base distance and nothing goes
below it. **Close Range widens from 0-1 to 0-2** at the same time.

Steps are Front 0, Middle 1, Back 2. Ally distance is unchanged (the difference
of the two steps, maximum only, no screening).

### Why both halves are needed

Screening alone makes the back line safer, not reachable. The widening is what
lets a Close build cash in after breaking a screen: with the screen dead the
sniper sits at distance 2, which Close 0-1 cannot reach and Close 0-2 can.

A survey of all 4900 kit-and-formation board states
(`tool/stall_finder.dart`) found that Close 0-2 is also what removes every board
state in which neither side can reach the other. Under Close 0-1 one such state
survives; under 0-2 there are none.

### What it produces

A squad stacked on one line screens nobody, so the back-camp stops working of
its own accord. A sniper behind two bodies sits at effective distance 4 and only
Long Range reaches; kill one screen and Mid opens up; kill both and Close
arrives. No squad can make itself entirely unreachable, because the frontmost
character always has zero screens.

## Where the code is

| What | Where |
|---|---|
| Distance and reach windows | `packages/battle_engine/lib/src/models/battle_position.dart` |
| `canReach` / `canTarget` / `reachableAbilityCount` / `suggestReposition` | `.../engine/turn_engine.dart` |
| AI positional judgement (`_planStep`) | `.../ai/profile_driven_ai.dart` |
| Projected position, queueing, the arm phase | `app/lib/src/game/play_session.dart` |
| The battlefield strip and its distance ruler | `app/lib/src/widgets/battlefield_rail.dart` |

`BattleDistance.betweenEnemies` is the single place the enemy distance is
computed. Screening needs the target's team, which that helper does not
currently receive, so the signature has to change and every caller with it.
That is the main mechanical shape of the work.

## Watch for

- **The distance ruler** in the battlefield strip prints the real number, so it
  must print the screened one. That is most of the interface work.
- **`maxEnemyDistance` is 4** and screened distances reach 6. Anything relying
  on the old bound needs checking.
- **Ally-targeted abilities are not screened.** Only enemy distance changes.
- **Area attacks and traps** both read the same distance, so they inherit
  screening for free. Confirm rather than assume.
- **The AI must still find a firing position.** Its walk-toward-the-band
  fallback should handle two-step approaches, but that is untested; a test that
  a stranded squad reaches firing position within two turns would earn its keep.

## Tools that answer questions without guessing

All in `packages/battle_engine/tool/`, runnable with `dart run`:

| Tool | Answers |
|---|---|
| `position_matrix.dart` | Position against ability range across the live catalogue. |
| `screening_model.dart` | The proposed rule per formation, against the current one. |
| `formation_matrix.dart` | Formation versus formation; `--kits` for archetype viability. |
| `stall_finder.dart` | Every mutually unreachable board state and whether it can be escaped. |
| `reach_check.dart` | Three specific reach claims, plus the maximum-health invariant. |
| `stackable_statuses.dart` | Which statuses should stack and why. |
| `balance_report.dart` | Accuracy, dice share, Trigger value, and 200 simulated battles against the 8-20 round target. |

## Decided, so do not re-litigate

- Screening adds distance. No subtraction.
- Close Range 0-2.
- Redirect-a-hit is a Side Effect, not a global rule.
- Pull and push (1c) come after #4, not with 1b.
- The 30-round limit with a health tiebreak belongs to #4.
- FAT: still a per-character roll each turn; the squad claims it when one
  character queues a **second** action, which switches it off for the others.
  Un-queueing that action releases the claim. The cooldown wipe stays with
  everyone who rolled.
- Perks are being renamed to **Side Effects (SEs)** as item 5c, in its own
  commit.

## Noticed at the end of #1, not yet chased

A balance run on `main` produced a **118-round battle** out of 200. Everything
concluded and the median is 14, so it is not a stall, but it is item **4b** now.
It matters before #4's 30-round limit lands: a match that would have run 40
rounds will instead end on the health tiebreak, handing the win to whoever led
at round 30.

## Still open

- The four remaining unreachable statuses (`wet`, `enraged`, `adrenaline_rush`,
  `battle_trance`) get homes under item 3b rather than deletion. A test
  asserting every status is reachable should land with that work.
- Whether the 1b branch also carries the interface work or leaves it to a
  follow-up. The strip and the ruler are the visible half, so probably together.

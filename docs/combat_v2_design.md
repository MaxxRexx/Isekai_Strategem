# Combat v2: Queue Resolution, Counters, Uniques, and Team Efficiency Grade

Status: approved design, implementation in progress (see section 13 for the
live build status). This document is the source of truth for the multi-phase
combat rework. It supersedes ad-hoc chat design notes. Numbers marked
"tunable" are proposals to be finalized during implementation.

## 1. Goals

1. Replace immediate ability resolution with a **queue then resolve** turn
   model, so reactive/counter abilities can exist and so the framework is
   ready for server-authoritative multiplayer.
2. Add a large set of **counter** abilities (active, Black Trigger, and
   passive) that reward reading the opponent, in the spirit of
   Naruto-Arena, Hunter x Hunter Nen restrictions, World Trigger traps, and
   Bleach constant effects.
3. Add a real **Unique** attack subtype: bespoke-resolution abilities that
   do not fit single/AoE/burst.
4. Rebalance the base Trigger catalog to 20 melee / 20 ranged / 20 psychic.
5. Add a **Team Efficiency Grade (TEG)** that scores squad build quality and
   feeds a set of dice-advantage effects (see section 5.2).

## 2. Turn model (alternating queue resolution)

Alternating turns, Naruto-Arena style:

> you queue -> end turn -> your queue resolves -> opponent queues -> end
> turn -> their queue resolves -> repeat.

Rules:

- **Trion is spent at queue time** (prevents over-queuing). **Un-queueing
  refunds it.**
- **Cooldown is applied at resolve time**, not queue time, so an un-queued
  ability is not stuck on cooldown.
- The player may add/remove/change queued actions freely until End Turn.
  Once End Turn is pressed, the queue is locked (no un-queue mid-resolution).
- A cosmetic "Resolving..." delay (about 1.5 to 2 seconds) precedes results.
  VFX/animation can slot in here later.
- **Counters/traps are set on your turn and trigger on the opponent's
  turn.** Nothing peeks a live pending queue (impossible under alternating
  turns). You place a ward/trap/mark on your turn; when the opponent acts
  into it during their resolution, it fires. This is the correct framing for
  Deadfall, Puppet Strings, Foresight Counter, etc.

## 3. Resolution-order formula

When a team's queue resolves, actions do NOT resolve in click order. Each is
sorted into a phase; phases resolve in fixed order; within a phase, ties
break by Initiative.

Phases:

1. **Arm / Setup**: wards, traps, marks, untargetable, vows, Mind's Eye
   reveal (anything that only sets state, no damage). Live before anything
   else.
2. **Buffs**: self/ally buffs (empower, guard). So your own later attacks
   benefit.
3. **Control**: pure debuffs with no damage (stun, silence, Called Shot,
   Seal of Severance, forced-miss). Land before damage.
4. **Attacks**: anything that deals damage (including damage-plus-status
   riders). Each attack is resolved against the target's standing reactive
   stack (counters, wards, redirects, resonance, passives) which can negate,
   reflect, dodge, redirect, or modify it. This is the "compare against the
   opponent" step.
5. **Heals / Drains**: non-damage healing and siphons, after damage so the
   math is sane.
6. **Cleanup**: delayed detonations, end-of-turn triggered actions (for
   example Gravehour's free finisher), end-of-turn ticks.

**Initiative:**

- **Cross-team** (both teams' effects would resolve at the same instant -
  for example a reactive trigger from each side clashing): does not arise
  under alternating resolution, because the two teams never resolve in the
  same pass. The earlier design used TEG as a cross-team resolution-order
  tiebreak here; that has been **retired** (it can never fire). TEG's
  mechanical role is now the dice-advantage effect set in section 5.2. Turn
  order (who acts first) remains a separate, even 50-50 coin flip, not tied
  to TEG or any stat.
- **Within a single team's own queue**, phase order governs; ties within a
  phase break by the acting character's **Team Spirit deviation from
  midpoint** (bigger commitment = higher initiative), then queue order. TEG
  cannot tiebreak here because it is shared across the team.

Worked example: you queue War Chant (self-empower), Longshot (single-target
on EnemyX), Frost Lance (single-target damage+chill on EnemyX). EnemyX has
Mirror Ward standing. Phase 2 empowers you. Phase 4 resolves Longshot, which
is single-target, so Mirror Ward reflects it back onto your shooter at full
effect, boosted by your own empower. Frost Lance likewise reflects. Lesson:
an AoE would have bypassed the ward.

## 4. Team Spirit model (unchanged) and display

Team Spirit is [0, 100] with 50 neutral (constants.dart). Toward 0 it scales
offense (up to +30% single/burst damage, +20 crit at TS 0). Toward 100 it
scales sustain (up to +30% heal regen, +20 FAT chance at TS 100). At 50, all
bonuses are 0. There is no negative TS and no 0-centered model. Both extremes
are good, for different builds.

UI: when TS is displayed, also show the live effects at the current value,
for example "TS 45 -> +6% damage, +4 crit (offense pole)", so the
dual-direction stat is legible.

## 5. Team Efficiency Grade (TEG)

A squad-level grade, D to SSS, shown under Player Info, measuring how well
tuned a squad is (not how powerful).

### 5.1 What TEG scores (six sub-scores)

Six sub-scores (each 0 to 100), weighted into a 0 to 100 composite (weights
tunable):

| Sub-score | Weight | Rewards |
|---|---|---|
| Team Spirit Alignment | 25% | Whether each character's loadout leans offense or sustain, and whether their TS sits on the matching pole. Committed matching extremes score highest; a mismatch tanks it. This is the "is high or low TS actually right for this squad" factor. |
| Stat Coherence | 20% | Each character's raw stats fitting their loadout's role (attacker kit wants ATK/Crit, defender kit wants Armor/DEF, afflictor wants Infliction). |
| Loadout Synergy | 20% | Complementary abilities across the three: setup to payoff chains, debuff-applier plus debuff-exploiter, protector plus carry, counters that fit the plan. |
| Perk Utilization | 15% | How well the loadout plays to each character's Perk. |
| Trion Economy | 10% | Whether the squad can afford its per-turn ability costs given Capacity/Affinity. |
| Resonance Fit | 10% | Only if Black Triggers are equipped: each BT's resonance grade with its wielder's type. No BT means this weight is dropped and the other five renormalize. |

Tier ladder (composite to grade, tunable): D 0-39, C 40-54, B 55-67,
A 68-78, S 79-88, SS 89-95, SSS 96-100. SSS is deliberately hard.

### 5.2 TEG's mechanical effects (the combination amplifier)

Design decision (supersedes the earlier cross-team resolution-order
tiebreak, which cannot occur under the alternating resolution we are
keeping: two teams never resolve in the same pass, so there is never a
cross-team tie). TEG expresses itself as a **combination amplifier routed
through the existing d20 / RollContext advantage system**
(`util/dice.dart`: `RollMode`, composable `RollContext`, `D20RollResult`
with nat-20/nat-1 crits). Higher TEG does **not** inflate damage or stats;
it changes how often the dice favor a coordinated squad. Low TEG is never
penalized in combat; instead it earns more post-battle XP, so TEG is a
risk/reward dial, not a strictly-better stat. All numbers below are
first-pass and tunable (Phase H).

**Effect 1 - Coordination (offensive advantage).** Per qualifying
**offensive** d20 (attack to-hit and, by design, status-infliction rolls),
the squad has a TEG-scaled chance to gain **advantage**. Engine hook (code):
`TurnEngine._applyTegOffenseAdvantage` rolls the chance and calls
`addAdvantage('teg_offense')` on the attacker's `RollContext` before
`resolveAttackRoll`. Wired today on the attack to-hit roll only; the
status-infliction roll site uses the same helper but is not yet wired.

| TEG | D | C | B | A | S | SS | SSS |
|---|---|---|---|---|---|---|---|
| Adv chance | 0% | 3% | 6% | 9% | 12% | 16% | 20% |

**XP counterweight (inverse).** Battle XP is scaled inversely to TEG, so a
weaker-graded squad levels faster (an underdog playstyle) and an elite squad
pays an "elite tax." Depends on real, server-authoritative XP + an account
system (see section 15, product roadmap). Drafted as a bonus multiplier on
base XP; exact formula pinned by that task.

| TEG | D | C | B | A | S | SS | SSS |
|---|---|---|---|---|---|---|---|
| Battle XP bonus | +75% | +63% | +51% | +40% | +28% | +16% | +5% |

**Effect 2 - Operator's Read (defensive advantage, inverted).** Advantage on
the squad's **defensive** d20s only: the defender's roll in an opposed attack
contest (`resolveAttackRoll`'s `defenderContext`) and status-resistance rolls
(`rollContextFor(StatusRollTag.statusResistanceRoll)`). **Inverted** vs TEG:
the less in sync a squad is, the more it runs on instinct. Note (verified in
code): counters/traps themselves do **not** roll (they fire on a condition
match, not a contest), so Effect 2 attaches to these two real defensive
rolls, not to counter resolution.

| TEG | D | C | B | A | S | SS | SSS |
|---|---|---|---|---|---|---|---|
| Def adv chance | 20% | 16% | 12% | 9% | 6% | 3% | 0% |

**Effect 3 - Synergy Refunds (Trion).** On a recognized **setup->payoff**
combo (a payoff offensive ability landing on an enemy under a control/debuff
status **an ally applied**), refund part of the payoff's Trion cost. **SS
caps at 20%; SSS is 0%** and takes Effect 5 in its place.

| TEG | D | C | B | A | S | SS | SSS |
|---|---|---|---|---|---|---|---|
| Trion refund | 0% | 4% | 8% | 12% | 16% | 20% | 0% (-> fx5) |

**Effect 4 - Focus Fire / combo amplifier (recognizer built; consumption not
yet wired).** When the squad executes a **recognized combo**, the payoff
gains advantage, its strength scaled by the combo and **hard-capped at 20%**
(the universal advantage-chance ceiling; focus fire is how sub-SSS squads
climb to it). This is deliberately **not** positional: it depends on the
**Combo Recognition system** (Phase I, merged to main: action ledger +
condition primitives + `ComboRecognizer` + Layer-1 generic catalog). The
recognizer exists and is unit-tested; Effect 4's consumption of it (mapping a
`RecognizedCombo`'s strength to an advantage chance, plus live ledger
population during resolution) is **not yet built**.

**Effect 5 - Crit Range Widener (SSS only).** Always-on at **SSS only**: the
squad's attack rolls crit on a **natural 18-20** on the kept die (vs nat-20
normally; hooks `criticalHitThreshold` / kept-die crit eval). Compounds with
advantage. This is what SSS gets **instead of** Effect 3 refunds.

### 5.3 Resulting tier identities (sanity check)

- **D (instinct survivor):** 0% offense adv, best defense (20%), no refunds,
  no crit widen, most XP (+75%). Fast-leveling underdog.
- **SS (peak economy):** strong offense (16%), thin defense (3%), max refunds
  (20%), low XP. The combo-engine sweet spot.
- **SSS (coordination glass cannon):** max offense (20%), no defensive read
  (0%), no refunds, crit on 18-20, least XP (+5%). All-in on offense.

Display: letter grade prominent under Player Info; tap to expand the six
sub-scores. Also surface which effects are live at the current grade so
players can optimize toward it. Draegor's counter also reads the grade as a
threshold (section 6.2), and its "raise TEG 2 tiers" effect now has teeth
again because TEG shifts the roll-advantage tables above.

## 6. Counters

### 6.1 Active / Black Trigger counters (13)

Each is a distinct archetype. Home = the existing Trigger or Black Trigger it
attaches to.

| Ability | Home | Mechanic |
|---|---|---|
| Foresight Counter | Bastion Frame (BT) | Call one attack class when set; if the opponent's move against the warded ally matches, negate it and Stun the attacker 2. Wrong guess: nothing. |
| Mirror Ward | Wellspring (BT) | The only reflect. Any non-AoE hit against the wielder bounces back onto its user at full effect. AoE bypasses. |
| Seal of Severance | Ashbringer (BT) | On hit, lock out one origin category (Physical/Energy/Afflict/Mental) for 2 turns; every ability the target owns in that category becomes uncastable. |
| One More Breath | Gravebind (BT) | Enriches the survive-at-1-HP world ability: on trigger, double all the wielder's current status durations and Stun whoever landed the blow. |
| Puppet Strings | Paradox Shard (BT) | Name a target; if the opponent's next queued ability attacks it, redirect onto one of their own allies. Wielder is Exposed while armed. |
| Deadfall | Paradox Shard (BT) | Mark an enemy; during their next turn, if the marked enemy uses a damaging ability, it is countered and they take the trap damage. |
| Root Snare | binding_snare (trigger) | On hit, apply forced_repetition: target is locked to only their last-used ability; if it is on cooldown, they have no legal action until Forced Repetition expires or that ability returns. |
| Predictive Parry | Twin Fang Strike (trigger) | The only dodge. Once/battle: a melee single-target attack is dodged and answered with a free counter-hit. |
| Numbing Toxin | Venom Needle (trigger) | Burst mitigation: a multi-hit Burst against the wielder only lands its first hit. |
| Death Ledger | Marked for Death (trigger) | Mark one enemy (once per enemy per battle). If they use an AoE against your team, it is nullified and the wielder swaps their nearest-Trion-cost Trigger with that AoE Trigger for 2 turns, then reverts. |
| Scramble | Mind Shatter (trigger) | For 2 turns, the target's queued attacks have a chance to misfire onto their own teammate (random, not chosen). |
| Stored Retribution | Guardian's Aegis (trigger) | While Guarded/Braced, incoming damage is banked as a charge; the wielder's next ability deals bonus damage from the store. |
| Frozen Tempo | Frost Lance (trigger) | The ranged attack lands, but the attacker's ability takes twice as long to come off cooldown next. |

### 6.2 Passive-trigger counters (6)

Each is stateful/reactive, sits on a distinct system lever, encourages
forward play, and is not a flat stat buff.

**Draegor** (lever: the resolution engine).
- Each time the holder uses an ability, +1 Enmity.
- At 5 Enmity, consume all 5, gain 1 Regret (lasts 2 turns).
- While Regret is up, if the opponent chains 2+ abilities in a FAT turn,
  consume 1 Regret and for 2 turns: raise your TEG by 2 tiers (cap SSS).
  Exception: if TEG is already SS or SSS, instead double the Trion Affinity
  of your highest-TA ally for those 2 turns.
- Hard cap: your team may only gain 3 Regret total per battle; then Enmity
  and Regret generation stop.
- Design notes: the player controls when the 5th ability lands, so they
  choose when the window opens. Your own FAT can force a window open
  prematurely (a self-imposed timing dilemma). The 3-Regret cap is team-wide,
  so running multiple Draegors is redundant (no extra windows) and
  simultaneous windows waste (one FAT-chain is caught once). Spread windows
  over time with a single Draegor; concentrate on a turn you can read a
  forced FAT-chain.

**Nullhymn** (lever: power-investment; anti-BT and anti-affliction).
- +1 Discord when an enemy uses a Black Trigger active against your team; +1
  when an enemy inflicts a status on the holder (deduped per status per
  turn).
- At 5 Discord, discharge (max twice per battle): if any enemy runs a BT,
  the most-recently-active one permanently loses a resonance grade
  (A to B to C to D). If no enemy runs a BT, purge all debuffs on your team
  and reflect them onto the enemy who applied the most, at remaining
  duration.

**Reckoning** (lever: luck and tempo debt).
- +1 Debt when an enemy lands a crit on your team; +1 when an enemy uses a
  2+ cooldown ability against your team.
- At 6 Debt, comes due (reset, internal lockout): the enemy who ran up the
  most Debt has all current cooldowns extended +1, their next attack roll is
  forced to a critical miss, and your team levies Trion (see Levy below).

**Gravehour** (lever: punishing indecision; merges Bloodclock and
Deathknell).
- At the end of each opponent turn, if the opponent either dealt no damage
  (stalled) or left any enemy alive at 30% HP or below: the holder makes a
  free, uncounterable finisher on the lowest-HP living enemy, and that enemy
  cannot be healed on the opponent's next turn.
- After it fires: 3-turn cooldown, and one of the holder's own abilities is
  put on cooldown 1 turn at random (if already on cooldown, extend by 1).
- The free finisher resolves as a Phase-6 triggered action during the
  opponent's turn (like a trap), attributed to the holder, uncounterable, no
  Trion, no queue slot.

**Coldread** (lever: prediction).
- At the start of each of your turns, secretly mark one enemy (hidden from
  the opponent).
- Resolves at the end of the opponent's next turn. On a **correct read**
  (the marked enemy took a damaging action) grant a reward that
  **alternates** each successful read, **Levy first**:
  - 1st successful read: **Levy** the marked enemy's costliest action's
    Trion (the shared steal rule below).
  - next successful read: **Seize** - grant the whole squad a flat **+2 to
    all their rolls for 1 turn**.
  - alternates thereafter (Levy, Seize, Levy, ...). A wrong read does not
    advance the alternation.
- On a **wrong read** (no damaging action from the marked enemy), your Trion
  gain is docked next turn.
- After a read resolves (right or wrong), 1-turn cooldown before the next
  call.
- Note: Seize's +2 is a flat roll **modifier** (added to the d20's
  `modifier`), distinct from advantage, applied squad-wide for 1 turn. This
  makes Coldread self-contained and independent of the TEG effects (it does
  NOT rely on the retired cross-team tiebreak).

**Ironvow** (lever: type discipline; merges Interdict and Ironvow).
- At the start of each of the holder's turns, one attack type is sanctioned
  at random, but never the type the holder attacked with last turn (forced
  rotation = Interdict's anti-repetition).
- Attack with the sanctioned type -> Sanctioned Strike: unblockable/
  undodgeable, strips one active buff, and brands the target with Interdict
  (if that enemy uses the same ability two consecutive turns, the repeat
  lands at heavily reduced power).
- Cost: honoring the vow leaves your other living allies Vulnerable to the
  sanctioned type until your next turn, unless the holder is the last one
  alive.
- Caps: 3 Sanctioned Strikes per battle, 2-turn cooldown between them.
  Attacking off-sanction is a normal attack. Mono-type loadouts self-punish
  (after their type is used, the rotation sanctions a type they do not own),
  so diverse kits earn the full 3.

**The Levy** (shared refund rule for Coldread and Reckoning): a steal, plus
your pool and minus theirs, capped at whatever Trion the enemy team actually
has. Not "give back what you spent," not free generation. An actual transfer.

## 7. Unique subtype

Unique is the bespoke-resolution subtype: each Unique ability defines its own
targeting (chosen, auto, self, or none) and its own resolution rule. It is
now legal for melee, ranged, and psychic (a one-line change to
AttackTypeSubtypes.validSubtypes). Engine-wise it is a closed set of named
behaviors the engine dispatches on (mirrors WorldAbilityEffect / CharacterPerk),
not open scripting.

### Melee unique (5)

- **Shared Agony**: auto-targets a random enemy the caster has melee-hit this
  battle. Roll damage; deal it to self in full (can kill the caster), and
  +20% to that enemy. Needs new fields on ActiveTrigger:
  selfDamagePercentOfDealt and linkedTargetDamageMultiplier.
- **Grave Bargain**: chosen. Spend a chunk of current HP; deal that exact
  amount as unavoidable true damage (no roll, ignores armor/defense).
- **Martyr's End**: none. Only usable below 25% HP. The caster is removed
  from the battle; every enemy takes massive damage.
- **Vow of the Duel**: chosen. Bind to one enemy for 3 turns: double damage
  to them, but the caster cannot act on anyone else or be healed. If they are
  alive when it ends, the caster is Stunned 2.
- **Sunder Arms**: chosen. Strike plus permanently destroy one random
  equipped Trigger of theirs for the battle; the caster permanently loses one
  of their own (their choice).

### Ranged unique (2)

- **Curving Shot**: chosen. Ignores the first ward/dodge/counter the target
  has up and always resolves.
- **Called Shot**: chosen plus a declared stat. Zero that stat on the target
  for 2 turns. No damage.

### Psychic unique (10)

- **Mind's Eye**: reveal one enemy's full loadout in their panel, clickable,
  for N turns. Cannot be used by the caster.
- **Forced Choice**: next turn the target may only use their cheapest or
  priciest ability (caster declares which).
- **Memory Theft**: copy the target's last-used ability; the caster may cast
  it once next turn. The copy occupies Memory Theft's own slot, so the caster
  never exceeds 4 active abilities.
- **Sensory Swap**: swap one active status effect between two characters
  (enemy to enemy, or self to enemy).
- **Dread Resonance**: damage scales with the total damage that enemy has
  dealt this battle.
- **Isolation**: for 2 turns, that enemy cannot be healed/buffed by allies
  and cannot heal/buff them.
- **Illusory Double**: 0 Trion cost, 2-turn cooldown always. Starts with 1
  charge; +1 charge each time an ally is defeated. Target self or an ally:
  that character is untargetable for the whole of the opponent's next turn
  (visible icon).
- **Echoing Doubt**: force the target's next attack to whiff while they still
  pay Trion and cooldown, then backlash plus Silence. Deterministic, rewards
  the play (not RNG).
- **Karmic Bind**: 3-turn damage/heal link with a chosen enemy; both
  fractions scale with the caster's Team Spirit (about 25% at low TS up to
  about 60% at high TS).
- **Unmaking**: invert all the target's active buffs into their debuff
  equivalents for the remaining duration (Empowered to Weakened, Guarded to
  Exposed, etc.).

### 7.1 Cross-team unique wiring (done in Phase E)

Two unique behaviors were implemented at the engine-state level in Phase C
but needed cross-team wiring that lives in the Battle layer, not
`TurnEngine`. Both are now wired (Phase E):

- **Karmic Bind live propagation** - done, "Punish" (one-way) semantics.
  `TurnEngine` gained an optional `characterRegistry` (set by the Battle
  constructor); `_propagateKarmicBind` fires from `_applyDamage` and both
  heal sites, dealing a Team-Spirit-scaled fraction of any damage the
  caster takes or healing it receives to the bound enemy as unavoidable
  true damage. Reads the fraction from the caster's `karmic_bind` status,
  so it stops when that 3-turn status expires; guarded against recursion.
- **Illusory Double charge-on-ally-death** - done.
  `Battle.initializeIllusoryDoubleCharges` grants holders their starting
  charge; `Battle.checkForDefeats()` grants a holder +1 charge per ally
  defeat (idempotent), called at start/end of turn and exposed for a host
  to call after mid-turn resolutions.

## 8. Trigger catalog rebalance to 20 / 20 / 20

Base Trigger catalog only (Black Triggers stay a bespoke 10-entry set).
About 26 new Triggers needed. Subtype distribution (respecting
AttackType.validSubtypes: melee has no burst/unique historically but unique
is now allowed; ranged has no unique historically but 2 are now allowed;
psychic has no burst):

| Type | Single | AoE | Burst | Unique | Total |
|---|---|---|---|---|---|
| Melee | 10 | 5 | 0 | 5 | 20 |
| Ranged | 5 | 5 | 8 | 2 | 20 |
| Psychic | 5 | 5 | 0 | 10 | 20 |

Exact ability list and dice/Trion/cooldown numbers to be finalized in
Phase D, following existing tuning conventions.

## 9. New engine primitives required

UniqueBehavior / unique target-rule dispatch; reactive-stack evaluation
during Phase 4 (generalize Sable's redirect); reflect / dodge / negate /
redirect / category-lockout / forced-repetition / forced-miss /
burst-mitigation / damage-banking / cooldown-sabotage; buff inversion;
status relocation and status steal; ability copy; persistent bidirectional
links; trigger swap and permanent trigger destruction; loadout-reveal state;
HP swap; cheat-death enrichment; selfDamagePercentOfDealt and
linkedTargetDamageMultiplier fields on ActiveTrigger; TEG scoring; FAT
activation hook; runtime-mutable resonance grade; crit tracking; the Levy
(Trion steal); the Interdict brand; charges-on-ally-death; untargetable
status; Enmity/Regret/Discord/Debt stateful counters; TEG dice-advantage
hook (feed a per-team advantage chance into the attacker/defender/resistance
RollContexts, plus SSS crit-range widening); a combo-recognition action
ledger + closed condition primitives + combo catalog (section 12, Phase I);
inverse-TEG battle XP scaling.

## 10. UI tasks

- Queue display: show each character's pending queued actions; allow un-queue
  before End Turn.
- Resolve beat: End Turn plays the cosmetic "Resolving..." delay, then
  reveals results.
- Clickable portraits (both teams) open the home-screen character detail
  panel. Your own characters: full detail. Opponent characters: public info
  only (type, base stats, perk, current HP, visible statuses, rank); equipped
  loadout stays hidden unless Mind's Eye has revealed it.
- Mind's Eye: populate a revealed enemy's abilities in their panel,
  clickable, for the duration.
- TEG display under Player Info with the six-sub-score breakdown on expand.
- Team Spirit: show the live offense/sustain effects next to the value.
- Surface the currently hidden stats (Trion Affinity, Team Spirit, Armor,
  Max HP, Infliction, Resistance) in CharacterStatRow, which today shows only
  ATK/DEF/CRIT/FAT/Trion Capacity.

## 11. AI

The AI builds a queue and resolves through the same path as the player
(important for future server authority), with a simulated thinking delay
before it commits. AI must also learn to value and play the new counters and
uniques.

## 12. Build phases

Ship Phase A first, in stages, with a commit and review at the end of each
stage. Nothing goes to main without explicit approval. When a phase is
complete, merge its branch to main, delete the branch, and start a new
branch for the next phase.

- **Phase A: turn-queue resolution engine** (no new content; all existing
  abilities keep working). Staged:
  - A1: Queue data model plus Trion-at-queue. Queue/unqueue, Trion spent at
    queue and refunded on unqueue, cooldown deferred to resolve. Resolution
    stays batched-at-end-turn in click order (interim). Tests: queue/unqueue,
    Trion accounting.
  - A2: Phase-priority resolution formula. Replace click-order with the
    6-phase sort, within-phase tiebreak by TS deviation then queue order, and
    add the Phase-4 reactive-stack hook (generalizing Sable's redirect, no
    new counters yet). Tests: ordering correctness, determinism.
  - A3: AI queues plus thinking-time. Refactor the AI to build a queue and
    resolve through the same path, with a simulated thinking delay. Tests:
    full-battle integration stays green.
  - A4: UI queue display plus resolve beat. Verify via the Playwright
    harness.
  - A5: Team Efficiency Grade compute plus display plus wire as cross-team
    Initiative. Tests: TEG scoring on known loadouts, opening-turn
    initiative. Deferrable/splittable if Phase A should stay lean.
- **Phase B: reactive/counter engine plus the 13 active and 6 passive
  counters.**
- **Phase C: Unique subtype plus the 17 unique abilities.**
- **Phase D: trigger rebalance to 20/20/20** (about 26 new triggers).
- **Phase E: new-content wiring** (Death Ledger swap, One More Breath, mutable
  resonance for Nullhymn, etc.).
- **Phase F: remaining UI** (clickable portraits, Mind's Eye panel, and any
  UI not already delivered in Phase A).
- **Phase G: AI tuning** for the new counters and uniques.
- **Phase H: balancing pass** (after all content phases are done). A
  dedicated tuning pass over the numbers that were set to first-pass,
  convention-following values during implementation: dice/Trion/cooldown
  for the 17 unique Triggers and the Phase D fillers, the Phase D
  `equipCost` values (note the LoadoutBuilder depends on a cheap-active
  tier existing - see the cheap-tier fix in Phase D), the UniqueConfig
  magnitudes (Shared Agony/Grave Bargain/Martyr's End/Dread Resonance/
  Karmic Bind/Echoing Doubt backlash), and status-effect durations. Play/
  sim-test for outliers rather than balancing each in isolation.
- **Phase I: Combo Recognition system.** A deterministic, data-driven
  subsystem that recognizes real combos from live battle state, so combos
  can drive rewards (TEG Effect 4, and Effect 3's setup->payoff). Follows
  the codebase's closed enumerable-behavior discipline (no open runtime
  scripting); the engine *matches* encoded combos, it does not *judge*
  narrative sense at runtime - that is an authoring-time decision. Staged:
  - I1: **Action ledger.** A battle-level rolling record of resolved
    actions this turn (actor id, trigger id and its tags - OriginTag /
    AttackType / AttackSubtype / category - target ids, statuses applied,
    sequence index). Extends today's thin per-character history
    (`lastUsedTriggerId`, `triggersUsedThisTurn`). Bounded and cheap.
  - I2: **Condition primitives + recognizer.** A closed set of composable
    predicates (`allOf` / `anyOf` / `not` + leaf matchers over the ledger,
    the payoff action, and the target's live state: ally-applied status
    present, ally used tag/origin, target hp threshold, character/perk
    identity, same target, within-turn). `ComboRecognizer.recognize(payoff,
    ledger, state) -> List<RecognizedCombo>`, deterministic and unit-tested.
  - I3: **Layer 1 - generic/emergent combos.** A seed catalog of combos
    that apply to anyone (control-then-strike, affliction-then-detonate,
    same-origin chain). Satisfies Effect 3 and unblocks Effect 4.
  - I4: **Layer 2 - signature/authored combos.** Named `ComboDefinition`
    entries in a `combo_catalog.dart` referencing specific characters,
    perks, triggers, and world/story context, each with flavor and a
    stronger reward. Added incrementally as content.
  - I5 (optional): **authoring tooling** (may be AI-assisted at design
    time, never at runtime) that proposes signature combos from the content
    data for human approval.
  - Consumers: Effect 4 maps a recognized combo's strength to advantage
    chance (capped 20%); Effect 3 refunds; later, combo VFX, combo-seeking
    AI, and story beats read the same recognizer output.
- **Phase J: TEG mechanical effects** (section 5.2). Implements the five
  dice-advantage effects. Effects 1, 2, 5 are self-contained (feed a
  per-team advantage chance / crit-range into the existing RollContext /
  crit path from an app-computed TEG). Effect 3 depends on Phase I's
  recognizer (setup->payoff category). Effect 4 depends on Phase I in full.
  The inverse-TEG XP counterweight depends on the server-XP + accounts task
  (section 15). App computes TEG and injects one scalar per team into the
  Battle at setup, so the engine stays pure and never compares two grades
  inline (the coupling that killed the old cross-team tiebreak).

## 13. Progress

**DONE (merged to main): the 6 passive counters are integrated into the
resolution loop and work in-game.** `play_session.dart`
(`_resolveAction` / `useAbility`) now feeds `notifyAbilityResolved`,
`notifyStatusInflicted`, `recordDamageDealt`, and `checkSanctionedStrike`,
and `battle.startTurn` ticks `tickReactiveEffects` once per turn. Coldread's
re-specced Seize (alternating with the Levy, +2 to the squad's rolls for 1
turn) is built too. So Draegor / Reckoning / Nullhymn / Ironvow now
accumulate, Coldread reads correctly, and Gravehour no longer over-fires.

**TEG mechanical role: DECIDED, partially built (Phase J).** We are
KEEPING alternating resolution, under which TEG's originally-specced
cross-team resolution-order tiebreak can never fire (two teams never resolve
in the same pass). That tiebreak is retired. TEG's new role is the
**combination amplifier**: five dice-advantage effects routed through the
existing d20 / RollContext system, plus an inverse-TEG XP counterweight (full
spec in section 5.2). **Effects 1/2/5 are built and merged to main**
(coordination advantage, inverted Operator's Read advantage, SSS crit
widener; injected per-team from the app-computed grade on the attack roll).
Effects 3 and 4 (the remaining Phase J work) depend on the **Combo
Recognition system (Phase I)** and are not built yet; the XP counterweight
depends on the server-XP + accounts task (section 15). So TEG is no longer
display-only: its roll-advantage and crit effects apply in-game. Turn order
still stays a 50-50 coin flip. NOTE: Draegor's "raise TEG 2 tiers" now has a
real effect target (it shifts the roll-advantage tables) but is not yet wired
to it. Coldread's "seize" has been re-specced (section 6.2) and **built**: a
flat +2 to the whole squad's rolls for 1 turn, alternating with the Levy on
successful reads (Levy first), self-contained and no longer dependent on the
retired tiebreak.

| Phase | Status | Branch |
|---|---|---|
| Phase A: turn-queue resolution engine | done + merged to main: queue model with Trion-at-queue / refund-on-unqueue and cooldown-at-resolve; the 6-phase within-team resolution ordering (Team-Spirit-deviation tiebreak, then queue order); AI builds and resolves a queue through the same path; TEG computed + displayed; turn order = even 50-50 coin flip. (Its deliverables are also itemized in 13.1 "Built and working".) | merged to main (early branch, deleted) |
| Phase B: reactive/counter engine + 19 counters | done + merged to main. The 13 active/reactive counters run inside `resolveAbilityUse`; the 6 passive counters are now fed by the app (see passive-counter integration row) and reactive expiry is ticked. All 19 work in-game. | `claude/phase-b-reactive-counters` (deleted) |
| Phase C: Unique subtype + 17 unique abilities | done (merged to main): C1 engine seam, C2 5 melee, C3 2 ranged + 10 psychic | `claude/tactical-combat-engine-5luk6z` |
| Phase D: trigger rebalance to 20/20/20 | done (merged to main): 17 unique Triggers wired + catalog balanced to exactly 20/20/20 (60 active) | `claude/tactical-combat-engine-5luk6z` |
| Phase E: new-content wiring | in progress: the two deferred unique hooks (7.1) done + merged; Coldread "seize" now built + merged; Nullhymn resonance downgrade still open (TEG tiebreak retired, superseded by Phases I/J) | `claude/tactical-combat-engine-5luk6z` |
| Phase F: remaining UI | not started | TBD |
| Phase G: AI tuning | not started | TBD |
| Phase H: balancing pass | not started (after all content phases) | TBD |
| Passive-counter integration (design 13.1 gap #1) | done + merged to main: all six counters fed from `play_session.dart`; reactive expiry ticked; Coldread Seize built | `claude/tactical-combat-engine-5luk6z` |
| Phase I: Combo Recognition system | I1-I3 done + merged to main: action ledger + condition primitives + recognizer + Layer-1 generic catalog, unit-tested. Live population + fx3/fx4 consumption land with Phase J Effects 3/4. Signature combos (I4) / authoring tooling (I5) later | `claude/tactical-combat-engine-5luk6z` |
| Phase J: TEG mechanical effects (section 5.2) | in progress: Effects 1/2/5 (roll-advantage + SSS crit) done + merged to main, applied on the attack roll. Effects 3/4 (consume Phase I + live ledger population) next; fx1/fx2 still to wire on status-infliction + unique-attack rolls; XP on section 15.8 | `claude/tactical-combat-engine-5luk6z` |

### 13.1 Build status (verified against code)

Read this before starting engine/game work; it is the accurate map of
what exists vs. what is only specced. Two layers, dependency app -> engine
(the engine is pure Dart and cannot import app code):

- `packages/battle_engine/` - engine: combat resolution, counters, uniques,
  status effects, catalogs (triggers/black triggers/roster), AI, story
  engine. 31 test files.
- `app/` - Flutter app: the queue/resolution orchestration
  (`lib/src/game/play_session.dart`), TEG (`lib/src/game/team_efficiency.dart`),
  draft/loadout/target selection, screens and widgets. 7 test files.

**Built and working:**
- Turn + queue model with 6-phase within-team resolution ordering
  (`play_session.dart` `_resolvePlan`: phase, then Team Spirit deviation,
  then queue order). Trion spent at queue, refunded on unqueue.
- Turn order (who acts first) = even 50-50 coin flip, not stat-tied.
- TEG computed and displayed (six sub-scores, D-SSS). App layer only.
- Phase B active/reactive counters (13): wired into `resolveAbilityUse` and
  work in-game - armed on your turn, fire when the opponent acts into them.
  Reactive expiry (`tickReactiveEffects`) is now ticked once per turn in
  `battle.startTurn`, so timed wards/traps/marks time out.
- The 6 passive counters are now integrated (merged to main): fed from
  `play_session.dart` via `notifyAbilityResolved` / `notifyStatusInflicted` /
  `recordDamageDealt` / `checkSanctionedStrike`. Coldread's Seize is built.
- Combo Recognition (Phase I1-I3, merged to main): action ledger,
  condition primitives, recognizer, Layer-1 generic catalog. Unit-tested;
  not yet populated during live resolution (that lands with Phase J
  Effects 3/4).
- TEG Effects 1/2/5 (Phase J, merged to main): per-team roll-advantage
  (coordination + inverted Operator's Read) and the SSS crit widener,
  injected from the app-computed grade and applied on the attack roll.
- Phase C: all 17 unique behaviors, wired to equippable Triggers.
- Phase D: active catalog balanced to exactly 20/20/20 (60 active).
- Phase E so far (merged to main): Illusory Double charge-on-ally-death
  and Karmic Bind live link (Punish, one-way).
- One More Breath (survive-lethal enrich) is implemented in the engine.

**Specced but NOT built (the real gaps), most important first:**
1. **TEG Effects 3 & 4, and the rest of the fx1/fx2 wiring (Phase J).**
   Effects 1/2/5 are built (above), but Effect 3 (setup->payoff Trion
   refund) and Effect 4 (focus-fire advantage) are not - they need the
   Phase I recognizer consumed and the combo ledger populated during live
   resolution. fx1/fx2 also still need wiring on the status-infliction and
   unique-attack roll sites (only the main attack roll is wired today).
2. **Draegor's "raise TEG 2 tiers"** now has a defined effect under the new
   model (it shifts the roll-advantage tables) but is unbuilt until Phase J;
   it currently runs its fallback (double the highest-TA ally's TA).
   (Coldread's Seize is now built - see above.)
3. **Nullhymn's resonance downgrade** - fallback only (purge + reflect
   debuffs). Permanently dropping an enemy Black Trigger's resonance grade
   needs a runtime-mutable `ResonanceGrid` (currently a const lookup).
4. **Death Ledger trigger-swap** - the AoE-nullify works; the swap part is
   deferred (`reactive_effect.dart`).

## 14. Open / tunable items

- TEG weights and tier thresholds.
- Exact dice/Trion/cooldown numbers for the 26 new triggers and all new
  abilities.
- TEG name (currently "Team Efficiency Grade").
- Whether A5 (TEG) ships inside Phase A or as its own slice.

## 15. Post-combat-v2 product roadmap (after Phases A-G)

These are app/product tasks, not combat-engine phases. They are scheduled
after the combat rework (Phases A-G) is complete. PvP is AI-backed for now;
real online multiplayer comes later (it does not gate these items).

1. Redesign the Guided Tutorial for the new systems (queue resolution,
   portrait-based targeting, counters/uniques).
2. Update How to Play with screenshots and worked examples; flesh out
   character backgrounds and world state; include the artwork the owner
   will provide.
3. Quick Battle becomes a first-class button like Play and drops you
   straight into a battle like Play, but auto-selects a random squad for
   you.
4. Redo Simulate to match the new systems and designs.
5. Replace Play with **Start Training Battle** (PvE) - the third home option.
6. Replace Quick Battle with **Start Quick Match** (PvP) - the second home
   option.
7. Add **Start Ladder Battle** (PvP) - the first home option.
8. **Accounts + server-authoritative player XP.** Stand up an account system
   with easy sign-in (Google first, room for Apple / email) and a server
   that owns the XP ledger. Real player XP must be server-authoritative (not
   client-trusted). The server applies the **inverse-TEG XP multiplier**
   (section 5.2: D +75% ... SSS +5%) at battle end from a client-reported,
   server-validated result. This gates TEG's XP counterweight (Phase J) and
   is a prerequisite for real online multiplayer generally. Capture: auth +
   provider sign-in, the XP ledger service and its multiplier formula, and a
   client hook that reports battle results.

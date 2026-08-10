# Isekai Strategem — Complete Game Design Document

**Status:** Living document, current as of `main`. This is the single authoritative
design reference: it explains every system, the numbers behind it, and the full
content catalogs. It consolidates and supersedes the older, partial docs
(`combat_v2_design.md` is the rework spec / build tracker; the
`packages/battle_engine/doc/*` reference files predate combat v2 and are stale).

> Inspirations: World Trigger (Trion, Triggers, Black Triggers, the
> Attacker/Shooter/Sniper/Trapper classes), Naruto (chakra-style resource play,
> genjutsu/shadow/seal status flavor), and tabletop D&D (the d20 to-hit engine,
> advantage/disadvantage, critical hits, conditions).

---

## Table of contents

1. What the game is
2. The gameplay loop
3. Squads, characters, and character types
4. Stats
5. Team Spirit (dual-direction stat)
6. Trion (the resource economy)
7. Triggers and Loadouts
8. Full Arms Trigger (FAT)
9. The turn & queue model
10. Resolution order (the six phases)
11. Combat resolution math (to-hit, crit, damage)
12. Status effects
13. Counters (reactive + passive)
14. Unique abilities
15. Combo recognition
16. Team Efficiency Grade (TEG)
17. Black Triggers
18. Character perks
19. AI opponents
20. Accounts & XP (server-authoritative backend)
21. Build status
- Appendix A: Full Trigger catalog (60)
- Appendix B: Character roster (20)
- Appendix C: Status effect magnitudes
- Appendix D: Tunable constants

---

## 1. What the game is

Isekai Strategem is a **turn-based 3v3 tactical squad battler**. Each player fields
a **squad of three characters**, each kitted with a **Loadout** of Triggers (and
optionally a Black Trigger). Two squads alternate turns, committing actions that
resolve through a fixed phase order, until one squad is wiped. A single character
can be deleted quickly, so the game rewards planning around resource tempo,
status setups, counters, and squad synergy rather than raw stat-checking.

There is also a story/visual-novel mode scaffold; this document covers the
combat game.

**Two layers of code:**

- `packages/battle_engine/` — pure-Dart engine: combat resolution, counters,
  uniques, status effects, catalogs (triggers / black triggers / roster), AI.
- `app/` — Flutter app: the queue/resolution orchestration
  (`play_session.dart`), Team Efficiency Grade, draft/loadout/target selection,
  screens, and the Supabase accounts/XP integration.

---

## 2. The gameplay loop

1. **Draft** three characters into a squad (each has a fixed base stat block, a
   type, and an innate perk).
2. **Build a Loadout** for each: equip Triggers within that character's Trion
   Capacity budget, satisfying the loadout rules (below).
3. The engine computes each squad's **Team Efficiency Grade (TEG)** from the
   drafted loadouts — a build-quality score that grants dice advantages in
   battle and inversely scales post-battle XP.
4. **Battle:** squads alternate turns. On your turn you queue one or more
   actions (more if FAT triggers), choose targets, and end the turn; the queue
   resolves through the six-phase order, then the opponent responds.
5. **Resolve to a winner;** award inverse-TEG XP to the player's account.

---

## 3. Squads, characters, and character types

A squad is **exactly three characters**. The roster has **20 characters** across
four **types** (see Appendix B for the full stat table):

| Type | Count | Role identity | Stat signature |
|---|---|---|---|
| **Attack** | 5 | Front-line damage | High Attack (22–27), low Defense, low Team Spirit (offense pole) |
| **Defense** | 5 | Damage soak / control | High Defense (14–16) & Armor, mid Team Spirit |
| **Support** | 5 | Heals / buffs / Trion | High Trion Affinity & Team Spirit (sustain pole), low Attack |
| **Unique** | 5 | Gimmick specialists | Built around a signature Unique ability + a distinctive perk |

Character type also feeds the TEG's Team Spirit Alignment and Stat Coherence
sub-scores (a squad whose stats and loadouts match their pole scores higher).

---

## 4. Stats

Every character has a base **Stats** block. All stats are visible in the UI
(the loadout/roster panels surface even the "hidden" ones).

| Stat | What it does |
|---|---|
| **Attack** | Added to the attacker's d20 to-hit roll; the dominant contributor to landing hits. |
| **Defense** | Added to the defender's d20 roll (opposed); the target's evasion/guard. |
| **Armor** | Flat damage subtracted after multipliers, every hit. |
| **Max Health** | Hit points (baseline 100 across the roster). At 0, the character is DEFEATED. |
| **Trion Capacity** | The character's Trion pool size / Loadout equip budget (see §6, §7). ~100–130. |
| **Trion Affinity** | Raises the chance of higher per-turn Trion income tiers (§6). |
| **Team Spirit** | Dual-direction stat: below 50 boosts offense, above 50 boosts sustain (§5). |
| **Critical Chance** | Chance an attack is a critical hit (widens the crit die-threshold; §11). |
| **FAT Chance** | Chance Full Arms Trigger activates on a turn, unlocking multi-action turns (§8). |
| **Status Infliction** | The "save DC" side of applying status effects. |
| **Status Resistance** | The "saving throw" side of resisting inflicted statuses. |

---

## 5. Team Spirit (dual-direction stat)

Team Spirit runs **0–100 with 50 neutral**. It is two independent linear scalers
from the midpoint out to each extreme (`TeamSpiritCurve`):

- **Below 50 → offense pole.** Scales up to, at Team Spirit 0:
  - +30% single-target damage, +30% burst damage, +20 flat Critical Chance.
- **Above 50 → sustain pole.** Scales up to, at Team Spirit 100:
  - +30% healing received, +20 flat FAT Chance.
- **At 50:** neutral, no bonus either way.

So an attack character (Team Spirit ~30–40) is a committed glass cannon, while a
support (~60–70) is a committed sustainer. The UI shows the live offense/sustain
readout next to the value. This stat is a major TEG input (Team Spirit Alignment
rewards a squad whose loadouts match their pole).

---

## 6. Trion (the resource economy)

**Trion** is the resource that pays for abilities. It exists as two related
quantities (per the World Trigger "Trion capacity" concept):

- **Trion Capacity** — the size of the pool and the **Loadout equip budget** (a
  Trigger has an *equip cost* paid against Capacity at build time, and a *Trion
  cost* paid from the running pool at use time).
- **Per-turn Trion income** — at the start of a turn each side rolls a tier:

  | Tier | Gain | How it's rolled |
  |---|---|---|
  | Low | +10 | Base state |
  | Medium | +20 | `35% + 1%·ΣTrionAffinity` chance to upgrade Low→Medium |
  | High | +35 | If Medium reached, a further `20% + 1%·ΣTrionAffinity` to upgrade |

  Trion Affinity therefore makes higher income more likely; a high-Affinity
  support like Haru Ellison (Affinity 32) is the squad's battery.

**Trion denial** is a real axis: `sapped` drains 25% of Trion Capacity,
`genjutsu_trapped` drains 15%, `silenced` blocks abilities, `overcharged`
halves costs, `choked` doubles them.

> Design note (see reviews): income is currently a semi-random tier and most
> turns spend one ability, so Trion capacity rarely bites. A future pass may make
> income deterministic and capacity-gate FAT.

---

## 7. Triggers and Loadouts

**Triggers** are the equippable abilities. A **Loadout** is a character's set of
equipped Triggers plus an optional Black Trigger.

**Loadout rules** (`LoadoutRulesConfig`):

- **Max 8 equipped items** total (Triggers + the Black Trigger count together).
- **Exactly 4 active abilities** required (an `ActiveTrigger` is 1; a Black
  Trigger contributes however many active abilities it carries).
- **Total equip cost ≤ the character's Trion Capacity.**

So loadout-building is a knapsack: fit exactly four usable abilities plus passive
support Triggers under the Trion budget. Passive Triggers (counters, stat
passives) fill the other slots.

**Trigger anatomy** (fields that define an `ActiveTrigger`): id, name, **category**
(functional role), equip cost, Trion cost, cooldown (turns), origin tag,
range tag (melee/ranged), attack type, **attack subtype** (single / burst / aoe),
damage type, damage (a `DiceExpression`, `NdM+flat`), target count, hits per use,
optional heal, inflicted status effects, optional **unique behavior** or
**reactive kind**.

**Trigger categories** and the catalog split (60 active Triggers total — see
Appendix A):

| Category | Count | Role (World Trigger analogue) |
|---|---|---|
| `attacker` | 16 | Melee bruisers (Attacker: Kogetsu/Scorpion) |
| `shooter` | 9 | Volume fire / bursts (Gunner/Shooter: Asteroid/Viper) |
| `sniper` | 3 | Long-range big hits (Sniper: Ibis/Lightning) |
| `trapper` | 24 | Control, DoT, debuffs, most uniques (Trapper: Spider/Escudo) |
| `optional` | 20 | Buffs, wards, self/utility, reactive counters |

*(Categories overlap the 60; some Triggers count in the flavour role that best
fits. The engine balance target is a broad, distinct spread — see §12/Appendix A.)*

---

## 8. Full Arms Trigger (FAT)

Normally a character uses **one ability per turn**. **FAT** (`FatConfig`) is the
burst valve:

- Each turn, a character can **trigger FAT** (chance = its FAT Chance stat, plus
  Team Spirit's sustain-pole bonus).
- On a FAT turn, that character may use **up to 3 abilities**.
- **Cost of greed:** if 2+ abilities are used on the FAT turn, a penalty applies —
  **cooldowns are doubled** and **Trion Affinity is halved** — and FAT then
  **locks out for 3 turns**.

FAT is the coordinated-nuke lever, deliberately taxed so it's a tempo decision,
not free. The **Draegor** passive counter specifically punishes an *opponent* who
FAT-chains 2+ abilities.

---

## 9. The turn & queue model

Turns **alternate** between squads. Cross-team who-goes-first (initiative) is
currently an **even 50/50 coin flip** at battle start. A 15-second turn timer
exists (`secondsPerTurn = 15`).

On the player's turn:

1. **Queue** actions (character + ability + targets). Trion is **spent at queue
   time**; **un-queueing refunds** it. Cooldowns are applied at resolve time.
2. Ability legality is enforced live (affordability, cooldown, targeting, the
   per-turn ability limit which scales with FAT).
3. **End Turn** → the queued actions **resolve** through the six-phase order
   (§10), results are shown after a brief cosmetic "Resolving…" beat, then the
   AI opponent takes its turn through the same path.

The AI builds and resolves a full queue through the *same* resolution path as the
player (important for future server authority).

---

## 10. Resolution order (the six phases)

Within a turn, queued actions do **not** resolve in the order queued. They
resolve by a fixed **phase order**, then by a within-phase tiebreak. The phases
group actions by kind so that setup lands before payoff:

1. Pre-emptive / reactive arming
2. **Buffs** (self/ally empowerment, wards)
3. **Control** (no-damage debuffs / crowd control)
4. **Attacks** (anything that deals damage)
5. Post-attack effects
6. Cleanup / expiry ticks

**Within a phase**, ties break by **Team Spirit deviation from 50** (the more
committed character acts first), and finally by queue order. Example: a buff
resolves before an attack queued earlier; between two attacks, the higher
Team-Spirit-deviation character strikes first.

Reactive expiry (timed wards/traps/marks) is ticked once per turn so temporary
effects time out.

---

## 11. Combat resolution math (to-hit, crit, damage)

Every damaging hit resolves in two independent rolls: an **opposed d20 to-hit**,
then a **separate damage roll**.

**To-hit (opposed d20):**

- Attacker rolls `d20 + Attack`; defender rolls `d20 + Defense`. Attacker total
  ≥ defender total → **hit**, else **miss**.
- **Advantage / disadvantage** roll two dice and keep the best / worst (perks and
  statuses grant these — e.g., Airi's *Feint* gives the first attacker against
  her disadvantage).

**Critical hits:**

- A hit is a **critical hit** if the attacker's natural d20 lands in the crit
  range. Crit chance maps to a widening threshold: at 0% crit chance you crit only
  on a natural 20 (`thresholdAtMinChance = 20`); at max crit chance the threshold
  drops to 5 (`thresholdAtMaxChance = 5`), i.e. crit on a natural 5+.
- A crit **doubles damage** (`criticalHitDamageMultiplier = 2.0`).
- A **critical miss** (natural low) penalizes the attacker (−20% Defense and
  −20% Team Spirit for 1 turn).

**Damage formula** (the log shows every step):

```
diceTotal            = the Trigger's own damage roll (NdM + flat)
× preCritMultiplier  = Team Spirit / perk / status outgoing-damage multiplier
× crit (×2 if crit)
− Armor              = the target's flat Armor
× resistance/vuln    = damage-type resistance (×0.5) or status multiplier
= final damage
```

Burst abilities roll this per hit; AoE applies to each target.

> Design note (see reviews): because flat stat modifiers (Attack ~26, damage flat
> +37…+86) dwarf the d20's ±19 swing, the roll currently contributes ~15% of
> outcomes — the "no bounded accuracy" issue flagged for a P0 rebalance.

---

## 12. Status effects

There are **~60 status effects** (`StatusEffectCatalog`), each with a tuned
duration and magnitude (`StatusEffectMagnitudes`; full values in Appendix C).
They fall into families:

- **Hard control:** stunned (1t), frozen (1t), prone (1t), charmed (3t),
  petrified (2t, but also halves damage taken), silenced (1t).
- **Damage-over-time:** bleeding (8/t), scorched (12/t), necrotic_wound (12/t),
  poisoned, corroded (also −3 Armor).
- **Damage-taken multipliers:** marked (×1.5, 1t), exposed (×1.25, 2t),
  guarded (×0.75), petrified (×0.5).
- **Outgoing-damage swings:** empowered (×1.25), enraged (×1.5 but −3 Def),
  weakened (×0.75).
- **Stat swings:** inspired (+2/+2), fatigued (−2/−2), hastened, slowed, chilled,
  scorched, shattered_guard, braced, focused, rallied (+20 max HP).
- **Economy / disruption:** sapped (−25% Trion cap), genjutsu_trapped (−15%),
  overcharged (×0.5 cost), choked (×2 cost), suppressed (−5 infliction),
  warded (+10 resistance), hexed (−10 resistance).
- **Utility / signature:** regenerating, radiant_blessing, adrenaline_rush
  (+15 crit), battle_trance (+20 FAT), misfire (50% self-fail), interdict,
  forced_repetition, isolation, untargetable, called_shot, minds_eye_reveal, etc.

Applying a status is contested: **Status Infliction (attacker) vs Status
Resistance (target)**, with immunities bypassing the roll.

> Design note: statuses are not yet on a shared power budget; magnitudes/durations
> vary widely (marked ×1.5/1t vs exposed ×1.25/2t; DoTs 8 vs 12), a flagged
> tuning target.

---

## 13. Counters (reactive + passive)

Counters are the reaction economy — armed on your turn, they fire when the
opponent acts into them. There are **two kinds**.

### 13.1 Reactive counters (armed → fire on the opponent's action)

Driven by `ReactiveKind`:

| Kind | Effect |
|---|---|
| `reflectNonAoe` | Reflect the next non-AoE attack back at the attacker. |
| `dodgeMeleeSingle` | Dodge the next single-target melee attack (e.g., `predictive_parry`). |
| `negateByOrigin` | Negate the next attack of a matching origin type. |
| `burstMitigation` | Reduce incoming burst damage (`numbing_toxin`). |
| `cooldownSabotage` | Extend an attacker's cooldowns when they act (`frozen_tempo`). |
| `redirectToOwnAlly` | Redirect an incoming attack onto one of the attacker's allies. |
| `trapOnAction` | Spring a trap when the target takes an action. |
| `nullifyAoe` | Nullify an incoming AoE (`death_ledger` — engine signals the app to borrow the nullified AoE into the wielder's loadout for 2 turns). |
| `bankDamage` | Bank damage taken, release it later (`stored_retribution`). |
| `enrichSurviveLethal` | Survive an otherwise-lethal hit ("One More Breath"). |

### 13.2 Passive counters (stateful, accumulate then discharge)

Six stateful counters (`PassiveCounterKind`) accumulate stacks from opponent
behavior and then fire. Thresholds from `PassiveCounterConfig`:

| Counter | Builds on | Threshold | Payoff |
|---|---|---|---|
| **Draegor** | Each ability the holder uses (Enmity) | 5 → Regret (2t) | If an enemy FAT-chains 2+ abilities while Regret is up, the squad's TEG rises 2 tiers for 2 turns (or, if already SS+, doubles the highest-Affinity ally's Trion Affinity). Max 3/battle. |
| **Nullhymn** | Enemy Black Trigger use / status on holder (Discord) | 5 | Discharges (2×/battle): permanently drops the most-recently-active enemy Black Trigger one resonance grade — or, if none, purges & reflects your team's debuffs. |
| **Reckoning** | Enemy crits / 2+ cd abilities vs your team (Debt) | 6 | Worst offender's cooldowns extended, their next attack forced to a critical miss, their Trion levied. |
| **Gravehour** | End of enemy turn, if they dealt no damage or left an enemy ≤30% HP | — (3t cd) | Free uncounterable finisher (+40 flat) on the lowest-HP enemy, who can't be healed next turn. |
| **Coldread** | Secretly marks an enemy each turn | — (1t cd) | Correct read alternates a reward (Levy their costliest Trion, then Seize: +2 to the whole squad's rolls for 1 turn). A wrong read docks your next Trion gain. |
| **Ironvow** | A random attack type is sanctioned each turn | — | Attack with the sanctioned type for a Sanctioned Strike (unblockable, strips a buff, brands the target). Cost: allies left vulnerable to that type. Max 3/battle. |

---

## 14. Unique abilities

**17 unique abilities** (`UniqueBehavior`, excluding the UI-only `clickable`)
give the Unique-type characters and select Triggers signature mechanics not
expressible as plain damage + status. Key ones (constants in Appendix D):

| Unique | Behavior |
|---|---|
| `sharedAgony` | Links two targets; damage to one bleeds to the other (×1.2). |
| `graveBargain` | Spend 25% of your own HP to power a strike. |
| `martyrsEnd` | Below 25% HP, detonate for 80 damage. |
| `vowOfTheDuel` | Bind a target: ×2 damage between the two, plus a 2-turn stun. |
| `sunderArms` | Heavy single-target armor sunder. |
| `curvingShot` | A shot that ignores certain cover/defense. |
| `calledShot` | Zero one of the target's stats for a duration. |
| `mindsEye` | Reveal an enemy's full loadout (clickable in their panel) for 3 turns. |
| `forcedChoice` | Force the target into a lose-lose choice. |
| `memoryTheft` | Steal / copy an ability. |
| `sensorySwap` | Swap a sense/targeting relationship on 2 targets. |
| `dreadResonance` | Damage scales with cumulative damage the target has taken (×0.15, min 5). |
| `isolation` | Cut a target off from ally support. |
| `illusoryDouble` | Start with 1 charge; gains charges on ally death; a decoy body. |
| `echoingDoubt` | A doubt that backlashes for 20 if acted against. |
| `karmicBind` | Two-way link scaling with Team Spirit (25%–60% fractions). |
| `unmaking` | A powerful unravelling debuff. |

---

## 15. Combo recognition

The engine runs a **combo recognizer** over a per-turn action ledger: it detects
setup→payoff patterns and rewards them (via TEG Effect 4's payoff advantage and
Effect 3's setup→payoff Trion refund). There are **18 recognized combos** across
two layers:

- **Layer 1 — generic patterns** (fire on structural conditions): *Control then
  Strike, Affliction Detonate, Setup Exploit, Focus Fire.*
- **Layer 2 — signature chains** (specific trigger/status pairings): *Frozen
  Detonation, Terror Cascade, Shatterpoint Execution, Piercing Corrosion, Pinned
  Shot, Mind Unravel, Charmed Opening, Flashfire, Opening Sweep, Venom Reap,
  Snared Execution, Brittle Pierce, Blinding Volley, Dread Shatter.*

The recognizer is fed live during resolution and cleared each turn. A design-time
proposer (`tool/propose_signature_combos.dart`) helps author new signature chains.

---

## 16. Team Efficiency Grade (TEG)

Before battle, each squad's Loadout is scored into a **Team Efficiency Grade** —
a build-quality meta-stat that both **helps you in battle** and **inversely gates
your XP**, making the Grade a genuine risk/reward dial rather than a strictly
better number.

**Six sub-scores** (weighted → composite 0–100 → tier):

| Sub-score | Weight | Measures |
|---|---|---|
| Team Spirit Alignment | 25% | Whether each character's loadout leans offense/sustain matching their Team Spirit pole. |
| Stat Coherence | — | Whether stats reinforce the intended role. |
| Loadout Synergy | — | How well the equipped Triggers combo. |
| Perk Utilization | — | Whether the loadout enables the character's perk. |
| Trion Economy | — | Whether the build's costs fit its income. |
| Resonance Fit | — | Black Trigger fit (null if no Black Trigger). |

**Tiers:** D, C, B, A, S, SS, SSS.

**In-battle effect (TEG Effects 1–5):** the Grade feeds a per-team **dice
advantage** into the to-hit, defense, and resistance rolls (coordination bonus +
an inverted "Operator's Read" on defense), an **SSS crit-range widener**, a
**recognized-combo payoff advantage** (Effect 4), and a **setup→payoff Trion
refund** (Effect 3). Draegor's counter can shift a squad's effective Grade up 2
tiers.

**Post-battle XP (the inverse counterweight):** a weaker Grade earns *more* XP,
an elite Grade pays an "elite tax":

| Tier | D | C | B | A | S | SS | SSS |
|---|---|---|---|---|---|---|---|
| XP bonus | +75% | +63% | +51% | +40% | +28% | +16% | +5% |

Awarded XP = `round(baseXp × (1 + bonus%))`, computed **server-side** (§20).

---

## 17. Black Triggers

**Black Triggers** are rare, powerful loadout pieces — effectively a whole extra
kit bolted onto one operator (a suite of active abilities, passives, and
sometimes a once-per-battle "World ability"). There are **9**:

| Black Trigger | Identity |
|---|---|
| **Ashbringer** | High-damage melee/ranged pair on short cooldowns. |
| **Fracture Edge** | A burst attack plus offense-focused passives. |
| **Solar Flare** | A single massive AoE nuke on a long cooldown, plus a Critical passive. |
| **Aegis Core** | A World ability that negates the first few instances of damage. |
| **Bastion Frame** | Armor, Damage Resistance, Status Resistance, and Foresight passives. |
| **Wellspring** | A direct heal, a Regenerating buff, and a Mirror Ward reflect. |
| **Chorus Bond** | Team Spirit and healing-focused passives — a support suite. |
| **Paradox Shard** | An unpredictable debuff ability plus a disruptive passive. |
| **Gravebind** | A World ability: once per battle, survive a hit that would defeat you. |

A Black Trigger's fit is scored by the TEG **Resonance Fit** sub-score, and the
**Nullhymn** counter can permanently downgrade an enemy Black Trigger's resonance.

---

## 18. Character perks

Each character has one **innate perk**, always active, that a good loadout should
enable (the TEG Perk Utilization sub-score rewards this):

| Character (type) | Perk | Effect |
|---|---|---|
| Kaito Reyes (atk) | **Last Ace** | Critical Chance doubled while Kaito is the last living teammate. |
| Vela Ashworth (atk) | **First Blood** | First attack of the battle gains bonus Critical Chance. |
| Dross (atk) | **Overwhelm** | AoE abilities deal bonus damage to a target that already has a debuff. |
| Ren Kobayashi (atk) | **First Strike** | Flat Attack bonus on the first ability used each battle. |
| Airi Tanaka (atk) | **Feint** | The first attack against Airi each battle is rolled with disadvantage. |
| Marren Osei (def) | **Bulwark** | Armor doubled while any living teammate remains. |
| Ilona Vance (def) | **Riposte** | When a melee attack against her misses, she gains a stacking Attack buff. |
| Bastian Cole (def) | **Absorb** | First instance of damage each battle is halved. |
| Dorian Voss (def) | **Immovable** | Resists forced movement / displacement effects. |
| Sable Whitlock (def) | *(defensive anchor)* | High Defense/Armor stat profile. |
| Priya Nakamura (sup) | **Combat Medic** | Heal-over-time effects heal for more. |
| Soren Talvik (sup) | **Weaken Resolve** | Debuffs hit harder vs a target already carrying one of his debuffs. |
| Yuki Amaral (sup) | **Devoted Aid** | +10% to all healing, any source. |
| Haru Ellison (sup) | **Battery** | Trion battery — very high Trion Affinity (32) fuels the squad. |
| Celestine Moreau (sup) | **Warding Presence** | Ally-targeted buffs also grant a resistance bonus. |
| Zheng Anders (unq) | **Foresight** | Once per battle, reroll one of his own attack rolls. |
| Nadia Kessler (unq) | **Chain Reaction** | Each additional ability in a FAT turn deals more than the last. |
| Rurik Voss (unq) | **All or Nothing** | Glass-cannon profile (Attack 29 / Defense 6): high risk, high reward. |
| Mireille Song (unq) | **Decoy** | Once per battle, an attack against her may simply miss. |
| Tobias Renner (unq) | **Versatile** | Small bonus to whichever stat matches the last ability category used. |

---

## 19. AI opponents

The opponent is an **AI profile** (skill classes: Beginner, Amateur,
Intermediate, Professional, Expert). The AI **builds and resolves a full queue
through the same resolution path as the player**, with a simulated "thinking"
delay before it commits, so single-player and future server-authoritative play
share one code path. AI tuning (valuing the counters/uniques/statuses well) is a
tracked future phase.

---

## 20. Accounts & XP (server-authoritative backend)

Accounts and XP are **live on a Supabase backend** (project
`zzsjkanssxhejhotbrca`), behind the `AccountService` / `XpLedger` interfaces via a
`Services` locator that falls back to local stubs if the backend is unreachable.

- **Stress-free auth:** guest (anonymous), passwordless email (magic link), and
  Google OAuth; upgrading a guest keeps the same id (no lost progress).
- **Server-authoritative XP:** the client reports a battle result; the Postgres
  function `award_battle_xp` **recomputes the inverse-TEG multiplier server-side**
  and owns the running total, so a client can never set its own XP. Row Level
  Security restricts every player to their own rows.
- A daily **keep-alive** GitHub Action prevents the free-tier project from pausing.

Setup and schema are documented in `docs/supabase_setup.md` and
`supabase/schema.sql`.

---

## 21. Build status

- **Engine (Phases A–E, I, J):** done & merged — queue engine, reactive + passive
  counters, unique subtype + 17 uniques, 20/20/20-ish trigger rebalance, combo
  recognition, TEG mechanical effects + inverse-TEG XP.
- **Accounts / XP (§20):** live and verified end-to-end.
- **Phase F UI:** TEG badge, hidden stats, Team Spirit readout, loadout-builder
  pass, passive-counter descriptions, clickable-portrait detail panel + Mind's Eye
  reveal, sign-in flow, post-battle XP readout, and the battle-log rework
  (tap-to-expand, plain-English breakdowns, clickable entity popups). Remaining:
  queue display + resolve-beat polish.
- **Balance:** the 5 near-duplicate trigger clusters have been differentiated; a
  full balance pass (bounded accuracy, initiative, status/trigger budgets) is
  proposed in `docs/reviews/` and pending.

---

## Appendix A: Full Trigger catalog (60 active Triggers)

Trion = use cost · cd = cooldown (turns) · eq = equip cost · sub = subtype · h = hits/use · tc = targets · special = unique behavior or reactive kind.


### Attacker (16)

| Trigger | Trion | cd | eq | sub | h | tc | damage | status | special |
|---|--:|--:|--:|---|--:|--:|---|---|---|
| "Martyr's End" | 10 | 4 | 28 | unique | 1 | 3 | — | — | martyrsEnd |
| Cinderburst | 18 | 2 | 26 | aoe | 1 | 3 | 1d6+18 | scorched | — |
| Cleave | 15 | 1 | 24 | aoe | 1 | 2 | 1d6+18 | shattered_guard | — |
| Cryo Burst | 18 | 2 | 26 | aoe | 1 | 3 | 1d6+14 | chilled | — |
| Dread Resonance | 18 | 2 | 26 | unique | 1 | 1 | — | — | dreadResonance |
| Dread Wave | 18 | 2 | 26 | aoe | 1 | 3 | 1d6+12 | overwhelmed | — |
| Frost Lance | 14 | 1 | 22 | single | 1 | 1 | 1d6+18 | chilled | — |
| Grave Bargain | 8 | 2 | 14 | unique | 1 | 1 | — | — | graveBargain |
| Piercing Thrust | 14 | 1 | 22 | single | 1 | 1 | 2d6+45 | — | — |
| Predictive Parry | 20 | 2 | 20 | single | 1 | 1 | — | — | dodgeMeleeSingle |
| Shared Agony | 12 | 2 | 24 | unique | 1 | 1 | 2d6+40 | — | sharedAgony |
| Soul Siphon | 16 | 2 | 24 | single | 1 | 1 | heal 1d4+-1 | — | — |
| Sunder Arms | 16 | 3 | 28 | unique | 1 | 1 | 2d6+30 | — | sunderArms |
| Twin Fang Strike | 10 | 1 | 20 | single | 1 | 1 | 2d6+37 | — | — |
| Vow of the Duel | 15 | 3 | 24 | unique | 1 | 1 | — | — | vowOfTheDuel |
| Whirlwind Slash | 12 | 1 | 20 | aoe | 1 | 3 | 1d4+16 | bleeding | — |

### Shooter (9)

| Trigger | Trion | cd | eq | sub | h | tc | damage | status | special |
|---|--:|--:|--:|---|--:|--:|---|---|---|
| Arc Volley | 20 | 2 | 26 | burst | 3 | 2 | 1d4+10 | — | — |
| Frag Grenade | 18 | 2 | 26 | aoe | 1 | 3 | 1d6+16 | — | — |
| Gatling Burst | 24 | 2 | 28 | burst | 5 | 1 | 1d4+8 | exposed | — |
| Pepper Shot | 16 | 1 | 14 | burst | 3 | 1 | 1d4+12 | — | — |
| Rapid Fire | 18 | 2 | 16 | burst | 3 | 1 | 1d4+14 | bleeding | — |
| Scattershot | 20 | 2 | 26 | burst | 4 | 3 | 1d4+6 | slowed | — |
| Split Shot | 18 | 2 | 16 | burst | 2 | 2 | 1d6+10 | — | — |
| Suppressing Fire | 20 | 2 | 26 | burst | 3 | 2 | 1d4+16 | suppressed | — |
| Thunderclap Round | 18 | 2 | 26 | aoe | 1 | 3 | 1d4+10 | overwhelmed | — |

### Sniper (3)

| Trigger | Trion | cd | eq | sub | h | tc | damage | status | special |
|---|--:|--:|--:|---|--:|--:|---|---|---|
| Called Shot | 16 | 2 | 24 | unique | 1 | 1 | — | — | calledShot |
| Curving Shot | 18 | 2 | 26 | unique | 1 | 1 | 2d6+30 | — | curvingShot |
| Longshot | 30 | 2 | 34 | single | 1 | 1 | 4d8+86 | — | — |

### Trapper (24)

| Trigger | Trion | cd | eq | sub | h | tc | damage | status | special |
|---|--:|--:|--:|---|--:|--:|---|---|---|
| Acid Spray | 16 | 2 | 24 | aoe | 1 | 3 | 1d4+10 | corroded | — |
| Caustic Cloud | 16 | 2 | 16 | aoe | 1 | 3 | 1d4+6 | poisoned | — |
| Charm Whisper | 20 | 2 | 26 | single | 1 | 1 | — | charmed | — |
| Death Ledger | 18 | 2 | 20 | single | 1 | 1 | 1d4+8 | — | nullifyAoe |
| Dread Gaze | 14 | 1 | 20 | single | 1 | 1 | 1d4+8 | terrified | — |
| Echoing Doubt | 16 | 3 | 24 | unique | 1 | 1 | — | — | echoingDoubt |
| Flashbang Round | 18 | 2 | 22 | aoe | 1 | 3 | — | blinded | — |
| Forced Choice | 14 | 2 | 22 | unique | 1 | 1 | — | — | forcedChoice |
| Isolation | 14 | 3 | 22 | unique | 1 | 1 | — | — | isolation |
| Karmic Bind | 16 | 3 | 26 | unique | 1 | 1 | — | — | karmicBind |
| Mass Confusion | 20 | 2 | 26 | aoe | 1 | 3 | 1d4+8 | silenced | — |
| Memory Theft | 16 | 3 | 24 | unique | 1 | 1 | — | — | memoryTheft |
| Mind Fog | 16 | 2 | 14 | aoe | 1 | 3 | 1d4+8 | blinded | — |
| Mind Shatter | 18 | 2 | 24 | single | 1 | 1 | 1d4+8 | silenced | — |
| Nightmare Pulse | 18 | 2 | 26 | aoe | 1 | 2 | 1d6+10 | terrified | — |
| Numbing Toxin | 20 | 2 | 18 | single | 1 | 1 | — | — | burstMitigation |
| Psychic Scream | 18 | 2 | 26 | aoe | 1 | 3 | 1d4+8 | silenced | — |
| Root Snare | 18 | 2 | 20 | single | 1 | 1 | 1d4+8 | forced_repetition | — |
| Scramble | 20 | 2 | 24 | single | 1 | 1 | 1d4+8 | misfire | — |
| Sensory Swap | 14 | 2 | 22 | unique | 1 | 2 | — | — | sensorySwap |
| Shatterpoint | 12 | 1 | 18 | single | 1 | 1 | 1d6+18 | corroded | — |
| Unmaking | 18 | 3 | 26 | unique | 1 | 1 | — | — | unmaking |
| Venom Needle | 12 | 1 | 18 | single | 1 | 1 | 1d4+12 | poisoned | — |
| Venom Spray | 20 | 2 | 24 | burst | 3 | 2 | 1d4+6 | poisoned | — |

### Optional (8)

| Trigger | Trion | cd | eq | sub | h | tc | damage | status | special |
|---|--:|--:|--:|---|--:|--:|---|---|---|
| "Guardian's Aegis" | 14 | 2 | 18 | single | 1 | 1 | — | guarded, braced | — |
| "Mind's Eye" | 10 | 3 | 20 | unique | 1 | 1 | — | — | mindsEye |
| Cleansing Ward | 16 | 2 | 22 | single | 1 | 1 | — | regenerating, warded | — |
| Frozen Tempo | 18 | 2 | 20 | single | 1 | 1 | — | — | cooldownSabotage |
| Illusory Double | 0 | 2 | 24 | unique | 1 | 1 | — | — | illusoryDouble |
| Rally Cry | 14 | 2 | 18 | aoe | 1 | 3 | — | inspired | — |
| Stored Retribution | 16 | 2 | 18 | single | 1 | 1 | — | — | bankDamage |
| War Chant | 10 | 2 | 14 | single | 1 | 1 | — | empowered | — |


## Appendix B: Character roster (20)

| Character | Type | ATK | DEF | ARM | HP | Trion | T.Aff | T.Spirit | Crit | FAT | Perk |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|---|
| Kaito Reyes | attack | 27 | 8 | 1 | 100 | 110 | 20 | 35 | 15 | 12 | Last Ace |
| Vela Ashworth | attack | 26 | 7 | 1 | 100 | 105 | 18 | 40 | 12 | 10 | First Blood |
| Dross | attack | 24 | 9 | 2 | 100 | 115 | 16 | 35 | 6 | 9 | Overwhelm |
| Ren Kobayashi | attack | 26 | 8 | 1 | 100 | 100 | 22 | 30 | 10 | 14 | First Strike |
| Airi Tanaka | attack | 22 | 9 | 1 | 100 | 100 | 20 | 45 | 13 | 11 | Feint |
| Marren Osei | defense | 12 | 16 | 3 | 100 | 120 | 16 | 55 | 3 | 7 | Bulwark |
| Ilona Vance | defense | 17 | 15 | 2 | 100 | 110 | 18 | 50 | 5 | 8 | Riposte |
| Bastian Cole | defense | 14 | 14 | 3 | 100 | 115 | 16 | 50 | 3 | 7 | Absorb |
| Dorian Voss | defense | 15 | 14 | 2 | 100 | 110 | 18 | 48 | 4 | 8 | Immovable |
| Sable Whitlock | defense | 14 | 15 | 3 | 100 | 115 | 18 | 55 | 4 | 8 | — |
| Priya Nakamura | support | 10 | 10 | 1 | 100 | 105 | 24 | 65 | 4 | 9 | Combat Medic |
| Soren Talvik | support | 12 | 9 | 1 | 100 | 105 | 20 | 60 | 5 | 9 | Weaken Resolve |
| Yuki Amaral | support | 10 | 11 | 2 | 100 | 105 | 22 | 70 | 4 | 8 | Devoted Aid |
| Haru Ellison | support | 10 | 10 | 1 | 100 | 130 | 32 | 60 | 4 | 9 | Battery |
| Celestine Moreau | support | 10 | 11 | 2 | 100 | 110 | 20 | 62 | 4 | 8 | Warding Presence |
| Zheng Anders | unique | 19 | 10 | 1 | 100 | 105 | 24 | 45 | 8 | 12 | Foresight |
| Nadia Kessler | unique | 22 | 9 | 1 | 100 | 100 | 20 | 40 | 9 | 16 | Chain Reaction |
| Rurik Voss | unique | 29 | 6 | 1 | 100 | 100 | 18 | 30 | 14 | 13 | All or Nothing |
| Mireille Song | unique | 19 | 9 | 1 | 100 | 100 | 20 | 45 | 8 | 11 | Decoy |
| Tobias Renner | unique | 19 | 10 | 1 | 100 | 105 | 20 | 45 | 7 | 11 | Versatile |


## Appendix C: Status effect magnitudes (selected)

| Constant | Value |
|---|---|
| `bleedingDamagePerTurn` | 8 |
| `scorchedDamagePerTurn` | 12 |
| `necroticWoundDamagePerTurn` | 12 |
| `poisonedDurationTurns` | 3 |
| `acidArmorReduction` | 5 |
| `corrodedArmorReduction` | 3 |
| `markedAllDamageTakenMultiplier` | 1.5 |
| `exposedAllDamageTakenMultiplier` | 1.25 |
| `guardedAllDamageTakenMultiplier` | 0.75 |
| `petrifiedAllDamageTakenMultiplier` | 0.5 |
| `empoweredOutgoingDamageMultiplier` | 1.25 |
| `enragedOutgoingDamageMultiplier` | 1.5 |
| `weakenedOutgoingDamageMultiplier` | 0.75 |
| `stunnedDurationTurns` | 1 |
| `frozenDurationTurns` | 1 |
| `charmedDurationTurns` | 3 |
| `silencedDurationTurns` | 1 |
| `sappedDrainPercentOfTrionCapacity` | 0.25 |
| `genjutsuTrappedDrainPercentOfTrionCapacity` | 0.15 |
| `adrenalineRushCriticalChanceBonus` | 15 |
| `battleTranceFatChanceBonus` | 20 |
| `ralliedMaxHealthBonus` | 20 |
| `inspiredAttackBonus` | 2 |
| `fatiguedAttackPenalty` | 2 |


## Appendix D: Tunable constants

### Trion income
| Constant | Value |
|---|---|
| `baseChanceLowToMedium` | 0.35 |
| `baseChanceMediumToHigh` | 0.20 |
| `affinityWeightPerPoint` | 0.01 |
| `lowAmount` | 10 |
| `mediumAmount` | 20 |
| `highAmount` | 35 |

### FAT
| Constant | Value |
|---|---|
| `baseFatCooldownTurns` | 3 |
| `maxAbilitiesOnFatTrigger` | 3 |
| `normalAbilitiesPerTurn` | 1 |
| `multiAbilityPenaltyThreshold` | 2 |
| `cooldownDoubleMultiplier` | 2.0 |
| `trionAffinityPenaltyMultiplier` | 0.5 |

### Combat / crit
| Constant | Value |
|---|---|
| `criticalHitDamageMultiplier` | 2.0 |
| `criticalMissDefensePenaltyPct` | 0.20 |
| `criticalMissTeamSpiritPenaltyPct` | 0.20 |
| `thresholdAtMinChance` | 20 |
| `thresholdAtMaxChance` | 5 |
| `minChancePercent` | 0 |
| `maxChancePercent` | 90 |

### Loadout & Team Spirit
| Constant | Value |
|---|---|
| `maxEquippedTriggers` | 8 |
| `requiredActiveAbilityCount` | 4 |
| `statMin` | 0 |
| `statMax` | 100 |
| `midpoint` | 50 |
| `maxSingleTargetDamageBonus` | 0.30 |
| `maxBurstDamageBonus` | 0.30 |
| `maxCriticalChanceBonus` | 20 |
| `maxHealthRegenBonus` | 0.30 |
| `maxFatChanceBonus` | 20 |
| `secondsPerTurn` | 15}) |

### Passive counters
| Constant | Value |
|---|---|
| `draegorEnmityThreshold` | 5 |
| `draegorMaxRegretPerBattle` | 3 |
| `nullhymnDiscordThreshold` | 5 |
| `nullhymnMaxDischarges` | 2 |
| `reckoningDebtThreshold` | 6 |
| `gravehourCooldownTurns` | 3 |
| `gravehourFinisherFlatDamage` | 40 |
| `gravehourLowHpThreshold` | 0.3 |
| `coldreadSeizeRollBonus` | 2 |
| `ironvowMaxSanctionedStrikes` | 3 |

### Unique abilities
| Constant | Value |
|---|---|
| `sharedAgonyLinkedDamageMultiplier` | 1.2 |
| `graveBargainHpSpendFraction` | 0.25 |
| `martyrsEndHpThreshold` | 0.25 |
| `martyrsEndDamage` | 80 |
| `dreadResonanceDamagePerCumulativeDamage` | 0.15 |
| `dreadResonanceMinDamage` | 5 |
| `illusoryDoubleStartingCharges` | 1 |
| `karmicBindLowTsFraction` | 0.25 |
| `karmicBindHighTsFraction` | 0.60 |
| `echoingDoubtBacklashDamage` | 20 |
| `vowOfTheDuelDamageMultiplier` | 2.0 |
| `vowOfTheDuelStunDurationTurns` | 2 |


*Document generated from the live `main` sources. Numbers reflect the current catalog and constants.*

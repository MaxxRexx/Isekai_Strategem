# How to Play

Isekai Strategem is a turn-based 3v3 tactical battle. Two teams of 3
characters fight; a team is defeated once all 3 of its members reach 0
health. See [`CHARACTERS.md`](CHARACTERS.md) for the roster,
[`TRIGGERS.md`](TRIGGERS.md) for the abilities you'll draft, and
[`STATUS_EFFECTS.md`](STATUS_EFFECTS.md) for the full debuff/buff catalog.

## Before the battle: draft your Loadout

Each of your 3 characters needs a **Loadout** before the fight starts:

- **Trion Capacity budget.** Every character has a Trion Capacity stat
  (100-130). Everything you equip - Triggers and your Black Trigger - has
  an equip cost, and the total can't exceed this budget.
- **Exactly 4 active abilities.** A valid Loadout provides exactly 4
  *active* abilities in total. A Black Trigger's own active abilities
  (0-2 of them) count towards this; the rest comes from equipped
  `ActiveTrigger`s.
- **8 equipped items, max.** Triggers plus your Black Trigger (if any),
  counted together, can't exceed 8.
- **One Black Trigger, optional.** You may equip at most one. It can
  contribute active abilities, passive abilities, and/or a World
  ability (see below) - see [`TRIGGERS.md`](TRIGGERS.md#black-triggers)
  for the 10 available.
- **Any character can equip anything.** Your character's own
  `CharacterType` (Attack/Defense/Support/Unique) never blocks equipping
  a Trigger or Black Trigger of a different flavor - a Support character
  can run an all-attack Loadout if you want. The only place type
  matters is **Resonance** (below).

### Resonance: how well a Black Trigger suits your character

A Black Trigger has its own type (Attack/Defense/Support/Unique). How
well that matches your character's own `CharacterType` sets a
**Resonance Grade** (A/B/C/D), which multiplies that Black Trigger's
damage/healing, divides its cooldowns, and scales its passive/World
ability magnitudes:

| Your Type \ Black Trigger Type | Attack | Defense | Support | Unique |
|---|---|---|---|---|
| **Attack**  | A | B | C | A |
| **Defense** | C | A | A | B |
| **Support** | D | A | A | B |
| **Unique**  | B | B | B | B |

Grade multipliers: **A** = 1.5x, **B** = 1.15x, **C** = 1.0x, **D** =
0.85x. A mismatched Black Trigger isn't illegal, just weaker - a
Support character running an Attack-type Black Trigger (D) is a real,
if inefficient, build.

## Turn structure

- A **turn belongs to a whole team**, not one character - any/all of
  your 3 living members may act during your team's turn.
- A **round** is one turn for each team. Teams alternate; the round
  counter increments once both sides have gone.
- Each **team turn is capped at 15 seconds** to lock in actions (a
  Black Trigger's World ability can raise or lower this for a team).
- **First-move handicap:** whichever team acts first in the battle gets
  a reduced Trion gain roll on that single opening turn only (forced to
  the lowest tier) - an offset for the tempo advantage of going first.
  Normal rolls resume immediately after.

### What happens at the start of your team's turn

1. **Trion gain.** Your team rolls for Trion income (see below) and it's
   added to your shared team Trion Pool.
2. **Status effects tick** for each living member (damage-over-time,
   heal-over-time, Trion drain, etc.) - see
   [`STATUS_EFFECTS.md`](STATUS_EFFECTS.md).
3. **Full Arms Trigger (FAT)** is rolled per character (see below).

### Taking actions

Normally each character gets **1 ability use** per turn. If FAT
triggers for a character this turn, they get **up to 3** ability uses
instead - but chaining 2+ uses in one turn carries a real cost (see
FAT below). Using an ability costs Trion from your team's shared pool
and puts that ability on cooldown.

### Ending your turn

Cooldowns and any pending penalties finalize for characters who acted.
Control passes to the other team.

## Trion: two separate resources

- **Trion Capacity** (per character, 100-130): your Loadout budget,
  spent once during drafting. Doesn't change in battle.
- **Trion Pool** (per team, starts empty): the in-battle currency spent
  to use abilities, refilled each of your team's turns via the Trion
  gain roll below. Shared by your whole team.

### The Trion gain roll

Each of your team's turns, you roll for a tier of Trion income - **Low**
(10), **Medium** (20), or **High** (35) - modeled as two upgrade checks:
a roll to go from Low to Medium, and (if that succeeds) another to go
from Medium to High. The chance of upgrading is `base chance + 0.01 x
your team's summed Trion Affinity (of living members) + any active
modifiers`. Higher Trion Affinity stats meaningfully raise your odds of
a bigger income turn - and a character with an ability that provides a
positive modifier makes this even more likely.

## Full Arms Trigger (FAT)

FAT is rolled per character at the start of your turn, using their FAT
Chance stat (plus a Team Spirit bonus - see below). If it triggers, that
character may use **up to 3 abilities this turn** instead of 1.

Chaining 2 or more abilities via FAT in the same turn carries a real
cost for *that character only*:
- All cooldowns used that turn are **doubled**.
- Their Trion Affinity is **halved** for their next turn.
- FAT itself goes on a cooldown (3 turns, before modifiers) before it
  can trigger for them again.

Using only 1 ability in a FAT-triggered turn avoids this penalty
entirely - the extra actions are optional, not forced.

## Team Spirit: a dual-direction stat

Team Spirit runs 0-100 with 50 as a neutral midpoint, and pulls in two
different directions depending which side of the midpoint you're on:

- **Below 50** (aggressive end): bonus single-target damage (up to
  +30%), bonus Burst damage (up to +30%), and bonus Critical Chance (up
  to +20 percentage points) - all scaling linearly toward the extreme.
- **Above 50** (sustain end): bonus Health Regeneration amount when
  healed (up to +30%) and bonus FAT Chance (up to +20 percentage
  points).

A character sitting exactly at 50 gets neither bonus. There's no
"best" value in isolation - it's a build axis, not a stat to always
maximize.

## Combat resolution

An attack is an opposed roll: **attacker rolls d20 + Attack**, **target
rolls d20 + Defense**. The attacker wins ties. A natural 1 on the
attacker's die is always a critical miss (automatic failure, and
inflicts a 1-turn penalty on the attacker: -20% Defense, -20% Team
Spirit). A roll at or above a threshold set by the attacker's effective
Critical Chance is always a critical hit (automatic success, damage dice
rolled twice) - higher Critical Chance lowers the natural roll needed,
from a natural 20 at 0% Critical Chance down to a natural 17 at 90%+.
That floor of 17 caps the crit rate at 20% of rolls no matter how much
Critical Chance a build stacks.

A crit doubles the **dice** only: the ability's damage dice are rolled a
second time and its flat bonus is left alone, so a crit is a strong
bonus rather than a whole extra attack.

Damage resolution order once a hit lands: **critical dice bonus** ->
**flat Armor reduction** (floored at 0) -> **damage-type multiplier** (status
effects like Wet, or a granted Damage Resistance, which halves the
instance). A World ability's damage-prevention charge (if any remain)
fully negates the whole instance before any of this, consuming one
charge.

## Status effects, perks, and Black Triggers interact generically

Nothing in the engine special-cases a status effect, perk, or Black
Trigger by name - they're all just data read by the same generic rules
(stat modifiers, roll advantage/disadvantage, damage multipliers,
action prevention, etc.). See [`STATUS_EFFECTS.md`](STATUS_EFFECTS.md)
for the full 50-effect catalog and [`CHARACTERS.md`](CHARACTERS.md) for
each character's unique innate perk, which is always active regardless
of Loadout and combines with whatever you equip.

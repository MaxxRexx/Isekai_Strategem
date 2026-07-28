# AI Profiles

20 individually-authored opponents: 5 skill classes x 4 distinct
strategic identities each. Skill class controls *how well* a profile
executes (mistake chance, whether it weighs Defense/resistances, Expert
lookahead); the identity controls *what it's trying to do* (targeting,
ability choice, FAT usage, Black Trigger bias, Loadout tag preferences).
A "mistake" means that decision falls back to a random legal choice
instead of the profile's intended pick.

| Skill Class | Mistake Chance | Weighs Defense/Resistances | Lookahead |
|---|---|---|---|
| Beginner | 40% | No | No |
| Amateur | 25% | No | No |
| Intermediate | 12% | Yes | No |
| Professional | 5% | Yes | No |
| Expert | 2% | Yes | Yes - predicts whether a hit would actually secure a kill |

## Beginner

- **Button Masher** - targets whoever is first in its own target list
  and uses whatever ability is off cooldown in slot order. No
  evaluation at all.
- **The Turtle** - leans on self-buffs and passives over attacking, to
  a fault (skips the usual "is this actually useful right now" check),
  and never voluntarily chains FAT. Loadout favors buff/defense tags.
- **The Copycat** - no real target discipline (random targeting), and
  just mirrors whatever category of move the opponent used last instead
  of reading the board.
- **The Berserker** - tunnel-visions on raw damage with no target or
  resource discipline, fixating on whoever it last drew blood from.

## Amateur

- **The Sharpshooter** - overvalues Ranged/Burst options even when a
  weaker choice this turn (both at draft time and in actual play).
- **The Healer's Crutch** - over-prioritizes healing/support even when
  finishing a kill would end the fight faster.
- **The Momentum Chaser** - chains every FAT proc on principle,
  productive or not.
- **The Grudge Holder** - fixates on whichever enemy has dealt the most
  cumulative damage this battle, ignoring current health or kill
  priority.

## Intermediate

- **The Executioner** - every character piles onto the same enemy until
  it dies, then the whole team retargets together.
- **The Afflictor** - prioritizes landing status effects over raw
  damage, even when a straight attack would do more immediate damage.
- **The Blast Radius** - reaches for AOE whenever one is off cooldown,
  even against a single remaining target.
- **The Gambler** - always fires its Black Trigger the moment it can,
  regardless of resonance fit (equips one even when it resonates
  poorly).

## Professional

- **The Tactician** - the Executioner's discipline plus real judgment:
  weighs Defense/resistances, not just health, and only chains FAT for
  a kill or a clear tempo swing.
- **The Controller** - sequences a debuff before committing to a burst,
  so the setup actually buys something.
- **The Sweeper** - defaults to focus fire, but switches to AOE only
  once two or more enemies are actually within its kill range together
  - not just "an AOE is available".
- **The Economist** - only spends extra FAT actions when they secure a
  kill or a clear tempo swing; otherwise banks resources.

## Expert

- **The Grandmaster** - full lookahead: predicts whether a hit would
  actually secure a kill before committing to a target, on top of a
  fully matchup-aware, resource-disciplined build.
- **The Silent Blade** - opens with debuff setup, then unloads a
  maximized burst with near-perfect FAT timing.
- **The Wall** - leans on World abilities and stacked passives to grind
  the opponent's resources down, then turns aggressive.
- **The Prodigy** - re-reads the board every single ability choice
  instead of committing to one fixed strategy: reaches for AOE once
  multiple enemies are alive, sets up a debuff on an undebuffed enemy,
  otherwise hits hardest - the closest thing to playing a skilled human.

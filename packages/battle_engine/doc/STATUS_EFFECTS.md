# Status Effects

50 status effects, all expressed as data against the same generic
definition - nothing in the engine special-cases an effect by name.
Duration is in turns (ticked down at the start of the affected
character's team's turn) unless noted otherwise.

| Name | Duration | Effect |
|---|---|---|
| Acid | 3 | -5 Armor |
| Wet | 3 | Immune to Fire; vulnerable to Lightning and Cold |
| Stunned | 1 | Prevents all actions; zeroes Team Spirit |
| Threatened | 2 | Disadvantage on ranged attack rolls |
| Sickened | 3 | Vulnerable to 4 random damage types |
| Sapped | 3 | Drains 25% of Trion Capacity to whoever inflicted it |
| Reeling | 3 | -1 Attack per remaining turn (stronger early, fades out) |
| Rallied | 3 | +20 max health |
| Prone | 1 | Locks a random equipped ability each turn |
| Prepared | 3 | +1 Attack per remaining turn (builds up) |
| Poisoned | 3 | Disadvantage on the poisoned character's own attack rolls |
| Frozen | 1 | Prevents all actions; zeroes Trion Affinity |
| Bleeding | 3 | 8 damage at turn start (Slashing); disadvantage on their own status-resistance rolls |
| Blinded | 2 | Ranged target count reduced by 1; disadvantage on ranged attack rolls |
| Braced | 3 | +1 Defense per remaining turn |
| Charmed | 3 | Can't target the charmer; charmer has advantage on rolls against them |
| Electrocuted | 2 | 1d4 damage at turn start (Lightning) |
| Regenerating | 3 | Heals 3 at turn start |
| Empowered | 2 | +25% outgoing damage |
| Weakened | 3 | -25% outgoing damage |
| Focused | 2 | Advantage on attack rolls |
| Guarded | 2 | Takes 25% less damage from everything |
| Exposed | 2 | Takes 25% more damage from everything |
| Marked | 1 | Takes 50% more damage; marker has advantage on rolls against them |
| Cursed | 3 | Prevents all healing |
| Silenced | 1 | Prevents all actions |
| Enraged | 2 | +50% outgoing damage, -3 Defense |
| Fatigued | 3 | -2 Attack, -2 Defense |
| Inspired | 2 | +2 Attack, +2 Defense |
| Shattered Guard | 2 | Zeroes Armor |
| Overcharged | 2 | Trion costs halved |
| Choked | 2 | Trion costs doubled |
| Petrified | 2 | Prevents all actions; takes 50% less damage; zeroes Team Spirit |
| Terrified | 2 | Disadvantage on attack/ranged-attack rolls; can't target the source |
| Slowed | 2 | -1 Defense per remaining turn; disadvantage on attack rolls |
| Hastened | 2 | Advantage on attack rolls; +1 Attack per remaining turn |
| Scorched | 2 | Vulnerable to Fire; 12 damage at turn start (Fire) |
| Chilled | 2 | Vulnerable to Cold; -1 Attack per remaining turn |
| Corroded | 2 | -3 Armor; vulnerable to Acid |
| Shadow-Bound | 2 | Locks a random equipped ability each turn; disadvantage on attack rolls |
| Genjutsu Trapped | 1 | Prevents all actions; drains 15% Trion Capacity to the causer |
| Sealed | 2 | Zeroes Trion Affinity and FAT Chance |
| Overwhelmed | 2 | Zeroes Critical Chance; disadvantage on attack rolls |
| Adrenaline Rush | 2 | +15 Critical Chance |
| Battle Trance | 2 | +20 FAT Chance |
| Suppressed | 2 | -5 Status Effect Infliction |
| Warded | 2 | +10 Status Effect Resistance |
| Hexed | 2 | -10 Status Effect Resistance |
| Radiant Blessing | 3 | Heals 1 at turn start; +10 max health; takes 10% less damage |
| Necrotic Wound | 3 | 12 damage at turn start (Necrotic); prevents all healing |

## Notes on interpretation

- **"Advantage"/"disadvantage"** apply to a specific roll (attack roll,
  ranged attack roll, or status-resistance roll) - multiple sources of
  the same direction don't stack further, and one of each direction
  cancels out to a normal roll.
- **"Per remaining turn"** modifiers (Reeling, Prepared, Braced, Slowed,
  Hastened, Chilled) scale with however many turns are left on the
  effect, so they're strongest right after being inflicted and fade as
  the duration ticks down (or build up over the duration, for the
  positive ones like Prepared/Hastened).
- **"Prevents all actions"** (Stunned, Frozen, Silenced, Petrified,
  Genjutsu Trapped) means that character cannot use any ability at all
  while it's active - not even the one ability FAT would normally allow
  beyond the first.
- **Zeroed stats** override the stat to 0 outright rather than applying
  a percentage or flat penalty.

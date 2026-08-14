# Isekai Strategem: Complete Game Design Document

**What this is.** A single, plain-language explanation of the entire game as it
exists on the `main` branch. It is written to be read start to finish by someone
who has never seen the game before. Every system is explained in normal English,
every number that matters is given, and every piece of content (each Trigger,
each Black Trigger ability, each status effect, each perk, each counter, each
unique ability, each combo) is described so you know exactly what it does.

This document replaces the older, partial notes.
(`docs/current_development_status.md` tracks what is done, in progress, and
planned, plus the combat-rework design detail; the files under
`packages/battle_engine/doc/` are from before that rework and are out of date.)

**The short version.** Isekai Strategem is a turn-based fighting game where you
build a team of three characters, give each one a set of abilities, and battle
another team of three until one side is wiped out. Its ideas come from three
places: the anime/manga World Trigger (the words Trion, Trigger, Black Trigger,
and the Attacker / Shooter / Sniper / Trapper roles), Naruto (energy-style
resource play and status effects like genjutsu, shadow-binding, and sealing),
and tabletop Dungeons and Dragons (rolling a 20-sided die to hit, rolling with
advantage or disadvantage, critical hits, and a big list of status conditions).

---

## Table of contents

1. What the game is, in one page
2. The moment-to-moment loop
3. Your team: characters and the four types
4. Stats: what each number means
5. Team Spirit: the offense-or-sustain slider
6. Trion: the resource you spend
7. Triggers and Loadouts: building an ability set
8. Full Arms Trigger (FAT): your burst turn
9. How a turn works: queue then resolve
10. Resolution order: the six phases
11. How an attack is decided: the dice math
12. Status effects: the full list, explained
13. Counters: reacting to the enemy
14. Unique abilities: the signature moves
15. Combos: rewarding setups
16. Team Efficiency Grade: your build score
17. Black Triggers: the ultimate gear
18. Character perks: innate traits
19. The AI opponent
20. Accounts and XP: the online part
21. What is built so far
- Appendix A: every Trigger, explained
- Appendix B: the full character roster
- Appendix C: every status effect magnitude
- Appendix D: all the tunable numbers

---

## 1. What the game is, in one page

You control a **squad of three characters**. So does your opponent (usually an
AI). Each of your characters carries a **Loadout**, which is a small set of
**Triggers** (abilities) plus, optionally, one powerful **Black Trigger**.

A battle is a series of **turns** that alternate between the two squads. On your
turn you pick actions for your living characters, choose their targets, and end
the turn. Your actions then play out, the enemy takes its turn, and this repeats
until every character on one side has been reduced to 0 Health. Reducing a
character to 0 Health takes it out of the fight for good ("DEFEATED"), and a
strong hit can do that in one blow, so the game is about smart planning: managing
your resource, landing status effects at the right moment, setting traps for the
enemy, and building a team whose pieces support each other. It is not about
simply having bigger numbers.

There is also an unfinished story mode (visual-novel style). This document is
about the battle game.

---

## 2. The moment-to-moment loop

Here is what you actually do, in order, every time you play:

1. **Pick your three characters.** Each has fixed starting stats, a type
   (Attack, Defense, Support, or Unique), and one built-in perk that is always on.
2. **Build each character's Loadout.** You equip Triggers into their slots. Every
   Trigger has an equip cost, and the total must fit inside that character's Trion
   Capacity. You must end up with exactly four usable abilities (more on the rules
   in the Loadouts section).
3. **The game grades your team.** Before the fight, it looks at your three
   Loadouts and gives your squad a **Team Efficiency Grade** (a letter grade from
   D up to SSS). A higher grade helps you in the fight but earns you less XP
   afterward, and a lower grade is the reverse. This is a deliberate risk-reward
   trade.
4. **Fight.** Turns alternate. On your turn you queue up actions and end the turn;
   they resolve in a set order, then the AI responds.
5. **Win or lose, then get XP.** When one squad is wiped out, the winner is
   decided and the player earns XP based on the inverse of their grade.

---

## 3. Your team: characters and the four types

A squad is always **exactly three characters**, chosen from a roster of **20**.
Every character belongs to one of four **types**, and the type tells you their
job and the general shape of their stats. (The exact stats for all 20 characters
are in Appendix B.)

- **Attack (5 characters).** Front-line damage dealers. High Attack (10 to 13),
  low Defense, and low Team Spirit, which as you will see leans them toward
  hitting hard. These are your glass cannons.
- **Defense (5 characters).** Tanks. High Defense (10 to 12) and higher Armor,
  so they soak hits and hold the line. They also carry more control tools.
- **Support (5 characters).** Healers and enablers. High Trion Affinity (so they
  fuel the team's resource) and high Team Spirit (so they lean toward sustaining
  the team), with low Attack. They keep everyone alive and topped up.
- **Unique (5 characters).** Specialists. Each is built around one signature
  "unique" ability and a distinctive perk, so they do something no plain
  character can.

Your choice of types also feeds the Team Efficiency Grade: a team whose stats and
abilities all pull in the same clear direction scores better than a muddled one.

---

## 4. Stats: what each number means

Every character has a block of stats. All of them are shown in the game (the
loadout and roster screens display even the ones that used to be hidden). Here is
what each one actually does in plain terms:

- **Attack.** Added to your 20-sided die roll when you try to hit someone. Higher
  Attack means you land hits more often. It is the biggest factor in whether an
  attack connects.
- **Defense.** Added to the defender's die roll when they are attacked. Higher
  Defense means enemies miss you more often.
- **Armor.** A flat amount of damage removed from every hit that lands on you,
  after all the multipliers. Small but constant protection.
- **Max Health.** How much damage you can take before you are knocked out. Every
  character starts at 100. At 0 Health, the character is DEFEATED and gone.
- **Trion Capacity.** Two things at once: the size of your spendable resource
  pool, and the budget you have for equipping Triggers when you build the Loadout.
  It ranges from about 100 to 130 across the roster.
- **Trion Affinity.** Improves the odds that you gain a larger amount of Trion at
  the start of each turn. A high-Affinity character is your team's battery.
- **Team Spirit.** A slider from 0 to 100 (explained in the next section). Below
  50 it makes you more offensive, above 50 it makes you better at sustaining.
- **Critical Chance.** The chance that an attack becomes a critical hit, which
  rolls the ability's damage dice a second time. Mechanically, more Critical
  Chance widens the range of dice rolls that count as a crit, down to a natural
  17 at the very most.
- **FAT Chance.** The chance that Full Arms Trigger activates on your turn, which
  lets that character use up to three abilities in one turn instead of one.
- **Status Infliction.** How good you are at making your status effects stick when
  you try to apply them. Think of it as the strength of your attempt.
- **Status Resistance.** How good you are at shrugging off status effects that
  others try to put on you. Think of it as your saving throw.

---

## 5. Team Spirit: the offense-or-sustain slider

Team Spirit is a single number from 0 to 100, where **50 is neutral**. It pulls
in two opposite directions depending on which side of 50 you are on:

- **Below 50 leans offensive.** The lower you go, the bigger the bonus. At the
  extreme (Team Spirit 0) you get up to +30% damage on single-target attacks,
  +30% damage on burst attacks, and +20 Critical Chance.
- **Above 50 leans sustaining.** The higher you go, the bigger the bonus. At the
  extreme (Team Spirit 100) you get up to +30% to healing you receive and +20 FAT
  Chance.
- **At exactly 50** you get nothing either way.

So an Attack character sitting around 30 to 40 Team Spirit is a committed glass
cannon (extra damage and crits), while a Support around 60 to 70 is a committed
sustainer (better healing and more frequent burst turns). The game shows a live
readout next to the value telling you which way it currently leans and by how
much. Because committing hard to one pole is rewarded, Team Spirit is one of the
biggest inputs into your Team Efficiency Grade.

---

## 6. Trion: the resource you spend

**Trion** is the energy you spend to use abilities. It comes in two connected
forms:

- **Trion Capacity** is your pool size and also your Loadout building budget.
  Every Trigger has two costs: an **equip cost** (paid once against your Capacity
  when you build the team) and a **Trion cost** (paid from your running pool each
  time you use it in battle).
- **Per-turn income.** At the start of each of your turns, your side rolls for how
  much Trion it gains that turn. There are three tiers:

  | Tier | You gain | How it is rolled |
  |---|---|---|
  | Low | +10 | The starting state every turn. |
  | Medium | +20 | You have a 35% base chance to upgrade Low to Medium, plus 1% for each point of your squad's total Trion Affinity. |
  | High | +35 | If you reached Medium, you roll again to reach High: a 20% base chance plus 1% per point of total Trion Affinity. |

  So the more Trion Affinity your squad has, the more often you gain the bigger
  amounts. A high-Affinity Support like Haru Ellison (Affinity 32) noticeably
  raises the whole team's income.

**Attacking the enemy's Trion is a real strategy.** Several status effects target
it: Sapped drains a quarter of the target's Trion Capacity, Genjutsu Trapped
drains 15% of it (and stops them acting), Silenced stops them using abilities at
all, Overcharged halves your ability costs, and Choked doubles the target's
costs.

*Design note: right now income is a semi-random roll and most turns you only cast
one ability, so your Capacity rarely runs dry. A future balance pass may make
income steadier and tie your big burst turns to your Capacity.*

---

## 7. Triggers and Loadouts: building an ability set

A **Trigger** is a single ability. A **Loadout** is one character's chosen set of
Triggers, plus optionally one Black Trigger. Building good Loadouts is the main
puzzle before the fight.

**The rules you must follow when building a Loadout:**

- You may equip at most **8 items** total (Triggers and the Black Trigger all
  count together toward this 8).
- You must have **exactly 4 active abilities** (an active Trigger counts as 1, and
  a Black Trigger contributes however many active abilities it carries).
- The **total equip cost cannot exceed** that character's Trion Capacity.

So it is a packing puzzle: fit exactly four usable abilities, plus any passive
Triggers you want (counters, stat boosts), all inside the Trion budget. Passive
Triggers do not attack; they sit in your slots and do things automatically, like
firing a counter or granting a stat.

**What defines a Trigger.** Each active Trigger has: a name, a **category** (its
role), an equip cost, a Trion cost, a cooldown in turns, whether it is melee or
ranged, an **attack subtype** (single-target, burst, or area), a damage type,
how much damage it rolls, how many targets it can hit, how many separate hits it
makes, an optional heal, any status effects it applies, and sometimes a special
unique or counter behavior.

The 60 active Triggers are grouped into five **categories** by their role, which
line up with World Trigger's classes:

- **Attacker (16):** melee bruisers who close in and hit hard.
- **Shooter (9):** ranged fighters who fire volume, often in bursts.
- **Sniper (3):** long-range specialists who land one big shot.
- **Trapper (24):** control, damage-over-time, debuffs, and most of the unique
  abilities.
- **Optional (20):** buffs, wards, self-help, and the reactive counters.

Every single Trigger is listed with a plain description in Appendix A.

---

## 8. Full Arms Trigger (FAT): your burst turn

Normally a character uses **one ability per turn**. **Full Arms Trigger**, or
**FAT**, is the exception that lets you go big.

- Each turn, a character has a chance (equal to its FAT Chance stat, boosted by a
  high Team Spirit) to **trigger FAT**.
- On a FAT turn, that character may use **up to 3 abilities** instead of 1.
- Going greedy has a price. If you use 2 or more abilities on the FAT turn, you
  pay a penalty: that character's cooldowns are **doubled** and its Trion Affinity
  is **halved**, and FAT then **locks out for 3 turns** before it can happen
  again.

FAT is your coordinated-nuke button, deliberately taxed so that spamming it hurts.
It also interacts with counters: the Draegor counter specifically punishes an
enemy who chains 2 or more abilities on a FAT turn.

---

## 9. How a turn works: queue then resolve

Turns **alternate** between the two squads. Who goes first at the very start of
the battle is decided by an **even coin flip** (a 50/50 chance). There is a
15-second timer per turn.

On your turn:

1. **You queue actions.** For each living character you pick an ability and its
   targets, and it goes into your queue. The Trion cost is **spent the moment you
   queue it**, and if you change your mind and remove it from the queue, you get
   the Trion back. Cooldowns, on the other hand, only start once the action
   actually resolves.
2. **The game keeps you honest.** It only lets you queue legal actions (you can
   afford them, they are off cooldown, they have valid targets, and you have not
   exceeded your per-turn ability limit, which is 1 normally or up to 3 on a FAT
   turn).
3. **You end the turn.** Your queued actions now resolve in a set order (next
   section), the results are shown after a brief "Resolving..." pause, and then
   the AI takes its turn through the exact same process.

The AI builds and resolves a full queue the same way you do, which keeps single
player and any future online play running on one shared system.

---

## 10. Resolution order: the six phases

When your turn resolves, your queued actions do **not** simply go in the order you
picked them. They are sorted into a fixed **phase order** so that setups happen
before payoffs. The phases are:

1. Pre-emptive and reactive setup (arming counters and traps).
2. **Buffs** (boosting yourself or an ally, putting up wards).
3. **Control** (debuffs that do not deal damage, like stuns and slows).
4. **Attacks** (anything that deals damage).
5. Post-attack effects.
6. Cleanup, where timed effects tick down and expire.

**Within a single phase**, ties are broken by **how far a character's Team Spirit
is from 50** (the more committed character goes first), and finally by the order
you queued them. For example, a buff you queued second still resolves before an
attack you queued first, because buffs are an earlier phase. And between two
attacks, the character whose Team Spirit is furthest from 50 strikes first.

Timed effects (wards, traps, marks that only last a couple of turns) are ticked
down once per turn during cleanup, so they eventually wear off.

---

## 11. How an attack is decided: the dice math

Every damaging hit is settled in two separate dice rolls: first a roll to see if
it **hits**, then a completely separate roll for **how much damage** it does.

**Step one, the to-hit roll.** Both sides roll a 20-sided die.

- The attacker rolls their die and adds their Attack stat.
- The defender rolls their die and adds their Defense stat.
- If the attacker's total is greater than or equal to the defender's total, the
  attack **hits**. Otherwise it **misses**.
- Some perks and status effects grant **advantage** (roll two dice, keep the
  higher) or **disadvantage** (roll two, keep the lower). For instance, Airi
  Tanaka's perk Feint makes the first attacker against her roll with
  disadvantage.

**Critical hits.** A hit becomes a **critical hit** when the attacker's raw die
lands in the critical range. With no Critical Chance you only crit on a natural
20; as Critical Chance climbs, the range widens, but only as far as a natural 17
even at the maximum, so the best possible crit build still crits on one roll in
five. A critical hit **rolls the ability's damage dice a second time** (the flat
damage bonus is not doubled). A **critical miss** (a very low roll) even
penalizes the attacker, dropping their Defense and Team Spirit by 20% for one
turn.

**Step two, the damage roll.** This is a fresh roll on the Trigger's own dice, and
it passes through a short chain of adjustments (the battle log shows every step):

1. Start with the **dice total** (the Trigger rolls its dice, like two 6-sided
   dice plus a flat bonus).
2. Multiply by any **outgoing-damage bonus** from Team Spirit, perks, or statuses.
3. If it was a critical hit, roll the ability's damage dice again and add them
   (the flat bonus is not doubled).
4. Subtract the target's **Armor**.
5. Apply any **resistance or vulnerability** (a resisted damage type is halved; a
   status like Exposed increases it).
6. The result is the **final damage** dealt.

Burst abilities run this whole chain once per hit, and area abilities apply it to
each target.

*Design note: this is where the balance pass did most of its work. Attack and
Defense used to run 10-29 and 6-16, which put a 15-point gap on a typical attack
and meant the die changed almost nothing: attacks landed over 90% of the time and
the roll was decoration. Attack now runs 4-14 and Defense 2-12, so the gap
between any two characters fits inside the die's own range and the roll decides
a real share of the outcome. Damage was rebuilt the same way: abilities used to
be a small die on a huge flat bonus (2d6+37, 4d8+86), and are now roughly half
dice (6d6+23, 6d8+29), so the damage roll swings too. Across 200 simulated
AI-versus-AI battles this moved the average hit rate to about 50% and roughly
doubled how long a fight lasts, which is what the reviews were asking for.*

---

## 12. Status effects: the full list, explained

Status effects are temporary conditions you put on characters. There are 62 of
them. Whether one sticks is a contest between the attacker's **Status Infliction**
and the target's **Status Resistance** (some characters are simply immune to
certain ones). Here is every status and exactly what it does. Durations are in
turns.

### Damage over time (they chip Health each turn)

- **Bleeding:** loses 8 Health each turn for 3 turns.
- **Poisoned:** loses Health each turn for 3 turns (a poison tick).
- **Scorched:** burning, loses 12 Health each turn for 2 turns.
- **Necrotic Wound:** rotting, loses 12 Health each turn for 3 turns.
- **Corroded:** Armor reduced by 3 for 2 turns (and pairs with acid attacks).
- **Acid:** Armor reduced by 5 for 3 turns.

### Hard control (they stop the target acting)

- **Stunned:** cannot act for 1 turn.
- **Frozen:** frozen solid, cannot act for 1 turn.
- **Petrified:** turned to stone, cannot act for 2 turns, but takes only half
  damage while petrified.
- **Silenced:** cannot use abilities for 1 turn.
- **Charmed:** turned against their own team for 3 turns (a long, powerful loss of
  control).
- **Genjutsu Trapped:** caught in an illusion, cannot act, and loses 15% of Trion
  Capacity, for 1 turn.
- **Prone:** knocked down for 1 turn, easier to hit and hampered.
- **Shadow-Bound:** pinned in place by shadow for 2 turns.

### Damage taken up or down

- **Marked:** takes +50% damage for 1 turn (a painter for a burst kill).
- **Exposed:** takes +25% damage for 2 turns.
- **Overwhelmed:** swamped and taking extra damage for 2 turns.
- **Guarded:** takes 25% less damage for 2 turns.
- **Braced:** braced for impact, reduced incoming damage for 3 turns.
- **Shattered Guard:** guard broken, defenses weakened for 2 turns.

### Damage dealt up or down

- **Empowered:** deals +25% damage for 2 turns.
- **Enraged:** deals +50% damage but loses 3 Defense for 2 turns (reckless).
- **Weakened:** deals 25% less damage for 3 turns.

### Stat changes

- **Inspired:** +2 Attack and +2 Defense for 2 turns.
- **Fatigued:** -2 Attack and -2 Defense for 3 turns.
- **Hastened:** Attack rises a little more each turn, for 2 turns.
- **Slowed:** Defense drops a little more each turn, for 2 turns.
- **Chilled:** Attack drops a little more each turn, for 2 turns.
- **Rallied:** +20 Max Health for 3 turns (a morale shield).
- **Focused:** sharpened aim and readiness for 2 turns.
- **Blinded:** attacks are much less accurate for 2 turns.
- **Reeling:** knocked off balance for 3 turns.
- **Threatened:** pressured and softened up for 2 turns.
- **Terrified:** too afraid to fight effectively for 2 turns.
- **Cursed:** a lingering hex that worsens the target for 3 turns.

### Crit and burst boosters

- **Adrenaline Rush:** +15 Critical Chance for 2 turns.
- **Battle Trance:** +20 FAT Chance for 2 turns.

### Trion and status economy

- **Sapped:** loses 25% of Trion Capacity for 3 turns.
- **Overcharged:** your abilities cost half Trion for 2 turns.
- **Choked:** abilities cost double Trion for 2 turns.
- **Suppressed:** 5 less Status Infliction for 2 turns (worse at applying
  statuses).
- **Warded:** +10 Status Resistance for 2 turns (better at shrugging statuses).
- **Hexed:** 10 less Status Resistance for 2 turns (easier to afflict).
- **Sealed:** one ability type is sealed off for 2 turns.
- **Origin Lockout:** locked out of a category of Trigger for 2 turns.

### Healing and protection

- **Regenerating:** heals a little Health each turn for 3 turns.
- **Radiant Blessing:** +10 Max Health, a small heal each turn, and slightly
  reduced incoming damage, for 3 turns.

### Setup and disruption

- **Wet:** soaked, setting up bonus damage from lightning and cold follow-ups, 3
  turns.
- **Sickened:** vulnerable to 4 random damage types (takes extra from them) for 3
  turns.
- **Electrocuted:** shocked for 2 turns (chains strongly off Wet).
- **Prepared:** readied, boosting your next action, for 3 turns.
- **Misfire:** a 50% chance that each of your actions simply fails, for 2 turns.
- **Forced Repetition:** forced to repeat the same action for 2 turns.
- **Interdict:** branded so that repeating an ability lands at 25% strength, for 2
  turns.
- **Forced Critical Miss:** your next attack is forced to be a critical miss.
- **Isolation:** cut off from ally support for 2 turns.
- **Untargetable:** cannot be targeted by anyone for 1 turn.
- **Echoing Doubt:** acting against this target backlashes onto you for 20 damage,
  for 1 turn.
- **Vow of the Duel:** two characters are bound in a duel: double damage passes
  between them, plus a 2-turn stun on the target.
- **Forced Choice:** forced into a lose-lose decision for 1 turn.
- **Karmic Bind:** a two-way link where damage is shared between the pair based on
  Team Spirit, for 3 turns.
- **Called Shot:** one of the target's stats is reduced to zero for 2 turns.
- **Mind's Eye:** the target's hidden Loadout is revealed to you for 3 turns.

---

## 13. Counters: reacting to the enemy

Counters are how you react to the opponent instead of just acting. You arm them on
your turn, and they fire automatically when the enemy does the right thing. There
are two kinds.

### Reactive counters (arm now, fire on the enemy's next action)

These come from special Triggers. Each does one specific thing:

- **Reflect:** bounces the next non-area attack straight back at whoever threw it.
- **Dodge Melee:** completely avoids the next single-target melee attack (this is
  the Predictive Parry Trigger).
- **Negate by Origin:** cancels the next attack that matches a chosen origin type.
- **Burst Mitigation:** cuts down incoming burst damage (the Numbing Toxin
  Trigger).
- **Cooldown Sabotage:** when the enemy attacks into it, their cooldowns get
  extended (the Frozen Tempo Trigger).
- **Redirect to Ally:** sends an incoming attack onto one of the attacker's own
  allies instead.
- **Trap on Action:** springs a trap the moment the target takes an action.
- **Nullify Area:** cancels an incoming area attack (the Death Ledger Trigger; the
  game then lets the holder borrow that nullified area ability into their own
  Loadout for 2 turns).
- **Bank Damage:** stores the damage you take and lets you release it later (the
  Stored Retribution Trigger).
- **Survive Lethal:** lets you live through a hit that would have knocked you out
  (the One More Breath ability).

### Passive counters (they charge up, then discharge)

Six of them build up stacks based on what the enemy does, then unleash a big
effect when full:

- **Draegor:** every ability its holder uses adds a stack of Enmity. At 5 stacks
  it becomes Regret for 2 turns. While Regret is up, if an enemy chains 2 or more
  abilities on a FAT turn, your squad's Team Efficiency Grade jumps 2 tiers for 2
  turns (or, if you are already very high grade, your best Trion character's
  Affinity doubles instead). This can happen up to 3 times per battle.
- **Nullhymn:** builds a stack of Discord whenever an enemy uses a Black Trigger
  against you or lands a status on the holder. At 5 stacks it discharges (up to
  twice per battle): it permanently drops the enemy's most recently used Black
  Trigger one power grade, or, if no enemy is running one, it purges your team's
  debuffs and reflects them back onto whoever applied the most.
- **Reckoning:** builds a stack of Debt whenever an enemy crits your team or uses a
  long-cooldown ability against it. At 6 stacks it comes due: the worst offender's
  cooldowns get extended, their next attack is forced to be a critical miss, and
  your team takes some of their Trion.
- **Gravehour:** at the end of an enemy turn, if they did no damage or left one of
  your enemies at 30% Health or lower, the holder gets a free, uncounterable
  finishing blow (40 flat damage) on the lowest-Health enemy, who also cannot be
  healed next turn. This has a 3-turn cooldown.
- **Coldread:** at the start of your turn it secretly marks an enemy. If that enemy
  then takes a damaging action, you earn a reward that alternates each time you
  read them correctly: first a Levy (steal the Trion from their costliest action),
  then a Seize (+2 to your whole squad's dice rolls for 1 turn). Guess wrong and
  your next Trion gain is docked.
- **Ironvow:** each turn a random attack type is "sanctioned" (never the same as
  last turn). If you attack with that type, you land a Sanctioned Strike that
  cannot be blocked, strips one of the target's buffs, and brands them (so
  repeating an ability against them two turns running lands weakened). The cost is
  that your other allies are left vulnerable to that type until your next turn.
  You get up to 3 of these per battle.

---

## 14. Unique abilities: the signature moves

The Unique-type characters and a handful of special Triggers have **unique
abilities**, which are effects too special to describe as plain damage plus a
status. There are 17 of them:

- **Shared Agony:** links two enemies together, so damage dealt to one also bleeds
  onto the other (at 1.2 times).
- **Grave Bargain:** you spend a quarter of your own current Health to power up a
  strike.
- **Martyr's End:** when you drop below 25% Health, you can detonate for 50 damage.
- **Vow of the Duel:** binds you and a target into a duel where double damage
  passes between you, and stuns them for 2 turns.
- **Sunder Arms:** a heavy single-target blow that shreds the target's armor.
- **Curving Shot:** a shot that curves past cover and defenses.
- **Called Shot:** a precise hit that reduces one of the target's stats to zero for
  a while.
- **Mind's Eye:** reveals a chosen enemy's full Loadout (and lets you click their
  abilities to read them) for 3 turns.
- **Forced Choice:** forces the target into a lose-lose decision.
- **Memory Theft:** steals or copies one of the target's abilities.
- **Sensory Swap:** swaps a targeting or sensory relationship between two targets.
- **Dread Resonance:** deals more damage the more total damage the target has
  already taken this battle (0.15 per point of prior damage, minimum 5).
- **Isolation:** cuts a target off from its allies' support.
- **Illusory Double:** you start with one decoy charge and gain more when an ally
  falls; the decoy soaks a hit meant for you.
- **Echoing Doubt:** plants a doubt so that acting against you backlashes for 20
  damage.
- **Karmic Bind:** ties you and a target together so damage is shared based on your
  Team Spirit values (between 25% and 60%).
- **Unmaking:** a powerful unravelling debuff that strips the target down.

---

## 15. Combos: rewarding setups

The game watches what your squad does within a turn and recognizes **combos**,
which are setup-then-payoff patterns. When it spots one, it rewards you (through
the Team Efficiency Grade's combo bonuses: extra dice advantage on the payoff, and
a Trion refund on the setup). There are 18 recognized combos in two layers.

**Layer one, general patterns** (they fire whenever the shape matches, no matter
which specific abilities you used):

- **Control then Strike:** you control a target (a stun, freeze, and so on) and
  then attack it.
- **Affliction Detonate:** you attack a target that already has a damage-over-time
  or affliction on it.
- **Setup Exploit:** you exploit a debuff an ally already applied.
- **Focus Fire:** two or more of your characters hit the same target in one turn.

**Layer two, signature chains** (specific ability or status pairings, more
thematic): Frozen Detonation, Terror Cascade, Shatterpoint Execution, Piercing
Corrosion, Pinned Shot, Mind Unravel, Charmed Opening, Flashfire, Opening Sweep,
Venom Reap, Snared Execution, Brittle Pierce, Blinding Volley, and Dread Shatter.
Each of these looks for a particular first move that a particular second move then
cashes in (for example, freezing a target and then shattering the ice, or
blinding a group and then firing into it).

---

## 16. Team Efficiency Grade: your build score

Before the battle, the game scores each squad's three Loadouts into a **Team
Efficiency Grade**, a letter grade that measures how well your team is built. It
is not just a badge: it both helps you during the fight and controls how much XP
you earn afterward, in opposite directions, so it is a genuine risk-reward choice.

**How the grade is calculated.** Six sub-scores are combined (weighted) into one
number from 0 to 100, which maps to a tier:

- **Team Spirit Alignment (weighted most, 25%):** does each character's Loadout
  lean the same way their Team Spirit does (offense or sustain)? Committed teams
  score high.
- **Stat Coherence:** do a character's stats reinforce the job you are asking them
  to do?
- **Loadout Synergy:** do the equipped Triggers work well together?
- **Perk Utilization:** does the Loadout actually enable that character's perk?
- **Trion Economy:** do the costs of the build fit its income?
- **Resonance Fit:** how well the Black Trigger suits the character (this is blank
  if there is no Black Trigger).

**The tiers, from worst to best:** D, C, B, A, S, SS, SSS.

**What the grade does in battle.** A higher grade feeds a dice advantage into your
attack, defense, and resistance rolls (a coordination bonus for you, and it also
makes the enemy read you less well). At the very top (SSS) it widens your critical
range. It also grants extra advantage on recognized combo payoffs and a Trion
refund on combo setups. And the Draegor counter can temporarily shove your
effective grade up 2 tiers.

**What the grade does afterward.** This is the clever part: a weaker grade earns
**more** XP and a stronger grade earns **less**, so climbing the grade makes you
better in the fight but slower to level up. The bonuses are:

| Grade | D | C | B | A | S | SS | SSS |
|---|---|---|---|---|---|---|---|
| XP bonus | +75% | +63% | +51% | +40% | +28% | +16% | +5% |

Your awarded XP is the base XP times (1 plus that bonus), rounded. It is computed
on the server so it cannot be faked (see the Accounts section).

---

## 17. Black Triggers: the ultimate gear

A **Black Trigger** is a rare, powerful Loadout piece: effectively a whole extra
kit bolted onto one character, usually a bundle of active abilities plus passive
bonuses, and sometimes a once-per-battle "World ability." There are 10, and here
is what each one gives you:

- **Ashbringer (attack):** three active abilities, Ashbringer Slash (a heavy melee
  hit), Ashbringer Volley (a ranged hit), and Seal of Severance. A well-rounded,
  short-cooldown damage package.
- **Fracture Edge (attack):** one active, Fracture Burst (a burst attack), plus the
  passive Sundering Focus that leans into offense.
- **Solar Flare (attack):** one active, Solar Flare, a single massive area nuke on a
  long cooldown, plus the passive Blazing Focus that boosts crits.
- **Aegis Core (defense):** a defensive World ability that negates the first few
  instances of damage you would take.
- **Bastion Frame (defense):** one active, Foresight Counter, plus three passives,
  Bastion Plating (armor), Hardened Shell (damage resistance), and Steady Mind
  (status resistance). A fortress package.
- **Wellspring (support):** two actives, Wellspring Surge (a direct heal) and
  Mirror Ward (a reflect), backing a sustain build.
- **Chorus Bond (support):** four passives, Bonded Resolve, Harmonic Focus, Warding
  Chorus, and Vital Chorus, all built around Team Spirit and team-wide healing.
- **Paradox Shard (unique):** four disruptive actives, Paradox Whisper, Paradox
  Fracture, Puppet Strings, and Deadfall, a bag of unpredictable debuffs and
  control.
- **Gravebind (unique):** one active, One More Breath, a World-style effect that
  lets you survive, once per battle, a hit that would otherwise defeat you.
- **Chrono Fragment (unique):** a time-themed unique piece.

How well a Black Trigger fits its wielder is measured by the Resonance Fit
sub-score of the Team Efficiency Grade, and the enemy's Nullhymn counter can
permanently weaken your Black Trigger.

---

## 18. Character perks: innate traits

Every character has one **perk** that is always active and that a good Loadout
should try to make use of (the grade's Perk Utilization sub-score rewards this).
Here is every perk and what it does:

| Character (type) | Perk | What it does |
|---|---|---|
| Kaito Reyes (Attack) | Last Ace | His Critical Chance doubles while he is the last living member of his team. |
| Vela Ashworth (Attack) | First Blood | Her first attack of the battle gains bonus Critical Chance. |
| Dross (Attack) | Overwhelm | His area attacks deal bonus damage to a target that already has a debuff. |
| Ren Kobayashi (Attack) | First Strike | He gets a flat Attack bonus on the first ability he uses each battle. |
| Airi Tanaka (Attack) | Feint | The first attack made against her each battle is rolled with disadvantage. |
| Marren Osei (Defense) | Bulwark | His Armor is doubled while any teammate is still alive. |
| Ilona Vance (Defense) | Riposte | Whenever a melee attack against her misses, she gains a stacking Attack buff for her next turn. |
| Bastian Cole (Defense) | Absorb | The first instance of damage he takes each battle is cut in half. |
| Dorian Voss (Defense) | Immovable | He resists forced movement and displacement effects. |
| Sable Whitlock (Defense) | Defensive anchor | Built around high Defense and Armor to hold the line. |
| Priya Nakamura (Support) | Combat Medic | Her heal-over-time effects heal for more. |
| Soren Talvik (Support) | Weaken Resolve | His debuffs hit harder against a target already carrying one of his other debuffs. |
| Yuki Amaral (Support) | Devoted Aid | She adds 10% to all healing, from any source. |
| Haru Ellison (Support) | Battery | A living Trion battery, with very high Trion Affinity (32) fueling the whole squad's income. |
| Celestine Moreau (Support) | Warding Presence | Her ally-targeted buffs also grant the ally a Status Resistance bonus. |
| Zheng Anders (Unique) | Foresight | Once per battle he can reroll one of his own attack rolls. |
| Nadia Kessler (Unique) | Chain Reaction | Each additional ability she uses on a single FAT turn deals more than the last. |
| Rurik Voss (Unique) | All or Nothing | A pure glass cannon (Attack 29, Defense 6): huge damage, very fragile. |
| Mireille Song (Unique) | Decoy | Once per battle, an attack against her has a chance to simply miss, as if she was never there. |
| Tobias Renner (Unique) | Versatile | He gets a small bonus to whichever stat matches the category of the ability he last used. |

---

## 19. The AI opponent

In single player you fight an **AI profile**, which comes in skill classes from
Beginner up through Amateur, Intermediate, Professional, and Expert. The AI plans
and resolves a full turn through the exact same system you do, with a short
"thinking" pause before it commits, so the same rules apply to both sides.
Teaching the AI to value the counters, uniques, and status effects well is a
planned future task.

---

## 20. Accounts and XP: the online part

Accounts and XP run on a real online backend (Supabase), with a safety net that
falls back to a local-only mode if the backend is ever unreachable, so the game
always runs.

- **Signing in is stress-free.** You can play instantly as a **guest** (no sign-up
  at all), or use **passwordless email** (you get a magic link, nothing to
  remember), or **Google**. If you start as a guest and later sign in, you keep
  the same account and all your progress.
- **XP is calculated on the server, so it cannot be cheated.** When a battle ends,
  your app reports the result, and the server recalculates the grade-based XP
  itself and updates your total. A player can never just set their own XP. The
  database also makes sure each player can only ever see and change their own data.
- A small daily automated task keeps the free online project awake so it is always
  available.

---

## 21. What is built so far

- **The battle engine is complete:** the queue-and-resolve turn system, all the
  reactive and passive counters, the unique abilities, the rebalanced Trigger
  catalog, combo recognition, and the Team Efficiency Grade with its in-battle
  effects and inverse XP.
- **Accounts and XP are live** and verified end to end.
- **The interface** has the grade badge, all stats shown, the Team Spirit readout,
  the Loadout builder, plain-language descriptions of the passive counters, the
  clickable character and enemy detail panels with the Mind's Eye reveal, the
  sign-in flow, the post-battle XP screen, and the rebuilt battle log (tap any line
  for a plain-English breakdown, and tap names or abilities to read them). Still to
  come: showing the pending queue during a turn, and polishing the resolve pause.
- **Balance:** the five near-duplicate Trigger pairs have been given distinct
  identities, critical hits have been capped and now double only the damage dice,
  and the four Triggers that dominated the catalog (Whirlwind Slash, Twin Fang
  Strike, Longshot, Cinderburst) have been re-costed. The rest of the balance pass
  (compressing the dice math, initiative, a spatial layer, and a points budget for
  statuses and Triggers) is written up in the design reviews and is the next big
  task.

---

## Appendix A: Every Trigger, explained

Each entry lists the cost in Trion, the cooldown in turns, and a plain description. There are 60 active Triggers.


### Attacker Triggers (melee bruisers) (16)

- **"Martyr's End"** (costs 10 Trion, 4-turn cooldown). A utility ability (no direct damage). Signature effect: detonates for 50 damage when you are below 25% Health.
- **Cinderburst** (costs 18 Trion, 2-turn cooldown). A melee area fire attack dealing about 15 damage to each of up to 3 enemies. Applies Scorched (12 burn damage per turn).
- **Cleave** (costs 15 Trion, 2-turn cooldown). A melee area slashing attack dealing about 22 damage to each of up to 2 enemies. Applies Shattered Guard (guard broken, weaker defense).
- **Cryo Burst** (costs 18 Trion, 2-turn cooldown). A ranged area cold attack dealing about 18 damage to each of up to 3 enemies. Applies Chilled (attack sinks each turn).
- **Dread Resonance** (costs 18 Trion, 2-turn cooldown). A utility ability (no direct damage). Signature effect: hits harder the more damage the target has taken.
- **Dread Wave** (costs 18 Trion, 2-turn cooldown). A ranged area psychic attack dealing about 16 damage to each of up to 3 enemies. Applies Overwhelmed (swamped, takes extra damage).
- **Frost Lance** (costs 14 Trion, 1-turn cooldown). A ranged single-target cold attack dealing about 22 damage. Applies Chilled (attack sinks each turn).
- **Grave Bargain** (costs 8 Trion, 2-turn cooldown). A utility ability (no direct damage). Signature effect: spends 25% of your own Health to power the strike.
- **Piercing Thrust** (costs 18 Trion, 2-turn cooldown). A melee single-target piercing attack dealing about 52 damage.
- **Predictive Parry** (costs 20 Trion, 2-turn cooldown). A self-targeted setup or counter (no direct damage). Counter: dodges the next single-target melee attack.
- **Shared Agony** (costs 14 Trion, 2-turn cooldown). A melee unique necrotic attack dealing about 47 damage. Signature effect: links two enemies so damage bleeds between them.
- **Soul Siphon** (costs 16 Trion, 2-turn cooldown). A ranged single-target psychic attack dealing about 22 damage.
- **Sunder Arms** (costs 16 Trion, 3-turn cooldown). A melee unique slashing attack dealing about 37 damage. Signature effect: shreds the target armor.
- **Twin Fang Strike** (costs 15 Trion, 2-turn cooldown). A melee single-target slashing attack dealing about 44 damage.
- **Vow of the Duel** (costs 15 Trion, 3-turn cooldown). A utility ability (no direct damage). Signature effect: binds a duel: double damage between you plus a 2-turn stun.
- **Whirlwind Slash** (costs 16 Trion, 2-turn cooldown). A melee area slashing attack dealing about 17 damage to each of up to 3 enemies. Applies Bleeding (8 damage per turn).

### Shooter Triggers (ranged volume) (9)

- **Arc Volley** (costs 20 Trion, 2-turn cooldown). A ranged rapid burst lightning attack dealing about 10 damage per hit across 3 hits on each of up to 2 targets.
- **Frag Grenade** (costs 20 Trion, 2-turn cooldown). A ranged area piercing attack dealing about 20 damage to each of up to 3 enemies.
- **Gatling Burst** (costs 24 Trion, 2-turn cooldown). A ranged rapid burst piercing attack dealing about 10 damage per hit across 5 hits. Applies Exposed (takes +25% damage).
- **Pepper Shot** (costs 16 Trion, 1-turn cooldown). A ranged rapid burst piercing attack dealing about 10 damage per hit across 3 hits.
- **Rapid Fire** (costs 18 Trion, 2-turn cooldown). A ranged rapid burst piercing attack dealing about 17 damage per hit across 3 hits. Applies Bleeding (8 damage per turn).
- **Scattershot** (costs 22 Trion, 2-turn cooldown). A ranged rapid burst piercing attack dealing about 6 damage per hit across 4 hits on each of up to 3 targets. Applies Slowed (defense sinks each turn).
- **Split Shot** (costs 18 Trion, 2-turn cooldown). A ranged rapid burst piercing attack dealing about 14 damage per hit across 2 hits on each of up to 2 targets.
- **Suppressing Fire** (costs 20 Trion, 2-turn cooldown). A ranged rapid burst piercing attack dealing about 10 damage per hit across 3 hits on each of up to 2 targets. Applies Suppressed (worse at applying statuses).
- **Thunderclap Round** (costs 18 Trion, 2-turn cooldown). A ranged area thunder attack dealing about 13 damage to each of up to 3 enemies. Applies Overwhelmed (swamped, takes extra damage).

### Sniper Triggers (long-range big hits) (3)

- **Called Shot** (costs 16 Trion, 2-turn cooldown). A utility ability (no direct damage). Signature effect: zeroes one of the target stats.
- **Curving Shot** (costs 18 Trion, 2-turn cooldown). A ranged unique piercing attack dealing about 37 damage. Signature effect: curves past cover and defense.
- **Longshot** (costs 24 Trion, 2-turn cooldown). A ranged single-target piercing attack dealing about 56 damage.

### Trapper Triggers (control and debuffs) (24)

- **Acid Spray** (costs 16 Trion, 2-turn cooldown). A melee area acid attack dealing about 13 damage to each of up to 3 enemies. Applies Corroded (-3 armor).
- **Caustic Cloud** (costs 16 Trion, 2-turn cooldown). A ranged area acid attack dealing about 9 damage to each of up to 3 enemies. Applies Poisoned (damage each turn).
- **Charm Whisper** (costs 20 Trion, 2-turn cooldown). A utility ability (no direct damage). Applies Charmed (turned against their team).
- **Death Ledger** (costs 18 Trion, 2-turn cooldown). A ranged single-target piercing attack dealing about 10 damage. Counter: nullifies an incoming area attack.
- **Dread Gaze** (costs 14 Trion, 1-turn cooldown). A ranged single-target psychic attack dealing about 10 damage. Applies Terrified (too afraid to fight well).
- **Echoing Doubt** (costs 16 Trion, 3-turn cooldown). A utility ability (no direct damage). Signature effect: backlashes for 20 if acted against.
- **Flashbang Round** (costs 18 Trion, 2-turn cooldown). A utility ability (no direct damage). Applies Blinded (much less accurate).
- **Forced Choice** (costs 14 Trion, 2-turn cooldown). A utility ability (no direct damage). Signature effect: forces a lose-lose choice.
- **Isolation** (costs 14 Trion, 3-turn cooldown). A utility ability (no direct damage). Signature effect: cuts the target off from allies.
- **Karmic Bind** (costs 16 Trion, 3-turn cooldown). A utility ability (no direct damage). Signature effect: shares damage between you based on Team Spirit.
- **Mass Confusion** (costs 20 Trion, 2-turn cooldown). A ranged area psychic attack dealing about 10 damage to each of up to 3 enemies. Applies Silenced (cannot use abilities).
- **Memory Theft** (costs 16 Trion, 3-turn cooldown). A utility ability (no direct damage). Signature effect: steals or copies an ability.
- **Mind Fog** (costs 16 Trion, 2-turn cooldown). A ranged area psychic attack dealing about 10 damage to each of up to 3 enemies. Applies Blinded (much less accurate).
- **Mind Shatter** (costs 18 Trion, 2-turn cooldown). A ranged single-target psychic attack dealing about 10 damage. Applies Silenced (cannot use abilities).
- **Nightmare Pulse** (costs 18 Trion, 2-turn cooldown). A ranged area psychic attack dealing about 14 damage to each of up to 2 enemies. Applies Terrified (too afraid to fight well).
- **Numbing Toxin** (costs 20 Trion, 2-turn cooldown). A self-targeted setup or counter (no direct damage). Counter: reduces incoming burst damage.
- **Psychic Scream** (costs 18 Trion, 2-turn cooldown). A ranged area psychic attack dealing about 10 damage to each of up to 3 enemies. Applies Silenced (cannot use abilities).
- **Root Snare** (costs 18 Trion, 2-turn cooldown). A ranged single-target bludgeoning attack dealing about 10 damage. Applies Forced Repetition (stuck repeating an action).
- **Scramble** (costs 20 Trion, 2-turn cooldown). A ranged single-target psychic attack dealing about 10 damage. Applies Misfire (50% chance actions fail).
- **Sensory Swap** (costs 14 Trion, 2-turn cooldown). A utility ability (no direct damage). Signature effect: swaps a targeting link between two enemies.
- **Shatterpoint** (costs 12 Trion, 1-turn cooldown). A melee single-target acid attack dealing about 22 damage. Applies Corroded (-3 armor).
- **Unmaking** (costs 18 Trion, 3-turn cooldown). A utility ability (no direct damage). Signature effect: a heavy unravelling debuff.
- **Venom Needle** (costs 12 Trion, 1-turn cooldown). A ranged single-target poison attack dealing about 15 damage. Applies Poisoned (damage each turn).
- **Venom Spray** (costs 20 Trion, 2-turn cooldown). A ranged rapid burst poison attack dealing about 9 damage per hit across 3 hits on each of up to 2 targets. Applies Poisoned (damage each turn).

### Optional Triggers (buffs, wards, counters) (8)

- **"Guardian's Aegis"** (costs 14 Trion, 2-turn cooldown). A self-targeted setup or counter (no direct damage). Applies Guarded (takes 25% less damage). Applies Braced (reduced incoming damage).
- **"Mind's Eye"** (costs 10 Trion, 3-turn cooldown). A utility ability (no direct damage). Signature effect: reveals the enemy Loadout for 3 turns.
- **Cleansing Ward** (costs 16 Trion, 2-turn cooldown). A utility ability (no direct damage). Applies Regenerating (heals each turn). Applies Warded (+resistance).
- **Frozen Tempo** (costs 18 Trion, 2-turn cooldown). A self-targeted setup or counter (no direct damage). Counter: extends the attacker cooldowns when they hit it.
- **Illusory Double** (costs 0 Trion, 2-turn cooldown). A utility ability (no direct damage). Signature effect: a decoy that soaks a hit.
- **Rally Cry** (costs 14 Trion, 2-turn cooldown). A utility ability (no direct damage). Applies Inspired (+2 attack and defense).
- **Stored Retribution** (costs 16 Trion, 2-turn cooldown). A self-targeted setup or counter (no direct damage). Counter: banks damage taken to release later.
- **War Chant** (costs 10 Trion, 2-turn cooldown). A self-targeted setup or counter (no direct damage). Applies Empowered (deals +25% damage).


## Appendix B: The full character roster (20)

| Character | Type | Attack | Defense | Armor | Health | Trion Cap | Trion Aff | Team Spirit | Crit | FAT | Perk |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|---|
| Kaito Reyes | attack | 13 | 4 | 1 | 100 | 110 | 20 | 35 | 15 | 12 | Last Ace |
| Vela Ashworth | attack | 12 | 3 | 1 | 100 | 105 | 18 | 40 | 12 | 10 | First Blood |
| Dross | attack | 11 | 5 | 2 | 100 | 115 | 16 | 35 | 6 | 9 | Overwhelm |
| Ren Kobayashi | attack | 12 | 4 | 1 | 100 | 100 | 22 | 30 | 10 | 14 | First Strike |
| Airi Tanaka | attack | 10 | 5 | 1 | 100 | 100 | 20 | 45 | 13 | 11 | Feint |
| Marren Osei | defense | 5 | 12 | 3 | 100 | 120 | 16 | 55 | 3 | 7 | Bulwark |
| Ilona Vance | defense | 8 | 11 | 2 | 100 | 110 | 18 | 50 | 5 | 8 | Riposte |
| Bastian Cole | defense | 6 | 10 | 3 | 100 | 115 | 16 | 50 | 3 | 7 | Absorb |
| Dorian Voss | defense | 7 | 10 | 2 | 100 | 110 | 18 | 48 | 4 | 8 | Immovable |
| Sable Whitlock | defense | 6 | 11 | 3 | 100 | 115 | 18 | 55 | 4 | 8 | - |
| Priya Nakamura | support | 4 | 6 | 1 | 100 | 105 | 24 | 65 | 4 | 9 | Combat Medic |
| Soren Talvik | support | 5 | 5 | 1 | 100 | 105 | 20 | 60 | 5 | 9 | Weaken Resolve |
| Yuki Amaral | support | 4 | 7 | 2 | 100 | 105 | 22 | 70 | 4 | 8 | Devoted Aid |
| Haru Ellison | support | 4 | 6 | 1 | 100 | 130 | 32 | 60 | 4 | 9 | Battery |
| Celestine Moreau | support | 4 | 7 | 2 | 100 | 110 | 20 | 62 | 4 | 8 | Warding Presence |
| Zheng Anders | unique | 9 | 6 | 1 | 100 | 105 | 24 | 45 | 8 | 12 | Foresight |
| Nadia Kessler | unique | 10 | 5 | 1 | 100 | 100 | 20 | 40 | 9 | 16 | Chain Reaction |
| Rurik Voss | unique | 14 | 2 | 1 | 100 | 100 | 18 | 30 | 14 | 13 | All or Nothing |
| Mireille Song | unique | 9 | 5 | 1 | 100 | 100 | 20 | 45 | 8 | 11 | Decoy |
| Tobias Renner | unique | 9 | 6 | 1 | 100 | 105 | 20 | 45 | 7 | 11 | Versatile |


## Appendix C: Status effect magnitudes


### Damage and armor
| Setting | Value |
|---|---|
| bleedingDamagePerTurn | 8 |
| scorchedDamagePerTurn | 12 |
| necroticWoundDamagePerTurn | 12 |
| acidArmorReduction | 5 |
| corrodedArmorReduction | 3 |

### Damage multipliers
| Setting | Value |
|---|---|
| markedAllDamageTakenMultiplier | 1.5 |
| exposedAllDamageTakenMultiplier | 1.25 |
| guardedAllDamageTakenMultiplier | 0.75 |
| petrifiedAllDamageTakenMultiplier | 0.5 |
| empoweredOutgoingDamageMultiplier | 1.25 |
| enragedOutgoingDamageMultiplier | 1.5 |
| weakenedOutgoingDamageMultiplier | 0.75 |

### Trion, crit, and other
| Setting | Value |
|---|---|
| sappedDrainPercentOfTrionCapacity | 0.25 |
| genjutsuTrappedDrainPercentOfTrionCapacity | 0.15 |
| adrenalineRushCriticalChanceBonus | 15 |
| battleTranceFatChanceBonus | 20 |
| ralliedMaxHealthBonus | 20 |


## Appendix D: All the tunable numbers


### Trion income
| Setting | Value |
|---|---|
| baseChanceLowToMedium | 0.35 |
| baseChanceMediumToHigh | 0.20 |
| affinityWeightPerPoint | 0.01 |
| lowAmount | 10 |
| mediumAmount | 20 |
| highAmount | 35 |

### Full Arms Trigger
| Setting | Value |
|---|---|
| baseFatCooldownTurns | 3 |
| maxAbilitiesOnFatTrigger | 3 |
| normalAbilitiesPerTurn | 1 |
| multiAbilityPenaltyThreshold | 2 |
| cooldownDoubleMultiplier | 2.0 |
| trionAffinityPenaltyMultiplier | 0.5 |

### Combat and crit
| Setting | Value |
|---|---|
| criticalHitDamageMultiplier | 2.0 |
| criticalMissDefensePenaltyPct | 0.20 |
| criticalMissTeamSpiritPenaltyPct | 0.20 |
| thresholdAtMinChance | 20 |
| thresholdAtMaxChance | 17 |
| minChancePercent | 0 |
| maxChancePercent | 90 |

### Loadout and Team Spirit
| Setting | Value |
|---|---|
| maxEquippedTriggers | 8 |
| requiredActiveAbilityCount | 4 |
| statMin | 0 |
| statMax | 100 |
| midpoint | 50 |
| maxSingleTargetDamageBonus | 0.30 |
| maxBurstDamageBonus | 0.30 |
| maxCriticalChanceBonus | 20 |
| maxHealthRegenBonus | 0.30 |
| maxFatChanceBonus | 20 |
| secondsPerTurn | 15}) |

### Passive counters
| Setting | Value |
|---|---|
| draegorEnmityThreshold | 5 |
| draegorMaxRegretPerBattle | 3 |
| nullhymnDiscordThreshold | 5 |
| nullhymnMaxDischarges | 2 |
| reckoningDebtThreshold | 6 |
| gravehourFinisherFlatDamage | 40 |
| gravehourLowHpThreshold | 0.3 |
| coldreadSeizeRollBonus | 2 |
| ironvowMaxSanctionedStrikes | 3 |

### Unique abilities
| Setting | Value |
|---|---|
| sharedAgonyLinkedDamageMultiplier | 1.2 |
| graveBargainHpSpendFraction | 0.25 |
| martyrsEndHpThreshold | 0.25 |
| martyrsEndDamage | 50 |
| dreadResonanceDamagePerCumulativeDamage | 0.15 |
| dreadResonanceMinDamage | 5 |
| illusoryDoubleStartingCharges | 1 |
| echoingDoubtBacklashDamage | 20 |
| vowOfTheDuelDamageMultiplier | 2.0 |
| vowOfTheDuelStunDurationTurns | 2 |


*This document is generated from the live sources on the main branch. The numbers match the current catalog and settings.*

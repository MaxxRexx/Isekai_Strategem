import '../models/damage_type.dart';
import '../models/passive_counter.dart';
import '../models/passive_effect.dart';
import '../models/reactive_effect.dart';
import '../models/status_effect.dart';
import '../models/trigger.dart';
import '../models/trion_type.dart';
import '../models/unique_behavior.dart';
import '../util/dice.dart';

/// The built-in 72-Trigger catalog (60 active, 12 passive), a shared draft
/// pool any character may equip regardless of their own [CharacterType] -
/// nothing in the [Loadout] rules restricts equipping by type.
///
/// The 60 active Triggers are balanced on two independent axes, 20 each
/// way (both asserted in the content-catalog tests):
///
///  - **Ability type**: 20 melee / 20 ranged / 20 psychic. Includes the 17
///    Unique-subtype Triggers (5 melee, 2 ranged, 10 psychic) that wire
///    the Phase C unique behaviors.
///  - **Range band** ([RangeTag]): 20 close / 20 mid / 20 long, and
///    critically, **every ability type spans all three bands**. The band
///    answers where the wielder has to be, which is a different question
///    from what kind of attack it is: Piercing Thrust is a melee lunge
///    that crosses the gap (long), Scattershot is a point-blank scattergun
///    (close), Charm Whisper is a psychic effect that needs whispering
///    distance (close). The full grid is melee 12/5/3, ranged 3/8/9 and
///    psychic 5/7/8 across close/mid/long. Keep every cell of that grid
///    populated: the band was a dead tag for as long as it was derivable
///    from the ability type.
class TriggerCatalog {
  final Map<String, Trigger> _byId;

  TriggerCatalog._(this._byId);

  Trigger operator [](String id) {
    final trigger = _byId[id];
    if (trigger == null) throw ArgumentError('Unknown Trigger id: $id');
    return trigger;
  }

  bool contains(String id) => _byId.containsKey(id);

  Iterable<Trigger> get all => _byId.values;
  Iterable<ActiveTrigger> get activeTriggers => all.whereType<ActiveTrigger>();
  Iterable<PassiveTrigger> get passiveTriggers =>
      all.whereType<PassiveTrigger>();

  factory TriggerCatalog.builtIn() {
    final triggers = <Trigger>[
      // Re-costed in the balance pass: at cooldown 1 for 10 Trion this was
      // pure single-target spam with no tempo decision behind it. Cooldown
      // 2 makes using it a choice about which turn you want it on.
      ActiveTrigger(
        id: 'twin_fang_strike',
        name: 'Twin Fang Strike',
        category: TriggerCategory.attacker,
        equipCost: 16,
        trionCost: 13,
        // Trion Types: SPTV 3.38: 13 Trion for 44 to one target on a 2-turn
        // cooldown. Two blades, and one of the best deals in the game, so it
        // pays like one.
        trionTypeCost: const TrionTypeCost({TrionType.physical: 3}),
        cooldownTurns: 2,
        originTag: OriginTag.physical,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.single,
        damageType: DamageType.slashing,
        damage: const DiceExpression(6, 6, flatBonus: 23),
      ),
      ActiveTrigger(
        id: 'cleave',
        name: 'Cleave',
        category: TriggerCategory.attacker,
        equipCost: 19,
        trionCost: 13,
        // Trion Types: SPTV 4.23, the best deal in the catalogue: 13 Trion,
        // cooldown 2, 22 slashing to each of two bodies and their guard
        // shattered. Pays the top price, all of it steel.
        trionTypeCost: const TrionTypeCost({TrionType.physical: 3}),
        cooldownTurns: 2,
        originTag: OriginTag.physical,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 2,
        damageType: DamageType.slashing,
        damage: const DiceExpression(3, 6, flatBonus: 11),
        inflictedStatusEffects: const [
          StatusEffectApplication('shattered_guard')
        ],
      ),
      ActiveTrigger(
        id: 'suppressing_fire',
        name: 'Suppressing Fire',
        category: TriggerCategory.shooter,
        equipCost: 35,
        trionCost: 27,
        // Trion Types: SPTV 2.59: 60 across two targets, and Suppressed drops
        // their chance of landing anything. Weight of fire that takes a
        // decision away from them.
        trionTypeCost:
            const TrionTypeCost({TrionType.physical: 1, TrionType.mental: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.physical,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.burst,
        hitsPerUse: 3,
        targetCount: 2,
        damageType: DamageType.piercing,
        damage: const DiceExpression(2, 4, flatBonus: 5),
        inflictedStatusEffects: const [StatusEffectApplication('suppressed')],
      ),
      ActiveTrigger(
        id: 'shatterpoint',
        name: 'Shatterpoint',
        category: TriggerCategory.trapper,
        equipCost: 15,
        trionCost: 10,
        // Trion Types: SPTV 3.81, third-best deal in the catalogue: 10 Trion,
        // 1-turn cooldown, 22 acid every turn and Corroded on top. Priced as
        // the bargain it is, not as the filler it looks like.
        trionTypeCost: const TrionTypeCost({TrionType.afflict: 3}),
        cooldownTurns: 1,
        originTag: OriginTag.afflict,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.single,
        damageType: DamageType.acid,
        damage: const DiceExpression(3, 6, flatBonus: 11),
        inflictedStatusEffects: const [StatusEffectApplication('corroded')],
      ),
      ActiveTrigger(
        id: 'venom_needle',
        name: 'Venom Needle',
        category: TriggerCategory.trapper,
        equipCost: 18,
        trionCost: 12,
        // Trion Types: SPTV 1.69: one dose of poison for 12 Trion.
        trionTypeCost: const TrionTypeCost({TrionType.afflict: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.afflict,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.single,
        damageType: DamageType.poison,
        damage: const DiceExpression(3, 4, flatBonus: 7),
        inflictedStatusEffects: const [StatusEffectApplication('poisoned')],
      ),
      ActiveTrigger(
        id: 'dread_gaze',
        name: 'Dread Gaze',
        category: TriggerCategory.trapper,
        equipCost: 20,
        trionCost: 14,
        // Trion Types: SPTV 0.99: ten damage and a light Terror.
        trionTypeCost: const TrionTypeCost({TrionType.afflict: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.afflict,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.single,
        damageType: DamageType.psychic,
        damage: const DiceExpression(2, 4, flatBonus: 5),
        inflictedStatusEffects: const [StatusEffectApplication('terrified')],
      ),
      ActiveTrigger(
        id: 'charm_whisper',
        name: 'Charm Whisper',
        category: TriggerCategory.trapper,
        equipCost: 21,
        trionCost: 18,
        // Trion Types: SPTV 0.32, the lowest in the catalogue: three turns of
        // Charmed and nothing else.
        trionTypeCost: const TrionTypeCost({TrionType.mental: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.mental,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.single,
        inflictedStatusEffects: const [StatusEffectApplication('charmed')],
      ),
      // Rally Cry: converted from single to AoE in Phase D (team Inspire),
      // which also fills the melee AoE slot count for the 20/20/20 rebalance.
      ActiveTrigger(
        id: 'rally_cry',
        name: 'Rally Cry',
        category: TriggerCategory.optional,
        equipCost: 20,
        trionCost: 14,
        // Trion Types: SPTV 0.97: Inspired across the squad for 14 Trion and
        // nothing else.
        trionTypeCost: const TrionTypeCost({TrionType.energy: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.energy,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        targetAffiliation: TargetAffiliation.ally,
        inflictedStatusEffects: const [StatusEffectApplication('inspired')],
      ),
      ActiveTrigger(
        id: 'war_chant',
        name: 'War Chant',
        category: TriggerCategory.optional,
        equipCost: 12,
        trionCost: 8,
        // Item #5's interim spot-fix, priced with #3's rule. As a self-buff
        // this was worth 0.30 against a 2.0 to 3.0 band: +25% of the 6.1
        // damage a character deals in a turn is 1.5 a turn, against an action
        // worth 12. A chant the whole squad hears, on a cooldown you can
        // actually keep up, prices at 2.05. Wave 4 prices it again for real.
        // Trion Types: SPTV 2.57 on an 8-Trion ability with a 1-turn cooldown:
        // the squad Empowered nearly every turn for the cheapest Raw Trion in
        // the game.
        trionTypeCost: const TrionTypeCost({TrionType.energy: 2}),
        cooldownTurns: 1,
        originTag: OriginTag.energy,
        // Close, which for an ally means one line either side. A chant sung
        // from the middle line reaches the whole squad; sung from the front
        // it reaches two of them. That is a position worth taking, and the
        // band split is 20/20/20 by design.
        rangeTag: RangeTag.close,
        abilityType: AbilityType.melee,
        // An area ability, like Rally Cry: it catches one line, everyone on
        // it. A single-target subtype with a target count of three would
        // promise a squad buff and deliver one character, since resolution
        // clamps a single to one.
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        targetAffiliation: TargetAffiliation.ally,
        inflictedStatusEffects: const [StatusEffectApplication('empowered')],
      ),
      ActiveTrigger(
        id: 'piercing_thrust',
        name: 'Piercing Thrust',
        category: TriggerCategory.attacker,
        equipCost: 26,
        trionCost: 22,
        // Trion Types: SPTV 2.34: the hardest single thrust in the game at 52,
        // and it costs 22 Trion for it.
        trionTypeCost: const TrionTypeCost({TrionType.physical: 2}),
        cooldownTurns: 2,
        originTag: OriginTag.physical,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.single,
        damageType: DamageType.piercing,
        damage: const DiceExpression(7, 6, flatBonus: 27),
      ),
      // Re-costed in the balance pass: cooldown 1, 12 Trion, three targets
      // and a bleed made this the best value in the catalog by a wide
      // margin. Now cooldown 2 at 16 Trion, so the three-target bleed is a
      // set-up you commit to rather than the default action every turn.
      ActiveTrigger(
        id: 'whirlwind_slash',
        name: 'Whirlwind Slash',
        category: TriggerCategory.attacker,
        equipCost: 18,
        trionCost: 14,
        // Trion Types: SPTV 3.11: the swing is 17; Bleeding at 30 SP is the
        // ability, so it is a blade that opens a wound that keeps bleeding.
        trionTypeCost:
            const TrionTypeCost({TrionType.physical: 1, TrionType.afflict: 2}),
        cooldownTurns: 2,
        originTag: OriginTag.afflict,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.melee,
        // Item #5 spot-fix knock-on: the two support abilities became
        // area buffs, and melee is authored at exactly 10 single to 5 area.
        // This was the catalogue's worst over-band outlier at the same
        // time, so single-target is both the invariant and the price.
        abilitySubtype: AbilitySubtype.single,
        targetCount: 1,
        damageType: DamageType.slashing,
        damage: const DiceExpression(3, 4, flatBonus: 9),
        inflictedStatusEffects: const [StatusEffectApplication('bleeding')],
      ),
      // Re-costed in the balance pass: 4d8+86 topped out at 118 against a
      // 100-health operator, so a single Longshot could delete someone
      // outright through a die roll that barely mattered. 4d8+38 keeps it
      // the hardest single hit in the catalog (56 average) while capping
      // its ceiling at 70, below the health of whoever it lands on.
      ActiveTrigger(
        id: 'longshot',
        name: 'Longshot',
        category: TriggerCategory.sniper,
        equipCost: 48,
        trionCost: 42,
        // Trion Types: SPTV 1.33, because 42 Raw Trion is the highest price in
        // the game and it pays it every shot. A 56-damage bullet, paid for in
        // Raw Trion rather than here.
        trionTypeCost: const TrionTypeCost({TrionType.physical: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.physical,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.single,
        damageType: DamageType.piercing,
        damage: const DiceExpression(6, 8, flatBonus: 29),
      ),
      ActiveTrigger(
        id: 'scattershot',
        name: 'Scattershot',
        category: TriggerCategory.shooter,
        equipCost: 21,
        trionCost: 20,
        // Trion Types: SPTV 4.10, second only to Cleave: twelve hits across
        // three of them for 20 Trion and they end up Slowed. A wall of shot.
        trionTypeCost: const TrionTypeCost({TrionType.physical: 3}),
        cooldownTurns: 2,
        originTag: OriginTag.physical,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.burst,
        hitsPerUse: 4,
        targetCount: 3,
        damageType: DamageType.piercing,
        damage: const DiceExpression(1, 4, flatBonus: 3),
        inflictedStatusEffects: const [StatusEffectApplication('slowed')],
      ),
      ActiveTrigger(
        id: 'flashbang_round',
        name: 'Flashbang Round',
        category: TriggerCategory.trapper,
        equipCost: 22,
        trionCost: 18,
        // Trion Types: SPTV 0.51, and Blinded is priced, so that is its real
        // worth: three of them lose their aim and nothing else happens. Cheap
        // in value, cheap in kinds.
        trionTypeCost: const TrionTypeCost({TrionType.energy: 1}),
        cooldownTurns: 3,
        originTag: OriginTag.energy,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        inflictedStatusEffects: const [StatusEffectApplication('blinded')],
      ),
      ActiveTrigger(
        id: 'frost_lance',
        name: 'Frost Lance',
        category: TriggerCategory.attacker,
        equipCost: 22,
        trionCost: 14,
        // Trion Types: SPTV 1.69: 22 cold and a light Chill, for 14 Trion.
        trionTypeCost: const TrionTypeCost({TrionType.energy: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.energy,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.single,
        damageType: DamageType.cold,
        damage: const DiceExpression(3, 6, flatBonus: 11),
        inflictedStatusEffects: const [StatusEffectApplication('chilled')],
      ),
      // Re-costed in the balance pass: 64 damage across three targets plus
      // a 12-per-turn burn on all three was two full payloads on one
      // ability. It now picks one axis and keeps the burn, so the up-front
      // hit is a third smaller and the damage arrives over time - which is
      // also what makes it read differently from Frag Grenade.
      ActiveTrigger(
        id: 'cinderburst',
        name: 'Cinderburst',
        category: TriggerCategory.attacker,
        equipCost: 21,
        trionCost: 16,
        // Trion Types: SPTV 2.26: the fire is 15; Scorched at 24 SP is most of
        // it, and a burn that keeps burning is an affliction.
        trionTypeCost:
            const TrionTypeCost({TrionType.energy: 1, TrionType.afflict: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.energy,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.melee,
        // Item #5 spot-fix knock-on: the two support abilities became
        // area buffs, and melee is authored at exactly 10 single to 5 area.
        // This was the catalogue's worst over-band outlier at the same
        // time, so single-target is both the invariant and the price.
        abilitySubtype: AbilitySubtype.single,
        targetCount: 1,
        damageType: DamageType.fire,
        damage: const DiceExpression(3, 4, flatBonus: 7),
        inflictedStatusEffects: const [StatusEffectApplication('scorched')],
      ),
      ActiveTrigger(
        id: 'acid_spray',
        name: 'Acid Spray',
        category: TriggerCategory.trapper,
        equipCost: 24,
        trionCost: 16,
        // Trion Types: SPTV 2.54: acid to each of three, thrown by hand, and
        // Corroded after.
        trionTypeCost:
            const TrionTypeCost({TrionType.physical: 1, TrionType.afflict: 1}),
        cooldownTurns: 3,
        originTag: OriginTag.afflict,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        damageType: DamageType.acid,
        damage: const DiceExpression(2, 6, flatBonus: 6),
        inflictedStatusEffects: const [StatusEffectApplication('corroded')],
      ),
      ActiveTrigger(
        id: 'nightmare_pulse',
        name: 'Nightmare Pulse',
        category: TriggerCategory.trapper,
        equipCost: 35,
        trionCost: 22,
        // Trion Types: SPTV 1.62: 14 to two minds and Terrified, at 22 Trion.
        // Priced in Raw Trion already.
        trionTypeCost: const TrionTypeCost({TrionType.afflict: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.afflict,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 2,
        damageType: DamageType.psychic,
        damage: const DiceExpression(2, 6, flatBonus: 7),
        inflictedStatusEffects: const [StatusEffectApplication('terrified')],
      ),
      ActiveTrigger(
        id: 'soul_siphon',
        name: 'Soul Siphon',
        category: TriggerCategory.attacker,
        equipCost: 19,
        trionCost: 14,
        // Trion Types: SPTV 1.64: drains the target for 22 and feeds the
        // caster 2.
        trionTypeCost: const TrionTypeCost({TrionType.afflict: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.afflict,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.single,
        damageType: DamageType.psychic,
        damage: const DiceExpression(3, 6, flatBonus: 11),
        healAmount: const DiceExpression(1, 4, flatBonus: -1),
        healsCasterInstead: true,
      ),
      ActiveTrigger(
        id: 'mind_shatter',
        name: 'Mind Shatter',
        category: TriggerCategory.trapper,
        equipCost: 24,
        trionCost: 18,
        // Trion Types: SPTV 0.92: ten damage and one turn of Silence, for 18
        // Trion.
        trionTypeCost: const TrionTypeCost({TrionType.mental: 1}),
        cooldownTurns: 3,
        originTag: OriginTag.mental,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.single,
        damageType: DamageType.psychic,
        damage: const DiceExpression(2, 4, flatBonus: 5),
        inflictedStatusEffects: const [StatusEffectApplication('silenced')],
      ),
      ActiveTrigger(
        id: 'guardians_aegis',
        name: "Guardian's Aegis",
        category: TriggerCategory.optional,
        equipCost: 15,
        trionCost: 12,
        // Item #5's interim spot-fix, priced with #3's rule. A guardian who
        // only shields themself is not a guardian: as a self-buff this was
        // worth 0.46 against the 2.0 to 3.0 band. Spread over the squad it
        // prices at 1.38, with no magnitude touched at all.
        //
        // The cooldown stays at 2. Dropping it to 1 put the ability at 2.07,
        // squarely in band, and made the round-robin's Wall-against-Wall
        // mirror run past 150 rounds: a squad-wide 25% ward every single turn
        // out-sustains what two defensive squads can deal. Under band and
        // concluding beats in band and endless, and wave 4 owns the real
        // number.
        // Trion Types: SPTV 1.61: Guarded and Braced across the squad for 12
        // Trion. It stands in front of them and that is all it does.
        trionTypeCost: const TrionTypeCost({TrionType.physical: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.physical,
        // Close, same as War Chant: the guardian has to stand where they can
        // reach the people they are shielding.
        rangeTag: RangeTag.close,
        abilityType: AbilityType.melee,
        // Area, for the same reason as War Chant: it wards a line.
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        targetAffiliation: TargetAffiliation.ally,
        inflictedStatusEffects: const [
          StatusEffectApplication('guarded'),
          StatusEffectApplication('braced'),
        ],
      ),
      ActiveTrigger(
        id: 'cleansing_ward',
        name: 'Cleansing Ward',
        category: TriggerCategory.optional,
        equipCost: 22,
        trionCost: 16,
        // Trion Types: SPTV 1.01: mends and wards one ally. Modest in every
        // way.
        trionTypeCost: const TrionTypeCost({TrionType.energy: 1}),
        cooldownTurns: 3,
        originTag: OriginTag.energy,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.single,
        targetAffiliation: TargetAffiliation.ally,
        inflictedStatusEffects: const [
          StatusEffectApplication('regenerating'),
          StatusEffectApplication('warded'),
        ],
      ),
      ActiveTrigger(
        id: 'predictive_parry',
        name: 'Predictive Parry',
        category: TriggerCategory.attacker,
        equipCost: 16,
        trionCost: 18,
        // Trion Types: SPTV cannot price a counter. Once per battle it reads a
        // melee swing, dodges it, and answers with a free 44-damage counter-
        // hit.
        trionTypeCost:
            const TrionTypeCost({TrionType.physical: 1, TrionType.mental: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.mental,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.single,
        targetAffiliation: TargetAffiliation.self,
        armsReactive: ReactiveKind.dodgeMeleeSingle,
      ),
      ActiveTrigger(
        id: 'numbing_toxin',
        name: 'Numbing Toxin',
        category: TriggerCategory.trapper,
        equipCost: 15,
        trionCost: 18,
        // Trion Types: SPTV cannot price a counter, and this one only matters
        // against a burst: a multi-hit attack on the holder lands its first
        // hit only. Narrow, so it pays one.
        trionTypeCost: const TrionTypeCost({TrionType.afflict: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.afflict,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.single,
        targetAffiliation: TargetAffiliation.self,
        armsReactive: ReactiveKind.burstMitigation,
        armsReactiveDefaultTurns: 2,
      ),
      ActiveTrigger(
        id: 'root_snare',
        name: 'Root Snare',
        category: TriggerCategory.trapper,
        equipCost: 20,
        trionCost: 18,
        // Trion Types: SPTV 0.44 misses the ability: Forced Repetition is
        // unpriced, and it both locks them to their last ability and pins them
        // to their square for two turns. A snare on the body that takes their
        // choices away.
        trionTypeCost:
            const TrionTypeCost({TrionType.physical: 1, TrionType.mental: 1}),
        cooldownTurns: 3,
        originTag: OriginTag.physical,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.single,
        damageType: DamageType.bludgeoning,
        damage: const DiceExpression(2, 4, flatBonus: 5),
        inflictedStatusEffects: const [
          StatusEffectApplication('forced_repetition')
        ],
      ),
      ActiveTrigger(
        id: 'death_ledger',
        name: 'Death Ledger',
        category: TriggerCategory.trapper,
        equipCost: 20,
        trionCost: 18,
        // Trion Types: SPTV 0.44 cannot see the counter: it marks one enemy,
        // once per enemy per battle, and cancels the next area attack they
        // make. A read of what they will do (Mental), warded away when it
        // comes (Energy), delivered by a bullet.
        trionTypeCost: const TrionTypeCost(
            {TrionType.physical: 1, TrionType.energy: 1, TrionType.mental: 1}),
        cooldownTurns: 3,
        originTag: OriginTag.physical,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.single,
        damageType: DamageType.piercing,
        damage: const DiceExpression(2, 4, flatBonus: 5),
        armsReactive: ReactiveKind.nullifyAoe,
        armsReactiveDefaultTurns: 3,
      ),
      ActiveTrigger(
        id: 'scramble',
        name: 'Scramble',
        category: TriggerCategory.trapper,
        equipCost: 24,
        trionCost: 20,
        // Trion Types: SPTV 0.40 misses Misfire, which is unpriced: a chance
        // their attacks go wrong for two turns. It scrambles what they meant
        // to do.
        trionTypeCost:
            const TrionTypeCost({TrionType.energy: 1, TrionType.mental: 1}),
        cooldownTurns: 3,
        originTag: OriginTag.energy,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.single,
        damageType: DamageType.psychic,
        damage: const DiceExpression(2, 4, flatBonus: 5),
        inflictedStatusEffects: const [StatusEffectApplication('misfire')],
      ),
      ActiveTrigger(
        id: 'stored_retribution',
        name: 'Stored Retribution',
        category: TriggerCategory.optional,
        equipCost: 15,
        trionCost: 14,
        // Trion Types: SPTV cannot price a counter. While Guarded it banks the
        // damage taken, then returns it as bonus damage on the next attack:
        // taken with the body, stored, given back.
        trionTypeCost:
            const TrionTypeCost({TrionType.physical: 1, TrionType.energy: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.physical,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.single,
        targetAffiliation: TargetAffiliation.self,
        armsReactive: ReactiveKind.bankDamage,
      ),
      ActiveTrigger(
        id: 'frozen_tempo',
        name: 'Frozen Tempo',
        category: TriggerCategory.optional,
        equipCost: 16,
        trionCost: 16,
        // Trion Types: SPTV cannot price a counter. A ranged attacker who hits
        // the holder has that ability's cooldown doubled: it freezes their
        // timing, which is a decision rather than a body.
        trionTypeCost:
            const TrionTypeCost({TrionType.energy: 1, TrionType.mental: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.energy,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.single,
        targetAffiliation: TargetAffiliation.self,
        armsReactive: ReactiveKind.cooldownSabotage,
        armsReactiveDefaultTurns: 2,
      ),

      // Item #2's counter-play, and the 61st active Trigger. It is deliberately
      // outside the catalog's even 20/20/20 splits by ability type and by band:
      // it is self-targeted and deals nothing, so neither its band nor its
      // ability type ever gates anything, and giving it either would tilt a grid
      // that describes the 60 combat Triggers.
      //
      // Untimed, like Predictive Parry and Stored Retribution: it stands until
      // it fires, so arming it early is a real commitment of an action rather
      // than a chore to re-cast. Costs are first-pass values set alongside its
      // Optional-category peers (Stored Retribution 18/16/2, Frozen Tempo
      // 20/18/2, Predictive Parry 20/20/2) and are unpriced until SPTV (#3).
      ActiveTrigger(
        id: 'refuse_to_bail',
        name: 'Refuse to Bail',
        category: TriggerCategory.optional,
        equipCost: 16,
        trionCost: 18,
        // Trion Types: SPTV cannot price a counter. The holder survives a
        // lethal blow at 1 health, acts once more, and is then gone for good
        // with no Salvage. One more action, bought with the Salvage.
        trionTypeCost: const TrionTypeCost({TrionType.mental: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.mental,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.single,
        targetAffiliation: TargetAffiliation.self,
        armsReactive: ReactiveKind.refuseToBail,
      ),

      // --- Phase D: Unique-subtype Triggers wiring the Phase C behaviors ---
      // Numbers here follow existing tuning conventions and are tunable.

      // Melee unique (5)
      ActiveTrigger(
        id: 'shared_agony',
        name: 'Shared Agony',
        category: TriggerCategory.attacker,
        equipCost: 24,
        trionCost: 14,
        // Trion Types: SPTV 2.69 counts the 47 necrotic and not the 47 the
        // caster takes too. It links two fates so the pain is shared, and the
        // self-damage is why it pays two rather than three.
        trionTypeCost:
            const TrionTypeCost({TrionType.afflict: 1, TrionType.mental: 1}),
        cooldownTurns: 3,
        originTag: OriginTag.afflict,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.sharedAgony,
        damageType: DamageType.necrotic,
        damage: const DiceExpression(6, 6, flatBonus: 26),
      ),
      ActiveTrigger(
        id: 'grave_bargain',
        name: 'Grave Bargain',
        category: TriggerCategory.attacker,
        equipCost: 14,
        trionCost: 8,
        // Trion Types: SPTV cannot price a unique: spend your own health, deal
        // exactly that as unavoidable true damage. The health is the price,
        // and it is paid in blood.
        trionTypeCost: const TrionTypeCost({TrionType.afflict: 1}),
        cooldownTurns: 3,
        originTag: OriginTag.afflict,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.graveBargain,
      ),
      ActiveTrigger(
        id: 'martyrs_end',
        name: "Martyr's End",
        category: TriggerCategory.attacker,
        equipCost: 41,
        trionCost: 12,
        // Trion Types: SPTV cannot price a unique, and this is the game's
        // nuke: below 25% health the caster leaves the battle and every enemy
        // takes massive damage. All the energy they have left, released at
        // once, and the price of the Trion Types is the only thing standing
        // between a dying character and pressing it.
        trionTypeCost: const TrionTypeCost({TrionType.energy: 3}),
        cooldownTurns: 4,
        originTag: OriginTag.energy,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.martyrsEnd,
        targetCount: 3,
      ),
      ActiveTrigger(
        id: 'vow_of_the_duel',
        name: 'Vow of the Duel',
        category: TriggerCategory.attacker,
        equipCost: 24,
        trionCost: 15,
        // Trion Types: SPTV cannot price a unique. A duel sworn for three
        // turns: double damage to them, but the caster can touch nobody else
        // and cannot be healed, and is Stunned if the enemy survives it.
        trionTypeCost:
            const TrionTypeCost({TrionType.physical: 1, TrionType.mental: 1}),
        cooldownTurns: 4,
        originTag: OriginTag.mental,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.vowOfTheDuel,
      ),
      ActiveTrigger(
        id: 'sunder_arms',
        name: 'Sunder Arms',
        category: TriggerCategory.attacker,
        equipCost: 22,
        trionCost: 14,
        // Trion Types: SPTV 2.61 on the 37 slashing alone; the unique
        // permanently destroys one of their Triggers and one of yours, which
        // is symmetric, so the damage is the deal. A blade that corrodes the
        // kit off them.
        trionTypeCost:
            const TrionTypeCost({TrionType.physical: 1, TrionType.afflict: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.afflict,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.sunderArms,
        damageType: DamageType.slashing,
        damage: const DiceExpression(5, 6, flatBonus: 19),
      ),

      // Ranged unique (2)
      ActiveTrigger(
        id: 'curving_shot',
        name: 'Curving Shot',
        category: TriggerCategory.sniper,
        equipCost: 35,
        trionCost: 22,
        // Trion Types: SPTV 1.66 on the 37 alone; the unique ignores the first
        // ward, dodge or counter the target has up, so the shot always lands.
        // That reliability is the second slot.
        trionTypeCost:
            const TrionTypeCost({TrionType.physical: 1, TrionType.mental: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.mental,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.curvingShot,
        damageType: DamageType.piercing,
        damage: const DiceExpression(5, 6, flatBonus: 19),
      ),
      ActiveTrigger(
        id: 'called_shot',
        name: 'Called Shot',
        category: TriggerCategory.sniper,
        equipCost: 30,
        trionCost: 18,
        // Trion Types: SPTV cannot price a unique. It reads the target, names
        // a stat, and zeroes it for two turns.
        trionTypeCost:
            const TrionTypeCost({TrionType.physical: 1, TrionType.mental: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.mental,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.calledShot,
      ),

      // Psychic unique (10)
      ActiveTrigger(
        id: 'minds_eye',
        name: "Mind's Eye",
        category: TriggerCategory.optional,
        equipCost: 22,
        trionCost: 12,
        // Trion Types: SPTV cannot price a unique, and this changes nothing on
        // the board: it reveals what the enemy is carrying.
        trionTypeCost: const TrionTypeCost({TrionType.mental: 1}),
        cooldownTurns: 3,
        originTag: OriginTag.mental,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.mindsEye,
      ),
      ActiveTrigger(
        id: 'forced_choice',
        name: 'Forced Choice',
        category: TriggerCategory.trapper,
        equipCost: 22,
        trionCost: 14,
        // Trion Types: SPTV cannot price a unique. Next turn they may use only
        // their cheapest or their priciest ability, and the caster picks
        // which.
        trionTypeCost: const TrionTypeCost({TrionType.mental: 2}),
        cooldownTurns: 3,
        originTag: OriginTag.mental,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.forcedChoice,
      ),
      ActiveTrigger(
        id: 'memory_theft',
        name: 'Memory Theft',
        category: TriggerCategory.trapper,
        equipCost: 19,
        trionCost: 14,
        // Trion Types: SPTV cannot price a unique. It copies the target's last
        // ability and lets the caster cast it next turn, so it is worth
        // whatever they just used.
        trionTypeCost: const TrionTypeCost({TrionType.mental: 2}),
        cooldownTurns: 2,
        originTag: OriginTag.mental,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.memoryTheft,
      ),
      ActiveTrigger(
        id: 'sensory_swap',
        name: 'Sensory Swap',
        category: TriggerCategory.trapper,
        equipCost: 18,
        trionCost: 12,
        // Trion Types: SPTV cannot price a unique. It moves one active status
        // from one character to another.
        trionTypeCost: const TrionTypeCost({TrionType.mental: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.mental,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.sensorySwap,
        targetCount: 2,
      ),
      ActiveTrigger(
        id: 'dread_resonance',
        name: 'Dread Resonance',
        category: TriggerCategory.attacker,
        equipCost: 35,
        trionCost: 22,
        // Trion Types: SPTV cannot price a unique. Its damage scales with
        // everything that enemy has dealt this battle: dread that feeds on
        // what they have done.
        trionTypeCost:
            const TrionTypeCost({TrionType.afflict: 1, TrionType.mental: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.afflict,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.dreadResonance,
        damageType: DamageType.psychic,
      ),
      ActiveTrigger(
        id: 'isolation',
        name: 'Isolation',
        category: TriggerCategory.trapper,
        equipCost: 26,
        trionCost: 14,
        // Trion Types: SPTV cannot price a unique, and this one only matters
        // against a squad that heals or buffs: for two turns that enemy can
        // neither be helped nor help. Narrow, so it pays one.
        trionTypeCost: const TrionTypeCost({TrionType.mental: 1}),
        cooldownTurns: 3,
        originTag: OriginTag.mental,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.isolation,
      ),
      ActiveTrigger(
        id: 'illusory_double',
        name: 'Illusory Double',
        category: TriggerCategory.optional,
        equipCost: 24,
        trionCost: 0,
        // Trion Types: SPTV is infinite because it costs no Raw Trion at all,
        // so its whole price is here. One character untargetable for the
        // opponent's next turn, and a charge back each time an ally falls.
        trionTypeCost: const TrionTypeCost({TrionType.mental: 3}),
        cooldownTurns: 3,
        originTag: OriginTag.mental,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.illusoryDouble,
        targetAffiliation: TargetAffiliation.ally,
      ),
      ActiveTrigger(
        id: 'echoing_doubt',
        name: 'Echoing Doubt',
        category: TriggerCategory.trapper,
        equipCost: 24,
        trionCost: 16,
        // Trion Types: SPTV cannot price a unique. Their next attack whiffs
        // while they still pay for it, then backlash and Silence. Doubt
        // planted in the mind, and it is deterministic.
        trionTypeCost:
            const TrionTypeCost({TrionType.afflict: 1, TrionType.mental: 1}),
        cooldownTurns: 4,
        originTag: OriginTag.afflict,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.echoingDoubt,
      ),
      ActiveTrigger(
        id: 'karmic_bind',
        name: 'Karmic Bind',
        category: TriggerCategory.trapper,
        equipCost: 21,
        trionCost: 14,
        // Trion Types: SPTV cannot price a unique. A three-turn damage and
        // heal link, scaling with the caster's Team Spirit.
        trionTypeCost: const TrionTypeCost({TrionType.mental: 2}),
        cooldownTurns: 2,
        originTag: OriginTag.mental,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.karmicBind,
      ),
      ActiveTrigger(
        id: 'unmaking',
        name: 'Unmaking',
        category: TriggerCategory.trapper,
        equipCost: 26,
        trionCost: 18,
        // Trion Types: SPTV cannot price a unique. It turns every buff the
        // target holds into its debuff equivalent: against a set-up enemy it
        // undoes a whole turn of their work in one action, and that is worth
        // three.
        trionTypeCost: const TrionTypeCost({TrionType.mental: 3}),
        cooldownTurns: 4,
        originTag: OriginTag.mental,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.unique,
        uniqueBehavior: UniqueBehavior.unmaking,
      ),

      // --- Phase D: 20/20/20 rebalance fillers (aoe + burst) ---

      // Ranged AoE (4)
      ActiveTrigger(
        id: 'frag_grenade',
        name: 'Frag Grenade',
        category: TriggerCategory.shooter,
        equipCost: 35,
        trionCost: 27,
        // Trion Types: SPTV 2.17: fragments carried by a blast, 20 to each of
        // three, at 27 Trion. A fair deal, not a bargain.
        trionTypeCost:
            const TrionTypeCost({TrionType.physical: 1, TrionType.energy: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.physical,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        damageType: DamageType.piercing,
        damage: const DiceExpression(3, 6, flatBonus: 9),
      ),
      ActiveTrigger(
        id: 'caustic_cloud',
        name: 'Caustic Cloud',
        category: TriggerCategory.trapper,
        equipCost: 18,
        trionCost: 18,
        // Trion Types: SPTV 2.45: nine acid to each of three, and Poisoned for
        // three turns at 19 SP, from Long range. Two of its own kind.
        trionTypeCost: const TrionTypeCost({TrionType.afflict: 2}),
        cooldownTurns: 2,
        originTag: OriginTag.afflict,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        damageType: DamageType.acid,
        damage: const DiceExpression(2, 4, flatBonus: 4),
        inflictedStatusEffects: const [StatusEffectApplication('poisoned')],
      ),
      ActiveTrigger(
        id: 'cryo_burst',
        name: 'Cryo Burst',
        category: TriggerCategory.attacker,
        equipCost: 35,
        trionCost: 22,
        // Trion Types: SPTV 2.67: 18 cold to each of three and Chilled. Cold
        // poured over the line.
        trionTypeCost: const TrionTypeCost({TrionType.energy: 2}),
        cooldownTurns: 2,
        originTag: OriginTag.energy,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        damageType: DamageType.cold,
        damage: const DiceExpression(3, 4, flatBonus: 10),
        inflictedStatusEffects: const [StatusEffectApplication('chilled')],
      ),
      ActiveTrigger(
        id: 'thunderclap_round',
        name: 'Thunderclap Round',
        category: TriggerCategory.shooter,
        equipCost: 35,
        trionCost: 22,
        // Trion Types: SPTV 2.29: thunder to three of them, loud enough to
        // leave them Overwhelmed.
        trionTypeCost:
            const TrionTypeCost({TrionType.energy: 1, TrionType.mental: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.energy,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        damageType: DamageType.thunder,
        damage: const DiceExpression(2, 6, flatBonus: 6),
        inflictedStatusEffects: const [StatusEffectApplication('overwhelmed')],
      ),

      // Ranged Burst (6)
      ActiveTrigger(
        id: 'rapid_fire',
        name: 'Rapid Fire',
        category: TriggerCategory.shooter,
        equipCost: 16,
        trionCost: 18,
        // Trion Types: SPTV 3.40: three rounds for 50, and Bleeding at 30 SP
        // is the heaviest wound in the game, so the Afflict is doing as much
        // work as the bullets.
        trionTypeCost:
            const TrionTypeCost({TrionType.physical: 2, TrionType.afflict: 1}),
        cooldownTurns: 3,
        originTag: OriginTag.physical,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.burst,
        hitsPerUse: 3,
        targetCount: 1,
        damageType: DamageType.piercing,
        damage: const DiceExpression(3, 4, flatBonus: 9),
        inflictedStatusEffects: const [StatusEffectApplication('bleeding')],
      ),
      ActiveTrigger(
        id: 'gatling_burst',
        name: 'Gatling Burst',
        category: TriggerCategory.shooter,
        equipCost: 28,
        trionCost: 24,
        // Trion Types: SPTV 1.76: five rounds for 50 and Exposed, but at 24
        // Trion and a 3-turn cooldown it is already paying its way in Raw
        // Trion.
        trionTypeCost: const TrionTypeCost({TrionType.physical: 1}),
        cooldownTurns: 3,
        originTag: OriginTag.physical,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.burst,
        hitsPerUse: 5,
        targetCount: 1,
        damageType: DamageType.piercing,
        damage: const DiceExpression(2, 4, flatBonus: 5),
        inflictedStatusEffects: const [StatusEffectApplication('exposed')],
      ),
      ActiveTrigger(
        id: 'split_shot',
        name: 'Split Shot',
        category: TriggerCategory.shooter,
        equipCost: 18,
        trionCost: 22,
        // Trion Types: SPTV 2.55: one shot, split across two, 56 in all for 22
        // Trion.
        trionTypeCost: const TrionTypeCost({TrionType.physical: 2}),
        cooldownTurns: 2,
        originTag: OriginTag.physical,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.burst,
        hitsPerUse: 2,
        targetCount: 2,
        damageType: DamageType.piercing,
        damage: const DiceExpression(2, 6, flatBonus: 7),
      ),
      ActiveTrigger(
        id: 'arc_volley',
        name: 'Arc Volley',
        category: TriggerCategory.shooter,
        equipCost: 26,
        trionCost: 20,
        // Trion Types: SPTV 2.40: three arcs each across two targets, 60 in
        // all.
        trionTypeCost: const TrionTypeCost({TrionType.energy: 2}),
        cooldownTurns: 3,
        originTag: OriginTag.energy,
        rangeTag: RangeTag.mid,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.burst,
        hitsPerUse: 3,
        targetCount: 2,
        damageType: DamageType.lightning,
        damage: const DiceExpression(2, 4, flatBonus: 5),
      ),
      ActiveTrigger(
        id: 'pepper_shot',
        name: 'Pepper Shot',
        category: TriggerCategory.shooter,
        equipCost: 12,
        trionCost: 14,
        // Trion Types: SPTV 3.21 on a 1-turn cooldown, so it is 30 damage
        // every single turn for 14 Trion. Three quick shots.
        trionTypeCost: const TrionTypeCost({TrionType.physical: 3}),
        cooldownTurns: 1,
        originTag: OriginTag.physical,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.burst,
        hitsPerUse: 3,
        targetCount: 1,
        damageType: DamageType.piercing,
        damage: const DiceExpression(2, 4, flatBonus: 5),
      ),
      ActiveTrigger(
        id: 'venom_spray',
        name: 'Venom Spray',
        category: TriggerCategory.trapper,
        equipCost: 19,
        trionCost: 18,
        // Trion Types: SPTV 3.64: six doses across two targets for 54, and
        // Poisoned after, at 18 Trion.
        trionTypeCost: const TrionTypeCost({TrionType.afflict: 3}),
        cooldownTurns: 2,
        originTag: OriginTag.afflict,
        rangeTag: RangeTag.close,
        abilityType: AbilityType.ranged,
        abilitySubtype: AbilitySubtype.burst,
        hitsPerUse: 3,
        targetCount: 2,
        damageType: DamageType.poison,
        damage: const DiceExpression(2, 4, flatBonus: 4),
        inflictedStatusEffects: const [StatusEffectApplication('poisoned')],
      ),

      // Psychic AoE (4)
      ActiveTrigger(
        id: 'psychic_scream',
        name: 'Psychic Scream',
        category: TriggerCategory.trapper,
        equipCost: 35,
        trionCost: 22,
        // Trion Types: SPTV 2.82: ten psychic to three of them and Silenced,
        // which is the heaviest control in the game at 36 SP across three
        // minds.
        trionTypeCost:
            const TrionTypeCost({TrionType.energy: 1, TrionType.mental: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.energy,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        damageType: DamageType.psychic,
        damage: const DiceExpression(2, 4, flatBonus: 5),
        inflictedStatusEffects: const [StatusEffectApplication('silenced')],
      ),
      ActiveTrigger(
        id: 'mind_fog',
        name: 'Mind Fog',
        category: TriggerCategory.trapper,
        equipCost: 18,
        trionCost: 18,
        // Trion Types: SPTV 2.30: three minds Blinded at once.
        trionTypeCost: const TrionTypeCost({TrionType.mental: 2}),
        cooldownTurns: 2,
        originTag: OriginTag.mental,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        damageType: DamageType.psychic,
        damage: const DiceExpression(2, 4, flatBonus: 5),
        inflictedStatusEffects: const [StatusEffectApplication('blinded')],
      ),
      ActiveTrigger(
        id: 'mass_confusion',
        name: 'Mass Confusion',
        category: TriggerCategory.trapper,
        equipCost: 35,
        trionCost: 27,
        // Trion Types: The same Silence across three minds as Psychic Scream,
        // at 27 Trion instead of 22, so SPTV 2.30 rather than 2.82. Same
        // kinds, and the extra Raw Trion is its price.
        trionTypeCost:
            const TrionTypeCost({TrionType.energy: 1, TrionType.mental: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.energy,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        damageType: DamageType.psychic,
        damage: const DiceExpression(2, 4, flatBonus: 5),
        inflictedStatusEffects: const [StatusEffectApplication('silenced')],
      ),
      ActiveTrigger(
        id: 'dread_wave',
        name: 'Dread Wave',
        category: TriggerCategory.attacker,
        equipCost: 35,
        trionCost: 22,
        // Trion Types: SPTV 2.63: raw force through three minds, and
        // Overwhelmed takes their criticals and their aim.
        trionTypeCost:
            const TrionTypeCost({TrionType.energy: 1, TrionType.mental: 1}),
        cooldownTurns: 2,
        originTag: OriginTag.energy,
        rangeTag: RangeTag.long,
        abilityType: AbilityType.psychic,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        damageType: DamageType.psychic,
        damage: const DiceExpression(3, 4, flatBonus: 8),
        inflictedStatusEffects: const [StatusEffectApplication('overwhelmed')],
      ),

      // The two armor passives keep their Armor, which is flat damage
      // reduction on a separate axis, but their Defense is trimmed to fit
      // the compressed accuracy band: Defense spans 2-12 across the whole
      // roster now, so +2 from a single piece of equipment was worth a
      // fifth of that spread.
      PassiveTrigger(
        id: 'guardians_bulwark',
        name: "Guardian's Bulwark",
        category: TriggerCategory.optional,
        equipCost: 16,
        effect: const PassiveEffect(
          flatStatModifiers: {
            ModifiableStat.armor: 3,
            ModifiableStat.defense: 1
          },
        ),
      ),
      PassiveTrigger(
        id: 'iron_will',
        name: 'Iron Will',
        category: TriggerCategory.optional,
        equipCost: 14,
        effect: const PassiveEffect(
          flatStatModifiers: {ModifiableStat.statusEffectResistance: 5},
        ),
      ),
      PassiveTrigger(
        id: 'keen_eye',
        name: 'Keen Eye',
        category: TriggerCategory.optional,
        equipCost: 16,
        effect: const PassiveEffect(
          flatStatModifiers: {ModifiableStat.criticalChance: 8},
        ),
      ),
      PassiveTrigger(
        id: 'overcharged_core',
        name: 'Overcharged Core',
        category: TriggerCategory.optional,
        equipCost: 16,
        effect: const PassiveEffect(
          flatStatModifiers: {ModifiableStat.fatChance: 8},
        ),
      ),
      PassiveTrigger(
        id: 'vanguards_discipline',
        name: "Vanguard's Discipline",
        category: TriggerCategory.optional,
        equipCost: 22,
        effect: const PassiveEffect(
          flatStatModifiers: {
            ModifiableStat.armor: 5,
            ModifiableStat.defense: 2
          },
        ),
      ),
      PassiveTrigger(
        id: 'silver_tongue',
        name: 'Silver Tongue',
        category: TriggerCategory.optional,
        equipCost: 16,
        effect: const PassiveEffect(
          flatStatModifiers: {ModifiableStat.statusEffectInfliction: 6},
        ),
      ),
      PassiveTrigger(
        id: 'draegor',
        name: 'Draegor',
        category: TriggerCategory.optional,
        equipCost: 24,
        effect: const PassiveEffect(),
        counterKind: PassiveCounterKind.draegor,
      ),
      PassiveTrigger(
        id: 'nullhymn',
        name: 'Nullhymn',
        category: TriggerCategory.optional,
        equipCost: 26,
        effect: const PassiveEffect(),
        counterKind: PassiveCounterKind.nullhymn,
      ),
      PassiveTrigger(
        id: 'reckoning',
        name: 'Reckoning',
        category: TriggerCategory.optional,
        equipCost: 28,
        effect: const PassiveEffect(),
        counterKind: PassiveCounterKind.reckoning,
      ),
      PassiveTrigger(
        id: 'gravehour',
        name: 'Gravehour',
        category: TriggerCategory.optional,
        equipCost: 26,
        effect: const PassiveEffect(),
        counterKind: PassiveCounterKind.gravehour,
      ),
      PassiveTrigger(
        id: 'coldread',
        name: 'Coldread',
        category: TriggerCategory.optional,
        equipCost: 22,
        effect: const PassiveEffect(),
        counterKind: PassiveCounterKind.coldread,
      ),
      PassiveTrigger(
        id: 'ironvow',
        name: 'Ironvow',
        category: TriggerCategory.optional,
        equipCost: 24,
        effect: const PassiveEffect(),
        counterKind: PassiveCounterKind.ironvow,
      ),
    ];

    return TriggerCatalog._({for (final t in triggers) t.id: t});
  }

  static final TriggerCatalog defaultCatalog = TriggerCatalog.builtIn();
}

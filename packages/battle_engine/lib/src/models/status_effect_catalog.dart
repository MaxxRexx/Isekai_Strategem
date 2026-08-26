import '../constants.dart';
import '../util/dice.dart';
import 'damage_type.dart';
import 'status_effect.dart';
import 'status_reaction.dart';

/// The full set of built-in status effect definitions, expressed purely
/// as data against [StatusEffectDefinition]. The engine never
/// switches on effect id/name; it only reads these generic fields, so
/// adding a new status effect means adding an entry here, not touching
/// engine code.
/// Item 5b's stack ceiling. Twelve effects pile up, and none of them past
/// three: a fourth stack of anything is a magnitude nobody designed for, and
/// three is where the badge still reads at a glance.
const int _stackCap = 3;

class StatusEffectCatalog {
  final Map<String, StatusEffectDefinition> _byId;

  StatusEffectCatalog._(this._byId);

  StatusEffectDefinition operator [](String id) {
    final def = _byId[id];
    if (def == null) throw ArgumentError('Unknown status effect id: $id');
    return def;
  }

  bool contains(String id) => _byId.containsKey(id);

  Iterable<StatusEffectDefinition> get all => _byId.values;

  factory StatusEffectCatalog.builtIn([
    StatusEffectMagnitudes magnitudes = StatusEffectMagnitudes.defaults,
  ]) {
    final defs = <StatusEffectDefinition>[
      StatusEffectDefinition(
        id: 'acid',
        name: 'Acid',
        maxStacks: _stackCap,
        defaultDurationTurns: magnitudes.acidDurationTurns,
        flatStatModifiers: {
          ModifiableStat.armor: -magnitudes.acidArmorReduction.toDouble()
        },
      ),
      StatusEffectDefinition(
        id: 'wet',
        name: 'Wet',
        defaultDurationTurns: magnitudes.wetDurationTurns,
        // Item 3b. Water is the setup half of the whole table: it freezes,
        // it conducts, and it boils off.
        reactions: const [
          StatusReaction(
            onDamageType: DamageType.cold,
            becomes: 'frozen',
            consumesTrigger: true,
          ),
          StatusReaction(
            onDamageType: DamageType.lightning,
            becomes: 'electrocuted',
            consumesTrigger: true,
          ),
          // Wet is already Fire-immune, so the hit deals nothing on its own.
          // What the reaction adds is that the water is gone afterwards.
          StatusReaction(
            onDamageType: DamageType.fire,
            consumesTrigger: true,
          ),
        ],
        damageTypeInteractions: const [
          DamageTypeInteractionRule.immune(DamageType.fire),
          DamageTypeInteractionRule.vulnerable(DamageType.lightning),
          DamageTypeInteractionRule.vulnerable(DamageType.cold),
        ],
      ),
      StatusEffectDefinition(
        id: 'stunned',
        name: 'Stunned',
        defaultDurationTurns: magnitudes.stunnedDurationTurns,
        preventsActions: true,
        zeroedStats: const {ModifiableStat.teamSpirit},
      ),
      StatusEffectDefinition(
        id: 'threatened',
        name: 'Threatened',
        defaultDurationTurns: magnitudes.threatenedDurationTurns,
        disadvantageRollTags: const {StatusRollTag.rangedAttackRoll},
      ),
      StatusEffectDefinition(
        id: 'sickened',
        name: 'Sickened',
        defaultDurationTurns: magnitudes.sickenedDurationTurns,
        vulnerableToRandomDamageTypesCount:
            magnitudes.sickenedVulnerableDamageTypeCount,
      ),
      StatusEffectDefinition(
        id: 'sapped',
        name: 'Sapped',
        maxStacks: _stackCap,
        defaultDurationTurns: magnitudes.sappedDurationTurns,
        trionCapacityDrainPercentToCauser:
            magnitudes.sappedDrainPercentOfTrionCapacity,
      ),
      StatusEffectDefinition(
        id: 'reeling',
        name: 'Reeling',
        defaultDurationTurns: magnitudes.reelingDurationTurns,
        perRemainingTurnStatModifiers: const {ModifiableStat.attack: -1},
      ),
      StatusEffectDefinition(
        id: 'prone',
        name: 'Prone',
        defaultDurationTurns: magnitudes.proneDurationTurns,
        locksRandomAbilityEachTurn: true,
      ),
      StatusEffectDefinition(
        id: 'prepared',
        name: 'Prepared',
        defaultDurationTurns: magnitudes.preparedDurationTurns,
        perRemainingTurnStatModifiers: const {ModifiableStat.attack: 1},
      ),
      StatusEffectDefinition(
        id: 'poisoned',
        name: 'Poisoned',
        defaultDurationTurns: magnitudes.poisonedDurationTurns,
        reactions: const [
          StatusReaction(
            onDamageType: DamageType.poison,
            becomes: 'sickened',
            consumesTrigger: true,
          ),
        ],
        disadvantageRollTags: const {StatusRollTag.attackRoll},
      ),
      StatusEffectDefinition(
        id: 'frozen',
        name: 'Frozen',
        defaultDurationTurns: magnitudes.frozenDurationTurns,
        // Shatter: a frozen target hit by something heavy takes double, and
        // the ice is gone.
        reactions: const [
          StatusReaction(
            onDamageType: DamageType.bludgeoning,
            consumesTrigger: true,
            damageMultiplier: 2.0,
          ),
          StatusReaction(
            onDamageType: DamageType.thunder,
            consumesTrigger: true,
            damageMultiplier: 2.0,
          ),
        ],
        preventsActions: true,
        zeroedStats: const {ModifiableStat.trionAffinity},
      ),
      StatusEffectDefinition(
        id: 'bleeding',
        name: 'Bleeding',
        maxStacks: _stackCap,
        defaultDurationTurns: magnitudes.bleedingDurationTurns,
        reactions: const [
          StatusReaction(onDamageType: DamageType.slashing, becomes: 'bleeding'),
        ],
        turnStartDamage:
            DiceExpression(0, 1, flatBonus: magnitudes.bleedingDamagePerTurn),
        turnStartDamageType: DamageType.slashing,
        // Disadvantage on the bleeding character's own status-resistance
        // roll. Under the two-roll opposed infliction formula (see
        // StatusEffectEngine.resolveInfliction), weakening their own roll
        // makes it easier for a causer's roll to beat/tie it, i.e. this
        // correctly raises the apply rate against them - a debuff.
        disadvantageRollTags: const {StatusRollTag.statusResistanceRoll},
      ),
      StatusEffectDefinition(
        id: 'blinded',
        name: 'Blinded',
        defaultDurationTurns: magnitudes.blindedDurationTurns,
        rangedTargetsReducedByOne: true,
        disadvantageRollTags: const {StatusRollTag.rangedAttackRoll},
      ),
      StatusEffectDefinition(
        id: 'braced',
        name: 'Braced',
        defaultDurationTurns: magnitudes.bracedDurationTurns,
        perRemainingTurnStatModifiers: const {ModifiableStat.defense: 1},
      ),
      StatusEffectDefinition(
        id: 'charmed',
        name: 'Charmed',
        defaultDurationTurns: magnitudes.charmedDurationTurns,
        cannotTargetSource: true,
        sourceHasAdvantageAgainstTarget: true,
      ),
      StatusEffectDefinition(
        id: 'electrocuted',
        name: 'Electrocuted',
        maxStacks: _stackCap,
        defaultDurationTurns: magnitudes.electrocutedDurationTurns,
        // Arcs to one other character standing on the same line as the
        // holder, on the holder's own side.
        reactions: const [
          StatusReaction(
            onDamageType: DamageType.thunder,
            becomes: 'electrocuted',
            arcsToSameLine: true,
          ),
        ],
        turnStartDamage: const DiceExpression(1, 4),
        turnStartDamageType: DamageType.lightning,
      ),
      StatusEffectDefinition(
        id: 'regenerating',
        name: 'Regenerating',
        maxStacks: _stackCap,
        defaultDurationTurns: magnitudes.regeneratingDurationTurns,
        turnStartHeal:
            DiceExpression(0, 1, flatBonus: magnitudes.regeneratingHealPerTurn),
      ),

      // --- 32 additions (D&D / Naruto-Arena / World Trigger inspired) ---
      StatusEffectDefinition(
        id: 'empowered',
        name: 'Empowered',
        defaultDurationTurns: magnitudes.empoweredDurationTurns,
        outgoingDamageMultiplier: magnitudes.empoweredOutgoingDamageMultiplier,
      ),
      StatusEffectDefinition(
        id: 'weakened',
        name: 'Weakened',
        defaultDurationTurns: magnitudes.weakenedDurationTurns,
        outgoingDamageMultiplier: magnitudes.weakenedOutgoingDamageMultiplier,
      ),
      StatusEffectDefinition(
        id: 'focused',
        name: 'Focused',
        defaultDurationTurns: magnitudes.focusedDurationTurns,
        advantageRollTags: const {StatusRollTag.attackRoll},
      ),
      StatusEffectDefinition(
        id: 'guarded',
        name: 'Guarded',
        defaultDurationTurns: magnitudes.guardedDurationTurns,
        allDamageTakenMultiplier: magnitudes.guardedAllDamageTakenMultiplier,
      ),
      StatusEffectDefinition(
        id: 'exposed',
        name: 'Exposed',
        defaultDurationTurns: magnitudes.exposedDurationTurns,
        allDamageTakenMultiplier: magnitudes.exposedAllDamageTakenMultiplier,
      ),
      StatusEffectDefinition(
        id: 'marked',
        name: 'Marked',
        defaultDurationTurns: magnitudes.markedDurationTurns,
        allDamageTakenMultiplier: magnitudes.markedAllDamageTakenMultiplier,
        sourceHasAdvantageAgainstTarget: true,
      ),
      StatusEffectDefinition(
        id: 'cursed',
        name: 'Cursed',
        defaultDurationTurns: magnitudes.cursedDurationTurns,
        preventsHealing: true,
      ),
      StatusEffectDefinition(
        id: 'silenced',
        name: 'Silenced',
        defaultDurationTurns: magnitudes.silencedDurationTurns,
        preventsActions: true,
      ),
      StatusEffectDefinition(
        id: 'enraged',
        name: 'Enraged',
        defaultDurationTurns: magnitudes.enragedDurationTurns,
        outgoingDamageMultiplier: magnitudes.enragedOutgoingDamageMultiplier,
        flatStatModifiers: {
          ModifiableStat.defense: -magnitudes.enragedDefensePenalty.toDouble()
        },
        // Item 3b's redesign. It was a stat swap that nothing applied. The
        // two clauses below make it a decision either way round: enraging
        // your own character buys damage and the game's only answer to a
        // psychic squad, at the cost of aiming; enraging an enemy blunts
        // their aim at the cost of making them hit harder.
        damageTypeInteractions: const [
          DamageTypeInteractionRule.immune(DamageType.psychic),
        ],
        randomizesOwnTargeting: true,
      ),
      StatusEffectDefinition(
        id: 'fatigued',
        name: 'Fatigued',
        maxStacks: _stackCap,
        defaultDurationTurns: magnitudes.fatiguedDurationTurns,
        flatStatModifiers: {
          ModifiableStat.attack: -magnitudes.fatiguedAttackPenalty.toDouble(),
          ModifiableStat.defense: -magnitudes.fatiguedDefensePenalty.toDouble(),
        },
      ),
      StatusEffectDefinition(
        id: 'inspired',
        name: 'Inspired',
        maxStacks: _stackCap,
        defaultDurationTurns: magnitudes.inspiredDurationTurns,
        flatStatModifiers: {
          ModifiableStat.attack: magnitudes.inspiredAttackBonus.toDouble(),
          ModifiableStat.defense: magnitudes.inspiredDefenseBonus.toDouble(),
        },
      ),
      StatusEffectDefinition(
        id: 'shattered_guard',
        name: 'Shattered Guard',
        defaultDurationTurns: magnitudes.shatteredGuardDurationTurns,
        zeroedStats: const {ModifiableStat.armor},
      ),
      StatusEffectDefinition(
        id: 'overcharged',
        name: 'Overcharged',
        defaultDurationTurns: magnitudes.overchargedDurationTurns,
        trionCostMultiplier: magnitudes.overchargedTrionCostMultiplier,
      ),
      StatusEffectDefinition(
        id: 'choked',
        name: 'Choked',
        defaultDurationTurns: magnitudes.chokedDurationTurns,
        trionCostMultiplier: magnitudes.chokedTrionCostMultiplier,
      ),
      StatusEffectDefinition(
        id: 'petrified',
        name: 'Petrified',
        defaultDurationTurns: magnitudes.petrifiedDurationTurns,
        preventsActions: true,
        allDamageTakenMultiplier: magnitudes.petrifiedAllDamageTakenMultiplier,
        zeroedStats: const {ModifiableStat.teamSpirit},
      ),
      StatusEffectDefinition(
        id: 'terrified',
        name: 'Terrified',
        defaultDurationTurns: magnitudes.terrifiedDurationTurns,
        disadvantageRollTags: const {
          StatusRollTag.attackRoll,
          StatusRollTag.rangedAttackRoll,
        },
        cannotTargetSource: true,
      ),
      StatusEffectDefinition(
        id: 'slowed',
        name: 'Slowed',
        defaultDurationTurns: magnitudes.slowedDurationTurns,
        perRemainingTurnStatModifiers: {
          ModifiableStat.defense:
              -magnitudes.slowedDefensePenaltyPerTurn.toDouble()
        },
        disadvantageRollTags: const {StatusRollTag.attackRoll},
      ),
      StatusEffectDefinition(
        id: 'hastened',
        name: 'Hastened',
        defaultDurationTurns: magnitudes.hastenedDurationTurns,
        advantageRollTags: const {StatusRollTag.attackRoll},
        perRemainingTurnStatModifiers: {
          ModifiableStat.attack:
              magnitudes.hastenedAttackBonusPerTurn.toDouble()
        },
      ),
      StatusEffectDefinition(
        id: 'scorched',
        name: 'Scorched',
        defaultDurationTurns: magnitudes.scorchedDurationTurns,
        reactions: const [
          // Quenched: the burn goes out and leaves the target Chilled.
          StatusReaction(
            onDamageType: DamageType.cold,
            becomes: 'chilled',
            consumesTrigger: true,
          ),
          // A Scorched target is already Fire-vulnerable, so this is the
          // burn build's payoff rather than a transformation.
          StatusReaction(
            onDamageType: DamageType.fire,
            becomes: 'scorched',
          ),
        ],
        damageTypeInteractions: const [
          DamageTypeInteractionRule.vulnerable(DamageType.fire),
        ],
        turnStartDamage:
            DiceExpression(0, 1, flatBonus: magnitudes.scorchedDamagePerTurn),
        turnStartDamageType: DamageType.fire,
      ),
      StatusEffectDefinition(
        id: 'chilled',
        name: 'Chilled',
        defaultDurationTurns: magnitudes.chilledDurationTurns,
        reactions: const [
          StatusReaction(
            onDamageType: DamageType.cold,
            becomes: 'frozen',
            consumesTrigger: true,
          ),
          // The ice melts back to water, which sets up the next Cold or
          // Lightning hit. A Cold squad can cycle a target on its own, but
          // it costs them a turn each time.
          StatusReaction(
            onDamageType: DamageType.fire,
            becomes: 'wet',
            consumesTrigger: true,
          ),
        ],
        damageTypeInteractions: const [
          DamageTypeInteractionRule.vulnerable(DamageType.cold),
        ],
        perRemainingTurnStatModifiers: {
          ModifiableStat.attack:
              -magnitudes.chilledAttackPenaltyPerTurn.toDouble()
        },
      ),
      StatusEffectDefinition(
        id: 'corroded',
        name: 'Corroded',
        defaultDurationTurns: magnitudes.corrodedDurationTurns,
        // Another coat of acid on top, deepening the armour shred.
        reactions: const [
          StatusReaction(onDamageType: DamageType.acid, becomes: 'acid'),
        ],
        flatStatModifiers: {
          ModifiableStat.armor: -magnitudes.corrodedArmorReduction.toDouble()
        },
        damageTypeInteractions: const [
          DamageTypeInteractionRule.vulnerable(DamageType.acid),
        ],
      ),
      StatusEffectDefinition(
        id: 'shadow_bound',
        name: 'Shadow-Bound',
        defaultDurationTurns: magnitudes.shadowBoundDurationTurns,
        locksRandomAbilityEachTurn: true,
        disadvantageRollTags: const {StatusRollTag.attackRoll},
      ),
      StatusEffectDefinition(
        id: 'genjutsu_trapped',
        name: 'Genjutsu Trapped',
        defaultDurationTurns: magnitudes.genjutsuTrappedDurationTurns,
        preventsActions: true,
        trionCapacityDrainPercentToCauser:
            magnitudes.genjutsuTrappedDrainPercentOfTrionCapacity,
      ),
      StatusEffectDefinition(
        id: 'sealed',
        name: 'Sealed',
        defaultDurationTurns: magnitudes.sealedDurationTurns,
        zeroedStats: const {
          ModifiableStat.trionAffinity,
          ModifiableStat.fatChance,
        },
      ),
      StatusEffectDefinition(
        id: 'overwhelmed',
        name: 'Overwhelmed',
        defaultDurationTurns: magnitudes.overwhelmedDurationTurns,
        zeroedStats: const {ModifiableStat.criticalChance},
        disadvantageRollTags: const {StatusRollTag.attackRoll},
      ),
      StatusEffectDefinition(
        id: 'adrenaline_rush',
        name: 'Adrenaline Rush',
        maxStacks: _stackCap,
        defaultDurationTurns: magnitudes.adrenalineRushDurationTurns,
        flatStatModifiers: {
          ModifiableStat.criticalChance:
              magnitudes.adrenalineRushCriticalChanceBonus.toDouble()
        },
      ),
      StatusEffectDefinition(
        id: 'battle_trance',
        name: 'Battle Trance',
        maxStacks: _stackCap,
        defaultDurationTurns: magnitudes.battleTranceDurationTurns,
        flatStatModifiers: {
          ModifiableStat.fatChance:
              magnitudes.battleTranceFatChanceBonus.toDouble()
        },
      ),
      StatusEffectDefinition(
        id: 'suppressed',
        name: 'Suppressed',
        maxStacks: _stackCap,
        defaultDurationTurns: magnitudes.suppressedDurationTurns,
        flatStatModifiers: {
          ModifiableStat.statusEffectInfliction:
              -magnitudes.suppressedInflictionPenalty.toDouble()
        },
      ),
      StatusEffectDefinition(
        id: 'warded',
        name: 'Warded',
        maxStacks: _stackCap,
        defaultDurationTurns: magnitudes.wardedDurationTurns,
        flatStatModifiers: {
          ModifiableStat.statusEffectResistance:
              magnitudes.wardedResistanceBonus.toDouble()
        },
      ),
      StatusEffectDefinition(
        id: 'hexed',
        name: 'Hexed',
        maxStacks: _stackCap,
        defaultDurationTurns: magnitudes.hexedDurationTurns,
        flatStatModifiers: {
          ModifiableStat.statusEffectResistance:
              -magnitudes.hexedResistancePenalty.toDouble()
        },
      ),
      StatusEffectDefinition(
        id: 'radiant_blessing',
        name: 'Radiant Blessing',
        defaultDurationTurns: magnitudes.radiantBlessingDurationTurns,
        // Heals a little each turn and clamps to the character's maximum, so
        // it can never take anyone above it: at 99 of 100 it restores 1.
        // It used to raise maximum health as well, which let healing carry a
        // character past their own ceiling.
        turnStartHeal: DiceExpression(0, 1,
            flatBonus: magnitudes.radiantBlessingHealPerTurn),
        allDamageTakenMultiplier:
            magnitudes.radiantBlessingAllDamageTakenMultiplier,
      ),
      StatusEffectDefinition(
        id: 'necrotic_wound',
        name: 'Necrotic Wound',
        defaultDurationTurns: magnitudes.necroticWoundDurationTurns,
        turnStartDamage: DiceExpression(0, 1,
            flatBonus: magnitudes.necroticWoundDamagePerTurn),
        turnStartDamageType: DamageType.necrotic,
        preventsHealing: true,
      ),
      StatusEffectDefinition(
        id: 'origin_lockout',
        name: 'Origin Lockout',
        defaultDurationTurns: magnitudes.originLockoutDurationTurns,
        locksOriginFromData: true,
      ),
      StatusEffectDefinition(
        id: 'forced_repetition',
        name: 'Forced Repetition',
        defaultDurationTurns: magnitudes.forcedRepetitionDurationTurns,
        forcesRepetitionOfLastAbility: true,
        // Zone lock: Root Snare pins you as well as locking your ability,
        // so a Trapper decides where the fight happens.
        preventsReposition: true,
      ),
      StatusEffectDefinition(
        id: 'misfire',
        name: 'Misfire',
        defaultDurationTurns: magnitudes.misfireDurationTurns,
        misfireChance: magnitudes.misfireChance,
      ),
      // --- B4 passive-counter status effects ---
      StatusEffectDefinition(
        id: 'interdict',
        name: 'Interdict',
        defaultDurationTurns: magnitudes.interdictDurationTurns,
        repeatAbilityDamageMultiplier:
            magnitudes.interdictRepeatDamageMultiplier,
      ),
      StatusEffectDefinition(
        id: 'forced_critical_miss',
        name: 'Forced Critical Miss',
        defaultDurationTurns: 1,
      ),

      // --- C1 unique-subtype status effects ---
      StatusEffectDefinition(
        id: 'isolation',
        name: 'Isolation',
        defaultDurationTurns: magnitudes.isolationDurationTurns,
        preventsAllyInteraction: true,
      ),
      StatusEffectDefinition(
        id: 'untargetable',
        name: 'Untargetable',
        defaultDurationTurns: magnitudes.untargetableDurationTurns,
        preventsTargeting: true,
      ),
      StatusEffectDefinition(
        id: 'echoing_doubt',
        name: 'Echoing Doubt',
        defaultDurationTurns: magnitudes.echoingDoubtDurationTurns,
        forcesNextAttackMiss: true,
      ),
      StatusEffectDefinition(
        id: 'vow_of_the_duel',
        name: 'Vow of the Duel',
        defaultDurationTurns: magnitudes.vowOfTheDuelDurationTurns,
        outgoingDamageMultiplier: magnitudes.vowOfTheDuelDamageMultiplier,
        preventsHealing: true,
      ),
      StatusEffectDefinition(
        id: 'forced_choice',
        name: 'Forced Choice',
        defaultDurationTurns: magnitudes.forcedChoiceDurationTurns,
      ),
      StatusEffectDefinition(
        id: 'karmic_bind',
        name: 'Karmic Bind',
        defaultDurationTurns: magnitudes.karmicBindDurationTurns,
      ),
      StatusEffectDefinition(
        id: 'called_shot_stat_zero',
        name: 'Called Shot',
        defaultDurationTurns: magnitudes.calledShotDurationTurns,
      ),
      StatusEffectDefinition(
        id: 'minds_eye_reveal',
        name: "Mind's Eye",
        defaultDurationTurns: magnitudes.mindsEyeDurationTurns,
      ),
    ];
    return StatusEffectCatalog._({for (final d in defs) d.id: d});
  }

  static final StatusEffectCatalog defaultCatalog =
      StatusEffectCatalog.builtIn();
}

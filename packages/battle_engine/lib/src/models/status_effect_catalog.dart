import '../constants.dart';
import '../util/dice.dart';
import 'damage_type.dart';
import 'status_effect.dart';

/// The full set of built-in status effect definitions, expressed purely
/// as data against [StatusEffectDefinition]. The engine never
/// switches on effect id/name; it only reads these generic fields, so
/// adding a new status effect means adding an entry here, not touching
/// engine code.
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
        defaultDurationTurns: magnitudes.acidDurationTurns,
        flatStatModifiers: {
          ModifiableStat.armor: -magnitudes.acidArmorReduction.toDouble()
        },
      ),
      StatusEffectDefinition(
        id: 'wet',
        name: 'Wet',
        defaultDurationTurns: magnitudes.wetDurationTurns,
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
        id: 'rallied',
        name: 'Rallied',
        defaultDurationTurns: magnitudes.ralliedDurationTurns,
        flatStatModifiers: {
          ModifiableStat.maxHealth: magnitudes.ralliedMaxHealthBonus.toDouble()
        },
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
        disadvantageRollTags: const {StatusRollTag.attackRoll},
      ),
      StatusEffectDefinition(
        id: 'frozen',
        name: 'Frozen',
        defaultDurationTurns: magnitudes.frozenDurationTurns,
        preventsActions: true,
        zeroedStats: const {ModifiableStat.trionAffinity},
      ),
      StatusEffectDefinition(
        id: 'bleeding',
        name: 'Bleeding',
        defaultDurationTurns: magnitudes.bleedingDurationTurns,
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
        defaultDurationTurns: magnitudes.electrocutedDurationTurns,
        turnStartDamage: const DiceExpression(1, 4),
        turnStartDamageType: DamageType.lightning,
      ),
      StatusEffectDefinition(
        id: 'regenerating',
        name: 'Regenerating',
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
      ),
      StatusEffectDefinition(
        id: 'fatigued',
        name: 'Fatigued',
        defaultDurationTurns: magnitudes.fatiguedDurationTurns,
        flatStatModifiers: {
          ModifiableStat.attack: -magnitudes.fatiguedAttackPenalty.toDouble(),
          ModifiableStat.defense: -magnitudes.fatiguedDefensePenalty.toDouble(),
        },
      ),
      StatusEffectDefinition(
        id: 'inspired',
        name: 'Inspired',
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
        defaultDurationTurns: magnitudes.adrenalineRushDurationTurns,
        flatStatModifiers: {
          ModifiableStat.criticalChance:
              magnitudes.adrenalineRushCriticalChanceBonus.toDouble()
        },
      ),
      StatusEffectDefinition(
        id: 'battle_trance',
        name: 'Battle Trance',
        defaultDurationTurns: magnitudes.battleTranceDurationTurns,
        flatStatModifiers: {
          ModifiableStat.fatChance:
              magnitudes.battleTranceFatChanceBonus.toDouble()
        },
      ),
      StatusEffectDefinition(
        id: 'suppressed',
        name: 'Suppressed',
        defaultDurationTurns: magnitudes.suppressedDurationTurns,
        flatStatModifiers: {
          ModifiableStat.statusEffectInfliction:
              -magnitudes.suppressedInflictionPenalty.toDouble()
        },
      ),
      StatusEffectDefinition(
        id: 'warded',
        name: 'Warded',
        defaultDurationTurns: magnitudes.wardedDurationTurns,
        flatStatModifiers: {
          ModifiableStat.statusEffectResistance:
              magnitudes.wardedResistanceBonus.toDouble()
        },
      ),
      StatusEffectDefinition(
        id: 'hexed',
        name: 'Hexed',
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
        turnStartHeal: DiceExpression(0, 1,
            flatBonus: magnitudes.radiantBlessingHealPerTurn),
        flatStatModifiers: {
          ModifiableStat.maxHealth:
              magnitudes.radiantBlessingMaxHealthBonus.toDouble()
        },
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

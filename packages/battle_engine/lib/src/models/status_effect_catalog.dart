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
    ];
    return StatusEffectCatalog._({for (final d in defs) d.id: d});
  }

  static final StatusEffectCatalog defaultCatalog =
      StatusEffectCatalog.builtIn();
}

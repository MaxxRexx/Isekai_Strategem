/// All numeric stats attached to a [Character].
///
/// Percentage-like stats (`criticalChance`, `fatChance`,
/// `statusEffectInfliction`/`statusEffectResistance` roll modifiers) are
/// stored as plain numbers whose scale is defined by the engine that
/// consumes them (documented at each call site) so this class stays a
/// simple, engine-agnostic data holder.
class Stats {
  /// Trion budget available to spend on equipping Triggers during the
  /// Loadout phase. Distinct from the team's in-battle [TrionPool].
  final int trionCapacity;

  /// Raises the team's chance of higher Trion tiers each turn; also
  /// halved for a turn as a Full Arms Trigger penalty.
  final int trionAffinity;

  /// Dual-direction stat, see [TeamSpiritCurve].
  final int teamSpirit;

  /// Base critical hit chance, as a percentage in [0, 100], before the
  /// Team Spirit curve bonus is applied.
  final double criticalChance;

  /// Base Full Arms Trigger chance, as a percentage in [0, 100], before
  /// the Team Spirit curve bonus is applied.
  final double fatChance;

  /// Flat post-hit damage reduction, applied before Damage Resistance.
  final int armor;

  final int maxHealth;

  /// Added to the attacker's d20 roll during combat resolution.
  final int attack;

  /// Added to the defender's d20 roll during combat resolution.
  final int defense;

  /// Compared against the target's [statusEffectResistance]-modified roll
  /// to determine whether a status effect is successfully inflicted.
  final int statusEffectInfliction;

  /// Subtracted from the defender's status-resistance roll (see
  /// [StatusEffectEngine]).
  final int statusEffectResistance;

  const Stats({
    required this.trionCapacity,
    required this.trionAffinity,
    required this.teamSpirit,
    required this.criticalChance,
    required this.fatChance,
    required this.armor,
    required this.maxHealth,
    required this.attack,
    required this.defense,
    required this.statusEffectInfliction,
    required this.statusEffectResistance,
  });

  Stats copyWith({
    int? trionCapacity,
    int? trionAffinity,
    int? teamSpirit,
    double? criticalChance,
    double? fatChance,
    int? armor,
    int? maxHealth,
    int? attack,
    int? defense,
    int? statusEffectInfliction,
    int? statusEffectResistance,
  }) {
    return Stats(
      trionCapacity: trionCapacity ?? this.trionCapacity,
      trionAffinity: trionAffinity ?? this.trionAffinity,
      teamSpirit: teamSpirit ?? this.teamSpirit,
      criticalChance: criticalChance ?? this.criticalChance,
      fatChance: fatChance ?? this.fatChance,
      armor: armor ?? this.armor,
      maxHealth: maxHealth ?? this.maxHealth,
      attack: attack ?? this.attack,
      defense: defense ?? this.defense,
      statusEffectInfliction:
          statusEffectInfliction ?? this.statusEffectInfliction,
      statusEffectResistance:
          statusEffectResistance ?? this.statusEffectResistance,
    );
  }
}

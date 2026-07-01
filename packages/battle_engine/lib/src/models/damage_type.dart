/// Broad damage category. Kept separate from [DamageType] because some
/// systems (resistance, status interactions) care about the specific type
/// while others may eventually care about the category.
enum DamageCategory { physical, elemental, magicalUtility }

/// Specific damage type/subtype. Every value belongs to exactly one
/// [DamageCategory] via [DamageTypeCategory.category].
enum DamageType {
  // Physical
  bludgeoning,
  piercing,
  slashing,
  // Elemental
  acid,
  cold,
  fire,
  lightning,
  poison,
  // Magical/Utility
  force,
  radiant,
  necrotic,
  psychic,
  thunder,
}

extension DamageTypeCategory on DamageType {
  DamageCategory get category {
    switch (this) {
      case DamageType.bludgeoning:
      case DamageType.piercing:
      case DamageType.slashing:
        return DamageCategory.physical;
      case DamageType.acid:
      case DamageType.cold:
      case DamageType.fire:
      case DamageType.lightning:
      case DamageType.poison:
        return DamageCategory.elemental;
      case DamageType.force:
      case DamageType.radiant:
      case DamageType.necrotic:
      case DamageType.psychic:
      case DamageType.thunder:
        return DamageCategory.magicalUtility;
    }
  }
}

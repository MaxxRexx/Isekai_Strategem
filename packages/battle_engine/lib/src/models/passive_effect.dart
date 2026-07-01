import 'damage_type.dart';
import 'status_effect.dart';

/// An always-on effect granted while a passive Trigger (or a Black
/// Trigger's passive ability) is equipped - no cooldown, no Trion cost,
/// no targeting, nothing to activate. Per the design brief, passives are
/// about status resistances, invulnerabilities, infliction chance, and
/// other stat bonuses; damage-type resistance is included too since it's
/// the same "while equipped" shape (e.g. a shield that grants Fire
/// resistance).
class PassiveEffect {
  /// Flat stat bonuses, reusing the same [ModifiableStat] vocabulary and
  /// folding mechanism status effects already use.
  final Map<ModifiableStat, double> flatStatModifiers;

  /// Status effect ids the wielder is immune to while this is equipped,
  /// in addition to the character's permanent
  /// `Character.statusInvulnerabilities`.
  final Set<String> statusInvulnerabilitiesGranted;

  /// Damage types the wielder resists (halved damage) while equipped, in
  /// addition to `Character.damageResistances`.
  final Set<DamageType> damageResistancesGranted;

  const PassiveEffect({
    this.flatStatModifiers = const {},
    this.statusInvulnerabilitiesGranted = const {},
    this.damageResistancesGranted = const {},
  });
}

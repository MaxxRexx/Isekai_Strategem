import '../constants.dart';
import 'black_trigger.dart';
import 'character.dart';
import 'trigger.dart';

class LoadoutValidationResult {
  final bool isValid;
  final List<String> errors;

  const LoadoutValidationResult(this.isValid, this.errors);
}

/// A character's chosen set of Triggers (and optional Black Trigger) for
/// a match, assigned during the pre-match Loadout phase.
class Loadout {
  final String characterId;
  final List<Trigger> triggers;
  final BlackTrigger? blackTrigger;

  const Loadout({
    required this.characterId,
    this.triggers = const [],
    this.blackTrigger,
  });

  int get totalEquipCost =>
      triggers.fold(0, (sum, t) => sum + t.equipCost) +
      (blackTrigger?.equipCost ?? 0);

  /// Total equipped items - regular Triggers plus the Black Trigger (if
  /// any), counted together against `LoadoutRulesConfig.maxEquippedTriggers`.
  int get totalEquippedCount =>
      triggers.length + (blackTrigger != null ? 1 : 0);

  /// Total active abilities this Loadout provides: 1 per equipped
  /// `ActiveTrigger`, plus however many of the Black Trigger's abilities
  /// are active.
  int get totalActiveAbilityCount =>
      triggers.whereType<ActiveTrigger>().length +
      (blackTrigger?.activeAbilityCount ?? 0);

  /// Validates this loadout against [character]'s Trion Capacity (equip
  /// budget) and the Loadout phase's equip-count/active-ability rules.
  LoadoutValidationResult validateFor(
    Character character, {
    LoadoutRulesConfig rules = LoadoutRulesConfig.defaults,
  }) {
    final errors = <String>[];
    if (totalEquipCost > character.baseStats.trionCapacity) {
      errors.add(
          'Total equip cost ($totalEquipCost) exceeds Trion Capacity (${character.baseStats.trionCapacity})');
    }
    if (totalEquippedCount > rules.maxEquippedTriggers) {
      errors.add(
          'Total equipped items ($totalEquippedCount) exceeds the max of ${rules.maxEquippedTriggers}');
    }
    if (totalActiveAbilityCount != rules.requiredActiveAbilityCount) {
      errors.add(
          'Total active abilities ($totalActiveAbilityCount) must equal exactly ${rules.requiredActiveAbilityCount}');
    }
    return LoadoutValidationResult(errors.isEmpty, errors);
  }
}

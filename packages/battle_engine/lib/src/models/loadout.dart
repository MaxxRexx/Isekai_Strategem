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

  int get totalEquipCost => triggers.fold(0, (sum, t) => sum + t.equipCost);
  int get totalSlotCost => triggers.fold(0, (sum, t) => sum + t.slotCost);

  /// Validates this loadout against [character]'s Trion Capacity (equip
  /// budget) and slot capacity.
  LoadoutValidationResult validateFor(Character character) {
    final errors = <String>[];
    if (totalEquipCost > character.baseStats.trionCapacity) {
      errors.add(
          'Total equip cost ($totalEquipCost) exceeds Trion Capacity (${character.baseStats.trionCapacity})');
    }
    if (totalSlotCost > character.baseStats.slotCapacity) {
      errors.add(
          'Total slot cost ($totalSlotCost) exceeds slot capacity (${character.baseStats.slotCapacity})');
    }
    return LoadoutValidationResult(errors.isEmpty, errors);
  }
}

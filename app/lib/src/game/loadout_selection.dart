import 'package:battle_engine/battle_engine.dart';

import 'draft.dart';

/// A player's in-progress Loadout choices for one character. Shared between
/// the Guided Tutorial's step-by-step wizard (PlayFlowScreen) and the Home
/// screen's inline squad builder, since both let a player equip Triggers
/// onto a character before it's committed to a squad.
class LoadoutSelection {
  final Set<String> triggerIds = {};
  String? blackTriggerId;

  Loadout toLoadout(String characterId) => Loadout(
    characterId: characterId,
    triggers: [for (final id in triggerIds) triggerCatalog[id]],
    blackTrigger: blackTriggerId == null
        ? null
        : blackTriggerCatalog[blackTriggerId!],
  );
}

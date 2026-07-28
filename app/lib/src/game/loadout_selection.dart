import 'package:battle_engine/battle_engine.dart';

import '../data/default_loadout_profiles.dart';
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

/// A character's curated default Loadout selection (see
/// data/default_loadout_profiles.dart), so a player can draft a squad and
/// hit Play without touching a single Trigger - every pick made this way
/// stays fully editable afterward, same as any other selection.
LoadoutSelection defaultLoadoutSelectionFor(String characterId) {
  final selection = LoadoutSelection();
  final profileId = defaultLoadoutProfileId[characterId];
  if (profileId == null) return selection;

  final loadout = loadoutBuilder.build(
    roster[characterId],
    activeTriggerPool: triggerCatalog.activeTriggers,
    passiveTriggerPool: triggerCatalog.passiveTriggers,
    blackTriggerPool: blackTriggerCatalog.all,
    profile: profileById(profileId),
  );
  selection.triggerIds.addAll(loadout.triggers.map((t) => t.id));
  selection.blackTriggerId = loadout.blackTrigger?.id;
  return selection;
}

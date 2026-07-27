import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../data/describe.dart';
import '../game/draft.dart';
import '../game/loadout_selection.dart';
import '../ui/palette.dart';
import 'ability_slot.dart';
import 'tag_chip.dart';
import 'trigger_icons.dart';

/// The approved Loadout-builder UI: a shared info panel above portrait-tile
/// grids for Active Triggers, Passive Triggers, and the Black Trigger.
/// Tapping any tile previews it in the info panel, which carries the
/// Equip/Unequip (or Select/Remove) action that actually mutates
/// [selection]. Shared by the Guided Tutorial's Loadout step and the Home
/// screen's inline per-character squad builder.
class LoadoutBuilderPanel extends StatefulWidget {
  final Character character;
  final LoadoutSelection selection;
  final Set<String>? allowedActiveIds;
  final String? allowedBlackId;
  final bool tutorialLocked;

  /// Called after [selection] is mutated (equip/unequip/select/remove) so
  /// a parent tracking its own derived state (Trion cost, validation, a
  /// squad list) can rebuild too.
  final VoidCallback onSelectionChanged;

  const LoadoutBuilderPanel({
    super.key,
    required this.character,
    required this.selection,
    this.allowedActiveIds,
    this.allowedBlackId,
    this.tutorialLocked = false,
    required this.onSelectionChanged,
  });

  @override
  State<LoadoutBuilderPanel> createState() => _LoadoutBuilderPanelState();
}

class _LoadoutBuilderPanelState extends State<LoadoutBuilderPanel> {
  // Whichever Trigger/Black Trigger tile was last tapped; the shared info
  // panel above the grids previews this one. Purely local UI state - the
  // actual equip/unequip mutates widget.selection instead.
  String? _previewTriggerId;

  void _mutate(VoidCallback fn) {
    setState(fn);
    widget.onSelectionChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _triggerInfoPanel(),
        const SizedBox(height: 12),
        _triggerPortraitGrid(
          heading: 'Active Triggers',
          triggers: triggerCatalog.activeTriggers.toList(),
        ),
        const SizedBox(height: 12),
        _triggerPortraitGrid(
          heading: 'Passive Triggers',
          triggers: triggerCatalog.passiveTriggers.toList(),
        ),
        const SizedBox(height: 12),
        _blackTriggerPortraitGrid(),
      ],
    );
  }

  Widget _triggerInfoPanel() {
    final selection = widget.selection;
    final id = _previewTriggerId;
    final active = id == null
        ? null
        : triggerCatalog.all.where((t) => t.id == id).firstOrNull;
    final black = id == null || active != null
        ? null
        : blackTriggerCatalog.all.where((bt) => bt.id == id).firstOrNull;

    if (active == null && black == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        child: const Text(
          'Tap a Trigger below to see its details.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }

    if (active != null) {
      final equipped = selection.triggerIds.contains(active.id);
      final locked =
          widget.allowedActiveIds != null &&
          !widget.allowedActiveIds!.contains(active.id);
      return _infoPanelShell(
        icon: TriggerIcon(trigger: active, size: 18),
        name: active.name,
        description: describeTrigger(active),
        tags: ['${active.equipCost} TRION'],
        buttonLabel: equipped ? 'UNEQUIP' : 'EQUIP',
        onPressed: locked
            ? null
            : () => _mutate(() {
                if (equipped) {
                  selection.triggerIds.remove(active.id);
                } else {
                  selection.triggerIds.add(active.id);
                }
              }),
      );
    }

    final bt = black!;
    final selected = selection.blackTriggerId == bt.id;
    final locked = widget.tutorialLocked && widget.allowedBlackId != bt.id;
    final grade = ResonanceGrid.defaultGrid.lookup(
      widget.character.type,
      bt.type,
    );
    return _infoPanelShell(
      icon: BlackTriggerIcon(blackTrigger: bt, size: 18),
      name: bt.name,
      description:
          '${bt.description}\n${blackTriggerAbilityLines(bt).join('\n')}',
      tags: ['${bt.equipCost} TRION'],
      extraTags: [_gradeTag(grade)],
      buttonLabel: selected ? 'REMOVE' : 'SELECT',
      onPressed: locked
          ? null
          : () => _mutate(
              () => selection.blackTriggerId = selected ? null : bt.id,
            ),
    );
  }

  Widget _infoPanelShell({
    required Widget icon,
    required String name,
    required String description,
    required List<String> tags,
    List<Widget> extraTags = const [],
    required String buttonLabel,
    required VoidCallback? onPressed,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Palette.accent)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(color: Palette.accent),
            ),
            child: icon,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    for (final tag in tags) TagChip(tag),
                    ...extraTags,
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: onPressed, child: Text(buttonLabel)),
        ],
      ),
    );
  }

  Widget _triggerPortraitGrid({
    required String heading,
    required List<Trigger> triggers,
  }) {
    final selection = widget.selection;
    return _panel(
      children: [
        Text(
          heading.toUpperCase(),
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in triggers)
              AbilitySlot(
                icon: TriggerIcon(trigger: t, size: 20),
                selected: selection.triggerIds.contains(t.id),
                highlighted:
                    !selection.triggerIds.contains(t.id) &&
                    _previewTriggerId == t.id,
                enabled:
                    widget.allowedActiveIds == null ||
                    widget.allowedActiveIds!.contains(t.id),
                tooltip: t.name,
                onTap: () => setState(() => _previewTriggerId = t.id),
                size: 44,
              ),
          ],
        ),
      ],
    );
  }

  Widget _blackTriggerPortraitGrid() {
    final selection = widget.selection;
    final allowedId = widget.allowedBlackId;
    final tutorialLocked = widget.tutorialLocked;
    return _panel(
      children: [
        const Text(
          'BLACK TRIGGER (OPTIONAL, MAX 1)',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AbilitySlot(
              icon: const Icon(
                Icons.not_interested,
                size: 18,
                color: Palette.accent,
              ),
              selected: selection.blackTriggerId == null,
              enabled: !(tutorialLocked && allowedId != null),
              tooltip: 'None',
              onTap: () => _mutate(() {
                selection.blackTriggerId = null;
                _previewTriggerId = null;
              }),
              size: 44,
            ),
            for (final bt in blackTriggerCatalog.all)
              AbilitySlot(
                icon: BlackTriggerIcon(blackTrigger: bt, size: 20),
                selected: selection.blackTriggerId == bt.id,
                highlighted:
                    selection.blackTriggerId != bt.id &&
                    _previewTriggerId == bt.id,
                enabled: !tutorialLocked || allowedId == bt.id,
                tooltip: bt.name,
                onTap: () => setState(() => _previewTriggerId = bt.id),
                size: 44,
              ),
          ],
        ),
      ],
    );
  }

  Widget _gradeTag(ResonanceGrade grade) {
    final color = switch (grade) {
      ResonanceGrade.a => Palette.good,
      ResonanceGrade.b => Palette.accent,
      ResonanceGrade.c => Colors.white54,
      ResonanceGrade.d => Palette.danger,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        grade.name.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _panel({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: const Border(top: BorderSide(color: Colors.white12, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

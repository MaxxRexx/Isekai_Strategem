import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../data/describe.dart';
import '../game/draft.dart';
import '../game/loadout_selection.dart';
import '../ui/notched.dart';
import '../ui/palette.dart';
import 'ability_slot.dart';
import 'black_trigger_ability_list.dart';
import 'tag_chip.dart';
import 'trigger_icons.dart';

enum _TriggerTab { active, passive, black }

/// The approved Loadout-builder UI: a shared info panel above a single
/// tabbed panel (Active / Passive / Black Trigger, switched instantly, no
/// separate boxes) of portrait-tile grids. Tapping any tile previews it in
/// the info panel, which carries the Equip/Unequip (or Select/Remove)
/// action that actually mutates [selection]. The tabbed panel can be
/// collapsed once trigger selection is done and reopened from its header.
/// Shared by the Guided Tutorial's Loadout step and the Home screen's
/// inline per-character squad builder.
class LoadoutBuilderPanel extends StatefulWidget {
  final Character character;
  final LoadoutSelection selection;
  final Set<String>? allowedActiveIds;
  final String? allowedBlackId;
  final bool tutorialLocked;

  /// Trion left in this character's budget (Capacity minus the current
  /// Loadout's total equip cost). Not-yet-equipped Triggers/Black Trigger
  /// costing more than this are disabled - already-equipped ones stay
  /// tappable regardless, since unequipping only ever frees budget.
  final int remainingTrion;

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
    required this.remainingTrion,
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

  _TriggerTab _tab = _TriggerTab.active;
  bool _collapsed = false;

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
        _tabbedGridPanel(),
      ],
    );
  }

  Widget _tabbedGridPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: const Border(top: BorderSide(color: Colors.white12, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  children: [
                    _tabButton('Active', _TriggerTab.active, _activeCount),
                    _tabButton('Passive', _TriggerTab.passive, _passiveCount),
                    _tabButton('Black Trigger', _TriggerTab.black, _blackCount),
                  ],
                ),
              ),
              InkWell(
                onTap: () => setState(() => _collapsed = !_collapsed),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    _collapsed ? Icons.expand_more : Icons.expand_less,
                    size: 18,
                    color: Colors.white54,
                  ),
                ),
              ),
            ],
          ),
          if (!_collapsed) ...[
            const SizedBox(height: 10),
            switch (_tab) {
              _TriggerTab.active => _triggerGrid(
                triggerCatalog.activeTriggers.toList(),
              ),
              _TriggerTab.passive => _triggerGrid(
                triggerCatalog.passiveTriggers.toList(),
              ),
              _TriggerTab.black => _blackTriggerGrid(),
            },
          ],
        ],
      ),
    );
  }

  int get _activeCount {
    final activeIds = triggerCatalog.activeTriggers.map((t) => t.id).toSet();
    return widget.selection.triggerIds.where(activeIds.contains).length;
  }

  int get _passiveCount {
    final passiveIds = triggerCatalog.passiveTriggers.map((t) => t.id).toSet();
    return widget.selection.triggerIds.where(passiveIds.contains).length;
  }

  int get _blackCount => widget.selection.blackTriggerId == null ? 0 : 1;

  Widget _tabButton(String label, _TriggerTab tab, int count) {
    final active = _tab == tab;
    return InkWell(
      onTap: () => setState(() {
        _tab = tab;
        _collapsed = false;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Palette.accent.withValues(alpha: 0.12) : null,
          border: Border(
            bottom: BorderSide(
              color: active ? Palette.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: label.toUpperCase(),
                style: TextStyle(
                  color: active ? Palette.accent : Colors.white54,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  fontSize: 11,
                  letterSpacing: 0.6,
                ),
              ),
              TextSpan(
                text: ' ($count)',
                style: const TextStyle(
                  color: Palette.gold,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
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
      final tutorialBlocked =
          widget.allowedActiveIds != null &&
          !widget.allowedActiveIds!.contains(active.id);
      final unaffordable =
          !equipped && active.equipCost > widget.remainingTrion;
      final locked = tutorialBlocked || unaffordable;
      return _infoPanelShell(
        icon: TriggerIcon(trigger: active, size: 18),
        name: active.name,
        description: describeTrigger(active),
        tags: ['${active.equipCost} TRION'],
        note: tutorialBlocked
            ? 'Locked during the tutorial.'
            : unaffordable
                ? 'Not enough Trion to equip.'
                : null,
        buttonLabel: equipped ? 'UNEQUIP' : 'EQUIP',
        // Equip keeps the solid fill; unequip switches to the open outline.
        filled: !equipped,
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
    final tutorialBlocked =
        widget.tutorialLocked && widget.allowedBlackId != bt.id;
    final unaffordable = !selected && bt.equipCost > widget.remainingTrion;
    final locked = tutorialBlocked || unaffordable;
    final grade = ResonanceGrid.defaultGrid.lookup(
      widget.character.type,
      bt.type,
    );
    return _infoPanelShell(
      icon: BlackTriggerIcon(blackTrigger: bt, size: 18),
      name: bt.name,
      description: null,
      descriptionWidget: BlackTriggerAbilityList(blackTrigger: bt),
      tags: ['${bt.equipCost} TRION'],
      extraTags: [_gradeTag(grade)],
      note: tutorialBlocked
          ? 'Locked during the tutorial.'
          : unaffordable
              ? 'Not enough Trion to equip.'
              : null,
      buttonLabel: selected ? 'UNEQUIP' : 'EQUIP',
      // Equip keeps the solid fill; unequip switches to the open outline.
      filled: !selected,
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
    required String? description,
    Widget? descriptionWidget,
    required List<String> tags,
    List<Widget> extraTags = const [],
    required String buttonLabel,
    required bool filled,
    required VoidCallback? onPressed,
    String? note,
  }) {
    // Equipped/selected items offer an unequip/remove action drawn as an
    // open-notch outlined button; not-yet-equipped items offer an
    // equip/select action drawn as the solid closed-notch filled button.
    final button = filled
        ? ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: const NotchedBorder(notch: 12),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            onPressed: onPressed,
            child: Text(buttonLabel),
          )
        : OutlinedButton(
            style: OutlinedButton.styleFrom(
              shape: const OpenNotchBorder(notch: 11),
              side: const BorderSide(color: Palette.accent, width: 1.5),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            onPressed: onPressed,
            child: Text(buttonLabel),
          );
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
                descriptionWidget ??
                    Text(
                      description ?? '',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
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
                if (note != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    note,
                    style: const TextStyle(
                      color: Palette.warn,
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          button,
        ],
      ),
    );
  }

  Widget _triggerGrid(List<Trigger> triggers) {
    final selection = widget.selection;
    return Wrap(
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
            // Always tappable so any Trigger (even one you can't equip yet)
            // can be previewed in the info panel; `dimmed` conveys the
            // unavailable state, and the Equip button there stays disabled.
            enabled: true,
            dimmed:
                !((widget.allowedActiveIds == null ||
                        widget.allowedActiveIds!.contains(t.id)) &&
                    (selection.triggerIds.contains(t.id) ||
                        t.equipCost <= widget.remainingTrion)),
            tooltip: t.name,
            onTap: () => setState(() => _previewTriggerId = t.id),
            size: 44,
          ),
      ],
    );
  }

  Widget _blackTriggerGrid() {
    final selection = widget.selection;
    final allowedId = widget.allowedBlackId;
    final tutorialLocked = widget.tutorialLocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'OPTIONAL, MAX 1',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 10,
            letterSpacing: 0.6,
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
                // Always tappable to preview; dimmed when it can't be equipped.
                enabled: true,
                dimmed:
                    !((!tutorialLocked || allowedId == bt.id) &&
                        (selection.blackTriggerId == bt.id ||
                            bt.equipCost <= widget.remainingTrion)),
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
}

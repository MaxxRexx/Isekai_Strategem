import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import 'game/draft.dart';
import 'game/loadout_selection.dart';
import 'quick_battle/quick_battle_screen.dart';
import 'screens/guide_screen.dart';
import 'screens/play_flow_screen.dart';
import 'screens/simulate_screen.dart';
import 'ui/notched.dart';
import 'ui/palette.dart';
import 'widgets/loadout_builder_panel.dart';
import 'widgets/loadout_budget_panel.dart';
import 'widgets/player_panel.dart';
import 'widgets/portrait_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedId;
  final List<String> _squadIds = [];
  final Map<String, LoadoutSelection> _selections = {};

  LoadoutSelection _selectionFor(String charId) =>
      _selections.putIfAbsent(charId, () => defaultLoadoutSelectionFor(charId));

  bool _isSquadValid(String charId) {
    final loadout = _selectionFor(charId).toLoadout(charId);
    return loadout.validateFor(roster[charId]).isValid;
  }

  bool get _squadReady =>
      _squadIds.length == 3 && _squadIds.every(_isSquadValid);

  void _selectCharacter(String id) {
    setState(() => _selectedId = id);
  }

  void _toggleSquad(String id) {
    setState(() {
      if (_squadIds.contains(id)) {
        _squadIds.remove(id);
      } else if (_squadIds.length < 3) {
        _squadIds.add(id);
      }
    });
  }

  void _autoFillSelected() {
    final selectedId = _selectedId;
    if (selectedId == null) return;
    final profile = AiProfile.all[Random().nextInt(AiProfile.all.length)];
    final loadout = loadoutBuilder.build(
      roster[selectedId],
      activeTriggerPool: triggerCatalog.activeTriggers,
      passiveTriggerPool: triggerCatalog.passiveTriggers,
      blackTriggerPool: blackTriggerCatalog.all,
      profile: profile,
    );
    setState(() {
      final selection = _selectionFor(selectedId)
        ..triggerIds.clear()
        ..blackTriggerId = loadout.blackTrigger?.id;
      selection.triggerIds.addAll(loadout.triggers.map((t) => t.id));
    });
  }

  void _play() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayFlowScreen(
          initialTeamAIds: List.of(_squadIds),
          initialSelections: {
            for (final id in _squadIds) id: _selectionFor(id),
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = _selectedId;
    final selected = selectedId == null ? null : roster[selectedId];
    final selection = selectedId == null ? null : _selectionFor(selectedId);
    final loadout = selection?.toLoadout(selectedId!);
    final validation = selected == null ? null : loadout!.validateFor(selected);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'ISEKAI STRATEGEM',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                selected == null
                    ? const _EmptySelectionPanel()
                    : LoadoutBudgetPanel(
                        character: selected,
                        loadout: loadout!,
                        errors: validation!.errors,
                        onAutoFill: _autoFillSelected,
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LoadoutBuilderPanel(
                              key: ValueKey(selectedId),
                              character: selected,
                              selection: selection!,
                              remainingTrion:
                                  selected.baseStats.trionCapacity -
                                  loadout.totalEquipCost,
                              onSelectionChanged: () => setState(() {}),
                            ),
                            const SizedBox(height: 12),
                            _SquadMembershipButton(
                              inSquad: _squadIds.contains(selectedId),
                              squadFull: _squadIds.length >= 3,
                              loadoutValid: validation.isValid,
                              onPressed: () => _toggleSquad(selectedId!),
                            ),
                          ],
                        ),
                      ),
                const SizedBox(height: 16),
                _ModeTabsRow(
                  onPlay: _squadReady ? _play : null,
                  onSimulate: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SimulateScreen()),
                  ),
                  onTutorial: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PlayFlowScreen(tutorial: true),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const QuickBattleScreen(),
                        ),
                      ),
                      child: const Text('Quick Battle'),
                    ),
                    const Text('·', style: TextStyle(color: Colors.white24)),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const GuideScreen()),
                      ),
                      child: const Text('How to Play'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _RosterAndPlayerPanel(
                  selectedId: selectedId,
                  squadIds: _squadIds,
                  onTap: _selectCharacter,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown at the top in place of a character's info until one is picked
/// from the roster grid below.
class _EmptySelectionPanel extends StatelessWidget {
  const _EmptySelectionPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white12, width: 3)),
      ),
      child: const Text(
        'Tap a character below to view their stats and build a Loadout.',
        style: TextStyle(color: Colors.white38, fontSize: 12),
      ),
    );
  }
}

class _ModeTabsRow extends StatelessWidget {
  final VoidCallback? onPlay;
  final VoidCallback onSimulate;
  final VoidCallback onTutorial;

  const _ModeTabsRow({
    required this.onPlay,
    required this.onSimulate,
    required this.onTutorial,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModeTab(icon: Icons.gps_fixed, label: 'Play', onTap: onPlay),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ModeTab(
            icon: Icons.auto_awesome,
            label: 'Simulate',
            iconColor: Palette.teamB,
            onTap: onSimulate,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ModeTab(
            icon: Icons.view_column_outlined,
            label: 'Guided Tutorial',
            onTap: onTutorial,
          ),
        ),
      ],
    );
  }
}

class _ModeTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback? onTap;

  const _ModeTab({
    required this.icon,
    required this.label,
    this.iconColor = Palette.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: Palette.panel,
            border: Border.all(color: Palette.hairline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The character-select roster grid and the Player panel sharing a single
/// bordered panel side by side (roster wide on the left, Player compact on
/// the right), matching the Naruto-Arena-style reference instead of two
/// separately-boxed sections stacked on top of each other.
class _RosterAndPlayerPanel extends StatelessWidget {
  final String? selectedId;
  final List<String> squadIds;
  final ValueChanged<String> onTap;

  const _RosterAndPlayerPanel({
    required this.selectedId,
    required this.squadIds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: const Border(top: BorderSide(color: Palette.teamA, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 7,
            child: _RosterPreviewGrid(
              selectedId: selectedId,
              squadIds: squadIds,
              onTap: onTap,
            ),
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 220, color: Palette.hairline),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: PlayerPanel(
              squadIds: squadIds,
              bordered: false,
              compact: true,
              onSquadMemberTap: onTap,
            ),
          ),
        ],
      ),
    );
  }
}

/// A browsable preview of the full roster: tap a tile to select it, showing
/// its stats above and its Loadout builder below. Squad membership is a
/// separate choice made via [_SquadMembershipButton], since previewing (or
/// still tweaking a squad member's Triggers) shouldn't itself change the
/// squad.
class _RosterPreviewGrid extends StatelessWidget {
  final String? selectedId;
  final List<String> squadIds;
  final ValueChanged<String> onTap;

  const _RosterPreviewGrid({
    required this.selectedId,
    required this.squadIds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in roster.all)
          InkWell(
            key: ValueKey('roster-${c.id}'),
            onTap: () => onTap(c.id),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: c.id == selectedId
                      ? Palette.accent
                      : squadIds.contains(c.id)
                      ? Palette.gold
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              padding: const EdgeInsets.all(2),
              child: PortraitTile(
                characterId: c.id,
                name: c.name,
                type: c.type,
                size: 56,
                showRank: false,
              ),
            ),
          ),
      ],
    );
  }
}

/// Adds or removes the currently-selected character from the squad. Adding
/// requires a complete, valid Loadout (mirrors the Guided Tutorial's
/// wizard, which also gates its "confirm" step on validation); removing
/// never has that restriction.
class _SquadMembershipButton extends StatelessWidget {
  final bool inSquad;
  final bool squadFull;
  final bool loadoutValid;
  final VoidCallback onPressed;

  const _SquadMembershipButton({
    required this.inSquad,
    required this.squadFull,
    required this.loadoutValid,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final canAdd = loadoutValid && !squadFull;
    return Align(
      alignment: Alignment.centerRight,
      child: inSquad
          // Outlined button: open L-bracket notch, matching the battle
          // screen's End Turn / Surrender treatment.
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: const OpenNotchBorder(notch: 11),
                side: const BorderSide(color: Palette.danger, width: 1.5),
                foregroundColor: Palette.danger,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              onPressed: onPressed,
              child: const Text('REMOVE FROM SQUAD'),
            )
          // Filled button: solid closed diagonal notch, matching the battle
          // screen's Queue / Return to Home buttons.
          : ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: const NotchedBorder(notch: 12),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              onPressed: canAdd ? onPressed : null,
              child: const Text('ADD TO SQUAD'),
            ),
    );
  }
}

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../data/describe.dart';
import '../data/flavor_text.dart';
import '../game/draft.dart';
import '../ui/palette.dart';
import 'character_card.dart';
import 'portrait_tile.dart';

/// A tappable slot that opens a grouped bottom-sheet picker of rich
/// character cards (the Flutter analogue of the demo's custom picker,
/// since a bare dropdown can't show stats/perk/flavor on mobile).
class CharacterSlot extends StatelessWidget {
  final String label;
  final String? selectedId;

  /// Ids unavailable because another slot on the same squad holds them.
  final Set<String> disabledIds;
  final ValueChanged<String> onChanged;
  final bool enabled;

  /// Tutorial hook: when set, only this character may be picked.
  final String? lockToCharacterId;

  const CharacterSlot({
    super.key,
    required this.label,
    required this.selectedId,
    required this.disabledIds,
    required this.onChanged,
    this.enabled = true,
    this.lockToCharacterId,
  });

  @override
  Widget build(BuildContext context) {
    final character = selectedId == null ? null : roster[selectedId!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: enabled ? () => _openPicker(context) : null,
          child: Container(
            width: double.infinity,
            height: 64,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: character != null
                  ? Palette.gold.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: enabled ? 0.04 : 0.02),
              border: Border.all(
                color: character != null
                    ? Palette.gold
                    : enabled
                    ? Colors.white24
                    : Colors.white10,
                width: character != null ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: character == null
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Choose a character...',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                : Row(
                    children: [
                      PortraitTile(
                        name: character.name,
                        type: character.type,
                        size: 48,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              character.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '${typeLabel[character.type]} · ${character.perk?.name ?? 'No perk'}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  void _openPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.panel,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (context, scrollController) => _CharacterPickerSheet(
          scrollController: scrollController,
          selectedId: selectedId,
          disabledIds: disabledIds,
          lockToCharacterId: lockToCharacterId,
          onPick: (id) {
            Navigator.of(sheetContext).pop();
            onChanged(id);
          },
        ),
      ),
    );
  }
}

/// The picker sheet's body: a roster grid of portrait tiles grouped by
/// Character Type, with a bottom detail panel that fills in on tap
/// (previewing stats/perk) and a Draft button that commits the pick.
class _CharacterPickerSheet extends StatefulWidget {
  final ScrollController scrollController;
  final String? selectedId;
  final Set<String> disabledIds;
  final String? lockToCharacterId;
  final ValueChanged<String> onPick;

  const _CharacterPickerSheet({
    required this.scrollController,
    required this.selectedId,
    required this.disabledIds,
    required this.lockToCharacterId,
    required this.onPick,
  });

  @override
  State<_CharacterPickerSheet> createState() => _CharacterPickerSheetState();
}

class _CharacterPickerSheetState extends State<_CharacterPickerSheet> {
  late String? _focusedId = widget.selectedId ?? widget.lockToCharacterId;

  bool _enabledFor(String id) =>
      !widget.disabledIds.contains(id) &&
      (widget.lockToCharacterId == null || id == widget.lockToCharacterId);

  @override
  Widget build(BuildContext context) {
    final byType = <CharacterType, List<Character>>{};
    for (final c in roster.all) {
      byType.putIfAbsent(c.type, () => []).add(c);
    }
    final focused = _focusedId == null ? null : roster[_focusedId!];

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            children: [
              for (final type in CharacterType.values) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    typeLabel[type]!,
                    style: const TextStyle(
                      color: Palette.accent,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in byType[type] ?? const <Character>[])
                      _RosterTile(
                        character: c,
                        selected: c.id == _focusedId,
                        enabled: _enabledFor(c.id),
                        onTap: () => setState(() => _focusedId = c.id),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        _detailPanel(focused),
      ],
    );
  }

  Widget _detailPanel(Character? character) {
    if (character == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        child: const Text(
          'Tap an Agent to preview stats and perk.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }
    final enabled = _enabledFor(character.id);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Palette.accent)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PortraitTile(name: character.name, type: character.type, size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  character.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  character.perk?.name ?? 'No perk',
                  style: const TextStyle(
                    color: Palette.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (characterFlavor[character.id] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      characterFlavor[character.id]!,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                _statRow(character.baseStats),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: enabled ? () => widget.onPick(character.id) : null,
            child: const Text('Draft'),
          ),
        ],
      ),
    );
  }

  Widget _statRow(Stats stats) {
    final pairs = <(String, String)>[
      ('ATK', '${stats.attack}'),
      ('DEF', '${stats.defense}'),
      ('CRIT', '${stats.criticalChance.round()}%'),
      ('FAT', '${stats.fatChance.round()}%'),
      ('TRION', '${stats.trionCapacity}'),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 2,
      children: [
        for (final (label, value) in pairs)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label ',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One roster-grid entry: a portrait tile plus name/role, the mockup's
/// `.roster-card`.
class _RosterTile extends StatelessWidget {
  final Character character;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _RosterTile({
    required this.character,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 86,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: selected
                ? Palette.accent.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.03),
            border: Border.all(
              color: selected ? Palette.accent : Colors.white12,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            children: [
              PortraitTile(name: character.name, type: character.type),
              const SizedBox(height: 6),
              Text(
                character.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                character.perk?.name ?? 'No perk',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable slot that opens a bottom-sheet picker of AI profiles,
/// grouped by skill class.
class ProfileSlot extends StatelessWidget {
  final String label;
  final String? selectedId;
  final ValueChanged<String> onChanged;
  final bool enabled;

  const ProfileSlot({
    super.key,
    required this.label,
    required this.selectedId,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final profile = selectedId == null ? null : profileById(selectedId!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: enabled ? () => _openPicker(context) : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: enabled ? 0.04 : 0.02),
              border: Border.all(
                color: enabled ? Colors.white24 : Colors.white10,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: profile == null
                ? const Text(
                    'Choose an AI Profile...',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  )
                : ProfileCard(profile: profile),
          ),
        ),
      ],
    );
  }

  void _openPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.panel,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(12),
          children: [
            for (final skillClass in AiSkillClass.values) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  skillClassLabel[skillClass]!,
                  style: const TextStyle(
                    color: Palette.accent,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
              ),
              for (final p in AiProfile.all.where(
                (p) => p.skillClass == skillClass,
              ))
                _PickRow(
                  selected: p.id == selectedId,
                  enabled: true,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onChanged(p.id);
                  },
                  child: ProfileCard(profile: p),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  const _PickRow({
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected
                ? Palette.accent.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.03),
            border: Border.all(
              color: selected ? Palette.accent : Colors.white12,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: child,
        ),
      ),
    );
  }
}

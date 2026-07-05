import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../data/describe.dart';
import '../game/draft.dart';
import '../ui/palette.dart';
import 'character_card.dart';

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
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: enabled ? 0.04 : 0.02),
              border: Border.all(
                color: enabled ? Colors.white24 : Colors.white10,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: character == null
                ? const Text(
                    'Choose a character...',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  )
                : CharacterCard(character: character),
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
      builder: (sheetContext) {
        final byType = <CharacterType, List<Character>>{};
        for (final c in roster.all) {
          byType.putIfAbsent(c.type, () => []).add(c);
        }
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(12),
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
                for (final c in byType[type] ?? const <Character>[])
                  _PickRow(
                    selected: c.id == selectedId,
                    enabled:
                        !disabledIds.contains(c.id) &&
                        (lockToCharacterId == null ||
                            c.id == lockToCharacterId),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onChanged(c.id);
                    },
                    child: CharacterCard(character: c),
                  ),
              ],
            ],
          ),
        );
      },
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

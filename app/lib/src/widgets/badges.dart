import 'package:flutter/material.dart';

import '../data/flavor_text.dart';
import '../ui/palette.dart';
import 'game_icons.dart';

/// The Full Arms Trigger indicator, shown next to a character whose FAT
/// roll succeeded this turn.
class FatBadge extends StatelessWidget {
  const FatBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          'Full Arms Trigger is active: up to 3 ability uses this turn instead of 1.',
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Palette.warn.withValues(alpha: 0.15),
          border: Border.all(color: Palette.warn),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(GameIcons.burst, size: 11, color: Palette.warn),
            Text(
              'FAT',
              style: TextStyle(
                color: Palette.warn,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A status effect name chip; tapping shows duration + effect summary.
class StatusBadge extends StatelessWidget {
  final String name;
  final int? remainingTurns;
  const StatusBadge({super.key, required this.name, this.remainingTurns});

  @override
  Widget build(BuildContext context) {
    final info = statusInfo[name];
    final message = info == null
        ? name
        : '$name (${info.duration} turn${info.duration == 1 ? '' : 's'}): ${info.effect}';
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: Palette.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          remainingTurns == null ? name : '$name ($remainingTurns)',
          style: const TextStyle(color: Palette.accent, fontSize: 10),
        ),
      ),
    );
  }
}

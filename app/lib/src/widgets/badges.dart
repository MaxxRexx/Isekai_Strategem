import 'package:flutter/material.dart';

import '../data/describe.dart';
import '../ui/notched.dart';
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

/// A status-effect square icon badge (the effect-strip look from the
/// approved mockup); tapping shows the name, duration, and effect summary.
class StatusBadge extends StatelessWidget {
  final String name;
  final int? remainingTurns;

  /// The catalog id, so the tooltip can read what the effect actually does
  /// rather than repeating its display name. Optional only because a few
  /// callers still have nothing but a name to hand.
  final String? id;

  /// Whether this badge sits on one of the player's own characters, which
  /// decides whose turns the remaining duration is counted in.
  final bool onSelf;

  const StatusBadge({
    super.key,
    required this.name,
    this.remainingTurns,
    this.id,
    this.onSelf = true,
  });

  @override
  Widget build(BuildContext context) {
    final message = id == null
        ? name
        : describeStatusBadge(
            id: id!,
            name: name,
            remainingTurns: remainingTurns,
            onSelf: onSelf,
          );
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        width: 19,
        height: 19,
        alignment: Alignment.center,
        decoration: const ShapeDecoration(
          color: Palette.panel,
          shape: OpenNotchBorder(
            side: BorderSide(color: Palette.accent),
            notch: 5,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            const Icon(GameIcons.status, size: 11, color: Palette.accent),
            if (remainingTurns != null)
              Positioned(
                bottom: -4,
                right: -4,
                child: Text(
                  '$remainingTurns',
                  style: const TextStyle(
                    color: Palette.accent,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

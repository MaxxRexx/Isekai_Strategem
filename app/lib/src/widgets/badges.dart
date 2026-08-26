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

/// The Bail Out pill: this operator is leaving, but their body is still on
/// the board for one contested turn.
///
/// Deliberately colourless. Amber is the Full Arms Trigger, gold is critical
/// hits and stat values, red is death, cyan is status effects and your own
/// squad, green is healing and violet is a bent shot: every hue in this
/// interface already means something, and the one hue left (a cold blue) sits
/// right on top of your own squad's cyan. Drained of colour is also what the
/// state is, so it is the honest reading rather than a leftover.
class BailingOutBadge extends StatelessWidget {
  /// Whose body it is, which decides what the player can do about it.
  final bool isOwnSquad;

  const BailingOutBadge({super.key, required this.isOwnSquad});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isOwnSquad
          ? 'Bailing out. The operator is leaving the engagement and cannot '
              'act, be healed or be moved. Their body still screens whoever '
              'is behind it. If the enemy leaves it alone until the end of '
              'their next turn it is recalled and your squad banks the Trion '
              'Salvage; if they hit it, the body is destroyed and the Salvage '
              'is lost.'
          : 'Bailing out. The body is still standing there, still screening, '
              'and one hit of any size destroys it. Destroying it denies them '
              'the Trion Salvage and pays your squad a smaller share; leaving '
              'it alone lets them bank the lot at the end of your next turn.',
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white54),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text(
          'BAILING OUT',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
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

  /// How many times this effect has stacked (item 5b). Anything above 1 is
  /// drawn on the badge, because three stacks of Bleeding is three times the
  /// damage and a player who cannot see the count cannot judge the threat.
  final int stacks;

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
    this.stacks = 1,
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
            stacks: stacks,
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
            if (stacks > 1)
              Positioned(
                top: -4,
                left: -4,
                child: Text(
                  'x$stacks',
                  style: const TextStyle(
                    color: Palette.warn,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
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

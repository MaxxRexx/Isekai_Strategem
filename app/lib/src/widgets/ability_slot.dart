import 'package:flutter/material.dart';

import '../ui/notched.dart';
import '../ui/palette.dart';

/// A square ability icon button (the ability-row slot from the approved
/// mockup), used in place of a text pill so the icon reads at a glance.
class AbilitySlot extends StatefulWidget {
  final Widget icon;
  final bool selected;
  final bool highlighted;
  final bool enabled;

  /// Visual-only "unavailable" dimming that does NOT block [onTap]. Used in
  /// the Loadout builder so a not-yet-affordable Trigger still reads as
  /// unavailable but can be tapped to preview its details (the Equip action
  /// itself stays disabled in the info panel).
  final bool dimmed;

  final String? tooltip;
  final VoidCallback? onTap;
  final double size;

  /// Turns remaining before this ability is usable again. When positive,
  /// the icon underneath is dimmed and this count is overlaid on top -
  /// matching the reference's cooldown treatment - instead of the ability
  /// disappearing from the row entirely.
  final int cooldownRemaining;

  /// Draws a slow accent pulse on the slot. Reserved for one meaning: the
  /// ability is in range from the line this character is stepping to, and the
  /// only thing left is an action to spend on it. Every other unavailable
  /// reason is a flat dim, because every other reason is not about to change.
  final bool pending;

  const AbilitySlot({
    super.key,
    required this.icon,
    this.selected = false,
    this.highlighted = false,
    this.enabled = true,
    this.dimmed = false,
    this.tooltip,
    this.onTap,
    this.size = 48,
    this.cooldownRemaining = 0,
    this.pending = false,
  });

  @override
  State<AbilitySlot> createState() => _AbilitySlotState();
}

class _AbilitySlotState extends State<AbilitySlot>
    with SingleTickerProviderStateMixin {
  // Created only for a slot that actually pulses. Ability slots are rendered
  // by the dozen (the Loadout builder lists all 60 Triggers), so a controller
  // and a ticker each would be real cost for a state almost none of them are
  // ever in.
  AnimationController? _pulse;

  void _startPulse() {
    _pulse ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (!_pulse!.isAnimating) _pulse!.repeat(reverse: true);
  }

  @override
  void initState() {
    super.initState();
    if (widget.pending) _startPulse();
  }

  @override
  void didUpdateWidget(AbilitySlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pending) {
      _startPulse();
    } else {
      _pulse?.stop();
      _pulse?.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cooldownRemaining = widget.cooldownRemaining;
    final selected = widget.selected;
    final highlighted = widget.highlighted;
    final enabled = widget.enabled;
    final dimmed = widget.dimmed;
    final size = widget.size;
    final icon = widget.icon;
    final tooltip = widget.tooltip;
    final onTap = widget.onTap;
    final onCooldown = cooldownRemaining > 0;
    final borderColor = selected
        ? Palette.gold
        : highlighted
        ? Palette.warn
        : widget.pending
        ? Palette.accent
        // Brighter than the faint hairline so the open L-brackets read
        // clearly on an unselected slot.
        : Colors.white.withValues(alpha: 0.34);
    // A pending slot breathes between the dim and the ready opacity, so it
    // reads as "nearly available" rather than either state.
    final baseOpacity = (enabled && !dimmed) ? 1.0 : 0.4;
    final button = Opacity(
      opacity: baseOpacity,
      child: Material(
        color: Palette.panel,
        // Open L-bracket notch on the top-left + bottom-right corners (the
        // same open notch as the End Turn button), matching the Rift Cyan
        // ability slots.
        shape: OpenNotchBorder(
          side: BorderSide(
            color: borderColor,
            width: selected || highlighted || widget.pending ? 2 : 1,
          ),
          notch: size * 0.16,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: size,
            height: size,
            // StackFit.expand makes the layers fill the whole slot (not just
            // the small icon), so the cooldown cover and its number span the
            // entire box rather than sitting in the middle of the icon.
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Opacity(opacity: onCooldown ? 0.35 : 1, child: icon),
                ),
                if (onCooldown)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.6),
                      // The count fills the whole slot, so it reads as a
                      // cooldown cover rather than a small number floating in
                      // the middle of the icon.
                      // The number sits centered at 75% of the slot height
                      // (the dark cover still fills the whole slot).
                      child: Center(
                        child: FractionallySizedBox(
                          heightFactor: 0.75,
                          child: FittedBox(
                            fit: BoxFit.fitHeight,
                            child: Text(
                              '$cooldownRemaining',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final withTooltip = tooltip == null
        ? button
        : Tooltip(
            message: tooltip,
            triggerMode: TooltipTriggerMode.longPress,
            child: button,
          );
    if (!widget.pending) return withTooltip;
    // Respect the platform's reduce-motion setting: the state still reads
    // through the accent border and the description panel without it.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return Opacity(opacity: 0.75, child: withTooltip);
    }
    final pulse = _pulse;
    if (pulse == null) return withTooltip;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1.0).animate(
        CurvedAnimation(parent: pulse, curve: Curves.easeInOut),
      ),
      child: withTooltip,
    );
  }
}

import 'package:flutter/material.dart';

import '../ui/palette.dart';

/// A square ability icon button (the ability-row slot from the approved
/// mockup), used in place of a text pill so the icon reads at a glance.
class AbilitySlot extends StatelessWidget {
  final Widget icon;
  final bool selected;
  final bool highlighted;
  final bool enabled;
  final String? tooltip;
  final VoidCallback? onTap;
  final double size;

  /// Turns remaining before this ability is usable again. When positive,
  /// the icon underneath is dimmed and this count is overlaid on top -
  /// matching the reference's cooldown treatment - instead of the ability
  /// disappearing from the row entirely.
  final int cooldownRemaining;

  const AbilitySlot({
    super.key,
    required this.icon,
    this.selected = false,
    this.highlighted = false,
    this.enabled = true,
    this.tooltip,
    this.onTap,
    this.size = 48,
    this.cooldownRemaining = 0,
  });

  @override
  Widget build(BuildContext context) {
    final onCooldown = cooldownRemaining > 0;
    final borderColor = selected
        ? Palette.gold
        : highlighted
        ? Palette.warn
        : Palette.hairline;
    final button = Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Palette.panel,
            border: Border.all(
              color: borderColor,
              width: selected || highlighted ? 2 : 1,
            ),
          ),
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
    );
    return tooltip == null
        ? button
        : Tooltip(
            message: tooltip!,
            triggerMode: TooltipTriggerMode.longPress,
            child: button,
          );
  }
}

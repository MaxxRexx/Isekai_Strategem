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
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Palette.panel,
            border: Border.all(
              color: borderColor,
              width: selected || highlighted ? 2 : 1,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(opacity: onCooldown ? 0.35 : 1, child: icon),
              if (onCooldown)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.55),
                    child: Padding(
                      padding: EdgeInsets.all(size * 0.1),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Text(
                          '$cooldownRemaining',
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

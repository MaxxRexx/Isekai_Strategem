import 'package:flutter/material.dart';

import '../ui/palette.dart';

/// A square ability icon button (the ability-row slot from the approved
/// mockup), used in place of a text pill so the icon reads at a glance.
class AbilitySlot extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final bool highlighted;
  final bool enabled;
  final String? tooltip;
  final VoidCallback? onTap;
  final double size;

  const AbilitySlot({
    super.key,
    required this.icon,
    this.selected = false,
    this.highlighted = false,
    this.enabled = true,
    this.tooltip,
    this.onTap,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
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
          child: Icon(icon, size: size * 0.46, color: Palette.accent),
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

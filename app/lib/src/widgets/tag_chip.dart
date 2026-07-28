import 'package:flutter/material.dart';

import '../ui/palette.dart';

/// A small bordered label used for compact stat/cost callouts (e.g.
/// "4 TRION") wherever a trigger/ability is described.
class TagChip extends StatelessWidget {
  final String label;
  const TagChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: Palette.accent)),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 9,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

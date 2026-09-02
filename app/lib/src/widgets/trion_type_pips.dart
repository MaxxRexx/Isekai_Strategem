import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../data/describe.dart';
import '../ui/palette.dart';

/// One coloured square standing for a Trion Type, or for a Random slot.
///
/// Naruto-Arena shows its chakra as coloured squares rather than words, which
/// is what makes a cost readable at a glance instead of a sentence to parse.
class TrionTypeSquare extends StatelessWidget {
  /// The kind this square stands for, or null for a Random slot.
  final TrionType? type;
  final double size;

  const TrionTypeSquare({super.key, required this.type, this.size = 11});

  @override
  Widget build(BuildContext context) {
    final color =
        type == null ? Palette.trionRandom : Palette.trionType[type]!;
    return Semantics(
      label: type == null ? 'Random' : trionTypeLabel(type!),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
          // A Random slot is any kind, so it is outlined rather than solid:
          // it reads as an empty space to be filled, which is what it is.
          border: type == null
              ? Border.all(color: Colors.white24, width: 1)
              : null,
        ),
      ),
    );
  }
}

/// The squad's reserve: all four kinds, always, in a fixed order, each with
/// its count.
///
/// Always all four even at zero, because what you are missing is as much of
/// the decision as what you hold. Position and the number carry the meaning
/// as well as the colour does, so the row still reads without the colour.
class TrionTypeReserveRow extends StatelessWidget {
  final Map<TrionType, int> counts;
  final double squareSize;
  final double fontSize;

  const TrionTypeReserveRow({
    super.key,
    required this.counts,
    this.squareSize = 11,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final type in TrionType.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TrionTypeSquare(type: type, size: squareSize),
              const SizedBox(width: 4),
              Text(
                '${counts[type] ?? 0}',
                style: TextStyle(
                  color: (counts[type] ?? 0) > 0
                      ? Colors.white
                      : Colors.white38,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// What one ability asks for: a square per slot, named kinds first in a fixed
/// order, then the Random slots.
class TrionTypeCostRow extends StatelessWidget {
  final TrionTypeCost cost;
  final double squareSize;

  const TrionTypeCostRow({
    super.key,
    required this.cost,
    this.squareSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: describeTrionTypeCost(cost),
      child: Wrap(
        spacing: 3,
        runSpacing: 3,
        children: [
          for (final type in TrionType.values)
            for (var i = 0; i < cost[type]; i++)
              TrionTypeSquare(type: type, size: squareSize),
          for (var i = 0; i < cost.random; i++)
            TrionTypeSquare(type: null, size: squareSize),
        ],
      ),
    );
  }
}

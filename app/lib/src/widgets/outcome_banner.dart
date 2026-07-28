import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../ui/palette.dart';

(String, Color) outcomeCopy(BattleOutcome outcome) => switch (outcome) {
  BattleOutcome.teamAWins => ('SQUAD A WINS', Palette.teamA),
  BattleOutcome.teamBWins => ('SQUAD B WINS', Palette.teamB),
  BattleOutcome.draw => ('MUTUAL DEFEAT', Colors.grey),
  BattleOutcome.ongoing => ('NO CONCLUSION REACHED', Palette.warn),
};

class OutcomeBanner extends StatelessWidget {
  final BattleOutcome outcome;
  final String note;

  /// Overrides the default outcome text (Play mode says "VICTORY" or
  /// "DEFEAT" instead of "SQUAD A/B WINS").
  final String? textOverride;

  const OutcomeBanner({
    super.key,
    required this.outcome,
    required this.note,
    this.textOverride,
  });

  @override
  Widget build(BuildContext context) {
    final (text, color) = outcomeCopy(outcome);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 4)),
        color: Theme.of(context).cardColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            textOverride ?? text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          Text(
            note,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

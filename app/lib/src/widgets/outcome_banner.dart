import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../ui/palette.dart';

/// The headline for an outcome. [onRoundLimit] is item #4's round limit
/// deciding it, which changes only the level result: nobody was defeated
/// there, so calling it a mutual defeat would be plainly untrue.
(String, Color) outcomeCopy(BattleOutcome outcome,
        {bool onRoundLimit = false}) =>
    switch (outcome) {
      BattleOutcome.teamAWins => ('SQUAD A WINS', Palette.teamA),
      BattleOutcome.teamBWins => ('SQUAD B WINS', Palette.teamB),
      BattleOutcome.draw when onRoundLimit => ('STALEMATE', Colors.grey),
      BattleOutcome.draw => ('MUTUAL DEFEAT', Colors.grey),
      BattleOutcome.ongoing => ('NO CONCLUSION REACHED', Palette.warn),
    };

class OutcomeBanner extends StatelessWidget {
  final BattleOutcome outcome;
  final String note;

  /// Whether item #4's round limit decided this, which changes the wording
  /// of a level result.
  final bool onRoundLimit;

  /// Overrides the default outcome text (Play mode says "VICTORY" or
  /// "DEFEAT" instead of "SQUAD A/B WINS").
  final String? textOverride;

  const OutcomeBanner({
    super.key,
    required this.outcome,
    required this.note,
    this.textOverride,
    this.onRoundLimit = false,
  });

  @override
  Widget build(BuildContext context) {
    final (text, color) = outcomeCopy(outcome, onRoundLimit: onRoundLimit);
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

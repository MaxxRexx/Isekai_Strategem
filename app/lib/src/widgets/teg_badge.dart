import 'package:flutter/material.dart';

import '../game/battle_xp.dart';
import '../game/team_efficiency.dart';
import '../ui/palette.dart';

/// Combat-v2 §10: the squad's Team Efficiency Grade display. Shows the letter
/// grade prominently with the composite; tap to expand the six sub-scores and
/// the dice-advantage effects live at that grade (so players can optimise
/// toward them).
class TegBadge extends StatefulWidget {
  final TeamEfficiency teg;
  const TegBadge({super.key, required this.teg});

  @override
  State<TegBadge> createState() => _TegBadgeState();
}

class _TegBadgeState extends State<TegBadge> {
  bool _expanded = false;

  Color get _gradeColor => switch (widget.teg.tier) {
    TegTier.d || TegTier.c => Palette.danger,
    TegTier.b || TegTier.a => Palette.gold,
    TegTier.s || TegTier.ss || TegTier.sss => Palette.good,
  };

  @override
  Widget build(BuildContext context) {
    final teg = widget.teg;
    final profile = tegRollProfileFor(teg.tier);
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Palette.panel,
          border: Border.all(color: _gradeColor.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'TEAM EFFICIENCY GRADE',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                Text(
                  teg.tier.label,
                  style: TextStyle(
                    color: _gradeColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${teg.composite.round()}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Colors.white38,
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              _subScore('Team Spirit Alignment', teg.teamSpiritAlignment),
              _subScore('Stat Coherence', teg.statCoherence),
              _subScore('Loadout Synergy', teg.loadoutSynergy),
              _subScore('Perk Utilization', teg.perkUtilization),
              _subScore('Trion Economy', teg.trionEconomy),
              if (teg.resonanceFit != null)
                _subScore('Resonance Fit', teg.resonanceFit!),
              const Divider(color: Colors.white12, height: 16),
              const Text(
                'LIVE EFFECTS',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 9.5,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 4),
              _effect('Coordination advantage',
                  '${profile.offenseAdvantagePercent}%'),
              _effect("Operator's Read (defence)",
                  '${profile.defenseAdvantagePercent}%'),
              _effect('Setup→payoff Trion refund',
                  '${profile.trionRefundPercent}%'),
              if (profile.maxCritThreshold <= 18)
                _effect('Crit range', 'nat 18-20'),
              _effect('Post-battle XP',
                  '+${battleXpBonusPercentFor(teg.tier)}%'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _subScore(String label, double value) {
    final v = value.clamp(0, 100).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 10.5),
            ),
          ),
          Expanded(
            child: ClipRect(
              child: LinearProgressIndicator(
                value: v / 100,
                minHeight: 5,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation(_gradeColor),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 26,
            child: Text(
              '${v.round()}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white70, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _effect(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

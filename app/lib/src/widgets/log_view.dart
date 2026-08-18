import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/describe.dart';
import '../data/flavor_text.dart';
import '../game/draft.dart';
import '../ui/palette.dart';
import '../game/battle_models.dart';
import 'pickers.dart';

/// The scrollable battle log: one block per team turn, one line per
/// (action, target) pair, mirroring the HTML demo's log composition.
class BattleLogView extends StatefulWidget {
  final List<LogRound> rounds;
  final String title;

  /// Team labels in round headings ('Squad A'/'Squad B' for Simulate,
  /// 'You'/'Opponent' for Play mode).
  final String teamAName;
  final String teamBName;

  /// Height of the scrollable log body when the panel is expanded.
  final double bodyHeight;

  /// Whether the dropdown starts expanded, in uncontrolled mode. Ignored
  /// when [open] is provided (controlled mode).
  final bool initiallyOpen;

  /// Controlled open state. When non-null, the caller owns the open/closed
  /// state (so it survives this widget being rebuilt as siblings come and
  /// go) and must update it via [onToggle]. When null, the widget keeps its
  /// own state seeded from [initiallyOpen].
  final bool? open;
  final VoidCallback? onToggle;

  const BattleLogView({
    super.key,
    required this.rounds,
    this.title = 'BATTLE LOG',
    this.teamAName = 'Squad A',
    this.teamBName = 'Squad B',
    this.bodyHeight = 260,
    this.initiallyOpen = true,
    this.open,
    this.onToggle,
  });

  @override
  State<BattleLogView> createState() => _BattleLogViewState();
}

class _BattleLogViewState extends State<BattleLogView> {
  // Uncontrolled fallback state (used only when widget.open is null).
  late bool _internalOpen = widget.initiallyOpen;
  final _scrollController = ScrollController();

  bool get _open => widget.open ?? _internalOpen;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggle() {
    if (widget.onToggle != null) {
      widget.onToggle!();
    } else {
      setState(() => _internalOpen = !_internalOpen);
    }
  }

  int get _eventCount {
    var count = 0;
    for (final round in widget.rounds) {
      count += round.actions.isEmpty
          ? 1
          : round.actions.fold<int>(
              0,
              (sum, a) => sum + a.targets.length.clamp(1, 99),
            );
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '$_eventCount events',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _open ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const Divider(height: 1, color: Colors.white12),
            SizedBox(
              height: widget.bodyHeight,
              // An always-visible, chunky scrollbar so it's obvious the log
              // scrolls (players were unsure earlier turns were even recorded).
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                thickness: 8,
                radius: const Radius.circular(4),
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
                  itemCount: widget.rounds.length,
                  itemBuilder: (context, i) => RoundEntry(
                    round: widget.rounds[i],
                    teamAName: widget.teamAName,
                    teamBName: widget.teamBName,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class RoundEntry extends StatelessWidget {
  final LogRound round;
  final String teamAName;
  final String teamBName;
  const RoundEntry({
    super.key,
    required this.round,
    this.teamAName = 'Squad A',
    this.teamBName = 'Squad B',
  });

  @override
  Widget build(BuildContext context) {
    final actorColor = round.team == 'A' ? Palette.teamA : Palette.teamB;
    final teamName = round.team == 'A' ? teamAName : teamBName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '- Round ${round.roundNumber}, $teamName -',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          if (round.actions.isEmpty)
            const Text(
              '(no legal action taken)',
              style: TextStyle(
                color: Colors.white38,
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
            ),
          for (final action in round.actions)
            // A move has no target to roll against, so it gets its own plain
            // line. Rendering only per-target would drop it from the log
            // entirely, which is how Repositions went unrecorded.
            if (action.targets.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: UntargetedLogLine(action: action, color: actorColor),
              )
            else
              for (final t in action.targets)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: LogLine(action: action, target: t, color: actorColor),
                ),
        ],
      ),
    );
  }
}

/// A log line for an action that resolved against nobody: a Reposition. There
/// are no dice behind it, so unlike [LogLine] it has nothing to expand.
class UntargetedLogLine extends StatelessWidget {
  final LogAction action;
  final Color color;
  const UntargetedLogLine({
    super.key,
    required this.action,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.swap_horiz, size: 13, color: color.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                children: [
                  TextSpan(
                    text: action.characterName,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' '),
                  TextSpan(text: _phrase(action.triggerName)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "Reposition to the front line" reads as a label, not an event. Turn it
  /// into something that sits in a sentence after the character's name.
  static String _phrase(String triggerName) {
    const prefix = 'Reposition to the ';
    if (triggerName.startsWith(prefix)) {
      return 'moves to the ${triggerName.substring(prefix.length)}';
    }
    return triggerName;
  }
}

class LogLine extends StatefulWidget {
  final LogAction action;
  final LogTargetResult target;
  final Color color;
  const LogLine({
    super.key,
    required this.action,
    required this.target,
    required this.color,
  });

  @override
  State<LogLine> createState() => _LogLineState();
}

class _LogLineState extends State<LogLine> {
  bool _expanded = false;

  // Tap recognizers for the clickable names/ability in the line. They open an
  // info popup and win the tap over the line's expand InkWell, so tapping a
  // name shows its details while tapping elsewhere still toggles the breakdown.
  late final _actorTap = TapGestureRecognizer()
    ..onTap = () => _showCharacterInfo(widget.action.characterId);
  late final _abilityTap = TapGestureRecognizer()
    ..onTap = () =>
        _showAbilityInfo(widget.action.triggerId, widget.action.triggerName);
  late final _targetTap = TapGestureRecognizer()
    ..onTap = () => _showCharacterInfo(widget.target.targetId);

  @override
  void dispose() {
    _actorTap.dispose();
    _abilityTap.dispose();
    _targetTap.dispose();
    super.dispose();
  }

  static const _linkUnderline = TextDecoration.underline;

  void _showCharacterInfo(String characterId) {
    final character = roster[characterId];
    if (character == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.panel,
        title: Text(
          character.name,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${typeLabel[character.type] ?? ''}  ·  '
                '${character.perk?.name ?? 'No perk'}',
                style: const TextStyle(color: Palette.gold, fontSize: 12),
              ),
              if (character.perk != null) ...[
                const SizedBox(height: 2),
                Text(
                  character.perk!.description,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
              if (characterFlavor[characterId] != null) ...[
                const SizedBox(height: 6),
                Text(
                  characterFlavor[characterId]!,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              CharacterStatRow(stats: character.baseStats),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAbilityInfo(String triggerId, String triggerName) {
    final catalog = TriggerCatalog.defaultCatalog;
    final description = catalog.contains(triggerId)
        ? describeTrigger(catalog[triggerId])
        : 'No details available.';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.panel,
        title: Text(
          triggerName,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          description,
          style: const TextStyle(color: Colors.white70, fontSize: 12.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final t = widget.target;
    final rollBits = <String>[
      if (t.crits > 0) '${t.crits} crit',
      if (t.hits - t.crits - t.misses > 0) '${t.hits - t.crits - t.misses} hit',
      if (t.misses > 0) '${t.misses} miss',
    ];
    final hasBreakdown = t.rolls.isNotEmpty || t.statusEffectsApplied.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The whole line is the tap target (not just a tiny chevron), so it's
        // easy to open the details on a phone.
        InkWell(
          onTap: hasBreakdown
              ? () => setState(() => _expanded = !_expanded)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                      children: [
                        TextSpan(
                          text: action.characterName,
                          style: TextStyle(
                            color: widget.color,
                            fontWeight: FontWeight.bold,
                            decoration: _linkUnderline,
                            decorationColor: widget.color,
                          ),
                          recognizer: _actorTap,
                        ),
                        if (action.fatTriggered)
                          const TextSpan(
                            text: ' [FAT]',
                            style: TextStyle(
                              color: Palette.warn,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        const TextSpan(text: ' uses '),
                        TextSpan(
                          text: action.triggerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: _linkUnderline,
                            decorationColor: Colors.white54,
                          ),
                          recognizer: _abilityTap,
                        ),
                        const TextSpan(text: ' on '),
                        TextSpan(
                          text: t.targetName,
                          style: const TextStyle(
                            decoration: _linkUnderline,
                            decorationColor: Colors.white38,
                          ),
                          recognizer: _targetTap,
                        ),
                        if (rollBits.isNotEmpty)
                          TextSpan(text: ' (${rollBits.join(', ')})'),
                        if (t.damage > 0)
                          TextSpan(
                            text: ' ${t.damage} dmg',
                            style: const TextStyle(color: Palette.danger),
                          ),
                        if (t.statusEffectsApplied.isNotEmpty)
                          TextSpan(
                            text: ' [${t.statusEffectsApplied.join(', ')}]',
                            style: const TextStyle(color: Palette.accent),
                          ),
                        TextSpan(text: ' -> HP ${t.healthAfter}'),
                        if (t.died)
                          const TextSpan(
                            text: ' DEFEATED',
                            style: TextStyle(
                              color: Palette.danger,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (hasBreakdown) ...[
                  const SizedBox(width: 6),
                  _detailsAffordance(_expanded),
                ],
              ],
            ),
          ),
        ),
        if (_expanded && hasBreakdown)
          RollBreakdownView(
            actorName: action.characterName,
            abilityName: action.triggerName,
            targetName: t.targetName,
            rolls: t.rolls,
            statusEffectsApplied: t.statusEffectsApplied,
            healthAfter: t.healthAfter,
            died: t.died,
          ),
      ],
    );
  }

  /// A small pill that clearly reads as tappable ("Details ▾"), so players
  /// know each line opens an explanation.
  Widget _detailsAffordance(bool expanded) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Palette.accent.withValues(alpha: 0.10),
      border: Border.all(color: Palette.accent.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          expanded ? 'Hide' : 'Details',
          style: const TextStyle(color: Palette.accent, fontSize: 9.5),
        ),
        Icon(
          expanded ? Icons.expand_less : Icons.expand_more,
          size: 13,
          color: Palette.accent,
        ),
      ],
    ),
  );
}

/// A plain-English explanation of one Battle Log line, revealed by tapping it:
/// what happened, how the dice decided the hit, how the damage was built up
/// step by step, and what any status effects do. Numbers are colour-coded so
/// you can tell a die roll (cyan) from a character stat (gold) from a total
/// (white).
class RollBreakdownView extends StatelessWidget {
  final String actorName;
  final String abilityName;
  final String targetName;
  final List<LogRollBreakdown> rolls;
  final List<String> statusEffectsApplied;
  final int healthAfter;
  final bool died;
  const RollBreakdownView({
    super.key,
    required this.actorName,
    required this.abilityName,
    required this.targetName,
    required this.rolls,
    required this.statusEffectsApplied,
    required this.healthAfter,
    required this.died,
  });

  static const _body = TextStyle(
    fontSize: 11.5,
    color: Colors.white60,
    height: 1.4,
  );
  static const _die = TextStyle(color: Palette.accent, fontWeight: FontWeight.w600);
  static const _stat = TextStyle(color: Palette.gold, fontWeight: FontWeight.w600);
  static const _total = TextStyle(color: Colors.white, fontWeight: FontWeight.bold);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        border: const Border(left: BorderSide(color: Palette.accent, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: _body,
              children: [
                TextSpan(text: actorName, style: _total),
                const TextSpan(text: ' used '),
                TextSpan(text: abilityName, style: _total),
                TextSpan(text: ' on $targetName.'),
              ],
            ),
          ),
          if (rolls.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (var i = 0; i < rolls.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i > 0 ? 8 : 0),
                child: _rollBlock(rolls[i], rolls.length > 1 ? i + 1 : null),
              ),
          ],
          if (statusEffectsApplied.isNotEmpty) ...[
            const SizedBox(height: 8),
            _statusSection(),
          ],
          const SizedBox(height: 8),
          _resultLine(),
        ],
      ),
    );
  }

  Widget _rollBlock(LogRollBreakdown b, int? index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (index != null)
              Text(
                'Hit $index  ',
                style: const TextStyle(color: Colors.white38, fontSize: 10.5),
              ),
            _outcomeChip(b),
          ],
        ),
        const SizedBox(height: 3),
        RichText(text: TextSpan(style: _body, children: _toHitSpans(b))),
        if (b.damageDetail != null) ...[
          const SizedBox(height: 3),
          RichText(
            text: TextSpan(style: _body, children: _damageSpans(b.damageDetail!)),
          ),
        ],
      ],
    );
  }

  Widget _outcomeChip(LogRollBreakdown b) {
    final (label, color) = b.isCriticalMiss
        ? ('CRITICAL MISS', Palette.danger)
        : b.isCriticalHit
        ? ('CRITICAL HIT', Palette.good)
        : b.isHit
        ? ('HIT', Palette.accent)
        : ('MISS', Colors.white38);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  InlineSpan _dieSpan(LogDiceRoll r) {
    if (r.mode == RollMode.normal) {
      return TextSpan(text: 'd20 rolled ${r.rawRolls.single}', style: _die);
    }
    final word = r.mode == RollMode.advantage ? 'advantage' : 'disadvantage';
    return TextSpan(
      children: [
        TextSpan(text: 'd20 rolled ${r.rawRolls.join('/')}', style: _die),
        TextSpan(
          text: ' ($word, kept ${r.kept})',
          style: const TextStyle(
            color: Colors.white38,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  List<InlineSpan> _toHitSpans(LogRollBreakdown b) {
    final a = b.attackerRoll;
    final d = b.defenderRoll;
    return [
      const TextSpan(
        text: 'To land, the attack roll has to beat the target’s defense '
            'roll. ',
      ),
      const TextSpan(text: 'Attack: '),
      _dieSpan(a),
      const TextSpan(text: ' + Attack '),
      TextSpan(text: '${a.modifier}', style: _stat),
      const TextSpan(text: ' = '),
      TextSpan(text: '${a.total}', style: _total),
      const TextSpan(text: '.  Defense: '),
      _dieSpan(d),
      const TextSpan(text: ' + Defense '),
      TextSpan(text: '${d.modifier}', style: _stat),
      const TextSpan(text: ' = '),
      TextSpan(text: '${d.total}', style: _total),
      const TextSpan(text: '.  '),
      TextSpan(
        text: '${a.total} ${a.total >= d.total ? '≥' : '<'} ${d.total}',
        style: _total,
      ),
      TextSpan(text: b.isHit ? ', so it lands.' : ', so it misses.'),
      if (b.isCriticalHit)
        const TextSpan(
          text: ' The roll hit the critical range, so the damage is doubled.',
          style: TextStyle(color: Palette.good),
        ),
      if (b.isCriticalMiss)
        const TextSpan(
          text: ' A critical miss — the attack fails outright.',
          style: TextStyle(color: Palette.danger),
        ),
    ];
  }

  List<InlineSpan> _damageSpans(LogDamageDetail d) {
    if (d.prevented) {
      return const [
        TextSpan(
          text: 'Damage: fully prevented (blocked or warded), so 0 gets '
              'through.',
          style: TextStyle(color: Palette.accent),
        ),
      ];
    }
    final spans = <InlineSpan>[
      const TextSpan(text: 'Damage starts from the ability’s own dice: '),
      TextSpan(text: d.diceDescribe, style: _die),
      const TextSpan(text: ' = '),
      TextSpan(text: '${d.diceTotal}', style: _total),
    ];
    if (d.preCritMultiplier != 1.0) {
      final after = (d.diceTotal * d.preCritMultiplier).round();
      spans.addAll([
        const TextSpan(text: '. Team Spirit / perk bonus '),
        TextSpan(
          text: '×${d.preCritMultiplier.toStringAsFixed(2)}',
          style: _stat,
        ),
        const TextSpan(text: ' → '),
        TextSpan(text: '$after', style: _total),
      ]);
    }
    if (d.criticalHitApplied) {
      spans.addAll([
        const TextSpan(
          text: '. Critical hit: the damage dice are rolled again for ',
          style: TextStyle(color: Palette.good),
        ),
        TextSpan(text: '+${d.criticalBonusDamage}', style: _die),
        const TextSpan(text: ' (the flat bonus is not doubled) → '),
        TextSpan(text: '${d.afterCriticalHit}', style: _total),
      ]);
    }
    spans.addAll([
      const TextSpan(text: '. The target’s Armor '),
      TextSpan(text: '${d.armor}', style: _stat),
      const TextSpan(text: ' soaks some → '),
      TextSpan(text: '${d.afterArmor}', style: _total),
    ]);
    if (d.statusDamageTypeMultiplier != 1.0 || d.damageResistanceApplied) {
      final combined =
          d.statusDamageTypeMultiplier * (d.damageResistanceApplied ? 0.5 : 1);
      spans.addAll([
        const TextSpan(text: '. Resistance / vulnerability '),
        TextSpan(text: '×${combined.toStringAsFixed(2)}', style: _stat),
      ]);
    }
    spans.addAll([
      const TextSpan(text: '. Final: '),
      TextSpan(
        text: '${d.finalDamage} damage',
        style: const TextStyle(color: Palette.danger, fontWeight: FontWeight.bold),
      ),
      const TextSpan(text: '.'),
    ]);
    return spans;
  }

  Widget _statusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Status effects applied:',
          style: TextStyle(
            color: Palette.accent,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        for (final name in statusEffectsApplied)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: RichText(
              text: TextSpan(
                style: _body,
                children: [
                  TextSpan(text: '• $name', style: _total),
                  if (_statusExplain(name).isNotEmpty)
                    TextSpan(text: ' — ${_statusExplain(name)}'),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _resultLine() {
    return RichText(
      text: TextSpan(
        style: _body,
        children: [
          const TextSpan(text: 'Result: '),
          TextSpan(text: targetName, style: _total),
          const TextSpan(text: ' is now at '),
          TextSpan(text: '$healthAfter HP', style: _total),
          if (died)
            const TextSpan(
              text: ' and is defeated.',
              style: TextStyle(color: Palette.danger, fontWeight: FontWeight.bold),
            )
          else
            const TextSpan(text: '.'),
        ],
      ),
    );
  }

  /// A short plain-language description of what a status effect does, built
  /// from its mechanical definition (there is no authored prose to read).
  String _statusExplain(String displayName) {
    StatusEffectDefinition? def;
    for (final d in StatusEffectCatalog.defaultCatalog.all) {
      if (d.name == displayName) {
        def = d;
        break;
      }
    }
    if (def == null) return '';
    final bits = <String>[];
    if (def.preventsActions) bits.add('the target can’t act');
    for (final s in def.zeroedStats) {
      bits.add('${statLabel[s] ?? s.name} drops to 0');
    }
    def.flatStatModifiers.forEach((stat, v) {
      final n = v == v.roundToDouble() ? v.round().toString() : v.toString();
      bits.add('${v > 0 ? '+' : ''}$n ${statLabel[stat] ?? stat.name}');
    });
    if (def.perRemainingTurnStatModifiers.isNotEmpty) {
      bits.add('grows stronger each turn');
    }
    final dur = def.defaultDurationTurns;
    if (bits.isEmpty) {
      return dur != null ? 'lasts $dur turn${dur == 1 ? '' : 's'}' : '';
    }
    final tail = dur != null ? ' for $dur turn${dur == 1 ? '' : 's'}' : '';
    return '${bits.join(', ')}$tail';
  }
}

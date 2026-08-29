import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../data/describe.dart';
import '../ui/notched.dart';
import '../ui/palette.dart';
import 'game_icons.dart';
import 'status_role_icons.dart';

/// The Full Arms Trigger indicator, shown next to a character whose FAT
/// roll succeeded this turn.
class FatBadge extends StatelessWidget {
  const FatBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          'Full Arms Trigger is active: up to 3 ability uses this turn instead of 1.',
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Palette.warn.withValues(alpha: 0.15),
          border: Border.all(color: Palette.warn),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(GameIcons.burst, size: 11, color: Palette.warn),
            Text(
              'FAT',
              style: TextStyle(
                color: Palette.warn,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Bail Out pill: this operator is leaving, but their body is still on
/// the board for one contested turn.
///
/// Deliberately colourless. Amber is the Full Arms Trigger, gold is critical
/// hits and stat values, red is death, cyan is status effects and your own
/// squad, green is healing and violet is a bent shot: every hue in this
/// interface already means something, and the one hue left (a cold blue) sits
/// right on top of your own squad's cyan. Drained of colour is also what the
/// state is, so it is the honest reading rather than a leftover.
class BailingOutBadge extends StatelessWidget {
  /// Whose body it is, which decides what the player can do about it.
  final bool isOwnSquad;

  const BailingOutBadge({super.key, required this.isOwnSquad});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isOwnSquad
          ? 'Bailing out. The operator is leaving the engagement and cannot '
              'act, be healed or be moved. Their body still screens whoever '
              'is behind it. If the enemy leaves it alone until the end of '
              'their next turn it is recalled and your squad banks the Trion '
              'Salvage; if they hit it, the body is destroyed and the Salvage '
              'is lost.'
          : 'Bailing out. The body is still standing there, still screening, '
              'and one hit of any size destroys it. Destroying it denies them '
              'the Trion Salvage and pays your squad a smaller share; leaving '
              'it alone lets them bank the lot at the end of your next turn.',
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white54),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text(
          'BAILING OUT',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// One status effect on a character: a 19x19 notched square carrying a role
/// glyph, a valence colour, a stack pip row and a depleting duration rule.
/// Tapping it shows the full description and expands it into a named pill.
///
/// A playtest called the badges too small and their numbers unreadable. The
/// measurement said size was not the problem. Ninety-nine characters in a
/// hundred carry three effects or fewer (six is the most ever measured across
/// 42,614 samples), so the square was small to solve a crowding problem the
/// game does not have. What it actually lacked was information: all 62 effects
/// drew one shared icon in one shared cyan, so a bleed killing you and a ward
/// protecting you were the same picture, and the two 8-pixel corner digits
/// were the only differentiated pixels on the badge.
///
/// So the same footprint now carries four facts and **no text at all**:
///
/// - **What kind of effect**, from [StatusRoleX.role]: sixteen glyphs, drawn
///   from fields the definition already declares.
/// - **Whose side it is on**, from [StatusRoleX.valence]: red for harm, green
///   for help, violet for a trade that is genuinely neither.
/// - **How deep it is piled**, as up to three pips along the top edge. The cap
///   is three and the deepest pile ever measured is three, so a count that
///   small is better shown than spelled.
/// - **How close it is to gone**, as a rule along the bottom edge, amber on
///   the last turn. The rule is an absolute scale (three turns fills it), not
///   a fraction of the original duration, so two effects with two turns left
///   look alike, which is the comparison worth making.
class StatusBadge extends StatefulWidget {
  final String name;
  final int? remainingTurns;

  /// How many times this effect has stacked (item 5b). Three stacks of
  /// Bleeding is three times the damage, so a player who cannot see the count
  /// cannot judge the threat.
  final int stacks;

  /// The catalog id, which is what the glyph, the colour and the description
  /// are all read from. Optional only because a few callers still have
  /// nothing but a name to hand; without it the badge falls back to the
  /// neutral treatment.
  final String? id;

  /// Whether this badge sits on one of the player's own characters, which
  /// decides whose turns the remaining duration is counted in.
  final bool onSelf;

  /// Three turns fills the duration rule. Every effect in the catalogue runs
  /// 1 to 3 turns today; anything longer simply arrives full.
  static const fullDurationTurns = 3;

  /// Widget keys, so a test can ask what a badge is showing without reading
  /// colours off a border or measuring a bar.
  static const compactKey = 'status-badge-compact';
  static const expandedKey = 'status-badge-expanded';
  static const durationKey = 'status-badge-duration';
  static String pipKey(int index, {required bool lit}) =>
      'status-badge-pip-${lit ? 'on' : 'off'}-$index';

  const StatusBadge({
    super.key,
    required this.name,
    this.remainingTurns,
    this.id,
    this.onSelf = true,
    this.stacks = 1,
  });

  @override
  State<StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<StatusBadge> {
  /// Tapped open into the named pill. Per-badge rather than per-strip, so
  /// two effects can be held open side by side to compare them.
  bool _expanded = false;

  StatusEffectDefinition? get _definition {
    final id = widget.id;
    if (id == null) return null;
    final catalog = StatusEffectCatalog.defaultCatalog;
    return catalog.contains(id) ? catalog[id] : null;
  }

  StatusRole get _role => _definition?.role ?? StatusRole.special;

  /// Red for harm, green for help, violet for a trade. Violet is already the
  /// log's colour for a bent shot and nothing else, and "this one cuts both
  /// ways" is the same kind of statement.
  Color get _color => switch (_definition?.valence ?? StatusValence.neutral) {
        StatusValence.harmful => Palette.danger,
        StatusValence.helpful => Palette.good,
        StatusValence.neutral => Palette.bend,
      };

  bool get _lastTurn => widget.remainingTurns == 1;

  @override
  Widget build(BuildContext context) {
    final message = widget.id == null
        ? widget.name
        : describeStatusBadge(
            id: widget.id!,
            name: widget.name,
            remainingTurns: widget.remainingTurns,
            onSelf: widget.onSelf,
            stacks: widget.stacks,
          );
    // The tooltip still opens on the same tap that expands the badge, so
    // tapping never costs the player the description it used to give them.
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      onTriggered: () => setState(() => _expanded = !_expanded),
      child: _expanded ? _pill() : _square(),
    );
  }

  /// The resting state: 19x19, four facts, no text.
  Widget _square() {
    return Container(
      key: const Key(StatusBadge.compactKey),
      width: 19,
      height: 19,
      decoration: ShapeDecoration(
        color: Palette.panel,
        shape: OpenNotchBorder(side: BorderSide(color: _color), notch: 5),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The glyph is centred and never moved. The pip row and the
          // duration rule are sized to clear it: at 19 pixels there is
          // exactly enough room for a 10-pixel glyph with a hair either side,
          // and shunting it around to make space is what made an earlier
          // draft read as three stacked bands rather than one badge.
          StatusRoleIcon(role: _role, color: _color, size: 10),
          if (widget.stacks > 1) Positioned(top: 2, child: _pips()),
          if (widget.remainingTurns != null)
            Positioned(left: 3, right: 3, bottom: 2, child: _durationRule()),
        ],
      ),
    );
  }

  /// Three pips, lit to the count, unlit ones left as a dim track.
  ///
  /// The track is what makes the count readable: two lit pips only says
  /// "two of three" if the third is visibly there and unlit. Lit in the
  /// badge's own valence colour rather than a colour of their own, so amber
  /// on this badge means exactly one thing (see [_durationRule]).
  Widget _pips() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            key: Key(StatusBadge.pipKey(i, lit: i < widget.stacks)),
            width: 2.5,
            height: 1.5,
            margin: EdgeInsets.only(left: i == 0 ? 0 : 1),
            color: i < widget.stacks ? _color : Colors.white24,
          ),
      ],
    );
  }

  /// A rule that shortens as the turns run out, over a dim track that stays
  /// put. "About to expire" is a thing to see, not a digit to read, and the
  /// track is what turns a short fill into "nearly gone" rather than a stray
  /// mark in the corner.
  ///
  /// Amber on the last turn, on a buff and a debuff alike: it is the one
  /// warning colour on the badge, which is why the pips do not use it.
  Widget _durationRule() {
    final turns = widget.remainingTurns!.clamp(0, StatusBadge.fullDurationTurns);
    return SizedBox(
      height: 1.5,
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.white24)),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              key: const Key(StatusBadge.durationKey),
              widthFactor: turns / StatusBadge.fullDurationTurns,
              // Both factors, or the ColoredBox has no child to take its
              // height from and collapses to an invisible nothing over the
              // track.
              heightFactor: 1,
              child: ColoredBox(color: _lastTurn ? Palette.warn : _color),
            ),
          ),
        ],
      ),
    );
  }

  /// Tapped open: the same four facts, spelled out. This is the answer to
  /// "which one is this again" that does not cost a trip to the description
  /// panel, and the space for it is there because almost nobody is carrying
  /// more than three effects.
  Widget _pill() {
    return Container(
      key: const Key(StatusBadge.expandedKey),
      height: 19,
      padding: const EdgeInsets.only(left: 4, right: 5),
      decoration: ShapeDecoration(
        color: Palette.panel,
        shape: OpenNotchBorder(side: BorderSide(color: _color), notch: 5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusRoleIcon(role: _role, color: _color, size: 10),
          const SizedBox(width: 4),
          Text(
            widget.name.toUpperCase(),
            style: TextStyle(
              color: _color,
              fontSize: 9,
              height: 1.1,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          if (widget.stacks > 1) ...[
            const SizedBox(width: 4),
            Text(
              'x${widget.stacks}',
              style: const TextStyle(
                // Not amber. On this badge amber means one thing, and that
                // thing is the last turn.
                color: Colors.white70,
                fontSize: 9,
                height: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (widget.remainingTurns != null) ...[
            const SizedBox(width: 4),
            Text(
              '${widget.remainingTurns}t',
              style: TextStyle(
                color: _lastTurn ? Palette.warn : Colors.white54,
                fontSize: 9,
                height: 1.1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

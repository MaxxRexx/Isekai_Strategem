import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../data/describe.dart';
import '../game/draft.dart';
import '../ui/palette.dart';
import '../widgets/black_trigger_ability_list.dart';
import '../widgets/game_icons.dart';
import '../widgets/status_role_icons.dart';
import '../widgets/trigger_icons.dart';

/// A condensed reference for the rules: Loadout drafting, Resonance, turn
/// structure, Trion, FAT, Team Spirit, combat resolution, stats, Side Effects,
/// status effects, and the full Trigger/Black Trigger catalogs.
///
/// Presented as an instant sub-tab switcher (Rules / Side Effects /
/// Status Effects
/// / Triggers / Black Triggers) rather than one long scrolling strip, the
/// same pattern the app's top-level Play/Simulate/Guide tabs already use.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 5,
    vsync: this,
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('How to Play'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Palette.accent,
          labelColor: Palette.accent,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Rules'),
            Tab(text: 'Side Effects'),
            Tab(text: 'Status Effects'),
            Tab(text: 'Triggers'),
            Tab(text: 'Black Triggers'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _rulesTab(),
            _sideEffectsTab(),
            _statusEffectsTab(),
            _triggersTab(),
            _blackTriggersTab(),
          ],
        ),
      ),
    );
  }

  Widget _rulesTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'A condensed reference for everything below. The full write-up '
            'lives in the repo\'s docs/game_design.md.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        _section(
          icon: GameIcons.book,
          title: 'Before the Battle: Draft Your Loadout',
          children: const [
            _Bullet(
              'Trion Capacity budget. Every character has a Trion Capacity stat (100-130). Everything you equip, Triggers and your Black Trigger, has an equip cost, and the total can\'t exceed this budget.',
            ),
            _Bullet(
              'Exactly 4 active abilities. A valid Loadout provides exactly 4 active abilities total. A Black Trigger\'s own active abilities (0-2 of them) count toward this.',
            ),
            _Bullet(
              '8 equipped items, max. Triggers plus your Black Trigger (if any), counted together, can\'t exceed 8.',
            ),
            _Bullet(
              'One Black Trigger, optional. It can contribute active abilities, passive abilities, and/or a World ability, a battle-wide effect distinct from a stat bonus.',
            ),
            _Bullet(
              'Any character can equip anything. Your character\'s type never blocks equipping a Trigger of a different flavor. The only place type matters is Resonance, below.',
            ),
          ],
        ),
        _section(
          icon: GameIcons.blackTrigger,
          title: 'Resonance: How Well a Black Trigger Suits Your Character',
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'A Black Trigger has its own type. How well that matches '
                'your character\'s type sets a Resonance Grade, which '
                'multiplies that Black Trigger\'s damage/healing, divides '
                'its cooldowns, and scales its passive/World ability '
                'magnitudes.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            const _ResonanceTable(),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Grade multipliers: A = 1.5x, B = 1.15x, C = 1.0x, D = '
                '0.85x. A mismatched Black Trigger isn\'t illegal, just '
                'weaker.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
          ],
        ),
        _section(
          icon: GameIcons.ranged,
          title: 'Ability Type and Range Band',
          children: const [
            _Plain(
              'These are two different tags and it is worth keeping them apart. The ABILITY TYPE is what kind of ability it is: Melee, Ranged, or Psychic, 20 Triggers each. The RANGE BAND is how far away you can be when you use it: Close, Mid, or Long Range, also 20 each. Every ability type appears in every band.',
            ),
            _Bullet(
              'Close Range (20). You have to be right there. Mostly blades and fists, but also the point-blank shots (Scattershot, Pepper Shot) and the psychic effects that need contact (Charm Whisper, Soul Siphon, Memory Theft).',
            ),
            _Bullet(
              'Mid Range (20). You can see them clearly and reach them without being on top of each other. Sustained fire, poisons and traps you set nearby, and the psychic effects that only need eye contact.',
            ),
            _Bullet(
              'Long Range (20). Across the field. Sniper work, thrown and area ordnance, the broad psychic waves, and the melee moves that cross the gap to land: Piercing Thrust is a lunge, Rally Cry is a shout that carries, Martyr\'s End reaches everyone.',
            ),
            _Plain(
              'The band matters because several effects only touch attacks made at a distance. Threatened and Blinded penalize the rolls of Mid and Long Range attacks and leave Close Range alone, Blinded also cuts how many targets they can reach, and Frozen Tempo sabotages the cooldowns of anyone who attacks it from range. A Close Range build is quietly resistant to that whole family of debuffs.',
            ),
          ],
        ),
        _section(
          icon: GameIcons.burst,
          title: 'Turn Structure',
          children: const [
            _Bullet(
              'A turn belongs to a whole team, not one character. Any/all of your 3 living members may act.',
            ),
            _Bullet(
              'A round is one turn for each team. Teams alternate; the round counter increments once both sides have gone.',
            ),
            _Bullet(
              'Who moves first is earned, not flipped for. The opening turn is weighted by each squad\'s Team Efficiency Grade: two squads on the same grade are even, and every grade of separation shifts the odds 5 points, up to 65/35. A worse-graded squad still takes the opening move better than one time in three.',
            ),
            _Bullet(
              'First-move handicap: whichever team acts first in the battle gets a reduced Trion gain roll on that single opening turn only, forced to the lowest tier. Moving first is an advantage you pay a little for.',
            ),
            _Plain(
              'At the start of your team\'s turn: your team rolls for Trion gain, status effects tick for each living member, and Full Arms Trigger (FAT) is rolled per character. Normally each character gets 1 ability use per turn; if FAT triggers for them, they get up to 3 instead.',
            ),
          ],
        ),
        _section(
          icon: GameIcons.passive,
          title: 'Trion: Two Separate Resources',
          children: const [
            _Bullet(
              'Trion Capacity (per character): your Loadout budget, spent once during drafting. Doesn\'t change in battle.',
            ),
            _Bullet(
              'Trion Pool (per team, starts empty): the in-battle currency spent to use abilities, refilled each of your team\'s turns via the Trion gain roll. Shared by your whole team.',
            ),
            _Plain(
              'Each turn you roll for a tier of Trion income: Low (10), Medium (20), or High (35), as two upgrade checks in sequence. Higher Trion Affinity raises your odds of a bigger income turn.',
            ),
          ],
        ),
        _section(
          icon: GameIcons.status,
          title: 'Full Arms Trigger (FAT)',
          children: const [
            _Plain(
              'FAT is rolled per character at the start of your turn, using their FAT Chance stat plus a Team Spirit bonus. If it triggers, that character may use up to 3 abilities that turn instead of 1.',
            ),
            _Plain(
              'Chaining 2 or more abilities via FAT in the same turn carries a real cost for that character only: all cooldowns used that turn are doubled, their Trion Affinity is halved for their next turn, and FAT itself goes on a 3-turn cooldown before it can trigger for them again. Using only 1 ability in a FAT-triggered turn avoids this penalty entirely.',
            ),
          ],
        ),
        _section(
          icon: Icons.groups,
          title: 'Team Spirit: a Dual-Direction Stat',
          children: const [
            _Plain(
              'Team Spirit runs 0-100 with 50 as a neutral midpoint, and pulls in two different directions depending which side of the midpoint you\'re on:',
            ),
            _Bullet(
              'Below 50 (aggressive end): bonus single-target damage, bonus Burst damage, and bonus Critical Chance, all scaling toward the extreme.',
            ),
            _Bullet(
              'Above 50 (sustain end): bonus Health Regeneration amount when healed, and bonus FAT Chance.',
            ),
            _Plain(
              'A character sitting exactly at 50 gets neither bonus. It\'s a build axis, not a stat to always maximize.',
            ),
          ],
        ),
        _section(
          icon: GameIcons.melee,
          title: 'Combat Resolution',
          children: const [
            _Plain(
              'An attack is an opposed roll: the attacker rolls d20 + Attack, the target rolls d20 + Defense. The attacker wins ties. A natural 1 on the attacker\'s die is always a critical miss (automatic failure, and inflicts a 1-turn penalty on the attacker). A roll at or above a threshold set by the attacker\'s Critical Chance is always a critical hit (automatic success, and the damage dice are rolled twice).',
            ),
            _Plain(
              'A critical hit rolls the ability\'s damage dice a second time; the ability\'s flat damage bonus is not doubled. Even the best Critical Chance build only crits on a natural 17 or higher, so crits reward a good build without deciding matches on their own.',
            ),
            _Plain(
              'Both sides roll the same die, so what decides a hit is the gap between the attacker\'s Attack and the target\'s Defense. Those numbers are kept deliberately close together (Attack 4 to 14, Defense 2 to 12) so that gap always fits inside the d20\'s range: a Support swinging at a tank lands about one attack in five, a glass cannon against another glass cannon lands about four in five, and everything else falls in between. The roll is never a formality, and a +2 from a buff or a piece of equipment is worth a real 10%.',
            ),
            _Plain(
              'Damage resolution order once a hit lands: the critical dice bonus, then flat Armor reduction (floored at 0), then damage-type multiplier (status effects like Wet, or a granted Damage Resistance). A World ability\'s damage-prevention charge, if any remain, fully negates the whole instance before any of this.',
            ),
          ],
        ),
        _section(
          icon: GameIcons.passive,
          title: 'Character Stats',
          children: const [
            _Plain('Every character card shows the same 10 base stats:'),
            _Bullet(
              'TC (Trion Capacity). Your Loadout budget (100-130), spent once during drafting. Doesn\'t change in battle.',
            ),
            _Bullet(
              'TA (Trion Affinity). Raises your team\'s chance of a higher Trion gain tier each turn.',
            ),
            _Bullet(
              'TS (Team Spirit). A dual-direction stat, see above: below 50 boosts damage and Critical Chance, above 50 boosts Health Regeneration and FAT Chance.',
            ),
            _Bullet(
              'ARM (Armor). Flat damage reduction, applied after the critical dice bonus and before damage-type multipliers.',
            ),
            _Bullet(
              'ATK (Attack). Added to the attacker\'s d20 roll during combat resolution. It runs 4 to 14 across the roster.',
            ),
            _Bullet(
              'DEF (Defense). Added to the defender\'s d20 roll during combat resolution. It runs 2 to 12 across the roster.',
            ),
            _Bullet(
              'CRIT (Critical Chance). Raises the odds of a critical hit (automatic success, damage dice rolled twice). Higher values lower the natural roll needed to crit, from a natural 20 down to a natural 17 at the maximum.',
            ),
            _Bullet(
              'FAT (FAT Chance). Odds of Full Arms Trigger activating on a character\'s turn, allowing up to 3 ability uses instead of 1.',
            ),
            _Bullet(
              'INFL (Status Effect Infliction). Compared against a target\'s Status Effect Resistance to determine whether a status effect you inflict actually lands.',
            ),
            _Bullet(
              'RES (Status Effect Resistance). Subtracted from an attacker\'s infliction roll when they try to inflict a status effect on you.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _sideEffectsTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Every character has one innate Side Effect, always active '
            'regardless of Loadout, that combines with whatever you equip. '
            'Nothing in the engine special-cases a Side Effect by name, '
            'they\'re just data read by the same generic rules as everything '
            'else.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        for (final c in roster.all)
          _GuideEntry(
            icon: Icon(
              GameIcons.forCharacterType(c.type),
              size: 14,
              color: Palette.accent,
            ),
            title: c.name,
            meta: typeLabel[c.type]!,
            body: '${c.sideEffect?.name ?? 'No Side Effect'}. '
                '${c.sideEffect?.description ?? ''}',
          ),
      ],
    );
  }

  /// Every status effect, read straight off the catalogue.
  ///
  /// This tab used to run on a hand-written map of 49 names with its own
  /// durations and effect text, beside a catalogue of 62. The gap was the
  /// predictable one: thirteen effects were missing outright, Empowered's
  /// duration was a turn short, Electrocuted still claimed a flat 3 where it
  /// rolls 1d4, Enraged never mentioned the Psychic immunity or the random
  /// targeting item 3b gave it, and Radiant Blessing still promised +10
  /// maximum health that had been deliberately taken out. Every one of those
  /// is a rules reference telling a player something untrue.
  ///
  /// It is generated now, by the same `describeStatusEffect` the battle
  /// screen's badges and tooltips use, so there is one source of truth and a
  /// re-tuned magnitude updates the guide for free.
  Widget _statusEffectsTab() {
    final effects = StatusEffectCatalog.defaultCatalog.all.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${effects.length} status effects, all expressed as data against '
            'the same generic definition. Duration is in turns, ticked down '
            'at the end of the holder\'s own turn, so an effect that says two '
            'turns covers their next two. The icon and its colour are the '
            'same ones the badges use in battle: what kind of thing the '
            'effect is, and whether it helps you, hurts you, or does both.',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        for (final def in effects)
          _GuideEntry(
            icon: _statusRoleIcon(def.name),
            title: def.name,
            meta: def.defaultDurationTurns == null
                ? 'until removed'
                : '${def.defaultDurationTurns} turn'
                    '${def.defaultDurationTurns == 1 ? '' : 's'}',
            body: describeStatusEffect(
              def,
              onSelf: true,
              includeDuration: false,
            ),
          ),
      ],
    );
  }

  /// The badge glyph for a status named in the guide, matched to the
  /// catalogue by display name. Falls back to the generic status icon for
  /// anything named here that the catalogue does not carry.
  Widget _statusRoleIcon(String name) {
    final def = StatusEffectCatalog.defaultCatalog.all
        .where((d) => d.name == name)
        .firstOrNull;
    if (def == null) {
      return const Icon(GameIcons.status, size: 14, color: Palette.accent);
    }
    return StatusRoleIcon(
      role: def.role,
      size: 14,
      color: switch (def.valence) {
        StatusValence.harmful => Palette.danger,
        StatusValence.helpful => Palette.good,
        StatusValence.neutral => Palette.bend,
      },
    );
  }

  Widget _triggersTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            '40 regular Triggers (active and passive) form the shared '
            'draft pool, any character may equip any of them regardless of '
            'their own type. "Avg" damage/heal figures are the expected '
            'value of the dice before Armor/resistances/Team Spirit/'
            'Side Effect '
            'modifiers are applied.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        for (final t in triggerCatalog.all)
          _GuideEntry(
            icon: TriggerIcon(trigger: t, size: 14),
            title: t.name,
            meta: t is ActiveTrigger
                ? '${t.category.name} - ${t.rangeTag.label} - ${t.abilitySubtype.name}'
                : '${t.category.name} - passive',
            body: describeTrigger(t),
          ),
      ],
    );
  }

  Widget _blackTriggersTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Each character may equip at most one. A Black Trigger can '
            'carry active abilities (count toward the Loadout\'s required '
            '4), passive abilities (always on), and/or a World ability (a '
            'battle-wide effect, distinct from a passive stat bonus).',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        for (final bt in blackTriggerCatalog.all)
          _GuideEntry(
            icon: BlackTriggerIcon(blackTrigger: bt, size: 14),
            title: bt.name,
            meta:
                '${blackTriggerTypeLabel[bt.type]} type - equip ${bt.equipCost}',
            body: null,
            bodyWidget: BlackTriggerAbilityList(
              blackTrigger: bt,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121822),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Palette.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('- ', style: TextStyle(color: Colors.white38)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Plain extends StatelessWidget {
  final String text;
  const _Plain(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}

class _GuideEntry extends StatelessWidget {
  final Widget icon;
  final String title;
  final String meta;
  final String? body;
  final Widget? bodyWidget;
  const _GuideEntry({
    required this.icon,
    required this.title,
    required this.meta,
    required this.body,
    this.bodyWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          icon,
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      meta,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                bodyWidget ??
                    Text(
                      body ?? '',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResonanceTable extends StatelessWidget {
  const _ResonanceTable();

  @override
  Widget build(BuildContext context) {
    const grid = ResonanceGrid.defaultGrid;
    const charTypes = CharacterType.values;
    const btTypes = BlackTriggerType.values;

    Color gradeColor(ResonanceGrade g) => switch (g) {
      ResonanceGrade.a => Palette.good,
      ResonanceGrade.b => Palette.accent,
      ResonanceGrade.c => Colors.white54,
      ResonanceGrade.d => Palette.danger,
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(64),
        border: TableBorder.all(color: Colors.white12),
        children: [
          TableRow(
            children: [
              _cell('Your Type \\ BT Type', header: true),
              for (final bt in btTypes)
                _cell(blackTriggerTypeLabel[bt]!, header: true),
            ],
          ),
          for (final ct in charTypes)
            TableRow(
              children: [
                _cell(typeLabel[ct]!, header: true),
                for (final bt in btTypes)
                  _cell(
                    grid.lookup(ct, bt).name.toUpperCase(),
                    color: gradeColor(grid.lookup(ct, bt)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(String text, {bool header = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Text(
        text,
        style: TextStyle(
          color: color ?? (header ? Colors.white70 : Colors.white),
          fontSize: 10,
          fontWeight: header ? FontWeight.bold : FontWeight.bold,
        ),
      ),
    );
  }
}

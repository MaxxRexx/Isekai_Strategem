import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import 'data/flavor_text.dart';
import 'game/draft.dart';
import 'quick_battle/quick_battle_screen.dart';
import 'screens/guide_screen.dart';
import 'screens/play_flow_screen.dart';
import 'screens/simulate_screen.dart';
import 'ui/palette.dart';
import 'widgets/player_panel.dart';
import 'widgets/portrait_tile.dart';
import 'widgets/trigger_icons.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late String _featuredId = roster.all.first.id;
  final List<String> _squadIds = [];

  void _tapRosterTile(String id) {
    setState(() {
      _featuredId = id;
      if (_squadIds.contains(id)) {
        _squadIds.remove(id);
      } else if (_squadIds.length < 3) {
        _squadIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final featured = roster[_featuredId];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'ISEKAI STRATEGEM',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                _FeaturedCharacterCard(character: featured),
                const SizedBox(height: 16),
                _ModeTabsRow(
                  onPlay: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlayFlowScreen()),
                  ),
                  onSimulate: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SimulateScreen()),
                  ),
                  onTutorial: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PlayFlowScreen(tutorial: true),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const QuickBattleScreen(),
                        ),
                      ),
                      child: const Text('Quick Battle'),
                    ),
                    const Text('·', style: TextStyle(color: Colors.white24)),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const GuideScreen()),
                      ),
                      child: const Text('How to Play'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _RosterPreviewGrid(
                  featuredId: _featuredId,
                  squadIds: _squadIds,
                  onTap: _tapRosterTile,
                ),
                const SizedBox(height: 16),
                _YourSquadPreview(squadIds: _squadIds),
                const SizedBox(height: 12),
                const PlayerPanel(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "spotlight" card for whichever character is currently featured:
/// portrait, name, a sample 4-ability loadout, and perk copy. The ability
/// tiles are a representative example build (via the same LoadoutBuilder
/// used everywhere else), not a saved/equipped Loadout - nothing persists
/// a per-character default yet.
class _FeaturedCharacterCard extends StatelessWidget {
  final Character character;
  const _FeaturedCharacterCard({required this.character});

  @override
  Widget build(BuildContext context) {
    final sample = loadoutBuilder.build(
      character,
      activeTriggerPool: triggerCatalog.activeTriggers,
      passiveTriggerPool: triggerCatalog.passiveTriggers,
      blackTriggerPool: blackTriggerCatalog.all,
      profile: AiProfile.all.first,
    );
    final sampleActives = sample.triggers.whereType<ActiveTrigger>().toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3EAD3),
        border: Border.all(color: Palette.gold, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PortraitTile(
            characterId: character.id,
            name: character.name,
            type: character.type,
            size: 84,
            showRank: false,
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  character.name.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF241C10),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in sampleActives)
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE4D6B0),
                          border: Border.all(color: const Color(0xFFC9B37E)),
                        ),
                        child: TriggerIcon(
                          trigger: t,
                          size: 22,
                          color: const Color(0xFF6B4F1D),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (characterFlavor[character.id] != null)
                  Text(
                    characterFlavor[character.id]!,
                    style: const TextStyle(
                      color: Color(0xFF4A3D26),
                      fontSize: 12.5,
                    ),
                  ),
                if (character.perk != null) ...[
                  const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${character.perk!.name}: ',
                          style: const TextStyle(
                            color: Color(0xFF241C10),
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                        TextSpan(
                          text: character.perk!.description,
                          style: const TextStyle(
                            color: Color(0xFF4A3D26),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTabsRow extends StatelessWidget {
  final VoidCallback onPlay;
  final VoidCallback onSimulate;
  final VoidCallback onTutorial;

  const _ModeTabsRow({
    required this.onPlay,
    required this.onSimulate,
    required this.onTutorial,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModeTab(icon: Icons.gps_fixed, label: 'Play', onTap: onPlay),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ModeTab(
            icon: Icons.auto_awesome,
            label: 'Simulate',
            iconColor: Palette.teamB,
            onTap: onSimulate,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ModeTab(
            icon: Icons.view_column_outlined,
            label: 'Guided Tutorial',
            onTap: onTutorial,
          ),
        ),
      ],
    );
  }
}

class _ModeTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback onTap;

  const _ModeTab({
    required this.icon,
    required this.label,
    this.iconColor = Palette.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Palette.panel,
          border: Border.all(color: Palette.hairline),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A browsable preview of the full roster: tap a tile to feature it above
/// and toggle it into the 3-slot squad preview below. Purely a showcase -
/// it doesn't feed into Play mode's own squad drafting (yet).
class _RosterPreviewGrid extends StatelessWidget {
  final String featuredId;
  final List<String> squadIds;
  final ValueChanged<String> onTap;

  const _RosterPreviewGrid({
    required this.featuredId,
    required this.squadIds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in roster.all)
          InkWell(
            onTap: () => onTap(c.id),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: squadIds.contains(c.id) || c.id == featuredId
                      ? Palette.accent
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              padding: const EdgeInsets.all(2),
              child: PortraitTile(
                characterId: c.id,
                name: c.name,
                type: c.type,
                size: 56,
                showRank: false,
              ),
            ),
          ),
      ],
    );
  }
}

class _YourSquadPreview extends StatelessWidget {
  final List<String> squadIds;
  const _YourSquadPreview({required this.squadIds});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'YOUR SQUAD',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 10.5,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              i < squadIds.length
                  ? PortraitTile(
                      characterId: squadIds[i],
                      name: roster[squadIds[i]].name,
                      type: roster[squadIds[i]].type,
                      size: 56,
                      showRank: false,
                    )
                  : Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white24,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white24,
                        size: 20,
                      ),
                    ),
            ],
          ],
        ),
      ],
    );
  }
}

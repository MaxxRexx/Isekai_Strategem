import 'package:flutter/material.dart';

import '../game/test_scenarios.dart';
import '../ui/palette.dart';
import 'play_flow_screen.dart';

/// Tests mode: pick a pre-arranged board, read what it is for, and drop
/// straight into a real battle with it.
///
/// Everything under test is the ordinary battle screen. A separate harness
/// would only prove that the harness works, and what these scenarios are
/// checking is whether the real interface explains the rules it is running.
class TestLabScreen extends StatefulWidget {
  const TestLabScreen({super.key});

  @override
  State<TestLabScreen> createState() => _TestLabScreenState();
}

class _TestLabScreenState extends State<TestLabScreen> {
  late TestScenario _selected = testScenarios.first;

  void _launch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayFlowScreen(scenario: _selected)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.background,
      appBar: AppBar(
        backgroundColor: Palette.background,
        title: const Text('Tests'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const Text(
                  'Pre-arranged boards for the two features that are merged '
                  'but have not been played: screening (1b) and Bail Out '
                  '(#2). Each one sets up a case that is hard to reach from '
                  'an ordinary battle, and says what should happen.',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 16),
                _ScenarioPicker(
                  selected: _selected,
                  onChanged: (s) => setState(() => _selected = s),
                ),
                const SizedBox(height: 16),
                _ScenarioBrief(scenario: _selected),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.accent,
                    foregroundColor: Palette.background,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _launch,
                  child: const Text(
                    'START SCENARIO',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'You always move first. Both squads start with plenty of '
                  'Trion so nothing under test is blocked by the economy.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScenarioPicker extends StatelessWidget {
  final TestScenario selected;
  final ValueChanged<TestScenario> onChanged;

  const _ScenarioPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Palette.panel,
        border: Border.all(color: Palette.hairline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<TestScenario>(
          value: selected,
          isExpanded: true,
          dropdownColor: Palette.panel,
          borderRadius: BorderRadius.zero,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          onChanged: (s) {
            if (s != null) onChanged(s);
          },
          items: [
            for (final s in testScenarios)
              DropdownMenuItem(
                value: s,
                child: Row(
                  children: [
                    _ItemChip(item: s.item),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemChip extends StatelessWidget {
  final String item;
  const _ItemChip({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Palette.accent.withValues(alpha: 0.15),
        border: Border.all(color: Palette.accent.withValues(alpha: 0.5)),
      ),
      child: Text(
        item,
        style: const TextStyle(
          color: Palette.accent,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// The scenario's goal, steps, expectations and caveat. Shown on the picker
/// and again inside the battle, because a tester who has to remember six
/// bullet points across four turns will not.
class ScenarioBriefBody extends StatelessWidget {
  final TestScenario scenario;
  const ScenarioBriefBody({super.key, required this.scenario});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          scenario.goal,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 14),
        _BriefList(
          label: 'What to do',
          entries: scenario.orderedSteps,
          numbered: true,
          color: Palette.accent,
        ),
        const SizedBox(height: 14),
        _BriefList(
          label: 'What should happen',
          entries: scenario.expectations,
          numbered: false,
          color: Palette.good,
        ),
        if (scenario.caveat != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Palette.warn.withValues(alpha: 0.10),
              border: Border(
                left: BorderSide(color: Palette.warn, width: 3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 14, color: Palette.warn),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    scenario.caveat!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ScenarioBrief extends StatelessWidget {
  final TestScenario scenario;
  const _ScenarioBrief({required this.scenario});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.panel,
        border: Border.all(color: Palette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            scenario.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ScenarioBriefBody(scenario: scenario),
        ],
      ),
    );
  }
}

class _BriefList extends StatelessWidget {
  final String label;
  final List<String> entries;
  final bool numbered;
  final Color color;

  const _BriefList({
    required this.label,
    required this.entries,
    required this.numbered,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    numbered ? '${i + 1}.' : '•',
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    entries[i],
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

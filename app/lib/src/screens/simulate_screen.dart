import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/battle_models.dart';
import '../game/draft.dart';
import '../game/report.dart';
import '../game/simulate.dart';
import '../ui/palette.dart';
import '../widgets/fighter_row.dart';
import '../widgets/log_view.dart';
import '../widgets/outcome_banner.dart';
import '../widgets/pickers.dart';

/// Simulate mode: draft two AI-controlled squads and profiles, then run
/// one full battle in one shot and inspect the log/results.
class SimulateScreen extends StatefulWidget {
  const SimulateScreen({super.key});

  @override
  State<SimulateScreen> createState() => _SimulateScreenState();
}

class _SimulateScreenState extends State<SimulateScreen> {
  final List<String?> _teamAIds = [null, null, null];
  final List<String?> _teamBIds = [null, null, null];
  String? _profileAId;
  String? _profileBId;
  int _maxRounds = 40;
  String? _error;
  bool _running = false;

  SimulationConfig? _lastConfig;
  SimulationResult? _result;

  @override
  void initState() {
    super.initState();
    _randomizeTeam(_teamAIds, (id) => _profileAId = id);
    _randomizeTeam(_teamBIds, (id) => _profileBId = id);
  }

  /// Each squad only has to avoid itself: both may field the same character
  /// since item #14.
  void _randomizeTeam(
    List<String?> slots,
    void Function(String) setProfile,
  ) {
    final random = Random();
    final picked = randomSquadAvoiding(random, slots);
    for (var i = 0; i < 3; i++) {
      slots[i] = picked[i];
    }
    setProfile(AiProfile.all[random.nextInt(AiProfile.all.length)].id);
  }

  /// Every other slot on the same squad. The opposing squad is not excluded:
  /// mirror matches are supported since item #14.
  Set<String> _takenExcept(List<String?> slots, int slot) => {
    for (var i = 0; i < slots.length; i++)
      if (i != slot && slots[i] != null) slots[i]!,
  };

  void _engage() {
    final teamAIds = _teamAIds.whereType<String>().toList();
    final teamBIds = _teamBIds.whereType<String>().toList();
    if (teamAIds.toSet().length != 3 || teamBIds.toSet().length != 3) {
      setState(() => _error = 'Each squad needs 3 distinct Agents.');
      return;
    }
    if (_profileAId == null || _profileBId == null) {
      setState(() => _error = 'Pick an AI Profile for each squad.');
      return;
    }
    setState(() {
      _error = null;
      _running = true;
    });

    final config = SimulationConfig(
      teamAIds: teamAIds,
      teamBIds: teamBIds,
      teamAProfileId: _profileAId!,
      teamBProfileId: _profileBId!,
      maxRounds: _maxRounds,
    );

    // Yield a frame so the "Simulating..." state actually paints before
    // the (synchronous, potentially 40+ round) engine run blocks it.
    Future<void>.delayed(Duration.zero, () {
      final result = runSimulation(config);
      if (!mounted) return;
      setState(() {
        _lastConfig = config;
        _result = result;
        _running = false;
      });
    });
  }

  Future<void> _copyReport() async {
    if (_lastConfig == null || _result == null) return;
    final report = buildSimulationReport(_lastConfig!, _result!);
    await Clipboard.setData(ClipboardData(text: report));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report copied to clipboard.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Simulate')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _teamPanel(
              label: 'SQUAD A',
              color: Palette.teamA,
              slots: _teamAIds,
              profileId: _profileAId,
              onRandomize: () => setState(
                () => _randomizeTeam(_teamAIds, (id) => _profileAId = id),
              ),
              onProfileChanged: (id) => setState(() => _profileAId = id),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'VS',
                  style: TextStyle(
                    color: Colors.white38,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(width: 16),
                const Text(
                  'Round cap',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: TextFormField(
                    initialValue: '$_maxRounds',
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(isDense: true),
                    onChanged: (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null) {
                        _maxRounds = parsed.clamp(10, 200);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _teamPanel(
              label: 'SQUAD B',
              color: Palette.teamB,
              slots: _teamBIds,
              profileId: _profileBId,
              onRandomize: () => setState(
                () => _randomizeTeam(_teamBIds, (id) => _profileBId = id),
              ),
              onProfileChanged: (id) => setState(() => _profileBId = id),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Palette.danger, fontSize: 12),
                ),
              ),
            ElevatedButton(
              onPressed: _running ? null : _engage,
              child: Text(_running ? 'SIMULATING...' : 'ENGAGE'),
            ),
            if (_result != null) ...[
              const SizedBox(height: 20),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
              _resultsSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _teamPanel({
    required String label,
    required Color color,
    required List<String?> slots,
    required String? profileId,
    required VoidCallback onRandomize,
    required ValueChanged<String> onProfileChanged,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              TextButton(
                onPressed: onRandomize,
                child: const Text('Randomize'),
              ),
            ],
          ),
          ProfileSlot(
            label: 'AI Profile',
            selectedId: profileId,
            onChanged: onProfileChanged,
          ),
          const SizedBox(height: 8),
          for (var slot = 0; slot < 3; slot++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CharacterSlot(
                label: 'Agent ${['I', 'II', 'III'][slot]}',
                selectedId: slots[slot],
                disabledIds: _takenExcept(slots, slot),
                onChanged: (id) => setState(() => slots[slot] = id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultsSection() {
    final result = _result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutcomeBanner(
                outcome: result.outcome,
                note: result.concluded
                    ? 'Concluded in ${result.roundsPlayed} round(s).'
                    : 'Still contesting after ${result.roundsPlayed} rounds (round cap reached), raise the round cap to let it play out further.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _copyReport,
          child: const Text('COPY FULL REPORT'),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TeamPanel(
                label: 'Squad A - Final State',
                color: Palette.teamA,
                fighters: result.finalTeamA,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TeamPanel(
                label: 'Squad B - Final State',
                color: Palette.teamB,
                fighters: result.finalTeamB,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          title: const Text(
            'Drafted Loadouts',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          tilePadding: EdgeInsets.zero,
          children: [
            for (final entry in {
              ...result.teamALoadouts,
              ...result.teamBLoadouts,
            }.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roster[CombatantIds.characterOf(entry.key)].name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'Black Trigger: ${entry.value.blackTrigger?.name ?? 'none'}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      entry.value.triggers.map((t) => t.name).join(', '),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 320,
          child: BattleLogView(rounds: result.rounds, title: 'ENGAGEMENT LOG'),
        ),
      ],
    );
  }
}

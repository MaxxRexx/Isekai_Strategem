import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/describe.dart';
import '../game/battle_models.dart';
import '../game/draft.dart';
import '../game/play_session.dart';
import '../game/report.dart';
import '../game/tutorial.dart';
import '../ui/palette.dart';
import '../widgets/badges.dart';
import '../widgets/fighter_row.dart';
import '../widgets/game_icons.dart';
import '../widgets/log_view.dart';
import '../widgets/outcome_banner.dart';
import '../widgets/pickers.dart';

enum _PlayStep { setup, loadout, battle }

/// A player's in-progress Loadout choices for one character.
class LoadoutSelection {
  final Set<String> triggerIds = {};
  String? blackTriggerId;

  Loadout toLoadout(String characterId) => Loadout(
    characterId: characterId,
    triggers: [for (final id in triggerIds) triggerCatalog[id]],
    blackTrigger: blackTriggerId == null
        ? null
        : blackTriggerCatalog[blackTriggerId!],
  );
}

/// Play mode: draft your own squad and Loadouts, then play turn by turn
/// against an AI opponent. With [tutorial] set, the Guided Tutorial's
/// script locks each step to a single scripted action.
class PlayFlowScreen extends StatefulWidget {
  final bool tutorial;
  const PlayFlowScreen({super.key, this.tutorial = false});

  @override
  State<PlayFlowScreen> createState() => _PlayFlowScreenState();
}

class _PlayFlowScreenState extends State<PlayFlowScreen> {
  _PlayStep _step = _PlayStep.setup;

  final List<String?> _teamAIds = [null, null, null];
  final List<String?> _teamBIds = [null, null, null];
  String? _profileBId;
  String? _setupError;

  final Map<String, LoadoutSelection> _selections = {};
  int _currentLoadoutIndex = 0;
  int _maxVisitedLoadoutIndex = 0;
  String? _loadoutError;

  PlaySession? _session;
  final List<LogRound> _roundsLog = [];

  TutorialState? _tutorial;

  @override
  void initState() {
    super.initState();
    if (widget.tutorial) {
      _tutorial = TutorialState();
      // The tutorial pins the opponent squad and profile; the player's
      // own slots start empty and are filled by the script's steps.
      for (var i = 0; i < 3; i++) {
        _teamBIds[i] = tutorialOpponentIds[i];
      }
      _profileBId = tutorialOpponentProfileId;
    } else {
      _randomizeTeam(_teamAIds, withProfile: false);
      _randomizeTeam(_teamBIds, withProfile: true);
    }
  }

  void _randomizeTeam(List<String?> slots, {required bool withProfile}) {
    final random = Random();
    final pool = roster.all.map((c) => c.id).toList()..shuffle(random);
    for (var i = 0; i < 3; i++) {
      slots[i] = pool[i];
    }
    if (withProfile) {
      _profileBId = AiProfile.all[random.nextInt(AiProfile.all.length)].id;
    }
  }

  bool get _tutorialActive =>
      _tutorial != null && _tutorial!.phase != TutorialPhase.done;

  void _exitTutorial() {
    setState(() => _tutorial?.phase = TutorialPhase.done);
  }

  // ---------------- Setup step ----------------

  void _continueToLoadouts() {
    final ids = _teamAIds.whereType<String>().toList();
    if (ids.length != 3 || ids.toSet().length != 3) {
      setState(() => _setupError = 'Pick 3 distinct Agents for your squad.');
      return;
    }
    setState(() {
      _setupError = null;
      _selections.clear();
      _currentLoadoutIndex = 0;
      _maxVisitedLoadoutIndex = 0;
      _step = _PlayStep.loadout;
      _tutorial?.phase = _tutorialActive
          ? TutorialPhase.loadout
          : TutorialPhase.done;
    });
  }

  // ---------------- Loadout step ----------------

  LoadoutSelection _selectionFor(String charId) =>
      _selections.putIfAbsent(charId, LoadoutSelection.new);

  void _autoFillCurrentLoadout() {
    final charId = _teamAIds[_currentLoadoutIndex]!;
    final profile = AiProfile.all[Random().nextInt(AiProfile.all.length)];
    final loadout = loadoutBuilder.build(
      roster[charId],
      activeTriggerPool: triggerCatalog.activeTriggers,
      passiveTriggerPool: triggerCatalog.passiveTriggers,
      blackTriggerPool: blackTriggerCatalog.all,
      profile: profile,
    );
    setState(() {
      final selection = _selectionFor(charId)
        ..triggerIds.clear()
        ..blackTriggerId = loadout.blackTrigger?.id;
      selection.triggerIds.addAll(loadout.triggers.map((t) => t.id));
    });
  }

  void _confirmLoadout() {
    setState(() {
      _maxVisitedLoadoutIndex = max(
        _maxVisitedLoadoutIndex,
        _currentLoadoutIndex + 1,
      );
      if (_currentLoadoutIndex < 2) {
        _currentLoadoutIndex++;
      } else {
        _startBattle();
      }
    });
  }

  void _startBattle() {
    final playerIds = _teamAIds.whereType<String>().toList();
    try {
      _session = PlaySession.start(
        playerCharacterIds: playerIds,
        playerLoadouts: {
          for (final id in playerIds) id: _selectionFor(id).toLoadout(id),
        },
        opponentCharacterIds: _teamBIds.whereType<String>().toList(),
        opponentProfileId: _profileBId!,
        firstTurn: _tutorialActive ? 'teamA' : 'random',
      );
    } on ArgumentError catch (e) {
      _loadoutError = e.message as String;
      return;
    }
    _roundsLog.clear();
    if (_session!.openingAiRound != null) {
      _roundsLog.add(_session!.openingAiRound!);
    }
    _step = _PlayStep.battle;
    _tutorial?.phase = _tutorialActive
        ? TutorialPhase.battle
        : TutorialPhase.done;
    _afterBattleStateChange();
  }

  // ---------------- Battle step ----------------

  /// Tutorial bookkeeping that runs after every battle state change:
  /// forces FAT at the scripted step, and releases the tutorial once its
  /// script is exhausted (or the battle ends early).
  void _afterBattleStateChange() {
    final tutorial = _tutorial;
    final session = _session;
    if (tutorial == null || session == null) return;
    if (tutorial.phase != TutorialPhase.battle) return;
    if (session.isOver || tutorial.battleScriptFinished) {
      tutorial.phase = TutorialPhase.done;
      return;
    }
    final step = tutorial.currentBattleStep;
    if (step != null &&
        step.isFatStep &&
        !tutorial.fatForced &&
        session.isPlayerTurn) {
      tutorial.fatForced = true;
      tutorial.fatUsesThisRound = 0;
      session.forceFat(step.characterId);
    }
  }

  void _pushPlayerAction(LogAction action) {
    final roundNumber = _session!.roundNumber;
    final existing = _roundsLog.lastOrNull;
    if (existing != null &&
        existing.roundNumber == roundNumber &&
        existing.team == 'A') {
      existing.actions.add(action);
    } else {
      _roundsLog.add(
        LogRound(roundNumber: roundNumber, team: 'A', actions: [action]),
      );
    }
  }

  void _useAbility(
    String characterId,
    LegalAction action,
    List<String> targetIds,
  ) {
    final outcome = _session!.useAbility(
      characterId,
      action.trigger.id,
      targetIds,
    );
    setState(() {
      if (!outcome.success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(outcome.error!)));
        return;
      }
      _pushPlayerAction(outcome.action!);
      _tutorial?.onAbilityUsed(characterId, action.trigger.id);
      _afterBattleStateChange();
    });
  }

  void _endTurn() {
    setState(() {
      _tutorial?.onEndTurn();
      final aiRound = _session!.endTurn();
      _roundsLog.add(aiRound);
      _afterBattleStateChange();
    });
  }

  Future<void> _copyReport() async {
    final session = _session!;
    final report = buildPlayReport(
      playerIds: _teamAIds.whereType<String>().toList(),
      opponentIds: _teamBIds.whereType<String>().toList(),
      opponentProfileId: _profileBId!,
      outcome: session.outcome,
      roundNumber: session.roundNumber,
      teamA: session.teamA,
      teamB: session.teamB,
      loadouts: {...session.loadoutsA, ...session.loadoutsB},
      rounds: _roundsLog,
    );
    await Clipboard.setData(ClipboardData(text: report));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report copied to clipboard.')),
      );
    }
  }

  // ---------------- Build ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.tutorial && _tutorialActive
              ? 'Guided Tutorial'
              : 'Play Battle',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_tutorialActive) _tutorialBanner(),
            Expanded(
              child: switch (_step) {
                _PlayStep.setup => _buildSetupStep(),
                _PlayStep.loadout => _buildLoadoutStep(),
                _PlayStep.battle => _buildBattleStep(),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _tutorialBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.accent.withValues(alpha: 0.08),
        border: Border.all(color: Palette.accent),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'GUIDED TUTORIAL',
                style: TextStyle(
                  color: Palette.accent,
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: _exitTutorial,
                child: const Text('Exit Tutorial'),
              ),
            ],
          ),
          Text(
            _tutorial!.bannerText(
              teamAIds: _teamAIds.whereType<String>().toList(),
              currentLoadoutIndex: _currentLoadoutIndex,
            ),
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupStep() {
    final setupStep = _tutorialActive ? _tutorial!.currentSetupStep : null;
    final lockedByTutorial = _tutorialActive;

    Set<String> takenExcept(List<String?> slots, int slot) => {
      for (var i = 0; i < slots.length; i++)
        if (i != slot && slots[i] != null) slots[i]!,
    };

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _panel(
          borderColor: Palette.teamA,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'YOUR SQUAD',
                  style: TextStyle(
                    color: Palette.teamA,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                TextButton(
                  onPressed: lockedByTutorial
                      ? null
                      : () => setState(
                          () => _randomizeTeam(_teamAIds, withProfile: false),
                        ),
                  child: const Text('Randomize'),
                ),
              ],
            ),
            for (var slot = 0; slot < 3; slot++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CharacterSlot(
                  label: 'Agent ${['I', 'II', 'III'][slot]}',
                  selectedId: _teamAIds[slot],
                  disabledIds: takenExcept(_teamAIds, slot),
                  enabled:
                      !lockedByTutorial ||
                      (setupStep != null && setupStep.slot == slot),
                  lockToCharacterId: lockedByTutorial
                      ? setupStep?.charId
                      : null,
                  onChanged: (id) => setState(() {
                    _teamAIds[slot] = id;
                    _tutorial?.onSetupPick(slot, id);
                  }),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _panel(
          borderColor: Palette.teamB,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'OPPONENT SQUAD',
                  style: TextStyle(
                    color: Palette.teamB,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                TextButton(
                  onPressed: lockedByTutorial
                      ? null
                      : () => setState(
                          () => _randomizeTeam(_teamBIds, withProfile: true),
                        ),
                  child: const Text('Randomize'),
                ),
              ],
            ),
            ProfileSlot(
              label: 'AI Profile',
              selectedId: _profileBId,
              enabled: !lockedByTutorial,
              onChanged: (id) => setState(() => _profileBId = id),
            ),
            const SizedBox(height: 8),
            for (var slot = 0; slot < 3; slot++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CharacterSlot(
                  label: 'Agent ${['I', 'II', 'III'][slot]}',
                  selectedId: _teamBIds[slot],
                  disabledIds: takenExcept(_teamBIds, slot),
                  enabled: !lockedByTutorial,
                  onChanged: (id) => setState(() => _teamBIds[slot] = id),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_setupError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _setupError!,
              style: const TextStyle(color: Palette.danger, fontSize: 12),
            ),
          ),
        ElevatedButton(
          onPressed: _tutorialActive && _tutorial!.currentSetupStep != null
              ? null
              : _continueToLoadouts,
          child: const Text('NEXT: BUILD LOADOUTS'),
        ),
      ],
    );
  }

  Widget _buildLoadoutStep() {
    final charId = _teamAIds[_currentLoadoutIndex]!;
    final character = roster[charId];
    final selection = _selectionFor(charId);
    final loadout = selection.toLoadout(charId);
    final validation = loadout.validateFor(character);
    final tutorialScript = _tutorialActive ? tutorialLoadouts[charId] : null;
    final tutorialValid =
        tutorialScript?.blackTriggerId == null ||
        selection.blackTriggerId == tutorialScript!.blackTriggerId;

    final budget = character.baseStats.trionCapacity;
    final totalCost = loadout.totalEquipCost;
    const rules = LoadoutRulesConfig.defaults;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: _tutorialActive
                  ? null
                  : () => setState(() => _step = _PlayStep.setup),
              child: const Text('< Back to Squad Setup'),
            ),
            for (var i = 0; i < 3; i++) _loadoutNavChip(i),
          ],
        ),
        _panel(
          borderColor: Palette.teamA,
          children: [
            Text(
              '${character.name} - Trion Capacity $budget',
              style: const TextStyle(
                color: Palette.teamA,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text(
                  'Trion Cost',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: budget > 0 ? (totalCost / budget).clamp(0, 1) : 0,
                      minHeight: 8,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(
                        totalCost > budget ? Palette.danger : Palette.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$totalCost / $budget',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Text(
                  'Active Abilities',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(width: 10),
                Text(
                  '${loadout.totalActiveAbilityCount} / ${rules.requiredActiveAbilityCount}',
                  style: TextStyle(
                    color:
                        loadout.totalActiveAbilityCount ==
                            rules.requiredActiveAbilityCount
                        ? Palette.good
                        : Palette.warn,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (!_tutorialActive)
                  TextButton(
                    onPressed: _autoFillCurrentLoadout,
                    child: const Text('Auto-fill'),
                  ),
              ],
            ),
            if (validation.errors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  validation.errors.join(' '),
                  style: const TextStyle(color: Palette.danger, fontSize: 11),
                ),
              ),
            if (_loadoutError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _loadoutError!,
                  style: const TextStyle(color: Palette.danger, fontSize: 11),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _triggerChecklist(
          heading: 'Active Triggers',
          triggers: triggerCatalog.activeTriggers.toList(),
          selection: selection,
          allowedIds: tutorialScript?.triggerIds.toSet(),
        ),
        const SizedBox(height: 12),
        _triggerChecklist(
          heading: 'Passive Triggers',
          triggers: triggerCatalog.passiveTriggers.toList(),
          selection: selection,
          allowedIds: tutorialScript?.triggerIds.toSet(),
        ),
        const SizedBox(height: 12),
        _blackTriggerList(
          character,
          selection,
          allowedId: tutorialScript?.blackTriggerId,
          tutorialLocked: tutorialScript != null,
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: validation.isValid && tutorialValid
              ? _confirmLoadout
              : null,
          child: Text(
            _currentLoadoutIndex < 2
                ? 'CONFIRM LOADOUT'
                : 'CONFIRM LOADOUT & ENGAGE',
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _loadoutNavChip(int index) {
    final charId = _teamAIds[index];
    final reachable = index <= _maxVisitedLoadoutIndex && !_tutorialActive;
    final isCurrent = index == _currentLoadoutIndex;
    return ActionChip(
      label: Text(
        '${index + 1}. ${charId == null ? '?' : roster[charId].name}',
        style: TextStyle(
          fontSize: 11,
          color: isCurrent ? Palette.background : Colors.white70,
        ),
      ),
      backgroundColor: isCurrent ? Palette.accent : Colors.white10,
      onPressed: reachable && !isCurrent
          ? () => setState(() => _currentLoadoutIndex = index)
          : null,
    );
  }

  Widget _triggerChecklist({
    required String heading,
    required List<Trigger> triggers,
    required LoadoutSelection selection,
    Set<String>? allowedIds,
  }) {
    return _panel(
      borderColor: Colors.white12,
      children: [
        Text(
          heading.toUpperCase(),
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        // ListTile paints its background/ink on the nearest Material
        // ancestor; without this, the colored panel Container behind it
        // would block those effects.
        Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              for (final t in triggers)
                CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  value: selection.triggerIds.contains(t.id),
                  onChanged: allowedIds != null && !allowedIds.contains(t.id)
                      ? null
                      : (checked) => setState(() {
                          if (checked == true) {
                            selection.triggerIds.add(t.id);
                          } else {
                            selection.triggerIds.remove(t.id);
                          }
                        }),
                  title: Row(
                    children: [
                      Icon(
                        GameIcons.forTrigger(t),
                        size: 14,
                        color: Palette.accent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          t.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        '${t.equipCost}',
                        style: const TextStyle(
                          color: Palette.warn,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    describeTrigger(t),
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _blackTriggerList(
    Character character,
    LoadoutSelection selection, {
    String? allowedId,
    bool tutorialLocked = false,
  }) {
    const grid = ResonanceGrid.defaultGrid;
    return _panel(
      borderColor: Colors.white12,
      children: [
        const Text(
          'BLACK TRIGGER (OPTIONAL, MAX 1)',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              RadioListTile<String?>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: null,
                groupValue: selection.blackTriggerId,
                onChanged: tutorialLocked && allowedId != null
                    ? null
                    : (v) => setState(() => selection.blackTriggerId = null),
                title: const Text(
                  'None',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              for (final bt in blackTriggerCatalog.all)
                RadioListTile<String?>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: bt.id,
                  groupValue: selection.blackTriggerId,
                  onChanged: tutorialLocked && allowedId != bt.id
                      ? null
                      : (v) => setState(() => selection.blackTriggerId = v),
                  title: Row(
                    children: [
                      const Icon(
                        GameIcons.blackTrigger,
                        size: 14,
                        color: Palette.accent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          bt.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      _gradeTag(grid.lookup(character.type, bt.type)),
                      const SizedBox(width: 8),
                      Text(
                        '${bt.equipCost}',
                        style: const TextStyle(
                          color: Palette.warn,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    '${bt.description}\n${blackTriggerAbilityLines(bt).join('\n')}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _gradeTag(ResonanceGrade grade) {
    final color = switch (grade) {
      ResonanceGrade.a => Palette.good,
      ResonanceGrade.b => Palette.accent,
      ResonanceGrade.c => Colors.white54,
      ResonanceGrade.d => Palette.danger,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        grade.name.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildBattleStep() {
    final session = _session!;
    final tutorialStep =
        _tutorialActive && _tutorial!.phase == TutorialPhase.battle
        ? _tutorial!.currentBattleStep
        : null;
    final endTurnVisible =
        session.isPlayerTurn &&
        !session.isOver &&
        (!_tutorialActive ||
            _tutorial!.phase != TutorialPhase.battle ||
            _tutorial!.awaitingEndTurn);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: session.isOver
                ? Colors.white10
                : Palette.teamA.withValues(alpha: 0.12),
            border: Border.all(
              color: session.isOver ? Colors.white24 : Palette.teamA,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            session.isOver
                ? 'Battle Over'
                : 'Your Turn - Round ${session.roundNumber} (Team Trion: ${session.teamATrion})',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TeamPanel(
                label: 'Your Squad',
                color: Palette.teamA,
                fighters: session.teamA,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TeamPanel(
                label: 'Opponent Squad',
                color: Palette.teamB,
                fighters: session.teamB,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (session.isOver) ...[
          OutcomeBanner(
            outcome: session.outcome,
            textOverride: switch (session.outcome) {
              BattleOutcome.teamAWins => 'VICTORY',
              BattleOutcome.teamBWins => 'DEFEAT',
              _ => null,
            },
            note: 'Concluded in ${session.roundNumber} round(s).',
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _copyReport,
            child: const Text('COPY FULL REPORT'),
          ),
        ] else ...[
          for (final fighter in session.teamA.where((f) => f.alive))
            _ActionCard(
              key: ValueKey(
                '${fighter.id}-${session.roundNumber}-${_roundsLog.length}-${session.teamATrion}-${fighter.fatTriggered}',
              ),
              fighter: fighter,
              actions: session.legalActionsFor(fighter.id),
              session: session,
              tutorialStep: tutorialStep,
              onUse: _useAbility,
            ),
          if (endTurnVisible)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ElevatedButton(
                onPressed: _endTurn,
                child: const Text('END TURN'),
              ),
            ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          height: 280,
          child: BattleLogView(
            rounds: _roundsLog,
            teamAName: 'You',
            teamBName: 'Opponent',
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _panel({required Color borderColor, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: borderColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// One player character's action panel during their turn: the list of
/// currently legal abilities, and (once one is selected) a target picker.
class _ActionCard extends StatefulWidget {
  final FighterSnapshot fighter;
  final List<LegalAction> actions;
  final PlaySession session;
  final TutorialBattleStep? tutorialStep;
  final void Function(
    String characterId,
    LegalAction action,
    List<String> targetIds,
  )
  onUse;

  const _ActionCard({
    super.key,
    required this.fighter,
    required this.actions,
    required this.session,
    required this.tutorialStep,
    required this.onUse,
  });

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  LegalAction? _selected;
  final Set<String> _targets = {};

  bool get _lockedByTutorial =>
      widget.tutorialStep != null &&
      widget.tutorialStep!.characterId != widget.fighter.id;

  bool _abilityEnabled(LegalAction action) {
    if (!action.affordable) return false;
    final step = widget.tutorialStep;
    if (step == null || step.characterId != widget.fighter.id) return true;
    return step.isFatStep || step.triggerId == action.trigger.id;
  }

  void _selectAction(LegalAction action) {
    setState(() {
      _selected = action;
      _targets
        ..clear()
        ..addAll(action.legalTargetIds.take(action.maxTargets));
    });
  }

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final f in [...widget.session.teamA, ...widget.session.teamB])
        f.id: f.name,
    };
    return Opacity(
      opacity: _lockedByTutorial ? 0.4 : 1,
      child: IgnorePointer(
        ignoring: _lockedByTutorial,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(color: Colors.white12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.fighter.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (widget.fighter.fatTriggered) ...const [
                          SizedBox(width: 6),
                          FatBadge(),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    widget.actions.isEmpty
                        ? 'no actions available this turn'
                        : '${widget.actions.length} action(s) available',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
              if (widget.actions.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'On cooldown, action-prevented, or no further actions this turn.',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              if (widget.actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final action in widget.actions)
                        _abilityButton(action),
                    ],
                  ),
                ),
              if (_selected != null) _targetPicker(names),
            ],
          ),
        ),
      ),
    );
  }

  Widget _abilityButton(LegalAction action) {
    final t = action.trigger;
    final isSelected = _selected?.trigger.id == t.id;
    final highlight =
        widget.tutorialStep?.triggerId == t.id &&
        widget.tutorialStep?.characterId == widget.fighter.id;
    return Tooltip(
      message: action.affordable
          ? describeActiveTrigger(t)
          : 'Not enough Trion this turn.',
      triggerMode: TooltipTriggerMode.longPress,
      child: OutlinedButton(
        onPressed: _abilityEnabled(action) ? () => _selectAction(action) : null,
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: isSelected
                ? Palette.accent
                : highlight
                ? Palette.warn
                : Colors.white24,
          ),
          backgroundColor: isSelected
              ? Palette.accent.withValues(alpha: 0.12)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(GameIcons.forTrigger(t), size: 13, color: Palette.accent),
                const SizedBox(width: 5),
                Text(
                  t.name,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(width: 6),
                Text(
                  '${action.actualTrionCost} Trion',
                  style: const TextStyle(color: Palette.warn, fontSize: 10),
                ),
              ],
            ),
            Text(
              triggerSummaryLine(t),
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _targetPicker(Map<String, String> names) {
    final action = _selected!;
    final t = action.trigger;
    Widget targets;
    if (t.targetAffiliation == TargetAffiliation.self) {
      targets = Text(
        'Target: ${widget.fighter.name} (self)',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      );
    } else if (action.maxTargets == 1) {
      // A single-target ability should only ever let you pick one target,
      // not tick several boxes and have the extras silently discarded.
      targets = Wrap(
        spacing: 6,
        children: [
          for (final id in action.legalTargetIds)
            ChoiceChip(
              label: Text(
                names[id] ?? id,
                style: const TextStyle(fontSize: 11),
              ),
              selected: _targets.contains(id),
              onSelected: (_) => setState(
                () => _targets
                  ..clear()
                  ..add(id),
              ),
            ),
        ],
      );
    } else {
      targets = Wrap(
        spacing: 6,
        children: [
          for (final id in action.legalTargetIds)
            FilterChip(
              label: Text(
                names[id] ?? id,
                style: const TextStyle(fontSize: 11),
              ),
              selected: _targets.contains(id),
              onSelected: (selected) => setState(() {
                if (selected) {
                  if (_targets.length < action.maxTargets) _targets.add(id);
                } else {
                  _targets.remove(id);
                }
              }),
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t.targetAffiliation != TargetAffiliation.self &&
              action.maxTargets > 1)
            Text(
              'Pick up to ${action.maxTargets} target(s):',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          targets,
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed:
                _targets.isEmpty &&
                    t.targetAffiliation != TargetAffiliation.self
                ? null
                : () => widget.onUse(
                    widget.fighter.id,
                    action,
                    t.targetAffiliation == TargetAffiliation.self
                        ? [widget.fighter.id]
                        : _targets.take(action.maxTargets).toList(),
                  ),
            child: Text('USE ${action.trigger.name.toUpperCase()}'),
          ),
        ],
      ),
    );
  }
}

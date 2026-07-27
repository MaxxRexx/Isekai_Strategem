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
import '../widgets/ability_slot.dart';
import '../widgets/badges.dart';
import '../widgets/fighter_row.dart';
import '../widgets/log_view.dart';
import '../widgets/outcome_banner.dart';
import '../widgets/pickers.dart';
import '../widgets/portrait_tile.dart';
import '../widgets/trigger_icons.dart';

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

  // One shared selection for the whole battle step: whichever ability icon
  // was last tapped across the squad drives the single bottom action bar,
  // matching the approved reference (not a stacked card per character).
  String? _selectedCharacterId;
  LegalAction? _selectedAction;
  final Set<String> _selectedTargets = {};

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
    _clearSelection();
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
      _clearSelection();
      _afterBattleStateChange();
    });
  }

  void _clearSelection() {
    _selectedCharacterId = null;
    _selectedAction = null;
    _selectedTargets.clear();
  }

  void _selectAbility(String characterId, LegalAction action) {
    setState(() {
      _selectedCharacterId = characterId;
      _selectedAction = action;
      _selectedTargets
        ..clear()
        ..addAll(action.legalTargetIds.take(action.maxTargets));
    });
  }

  void _endTurn() {
    setState(() {
      _clearSelection();
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
                      TriggerIcon(trigger: t, size: 14),
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
                      BlackTriggerIcon(blackTrigger: bt, size: 14),
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
    final opponentProfile = profileById(_profileBId!);
    final names = {
      for (final f in [...session.teamA, ...session.teamB]) f.id: f.name,
    };

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _BattleTopBar(
          isOver: session.isOver,
          roundNumber: session.roundNumber,
          teamATrion: session.teamATrion,
          opponentName: opponentProfile.name,
          opponentSkillLabel: skillClassLabel[opponentProfile.skillClass]!,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 78,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border(
                    top: BorderSide(color: Palette.teamA, width: 3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YOUR SQUAD',
                      style: TextStyle(
                        color: Palette.teamA,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final fighter in session.teamA)
                      _playerFighterRow(fighter, session, tutorialStep),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 22,
              child: TeamPanel(
                label: 'Opponent Squad',
                color: Palette.teamB,
                fighters: session.teamB,
                portraitSize: 48,
                compact: true,
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
        ] else
          _bottomActionBar(names, tutorialStep, endTurnVisible),
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

  /// One living player fighter's row: portrait/HP/status on the left, and
  /// (unlike the opponent's compact panel) its legal ability icons inline
  /// on the right, feeding the single shared bottom action bar below.
  Widget _playerFighterRow(
    FighterSnapshot fighter,
    PlaySession session,
    TutorialBattleStep? tutorialStep,
  ) {
    final actions = fighter.alive
        ? session.legalActionsFor(fighter.id)
        : const <LegalAction>[];
    final lockedRow =
        tutorialStep != null && tutorialStep.characterId != fighter.id;

    return Opacity(
      opacity: !fighter.alive
          ? 0.4
          : lockedRow
          ? 0.4
          : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PortraitHealthBar(
              characterId: fighter.id,
              name: fighter.name,
              type: fighter.type,
              currentHealth: fighter.currentHealth,
              maxHealth: fighter.maxHealth,
              alive: fighter.alive,
              size: 64,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          fighter.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: fighter.alive
                                ? Colors.white
                                : Colors.white38,
                            decoration: fighter.alive
                                ? null
                                : TextDecoration.lineThrough,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (fighter.fatTriggered) ...const [
                        SizedBox(width: 6),
                        FatBadge(),
                      ],
                    ],
                  ),
                  if (fighter.statusEffects.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Wrap(
                        spacing: 3,
                        runSpacing: 3,
                        children: [
                          for (final s in fighter.statusEffects)
                            StatusBadge(
                              name: s.name,
                              remainingTurns: s.remainingTurns,
                            ),
                        ],
                      ),
                    ),
                  if (fighter.alive)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: actions.isEmpty
                          ? const Text(
                              'No actions available this turn.',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                            )
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final action in actions)
                                  _abilitySlot(action, fighter, tutorialStep),
                              ],
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

  bool _abilityEnabled(
    TutorialBattleStep? step,
    String fighterId,
    LegalAction action,
  ) {
    if (!action.affordable) return false;
    if (step == null || step.characterId != fighterId) return true;
    return step.isFatStep || step.triggerId == action.trigger.id;
  }

  Widget _abilitySlot(
    LegalAction action,
    FighterSnapshot fighter,
    TutorialBattleStep? tutorialStep,
  ) {
    final t = action.trigger;
    final isSelected =
        _selectedCharacterId == fighter.id &&
        _selectedAction?.trigger.id == t.id;
    final highlight =
        tutorialStep?.triggerId == t.id &&
        tutorialStep?.characterId == fighter.id;
    return AbilitySlot(
      icon: TriggerIcon(trigger: t, size: 20),
      selected: isSelected,
      highlighted: !isSelected && highlight,
      enabled: _abilityEnabled(tutorialStep, fighter.id, action),
      tooltip: action.affordable
          ? '${t.name} (${action.actualTrionCost} Trion) - ${triggerSummaryLine(t)}'
          : '${t.name}: not enough Trion this turn.',
      onTap: () => _selectAbility(fighter.id, action),
    );
  }

  /// The single shared bottom bar: whichever ability was last tapped
  /// anywhere in the squad list drives this one panel, matching the
  /// approved reference (not a stacked card per character).
  Widget _bottomActionBar(
    Map<String, String> names,
    TutorialBattleStep? tutorialStep,
    bool endTurnVisible,
  ) {
    final action = _selectedAction;
    final charId = _selectedCharacterId;
    if (action == null || charId == null) {
      if (!endTurnVisible) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.centerRight,
        child: ElevatedButton(
          onPressed: _endTurn,
          child: const Text('END TURN'),
        ),
      );
    }

    final t = action.trigger;
    Widget targets;
    if (t.targetAffiliation == TargetAffiliation.self) {
      targets = Text(
        'Target: ${names[charId]} (self)',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      );
    } else if (action.maxTargets == 1) {
      targets = Wrap(
        spacing: 6,
        children: [
          for (final id in action.legalTargetIds)
            ChoiceChip(
              label: Text(
                names[id] ?? id,
                style: const TextStyle(fontSize: 11),
              ),
              selected: _selectedTargets.contains(id),
              onSelected: (_) => setState(
                () => _selectedTargets
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
              selected: _selectedTargets.contains(id),
              onSelected: (selected) => setState(() {
                if (selected) {
                  if (_selectedTargets.length < action.maxTargets)
                    _selectedTargets.add(id);
                } else {
                  _selectedTargets.remove(id);
                }
              }),
            ),
        ],
      );
    }

    final canUse =
        _selectedTargets.isNotEmpty ||
        t.targetAffiliation == TargetAffiliation.self;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Palette.accent)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  border: Border.all(color: Palette.accent),
                ),
                child: TriggerIcon(trigger: t, size: 18),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.name.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      describeActiveTrigger(t),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        for (final tag in triggerSummaryLine(t).split(' - '))
                          _tagChip(tag),
                        _tagChip('${action.actualTrionCost} Trion'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (t.targetAffiliation != TargetAffiliation.self &&
              action.maxTargets > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Pick up to ${action.maxTargets} target(s):',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
          targets,
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (endTurnVisible)
                OutlinedButton(
                  onPressed: _endTurn,
                  child: const Text('END TURN'),
                )
              else
                const SizedBox.shrink(),
              ElevatedButton(
                onPressed: canUse
                    ? () => _useAbility(
                        charId,
                        action,
                        t.targetAffiliation == TargetAffiliation.self
                            ? [charId]
                            : _selectedTargets.take(action.maxTargets).toList(),
                      )
                    : null,
                child: Text(_useButtonLabel(t, names)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _useButtonLabel(ActiveTrigger t, Map<String, String> names) {
    if (t.targetAffiliation == TargetAffiliation.self) return 'USE (SELF)';
    if (_selectedTargets.length > 1) {
      return 'USE (${_selectedTargets.length} TARGETS)';
    }
    final only = _selectedTargets.firstOrNull;
    return only == null
        ? 'USE'
        : 'USE ON ${(names[only] ?? only).toUpperCase()}';
  }

  Widget _tagChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: Palette.accent)),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 9,
          letterSpacing: 0.3,
        ),
      ),
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

/// Team readout above the squads: your label on the left, the opponent's
/// AI profile name/skill class on the right, round/Trion centered between
/// them - matching the approved battle-screen mockup's top bar.
class _BattleTopBar extends StatelessWidget {
  final bool isOver;
  final int roundNumber;
  final int teamATrion;
  final String opponentName;
  final String opponentSkillLabel;

  const _BattleTopBar({
    required this.isOver,
    required this.roundNumber,
    required this.teamATrion,
    required this.opponentName,
    required this.opponentSkillLabel,
  });

  Widget _label(String name, String? subtitle, {required bool alignEnd}) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 10.5),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border.all(color: isOver ? Colors.white24 : Palette.accent),
      ),
      child: isOver
          ? const Text(
              'BATTLE OVER',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _label('YOU', null, alignEnd: false),
                Row(
                  children: [
                    Text(
                      'ROUND $roundNumber',
                      style: const TextStyle(
                        color: Palette.accent,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      '⟡ Trion $teamATrion',
                      style: const TextStyle(
                        color: Palette.gold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                _label(opponentName, opponentSkillLabel, alignEnd: true),
              ],
            ),
    );
  }
}

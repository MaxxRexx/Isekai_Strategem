import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/character_art.dart';
import '../data/describe.dart';
import '../game/battle_models.dart';
import '../game/draft.dart';
import '../game/loadout_selection.dart';
import '../game/play_session.dart';
import '../game/report.dart';
import '../game/tutorial.dart';
import '../ui/palette.dart';
import '../widgets/ability_slot.dart';
import '../widgets/badges.dart';
import '../widgets/fighter_row.dart';
import '../widgets/loadout_builder_panel.dart';
import '../widgets/loadout_budget_panel.dart';
import '../widgets/log_view.dart';
import '../widgets/outcome_banner.dart';
import '../widgets/pickers.dart';
import '../widgets/player_panel.dart';
import '../widgets/portrait_tile.dart';
import '../widgets/tag_chip.dart';
import '../widgets/trigger_icons.dart';

enum _PlayStep { setup, loadout, battle }

/// Play mode: draft your own squad and Loadouts, then play turn by turn
/// against an AI opponent. With [tutorial] set, the Guided Tutorial's
/// script locks each step to a single scripted action. With
/// [initialTeamAIds]/[initialSelections] set (the Home screen's inline
/// squad builder path), the squad is already fully built - skip straight
/// to the battle step instead of the setup/loadout wizard.
class PlayFlowScreen extends StatefulWidget {
  final bool tutorial;
  final List<String>? initialTeamAIds;
  final Map<String, LoadoutSelection>? initialSelections;

  const PlayFlowScreen({
    super.key,
    this.tutorial = false,
    this.initialTeamAIds,
    this.initialSelections,
  });

  @override
  State<PlayFlowScreen> createState() => _PlayFlowScreenState();
}

class _PlayFlowScreenState extends State<PlayFlowScreen> {
  _PlayStep _step = _PlayStep.setup;

  final List<String?> _teamAIds = [null, null, null];
  final List<String?> _teamBIds = [null, null, null];
  String? _profileBId;
  String? _setupError;

  // Which squad slot the inline roster grid is currently drafting into,
  // and which roster card is currently previewed in the detail panel below
  // it - matches the approved Squad Select mockup (one page, no modal).
  int _activeSlotA = 0;
  String? _previewIdA;
  int _activeSlotB = 0;
  String? _previewIdB;

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

  // Which cutout variant (if any) each character shows in the spotlight
  // panel this battle - chosen once and cached, not re-rolled every
  // rebuild, so a character doesn't flicker between art variants.
  final Map<String, String> _cutoutChoices = {};

  String? _cutoutFor(String characterId) {
    if (_cutoutChoices.containsKey(characterId)) {
      return _cutoutChoices[characterId];
    }
    final asset = randomCutoutAssetFor(characterId, Random());
    if (asset != null) _cutoutChoices[characterId] = asset;
    return asset;
  }

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
    } else if (widget.initialTeamAIds != null) {
      // The Home screen's inline squad builder already assembled a full,
      // validated squad and its Loadouts - skip the setup/loadout wizard
      // entirely and drop straight into battle.
      for (var i = 0; i < 3; i++) {
        _teamAIds[i] = widget.initialTeamAIds![i];
      }
      _selections.addAll(widget.initialSelections!);
      _randomizeTeam(_teamBIds, withProfile: true);
      _startBattle();
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

  /// Squad Select: the roster grid and detail panel are always visible on
  /// the page itself (matching the approved mockup), not hidden behind a
  /// modal - tapping a slot just marks it "active" for the grid below.
  Widget _buildSetupStep() {
    final setupStep = _tutorialActive ? _tutorial!.currentSetupStep : null;
    final lockedByTutorial = _tutorialActive;

    Set<String> takenExcept(List<String?> slots, int slot) => {
      for (var i = 0; i < slots.length; i++)
        if (i != slot && slots[i] != null) slots[i]!,
    };

    final activeSlotA = lockedByTutorial
        ? (setupStep?.slot ?? 0)
        : _activeSlotA;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _draftSection(
          teamLabel: 'YOUR SQUAD',
          color: Palette.teamA,
          ids: _teamAIds,
          activeSlot: activeSlotA,
          onSlotTap: lockedByTutorial
              ? null
              : (i) => setState(() {
                  _activeSlotA = i;
                  _previewIdA = _teamAIds[i];
                }),
          onRandomize: lockedByTutorial
              ? null
              : () => setState(() {
                  _randomizeTeam(_teamAIds, withProfile: false);
                  _activeSlotA = 0;
                  _previewIdA = null;
                }),
          lockToCharacterId: lockedByTutorial ? setupStep?.charId : null,
          rosterDisabled: takenExcept(_teamAIds, activeSlotA),
          previewId: _previewIdA,
          onPreview: (id) => setState(() => _previewIdA = id),
          onDraft: (id) => setState(() {
            _teamAIds[activeSlotA] = id;
            _tutorial?.onSetupPick(activeSlotA, id);
            _previewIdA = null;
            _activeSlotA = _nextEmptySlot(_teamAIds, activeSlotA);
          }),
        ),
        const SizedBox(height: 20),
        _draftSection(
          teamLabel: 'OPPONENT SQUAD',
          color: Palette.teamB,
          ids: _teamBIds,
          activeSlot: _activeSlotB,
          onSlotTap: lockedByTutorial
              ? null
              : (i) => setState(() {
                  _activeSlotB = i;
                  _previewIdB = _teamBIds[i];
                }),
          onRandomize: lockedByTutorial
              ? null
              : () => setState(() {
                  _randomizeTeam(_teamBIds, withProfile: true);
                  _activeSlotB = 0;
                  _previewIdB = null;
                }),
          lockToCharacterId: null,
          rosterDisabled: takenExcept(_teamBIds, _activeSlotB),
          previewId: _previewIdB,
          onPreview: lockedByTutorial
              ? null
              : (id) => setState(() => _previewIdB = id),
          onDraft: lockedByTutorial
              ? null
              : (id) => setState(() {
                  _teamBIds[_activeSlotB] = id;
                  _previewIdB = null;
                  _activeSlotB = _nextEmptySlot(_teamBIds, _activeSlotB);
                }),
          profileSlot: ProfileSlot(
            label: 'AI Profile',
            selectedId: _profileBId,
            enabled: !lockedByTutorial,
            onChanged: (id) => setState(() => _profileBId = id),
          ),
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

  int _nextEmptySlot(List<String?> ids, int justFilled) {
    for (var i = 0; i < ids.length; i++) {
      final idx = (justFilled + 1 + i) % ids.length;
      if (ids[idx] == null) return idx;
    }
    return justFilled;
  }

  Widget _draftSection({
    required String teamLabel,
    required Color color,
    required List<String?> ids,
    required int activeSlot,
    required void Function(int)? onSlotTap,
    required VoidCallback? onRandomize,
    required String? lockToCharacterId,
    required Set<String> rosterDisabled,
    required String? previewId,
    required void Function(String)? onPreview,
    required void Function(String)? onDraft,
    Widget? profileSlot,
  }) {
    final effectivePreviewId = previewId ?? ids[activeSlot];
    final preview = effectivePreviewId == null
        ? null
        : roster[effectivePreviewId];
    final ctaEnabled =
        effectivePreviewId != null &&
        !rosterDisabled.contains(effectivePreviewId) &&
        (lockToCharacterId == null ||
            effectivePreviewId == lockToCharacterId) &&
        onDraft != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panel(
          borderColor: color,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  teamLabel,
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
            if (profileSlot != null) ...[
              const SizedBox(height: 8),
              profileSlot,
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _slotChip(ids[i], i, activeSlot == i, onSlotTap),
                  ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        RosterGrid(
          selectedId: effectivePreviewId,
          disabledIds: rosterDisabled,
          lockToCharacterId: lockToCharacterId,
          onTap: onPreview ?? (_) {},
        ),
        CharacterDetailPanel(
          character: preview,
          enabled: ctaEnabled,
          ctaLabel: 'DRAFT AGENT ${['I', 'II', 'III'][activeSlot]}',
          onCta: effectivePreviewId == null
              ? null
              : () => onDraft?.call(effectivePreviewId),
        ),
      ],
    );
  }

  Widget _slotChip(
    String? id,
    int index,
    bool active,
    void Function(int)? onTap,
  ) {
    final character = id == null ? null : roster[id];
    return InkWell(
      onTap: onTap == null ? null : () => onTap(index),
      child: Container(
        height: 64,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: active
              ? Palette.gold.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: active ? Palette.gold : Colors.white24,
            width: active ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: character == null
            ? Center(
                child: Text(
                  'Agent ${['I', 'II', 'III'][index]}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              )
            : Row(
                children: [
                  PortraitTile(
                    characterId: character.id,
                    name: character.name,
                    type: character.type,
                    size: 44,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          character.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          typeLabel[character.type]!,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 9,
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
        LoadoutBudgetPanel(
          character: character,
          loadout: loadout,
          errors: validation.errors,
          startError: _loadoutError,
          onAutoFill: _tutorialActive ? null : _autoFillCurrentLoadout,
          trailing: LoadoutBuilderPanel(
            character: character,
            selection: selection,
            allowedActiveIds: tutorialScript?.triggerIds.toSet(),
            allowedBlackId: tutorialScript?.blackTriggerId,
            tutorialLocked: tutorialScript != null,
            remainingTrion:
                character.baseStats.trionCapacity - loadout.totalEquipCost,
            onSelectionChanged: () => setState(() {}),
          ),
        ),
        const SizedBox(height: 12),
        _yourPicksAndPlayerPanel(loadout, selection),
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

  /// A compact summary of this character's current picks, plus the
  /// player's account panel - the mockup's "panel to the right," adapted
  /// to sit above the trigger grids on our single-column mobile layout.
  Widget _yourPicksAndPlayerPanel(Loadout loadout, LoadoutSelection selection) {
    final picks = [
      for (final t in triggerCatalog.all)
        if (selection.triggerIds.contains(t.id)) t,
    ];
    final blackTrigger = selection.blackTriggerId == null
        ? null
        : blackTriggerCatalog[selection.blackTriggerId!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Palette.panel,
            border: Border.all(color: Palette.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'YOUR PICKS',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10.5,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              if (picks.isEmpty && blackTrigger == null)
                const Text(
                  'Nothing equipped yet - tap a Trigger below.',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in picks)
                      _pickChip(t.name, TriggerIcon(trigger: t, size: 12)),
                    if (blackTrigger != null)
                      _pickChip(
                        blackTrigger.name,
                        BlackTriggerIcon(blackTrigger: blackTrigger, size: 12),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        PlayerPanel(squadIds: _teamAIds.whereType<String>().toList()),
      ],
    );
  }

  Widget _pickChip(String label, Widget icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Palette.gold.withValues(alpha: 0.1),
        border: Border.all(color: Palette.gold),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
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
        _battleRow(session, tutorialStep),
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

  /// The three-column Your Squad / Spotlight / Opponent Squad row. Kept as
  /// its own [LayoutBuilder] so the spotlighted character's cutout art (if
  /// any) can be painted as a [Positioned] overlay sized/placed from the
  /// row's actual pixel widths - letting it bleed rightward past its own
  /// column into the Opponent Squad column's space a little, the way the
  /// approved reference lets a character's cutout drift over neighboring
  /// panels without covering their text.
  Widget _battleRow(PlaySession session, TutorialBattleStep? tutorialStep) {
    final fighter = _spotlightFighter(session);
    final cutout = fighter == null ? null : _cutoutFor(fighter.id);

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 48,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(top: BorderSide(color: Palette.teamA, width: 3)),
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
          flex: 26,
          child: _characterSpotlight(fighter, hasCutout: cutout != null),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 26,
          child: TeamPanel(
            label: 'Opponent Squad',
            color: Palette.teamB,
            fighters: session.teamB,
            portraitSize: 64,
            compact: true,
          ),
        ),
      ],
    );

    if (cutout == null) return row;

    // The source art (804x1400) is much narrower than tall, so fitting it
    // to the reserved 220px height gives its actual on-screen width here -
    // BoxFit.contain inside an artificially wide box would just center the
    // narrow result instead of pushing it to one edge, so the width has to
    // be computed for real to get a deliberate bleed past the column edge.
    const cutoutAspectRatio = 804 / 1400;
    const artHeight = 220.0;
    const artRenderWidth = artHeight * cutoutAspectRatio;
    const bleedIntoOpponent = 36.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gutters = 20.0;
        final flexWidth = constraints.maxWidth - gutters;
        final spotlightLeft = flexWidth * 48 / 100 + 10;
        final spotlightWidth = flexWidth * 26 / 100;
        final spotlightRight = spotlightLeft + spotlightWidth;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            row,
            Positioned(
              left: spotlightRight + bleedIntoOpponent - artRenderWidth,
              width: artRenderWidth,
              // Fixed to match _characterSpotlight's own reserved 220px
              // placeholder gap below the SPOTLIGHT label - not the tallest
              // sibling column's height (Your Squad's, which varies with
              // squad size and would otherwise stretch/misalign the art).
              top: 34,
              height: artHeight,
              child: IgnorePointer(
                child: Image.asset(cutout, fit: BoxFit.contain),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Whichever fighter the spotlight column shows: whoever's ability row
  /// was last tapped (so picking an ability spotlights its user), falling
  /// back to the first living squad member.
  FighterSnapshot? _spotlightFighter(PlaySession session) {
    for (final f in session.teamA) {
      if (f.id == _selectedCharacterId) return f;
    }
    for (final f in session.teamA) {
      if (f.alive) return f;
    }
    return session.teamA.isEmpty ? null : session.teamA.first;
  }

  /// A large "spotlight" panel for one character, reserving the screen
  /// real estate the approved reference gives to full character art. When
  /// [hasCutout] is true the actual cutout image is painted by [_battleRow]
  /// as a separate overlay (so it can bleed past this panel's own bounds);
  /// this just leaves room for it. Characters without art yet keep the
  /// shared portrait tile scaled up as a stand-in.
  Widget _characterSpotlight(
    FighterSnapshot? fighter, {
    bool hasCutout = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: fighter == null ? Colors.white12 : Palette.gold,
            width: 3,
          ),
        ),
      ),
      child: fighter == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No living character to spotlight.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            )
          : Column(
              children: [
                const Text(
                  'SPOTLIGHT',
                  style: TextStyle(
                    color: Palette.gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 10),
                if (hasCutout)
                  // The actual art is painted by _battleRow's overlay, sized
                  // and positioned from the row's real pixel widths; this
                  // just reserves matching vertical space in-flow.
                  const SizedBox(height: 220)
                else
                  LayoutBuilder(
                    builder: (context, constraints) => PortraitHealthBar(
                      characterId: fighter.id,
                      name: fighter.name,
                      type: fighter.type,
                      currentHealth: fighter.currentHealth,
                      maxHealth: fighter.maxHealth,
                      alive: fighter.alive,
                      size: constraints.maxWidth.clamp(0, 220),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  fighter.name,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fighter.alive ? Colors.white : Colors.white38,
                    decoration: fighter.alive
                        ? null
                        : TextDecoration.lineThrough,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (fighter.statusEffects.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 3,
                      runSpacing: 3,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final s in fighter.statusEffects)
                          StatusBadge(
                            name: s.name,
                            remainingTurns: s.remainingTurns,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
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
    final displays = fighter.alive
        ? session.abilityDisplaysFor(fighter.id)
        : const <AbilityDisplay>[];
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
              size: 96,
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
                      child: displays.isEmpty
                          ? const Text(
                              'No abilities equipped.',
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
                                for (final display in displays)
                                  _abilitySlot(display, fighter, tutorialStep),
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
    AbilityDisplay display,
  ) {
    if (!display.usable) return false;
    if (step == null || step.characterId != fighterId) return true;
    return step.isFatStep || step.triggerId == display.trigger.id;
  }

  Widget _abilitySlot(
    AbilityDisplay display,
    FighterSnapshot fighter,
    TutorialBattleStep? tutorialStep,
  ) {
    final t = display.trigger;
    final action = display.legalAction;
    final isSelected =
        _selectedCharacterId == fighter.id &&
        _selectedAction?.trigger.id == t.id;
    final highlight =
        tutorialStep?.triggerId == t.id &&
        tutorialStep?.characterId == fighter.id;
    final String tooltip;
    if (display.cooldownRemaining > 0) {
      tooltip =
          '${t.name}: on cooldown for ${display.cooldownRemaining} '
          'more turn(s).';
    } else if (action == null) {
      tooltip = '${t.name}: not usable right now.';
    } else if (!action.affordable) {
      tooltip = '${t.name}: not enough Trion this turn.';
    } else {
      tooltip =
          '${t.name} (${action.actualTrionCost} Trion) - '
          '${triggerSummaryLine(t)}';
    }
    return AbilitySlot(
      icon: TriggerIcon(trigger: t, size: 28),
      selected: isSelected,
      highlighted: !isSelected && highlight,
      enabled: _abilityEnabled(tutorialStep, fighter.id, display),
      cooldownRemaining: display.cooldownRemaining,
      tooltip: tooltip,
      onTap: action == null ? null : () => _selectAbility(fighter.id, action),
      size: 60,
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
                  if (_selectedTargets.length < action.maxTargets) {
                    _selectedTargets.add(id);
                  }
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
                          TagChip(tag),
                        TagChip('${action.actualTrionCost} Trion'),
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

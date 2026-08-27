import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/describe.dart';
import '../data/flavor_text.dart';
import '../data/placeholder_ranks.dart';
import '../game/battle_models.dart';
import '../game/battle_xp.dart';
import '../game/draft.dart';
import '../game/loadout_selection.dart';
import '../game/play_session.dart';
import '../game/report.dart';
import '../game/services.dart';
import '../game/target_selection.dart';
import '../game/team_efficiency.dart';
import '../game/test_scenarios.dart';
import '../game/tutorial.dart';
import '../game/xp_ledger.dart';
import '../ui/notched.dart';
import '../ui/palette.dart';
import 'test_lab_screen.dart' show ScenarioBriefBody;
import '../ui/rank.dart';
import '../widgets/ability_slot.dart';
import '../widgets/account_sheet.dart';
import '../widgets/badges.dart';
import '../widgets/battlefield_rail.dart';
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

/// Filled/primary buttons (Queue, Use, Return to Home) use the solid closed
/// diagonal notch on the top-left + bottom-right corners, matching the
/// Rift Cyan mockup's blue-background buttons.
const _filledNotchShape = NotchedBorder(notch: 12);

/// Outlined battle buttons (End Turn) use the open L-bracket notch.
const _openBtnStyleShape = OpenNotchBorder(notch: 11);

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

  /// A pre-arranged board from the Tests tab. Skips setup and Loadout
  /// entirely, since a scenario pins both squads, both kits and the whole
  /// starting position, and pins a brief to the battle screen so the tester
  /// can see what they are looking for without leaving it.
  final TestScenario? scenario;

  const PlayFlowScreen({
    super.key,
    this.tutorial = false,
    this.initialTeamAIds,
    this.initialSelections,
    this.scenario,
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

  /// Set when the player tapped an ability they cannot use, to read it. Never
  /// set at the same time as [_selectedAction].
  AbilityDisplay? _inspectedAbility;
  final Set<String> _selectedTargets = {};

  /// Which character's info the description panel is previewing (set by
  /// tapping a portrait while no ability is mid-selection). Cleared as soon
  /// as an ability is picked or the selection is dismissed.
  String? _infoCharacterId;

  /// Whether the description panel is previewing the player's own account
  /// info (set by tapping the top-bar player portrait). The squad section is
  /// omitted from that readout since it's already on screen during battle.
  bool _showPlayerInfo = false;

  /// Whether the description panel is previewing the opponent's AI profile
  /// info (set by tapping the top-bar opponent portrait), mirroring
  /// [_showPlayerInfo].
  bool _showOpponentInfo = false;

  /// True while the turn is resolving (player queue + the AI's response),
  /// which briefly locks input in Play mode.
  bool _resolving = false;

  /// The post-battle XP award (combat-v2 §15), computed once when a Play-mode
  /// battle ends. Null until awarded (or if nobody is signed in).
  XpAward? _xpAward;
  bool _xpAwardInFlight = false;

  /// Diagnostic: the error message if the XP award failed (e.g. an RPC error
  /// from the backend). Surfaced in the outcome readout so failures are visible
  /// instead of silently swallowed.
  String? _xpError;

  /// Whether the battle log dropdown is open. Owned here (not inside the
  /// log widget) so it survives turn-to-turn rebuilds and the queued-strip
  /// coming and going; only reset to closed when a new battle starts.
  bool _battleLogOpen = false;

  TutorialState? _tutorial;

  // Presentational only - there's no audio system to actually drive yet.
  double _volume = 0.6;

  @override
  void initState() {
    super.initState();
    final scenario = widget.scenario;
    if (scenario != null) {
      for (var i = 0; i < 3; i++) {
        _teamAIds[i] = scenario.playerIds[i];
        _teamBIds[i] = scenario.enemyIds[i];
      }
      _startScenario(scenario);
    } else if (widget.tutorial) {
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

  /// Each squad only has to avoid itself: both may field the same character
  /// since item #14.
  void _randomizeTeam(
    List<String?> slots, {
    required bool withProfile,
  }) {
    final random = Random();
    final picked = randomSquadAvoiding(random, slots);
    for (var i = 0; i < 3; i++) {
      slots[i] = picked[i];
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

  /// Drops straight into a scenario's arranged battle. Deliberately does not
  /// go through [_startBattle]: a scenario owns both squads' Loadouts and the
  /// board, so there is nothing for the setup or Loadout steps to decide.
  void _startScenario(TestScenario scenario) {
    // The battle screen reads the opponent's profile to show who it is
    // playing against, so this has to be set even though the scenario has
    // already handed the same id to the session.
    _profileBId = scenario.opponentProfileId;
    _session = scenario.start();
    _roundsLog.clear();
    _clearSelection();
    _battleLogOpen = false;
    _step = _PlayStep.battle;
    _tutorial = null;
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
    _battleLogOpen = false; // the log defaults to closed at battle start
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

  /// Awards post-battle XP once, when a Play-mode battle has ended and someone
  /// is signed in (including as a guest). Server-authoritative when the real
  /// backend is live; the local stub otherwise. Safe to call repeatedly.
  void _maybeAwardXp() {
    final session = _session;
    if (session == null || !session.isOver) return;
    if (_tutorialActive || _xpAward != null || _xpAwardInFlight) return;
    _xpAwardInFlight = true;
    _xpError = null;
    session
        .awardBattleXpTo(
          Services.instance.xpLedger,
          Services.instance.accountService,
        )
        .then((award) {
          if (!mounted) return;
          setState(() {
            _xpAward = award;
            _xpAwardInFlight = false;
            // Backend live + signed in but no award means the call came back
            // empty; make that visible rather than showing nothing.
            if (award == null &&
                Services.instance.backendLive &&
                Services.instance.accountService.current != null) {
              _xpError = 'No XP returned (backend reachable, signed in).';
            }
          });
        })
        .catchError((Object e) {
          if (mounted) {
            setState(() {
              _xpAwardInFlight = false;
              _xpError = '$e';
            });
          }
        });
  }

  /// The post-battle XP line under the outcome banner. Shows the awarded XP
  /// (with the inverse-TEG breakdown) when signed in, or a friendly prompt to
  /// sign in and save progress when not.
  Widget _xpAwardReadout() {
    final award = _xpAward;
    if (_xpError != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Palette.danger.withValues(alpha: 0.08),
            border: Border.all(color: Palette.danger.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'XP AWARD FAILED',
                style: TextStyle(
                  color: Palette.danger,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 3),
              SelectableText(
                _xpError!,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }
    if (award != null) {
      final tier = _session!.teamAEfficiency.tier;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Palette.gold.withValues(alpha: 0.08),
            border: Border.all(color: Palette.gold.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.star, color: Palette.gold, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '+${award.awardedXp} XP',
                    style: const TextStyle(
                      color: Palette.gold,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${award.totalXp} total',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Base ${award.baseXp}, ${tier.label}-grade bonus '
                '+${battleXpBonusPercentFor(tier)}% (lower grade earns more).',
                style: const TextStyle(color: Colors.white54, fontSize: 10.5),
              ),
            ],
          ),
        ),
      );
    }
    if (_xpAwardInFlight) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(
              'Tallying XP...',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      );
    }
    if (Services.instance.accountService.current == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => AccountSheet.show(context),
            icon: const Icon(Icons.person_outline, size: 16),
            label: const Text('Sign in to save your XP'),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
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

  /// Play mode: commit the selected ability to the turn queue (Trion is
  /// spent now, effects apply on End Turn) instead of resolving immediately.
  void _queueAbility(
    String characterId,
    LegalAction action,
    List<String> targetIds,
  ) {
    final outcome = _session!.queue(characterId, action.trigger.id, targetIds);
    setState(() {
      if (!outcome.success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(outcome.error!)));
        return;
      }
      _clearSelection();
      _afterBattleStateChange();
    });
  }

  void _clearSelection() {
    _selectedCharacterId = null;
    _selectedAction = null;
    _inspectedAbility = null;
    _selectedTargets.clear();
    _infoCharacterId = null;
    _showPlayerInfo = false;
    _showOpponentInfo = false;
  }

  /// An ability the player tapped purely to read about: on cooldown, out of
  /// range, unaffordable, or waiting on an action. It cannot be queued, so it
  /// never becomes a [LegalAction]; the description panel reads it instead.
  void _inspectAbility(String characterId, AbilityDisplay display) {
    setState(() {
      _clearSelection();
      _selectedCharacterId = characterId;
      _inspectedAbility = display;
    });
  }

  /// The top-bar player portrait was tapped: preview the player's account
  /// info in the description panel (clearing any ability/target selection).
  void _showAccountInfo() {
    setState(() {
      _clearSelection();
      _showPlayerInfo = true;
    });
  }

  /// The top-bar opponent portrait was tapped: preview the opponent's AI
  /// profile info in the description panel.
  void _showOpponentAccountInfo() {
    setState(() {
      _clearSelection();
      _showOpponentInfo = true;
    });
  }

  void _selectAbility(String characterId, LegalAction action) {
    setState(() {
      _infoCharacterId = null;
      _inspectedAbility = null;
      _selectedCharacterId = characterId;
      _selectedAction = action;
      // A self-cast highlights the caster, because there is nothing to
      // choose. Everything else starts empty and marks what it can reach,
      // for the player to pick from. (See autoSelectedTargets - shared so
      // it can be catalog-tested.)
      _selectedTargets
        ..clear()
        ..addAll(
          autoSelectedTargets(
            action.trigger,
            characterId,
            action.legalTargetIds,
            action.maxTargets,
          ),
        );
    });
  }

  /// Everyone the pending ability could be aimed at right now: empty when no
  /// ability is selected, so the board is unmarked until there is a choice
  /// to make. Ids carry their team (`player:` / `opponent:`), so handing the
  /// same set to both squad panels lights up only the side the ability is
  /// actually aimed at.
  Set<String> get _eligibleTargets {
    final action = _selectedAction;
    if (action == null || _resolving) return const {};
    return action.legalTargetIds.toSet();
  }

  /// The line a target is standing on, in the words the battlefield strip
  /// uses, so the aim reads the same in both places.
  String _lineLabelOf(String targetId) {
    final theirs =
        !_session!.teamA.any((f) => f.id == targetId);
    final line = switch (_session!.projectedPositionOf(targetId)) {
      BattlePosition.front => 'Front',
      BattlePosition.middle => 'Middle',
      BattlePosition.back => 'Back',
    };
    return theirs ? 'their $line line' : 'your $line line';
  }

  /// True when [action] leaves target choice up to the player, i.e. anything
  /// but a self-cast. While this holds, tapping a portrait toggles it as a
  /// target instead of previewing its info.
  bool _awaitingTargets(LegalAction action) =>
      awaitingManualTargets(action.trigger);

  /// A portrait was tapped. If an ability is mid-selection and waiting for
  /// targets, toggle this character as a target; otherwise preview its info
  /// in the description panel.
  void _onPortraitTap(String characterId) {
    final action = _selectedAction;
    if (action != null && _awaitingTargets(action)) {
      _toggleTarget(action, characterId);
    } else {
      setState(() => _infoCharacterId = characterId);
    }
  }

  void _toggleTarget(LegalAction action, String id) {
    if (!action.legalTargetIds.contains(id)) return;
    setState(() {
      // An area ability is aimed at a line, not at a person: tapping anyone
      // on it selects everyone legal standing there, and tapping again
      // clears. Anything else toggles the one portrait.
      if (action.trigger.attackSubtype == AttackSubtype.aoe) {
        final line = lineTargets(
          tappedId: id,
          legalTargetIds: action.legalTargetIds,
          positionOf: (t) => _session!.projectedPositionOf(t),
          maxTargets: action.maxTargets,
        );
        if (_selectedTargets.containsAll(line) &&
            _selectedTargets.length == line.length) {
          _selectedTargets.clear();
        } else {
          _selectedTargets
            ..clear()
            ..addAll(line);
        }
        return;
      }
      if (_selectedTargets.contains(id)) {
        _selectedTargets.remove(id);
      } else if (action.maxTargets == 1) {
        _selectedTargets
          ..clear()
          ..add(id);
      } else if (_selectedTargets.length < action.maxTargets) {
        _selectedTargets.add(id);
      }
    });
  }

  Future<void> _endTurn() async {
    if (_resolving) return;

    // The Guided Tutorial is scripted around immediate ability use, so it
    // keeps the direct end-turn path.
    if (_tutorialActive) {
      setState(() {
        _clearSelection();
        _tutorial?.onEndTurn();
        final aiRound = _session!.endTurn();
        _roundsLog.add(aiRound);
        _afterBattleStateChange();
      });
      return;
    }

    // Play mode: resolve the player's queued actions, show them, then let
    // the AI respond after a short "thinking" beat.
    final session = _session!;
    setState(() {
      _clearSelection();
      final playerRound = session.resolveQueue();
      if (playerRound.actions.isNotEmpty) _roundsLog.add(playerRound);
      _resolving = true;
      _afterBattleStateChange();
    });
    if (session.isOver) {
      setState(() => _resolving = false);
      _maybeAwardXp();
      return;
    }
    final aiRound = await session.endTurnWithDelay(
      const Duration(milliseconds: 1200),
    );
    if (!mounted) return;
    setState(() {
      _roundsLog.add(aiRound);
      _resolving = false;
      _afterBattleStateChange();
    });
    _maybeAwardXp();
  }

  Future<void> _confirmSurrender() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.panel,
        surfaceTintColor: Colors.transparent,
        // Open L-bracket notched panel with an accent border, matching the
        // app's Rift Cyan panels rather than the default rounded card.
        shape: const OpenNotchBorder(
          side: BorderSide(color: Palette.accent),
          notch: 16,
        ),
        title: const Text(
          'SURRENDER?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
        content: const Text(
          'This immediately ends the battle as a defeat. This cannot be '
          'undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Palette.hairline),
              shape: _openBtnStyleShape,
            ),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Palette.danger,
              side: const BorderSide(color: Palette.danger),
              shape: _openBtnStyleShape,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('SURRENDER'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _clearSelection();
      _session!.surrender();
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
        // No back button: a mid-battle exit goes through Surrender (which
        // ends the match), and the Return to Home button appears once the
        // match is over. A scenario is the exception: it is a test, not a
        // match, so backing out of one costs nothing.
        automaticallyImplyLeading: widget.scenario != null,
        title: widget.tutorial && _tutorialActive
            ? const Text('Guided Tutorial')
            : widget.scenario != null
                ? Text(widget.scenario!.name)
                : null,
        actions: [
          if (widget.scenario != null)
            IconButton(
              icon: const Icon(Icons.checklist_rtl),
              tooltip: 'What to look for',
              onPressed: _showScenarioBrief,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_tutorialActive) _tutorialBanner(),
            if (widget.scenario != null) _scenarioBanner(widget.scenario!),
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

  /// A one-line reminder of what this scenario is for, with the full brief
  /// one tap away. A tester four turns deep should never have to go back to
  /// the picker to remember what they are watching.
  Widget _scenarioBanner(TestScenario scenario) {
    return InkWell(
      onTap: _showScenarioBrief,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Palette.accent.withValues(alpha: 0.10),
          border: const Border(
            bottom: BorderSide(color: Palette.hairline),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Palette.accent.withValues(alpha: 0.6),
                ),
              ),
              child: Text(
                scenario.item,
                style: const TextStyle(
                  color: Palette.accent,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                scenario.orderedSteps.first,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11.5),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'BRIEF',
              style: TextStyle(
                color: Palette.accent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showScenarioBrief() {
    final scenario = widget.scenario;
    if (scenario == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.panel,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              scenario.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ScenarioBriefBody(scenario: scenario),
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

    // Every other slot on **this** squad. The other squad is deliberately
    // not here: since item #14 both sides may field the same character, and
    // two Ilona Vances are two combatants with their own health, statuses and
    // position. One squad still cannot field her twice, which is what this
    // greys out.
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
                  _randomizeTeam(_teamAIds,
                      withProfile: false);
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
                  _randomizeTeam(_teamBIds,
                      withProfile: true);
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
        decoration: ShapeDecoration(
          color: active
              ? Palette.gold.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.03),
          shape: OpenNotchBorder(
            side: BorderSide(
              color: active ? Palette.gold : Colors.white24,
              width: active ? 1.5 : 1,
            ),
            notch: 12,
          ),
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

    return GestureDetector(
      // Tapping any non-interactive area (empty space, panel backgrounds)
      // dismisses the current ability/target/info selection. Buttons and
      // portraits win the tap on themselves, so only "dead" space clears.
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_selectedAction != null ||
            _infoCharacterId != null ||
            _showPlayerInfo ||
            _showOpponentInfo ||
            _selectedTargets.isNotEmpty) {
          setState(_clearSelection);
        }
      },
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
        _BattleTopBar(
          isOver: session.isOver,
          roundNumber: session.roundNumber,
          teamATrion: session.teamATrion,
          opponentName: opponentProfile.name,
          opponentSkillLabel: skillClassLabel[opponentProfile.skillClass]!,
          onPlayerTap: _resolving ? null : _showAccountInfo,
          onOpponentTap: _resolving ? null : _showOpponentAccountInfo,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 48,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: ShapeDecoration(
                  color: Theme.of(context).cardColor,
                  shape: const OpenNotchBorder(
                    side: BorderSide(color: Palette.teamA),
                    notch: 16,
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
                    const SizedBox(height: 16),
                    for (final fighter in session.teamA)
                      _playerFighterRow(fighter, session, tutorialStep),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Breathing room between the two squads, restored after the
            // battlefield panel moved out of this row. The gap reads as the
            // space between the two sides, which the battlefield strip below
            // then measures.
            const Expanded(flex: 22, child: SizedBox()),
            const SizedBox(width: 10),
            Expanded(
              flex: 30,
              child: TeamPanel(
                label: 'Opponent Squad',
                color: Palette.teamB,
                fighters: session.teamB,
                portraitSize: 96,
                compact: true,
                isOpponent: true,
                rank: opponentAccountRank,
                selectedIds: _selectedAction != null
                    ? _selectedTargets
                    : const {},
                eligibleIds: _eligibleTargets,
                onFighterTap: _resolving ? null : _onPortraitTap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _battlefieldRail(session),
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
          _xpAwardReadout(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  shape: _filledNotchShape,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.home_outlined, size: 18),
                label: const Text('RETURN TO HOME'),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: _openBtnStyleShape,
                  side: const BorderSide(color: Palette.accent, width: 1.5),
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                onPressed: _copyReport,
                child: const Text('COPY FULL REPORT'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The description panel outlives the battle. It used to be inside
          // the else-branch along with End Turn and the queue, so a finished
          // battle swapped the whole bar out for the banner: portraits and
          // ability slots stayed tappable, set the selection, and had nowhere
          // to draw it. A finished battle is exactly when a player wants to
          // look back over who was carrying what, so the panel stays, minus
          // the controls that only mean something on a live turn.
          _bottomActionBar(names),
        ] else ...[
          if (!_tutorialActive && _session!.queuedActions.isNotEmpty)
            // Inset to line up with the (now narrower) description box: the
            // left inset clears the side controls, the right inset clears the
            // fixed End Turn column.
            Padding(
              padding: const EdgeInsets.only(left: 170, right: 144),
              child: _queuedStrip(names),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sideControls(),
              const SizedBox(width: 10),
              Expanded(child: _bottomActionBar(names)),
              const SizedBox(width: 10),
              // End Turn lives in its own fixed-width column to the right of
              // the description box, so it stays put and visible no matter
              // what the description box is showing.
              SizedBox(
                width: 134,
                child: endTurnVisible
                    ? _endTurnButton()
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        BattleLogView(
          rounds: _roundsLog,
          teamAName: 'You',
          teamBName: 'Opponent',
          open: _battleLogOpen,
          onToggle: () => setState(() => _battleLogOpen = !_battleLogOpen),
        ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// The full-width lane diagram under both squad panels. It draws projected
  /// positions rather than live ones, so a queued move shows the moment it is
  /// queued; it shades the enemy lines the selected ability reaches from
  /// there; and its own cells are the move control, so position is read and
  /// changed in one place.
  Widget _battlefieldRail(PlaySession session) {
    // Either a selected ability or one being read about tells us whose band
    // to shade and whose distances to rule.
    final band = _selectedAction?.trigger.rangeTag ??
        _inspectedAbility?.trigger.rangeTag;
    // Focus follows either a selected ability or a tapped portrait, so a
    // character can be moved without first picking one of their abilities.
    final playerIds = {for (final f in session.teamA) f.id};
    final focused = _selectedCharacterId ??
        (playerIds.contains(_infoCharacterId) ? _infoCharacterId : null);
    return BattlefieldRail(
      teamA: session.teamA,
      teamB: session.teamB,
      projected: {
        for (final f in session.teamA) f.id: session.projectedPositionOf(f.id),
      },
      focusedId: focused,
      reachFrom: focused == null || band == null
          ? null
          : session.projectedPositionOf(focused),
      reachBand: band,
      legalSteps: focused == null || _tutorialActive
          ? const {}
          : session.legalRepositionsFor(focused).toSet(),
      onStep: (_resolving || focused == null || _tutorialActive)
          ? null
          : (to) => _stepTo(focused, to),
    );
  }

  /// Queues one step for [characterId] and refreshes the screen. Failures
  /// surface as a snack bar rather than silently doing nothing, because the
  /// stepper only offers steps it believes are legal, so a rejection means
  /// something changed underneath.
  void _stepTo(String characterId, BattlePosition destination) {
    final result = _session!.queueReposition(characterId, destination);
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'That move is not available.')),
      );
      return;
    }
    setState(() {
      // A move can put the selected ability out of band, so drop the
      // selection rather than leave a target picker pointing at nothing.
      _clearSelection();
      _afterBattleStateChange();
    });
  }

  /// One living player fighter's row: portrait/HP/status on the left, and
  /// (unlike the opponent's compact panel) its legal ability icons inline
  /// on the right, feeding the single shared bottom action bar below.
  Widget _playerFighterRow(
    FighterSnapshot fighter,
    PlaySession session,
    TutorialBattleStep? tutorialStep,
  ) {
    // Equipped abilities stay visible (grayed out via _abilityEnabled/the
    // AbilitySlot's own disabled-opacity treatment) even once the fighter
    // is dead, rather than disappearing from the row entirely.
    final displays = session.abilityDisplaysFor(fighter.id);
    final lockedRow =
        tutorialStep != null && tutorialStep.characterId != fighter.id;

    return Opacity(
      // A bailing body is not a corpse. It is still standing on its line,
      // still screening, and still the thing the enemy has to decide about,
      // so it is dimmed less than a defeated character and never as far.
      opacity: fighter.alive
          ? (lockedRow ? 0.4 : 1)
          : (fighter.bailingOut ? 0.7 : 0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
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
              rank: playerAccountRank,
              selected:
                  _selectedAction != null &&
                  _selectedTargets.contains(fighter.id),
              eligible: _eligibleTargets.contains(fighter.id),
              onTap: _resolving ? null : () => _onPortraitTap(fighter.id),
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
                            // Same three-way treatment the opponent's row
                            // already used: white while alive, dimmed but
                            // unstruck while bailing, struck through only
                            // once they are actually gone. Striking through
                            // a bailing body reads as "defeated", which is
                            // exactly what item #2 is not.
                            color: fighter.alive
                                ? Colors.white
                                : (fighter.bailingOut
                                    ? Colors.white70
                                    : Colors.white38),
                            decoration: (fighter.alive || fighter.bailingOut)
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
                      if (fighter.bailingOut) ...const [
                        SizedBox(width: 6),
                        BailingOutBadge(isOwnSquad: true),
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
                              stacks: s.stacks,
                              id: s.id,
                            ),
                        ],
                      ),
                    ),
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
    if (_tutorialActive) {
      if (step == null || step.characterId != fighterId) return true;
      return step.isFatStep || step.triggerId == display.trigger.id;
    }
    // Play mode: gray out anything that could not actually be queued right
    // now (already queued, out of ability uses this turn, unaffordable) or
    // while the turn is resolving. Un-queueing re-enables it.
    if (_resolving) return false;
    return _session!.canQueueAbility(fighterId, display.trigger.id);
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
        (_selectedAction?.trigger.id == t.id ||
            _inspectedAbility?.trigger.id == t.id);
    final highlight =
        tutorialStep?.triggerId == t.id &&
        tutorialStep?.characterId == fighter.id;
    final enabled = _abilityEnabled(tutorialStep, fighter.id, display);
    // Waiting on an action rather than on range: the step already brought it
    // into band, and only a FAT turn buys both. Its own state, because the
    // fix is different from every other reason an ability is dark.
    final pending =
        !enabled && display.reachableAfterMove && fighter.alive && !_resolving;
    return AbilitySlot(
      icon: TriggerIcon(trigger: t, size: 28),
      selected: isSelected,
      highlighted: !isSelected && highlight,
      // `dimmed` rather than `enabled: false`: it gives the same unavailable
      // look but keeps the slot tappable, which is what lets an unusable
      // ability still open its description.
      enabled: true,
      dimmed: !enabled,
      pending: pending,
      // A dead fighter's abilities are just grayed out like the rest of its
      // row; no cooldown number is shown on them.
      cooldownRemaining: fighter.alive ? display.cooldownRemaining : 0,
      // No tooltip: an ability explains itself in the description panel when
      // tapped. Tooltips are reserved for status effects.
      tooltip: null,
      // Every ability is tappable, usable or not. A usable one is selected
      // for targeting; anything else opens its description with the reason it
      // is unavailable, which is the only way the player can learn the reason.
      onTap: _resolving
          ? null
          : () {
              if (isSelected) {
                setState(_clearSelection);
              } else if (enabled && action != null) {
                _selectAbility(fighter.id, action);
              } else {
                _inspectAbility(fighter.id, display);
              }
            },
      size: 60,
    );
  }

  /// Play mode: the actions the player has committed to the turn queue but
  /// not yet resolved, each removable (refunding its Trion) until End Turn.
  Widget _queuedStrip(Map<String, String> names) {
    final queued = _session!.queuedActions;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Palette.teamA.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'QUEUED THIS TURN',
            style: TextStyle(
              color: Palette.teamA,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < queued.length; i++)
            _queuedRow(i, queued[i], names),
        ],
      ),
    );
  }

  Widget _queuedRow(int index, QueuedAction q, Map<String, String> names) {
    final String label;
    if (q.isReposition) {
      // A queued move has no trigger to look up, and it resolves ahead of
      // every ability, so it says so rather than reading like just another
      // line in click order.
      label = 'move to the ${q.destination!.label.toLowerCase()} line (first)';
    } else {
      final trigger = _session!.equippedA[q.characterId]!.firstWhere(
        (t) => t.id == q.triggerId,
      );
      final targetLabel = q.targetIds.map((id) => names[id] ?? id).join(', ');
      label =
          '${trigger.name}${targetLabel.isEmpty ? '' : ' -> $targetLabel'}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${names[q.characterId] ?? q.characterId}: $label',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Palette.danger,
              side: const BorderSide(color: Palette.danger),
              shape: const OpenNotchBorder(notch: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _resolving
                ? null
                : () => setState(() {
                    _session!.unqueue(index);
                    _afterBattleStateChange();
                  }),
            icon: const Icon(Icons.close, size: 14),
            label: const Text('UNQUEUE'),
          ),
        ],
      ),
    );
  }

  /// The Surrender / Chat / BGM volume strip that sits to the left of the
  /// ability description panel, matching the reference's bottom-left
  /// controls. Chat has no backend in this single-player-vs-AI mode, and
  /// there's no audio system yet either, so both are presentational;
  /// Surrender is fully functional (see [_confirmSurrender]).
  Widget _sideControls() {
    return Container(
      width: 160,
      padding: const EdgeInsets.only(right: 14),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Colors.white24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Palette.danger,
              side: const BorderSide(color: Palette.danger, width: 1.5),
              shape: _openBtnStyleShape,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            onPressed: _confirmSurrender,
            child: const Text('SURRENDER'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              shape: _openBtnStyleShape,
              side: const BorderSide(color: Palette.accent, width: 1.5),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Chat is not available in this mode.'),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_outline, size: 16),
            label: const Text('CHAT'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                _volume == 0 ? Icons.volume_off : Icons.volume_up,
                color: Colors.white54,
                size: 16,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(
                    context,
                  ).copyWith(thumbShape: const _DiamondSliderThumbShape()),
                  child: Slider(
                    value: _volume,
                    onChanged: (v) => setState(() => _volume = v),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The single shared description panel to the right of the side controls.
  /// It shows the selected ability (with a portrait-driven target picker and
  /// a selected/total counter) or, when no ability is mid-selection, a
  /// preview of whichever portrait was last tapped. End Turn no longer lives
  /// here - it has its own fixed column (see [_endTurnButton]).
  Widget _bottomActionBar(Map<String, String> names) {
    if (_resolving) {
      return _descPanel(
        const Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              'Resolving...',
              style: TextStyle(color: Palette.accent, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final action = _selectedAction;
    final charId = _selectedCharacterId;
    if (action != null && charId != null) {
      return _abilityPanel(action, charId, names);
    }
    final inspected = _inspectedAbility;
    if (inspected != null && charId != null) {
      return _blockedAbilityPanel(inspected, charId);
    }
    if (_infoCharacterId != null) {
      return _characterInfoPanel(_infoCharacterId!);
    }
    if (_showPlayerInfo) {
      return _descPanel(
        PlayerPanel(
          squadIds: _teamAIds.whereType<String>().toList(),
          bordered: false,
          compact: true,
          showSquad: false,
        ),
      );
    }
    if (_showOpponentInfo) {
      return _opponentInfoPanel();
    }
    return const SizedBox.shrink();
  }

  /// The opponent AI profile preview: name, skill tier, and its behavioural
  /// description - the mirror of the player-account preview.
  Widget _opponentInfoPanel() {
    final profile = profileById(_profileBId!);
    return _descPanel(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Palette.teamB.withValues(alpha: 0.12),
              border: Border.all(color: Palette.teamB, width: 1.5),
            ),
            child: const Icon(Icons.person, color: Palette.teamB, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${skillClassLabel[profile.skillClass]!} AI',
                  style: const TextStyle(color: Palette.teamB, fontSize: 11),
                ),
                const SizedBox(height: 6),
                Text(
                  profile.description,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The description panel for an ability the player cannot use right now.
  /// Same blurb as the usable version, with the reason in place of the target
  /// picker and the Queue button. Out of range and "the move used your action"
  /// are both fixable on the spot, so they are stated in full rather than
  /// left as a grey icon.
  Widget _blockedAbilityPanel(AbilityDisplay display, String charId) {
    final t = display.trigger;
    final reasonColor = display.reachableAfterMove
        ? Palette.warn
        : display.blockedByRange
        ? Palette.accent
        : Colors.white54;
    return _descPanel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TriggerIcon(trigger: t, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.name.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              TagChip(t.rangeTag.label),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            describeTrigger(t),
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          if (display.blockedReason != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  display.reachableAfterMove
                      ? Icons.timer_outlined
                      : Icons.block_outlined,
                  size: 15,
                  color: reasonColor,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    display.blockedReason!,
                    style: TextStyle(color: reasonColor, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The open-notch accent panel that wraps every description-panel state.
  Widget _descPanel(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: const ShapeDecoration(
        shape: OpenNotchBorder(
          side: BorderSide(color: Palette.accent),
          notch: 14,
        ),
      ),
      child: child,
    );
  }

  /// The selected-ability description: the ability blurb plus a target
  /// instruction line (a live selected/total counter for multi-target and
  /// Burst abilities) and the Queue/Use button. Targets are chosen by
  /// tapping portraits, not from a list here.
  Widget _abilityPanel(
    LegalAction action,
    String charId,
    Map<String, String> names,
  ) {
    final t = action.trigger;

    Widget targetLine;
    if (t.targetAffiliation == TargetAffiliation.self) {
      targetLine = _targetHint('Self-cast: ${names[charId]} highlighted.');
    } else if (t.attackSubtype == AttackSubtype.aoe) {
      targetLine = _targetHint(
        _selectedTargets.isEmpty
            ? 'Area of effect: tap anyone to aim at their whole line. It '
                'catches up to ${action.maxTargets} standing there, and '
                'nobody on any other line.'
            : 'Aimed at ${_lineLabelOf(_selectedTargets.first)}: '
                '${_selectedTargets.length} caught.',
      );
    } else if (action.maxTargets > 1) {
      targetLine = Row(
        children: [
          const Expanded(
            child: Text(
              'Tap portraits to pick targets',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
          _targetCounter(_selectedTargets.length, action.maxTargets),
        ],
      );
    } else {
      final only = _selectedTargets.firstOrNull;
      targetLine = _targetHint(
        only == null
            ? "Tap a target's portrait to select it."
            : 'Target: ${names[only]}',
      );
    }

    final canUse =
        _selectedTargets.isNotEmpty ||
        t.targetAffiliation == TargetAffiliation.self;

    return _descPanel(
      Column(
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
          targetLine,
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: _filledNotchShape,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              onPressed: canUse
                  ? () {
                      final targets =
                          t.targetAffiliation == TargetAffiliation.self
                          ? [charId]
                          : _selectedTargets.take(action.maxTargets).toList();
                      // The tutorial resolves immediately; Play mode queues.
                      if (_tutorialActive) {
                        _useAbility(charId, action, targets);
                      } else {
                        _queueAbility(charId, action, targets);
                      }
                    }
                  : null,
              child: Text(
                _actionButtonLabel(t, names, _tutorialActive ? 'USE' : 'QUEUE'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetHint(String text) => Text(
    text,
    style: const TextStyle(color: Colors.white54, fontSize: 11),
  );

  /// The "currently selected / total selectable" counter shown for
  /// multi-target and Burst abilities.
  Widget _targetCounter(int selected, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(
        color: Palette.gold.withValues(alpha: 0.12),
        shape: const OpenNotchBorder(
          side: BorderSide(color: Palette.gold),
          notch: 6,
        ),
      ),
      child: Text(
        '$selected / $total',
        style: const TextStyle(
          color: Palette.gold,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  /// The portrait-preview state of the description panel: a tapped
  /// character's identity, health, flavor, and active status effects.
  /// The clickable-portrait detail panel (combat-v2 §10). Your own fighters
  /// show full intel (stats, Side Effect, and the equipped loadout). Opponent
  /// fighters show public intel only (type, base stats, Side Effect,
  /// current HP,
  /// visible statuses, account rank); their loadout stays hidden unless a
  /// Mind's Eye has revealed it, at which point their abilities are listed.
  Widget _characterInfoPanel(String id) {
    final fighter = _fighterById(id);
    if (fighter == null) return const SizedBox.shrink();
    // `id` is a combatant id here (item #14). The roster, the flavour text
    // and the portrait art are all properties of the character, not of the
    // combatant, so they are asked for by the character's own id.
    final characterId = CombatantIds.characterOf(id);
    final character = roster[characterId];
    final flavor = characterFlavor[characterId];
    final isOwn = _session!.teamA.any((f) => f.id == id);
    final revealed = isOwn || _session!.revealedEnemyIds.contains(id);
    final loadout = isOwn ? _session!.loadoutsA[id] : _session!.loadoutsB[id];
    return _descPanel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PortraitTile(
                characterId: id,
                name: fighter.name,
                type: fighter.type,
                size: 48,
                showRank: false,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            fighter.name.toUpperCase(),
                            style: TextStyle(
                              color: fighter.alive
                                  ? Colors.white
                                  : Colors.white38,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          '${fighter.currentHealth}/${fighter.maxHealth} HP',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          typeLabel[fighter.type]!,
                          style: const TextStyle(
                            color: Palette.accent,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isOwn ? 'FULL INTEL' : 'PUBLIC INTEL',
                          style: TextStyle(
                            color: isOwn ? Palette.teamA : Palette.teamB,
                            fontSize: 9,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    if (!isOwn) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Rank ${(placeholderRanks[id] ?? opponentAccountRank).label}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (character?.sideEffect != null) ...[
            const SizedBox(height: 8),
            Text(
              character!.sideEffect!.name,
              style: const TextStyle(
                color: Palette.gold,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              character.sideEffect!.description,
              style: const TextStyle(color: Colors.white54, fontSize: 10.5),
            ),
          ],
          if (flavor != null) ...[
            const SizedBox(height: 6),
            Text(
              flavor,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (character != null) ...[
            const SizedBox(height: 8),
            CharacterStatRow(stats: character.baseStats),
          ],
          if (fighter.statusEffects.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 3,
              runSpacing: 3,
              children: [
                for (final s in fighter.statusEffects)
                  StatusBadge(
                    name: s.name,
                    remainingTurns: s.remainingTurns,
                    stacks: s.stacks,
                    id: s.id,
                    onSelf: isOwn,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          _loadoutIntel(loadout, isOwn: isOwn, revealed: revealed),
        ],
      ),
    );
  }

  /// The abilities readout inside the character detail panel. Own fighters
  /// list their equipped Triggers outright; enemy fighters only list them
  /// once Mind's Eye has revealed the loadout, otherwise a hidden-intel hint
  /// stands in.
  Widget _loadoutIntel(
    Loadout? loadout, {
    required bool isOwn,
    required bool revealed,
  }) {
    final header = Text(
      isOwn ? 'LOADOUT' : (revealed ? 'REVEALED LOADOUT' : 'LOADOUT'),
      style: TextStyle(
        color: revealed ? Colors.white38 : Palette.teamB,
        fontSize: 9,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w700,
      ),
    );
    if (!revealed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 3),
          const Text(
            'Hidden. Reveal it with Mind\'s Eye.',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }
    final actives =
        loadout?.triggers.whereType<ActiveTrigger>().toList() ??
        const <ActiveTrigger>[];
    final bt = loadout?.blackTrigger;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final t in actives)
              _abilityChip(
                t.name,
                false,
                onTap: () => _showAbilityDetail(t.name, describeTrigger(t)),
              ),
            if (bt != null)
              _abilityChip(
                bt.name,
                true,
                onTap: () => _showAbilityDetail(bt.name, _describeBlackTrigger(bt)),
              ),
            if (actives.isEmpty && bt == null)
              const Text(
                'No abilities equipped.',
                style: TextStyle(color: Colors.white38, fontSize: 10.5),
              ),
          ],
        ),
      ],
    );
  }

  Widget _abilityChip(String label, bool isBlackTrigger, {VoidCallback? onTap}) {
    final color = isBlackTrigger ? Palette.gold : Palette.accent;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isBlackTrigger ? Palette.gold : Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 3),
              Icon(Icons.info_outline, size: 11, color: color),
            ],
          ],
        ),
      ),
    );
  }

  String _describeBlackTrigger(BlackTrigger bt) {
    final parts = <String>[bt.description];
    if (bt.activeAbilities.isNotEmpty) {
      parts.add(
        'Abilities: ${bt.activeAbilities.map((a) => a.name).join(', ')}.',
      );
    }
    return parts.join(' ');
  }

  void _showAbilityDetail(String name, String description) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.panel,
        title: Text(
          name,
          style: const TextStyle(color: Colors.white, fontSize: 15),
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

  FighterSnapshot? _fighterById(String id) {
    for (final f in [..._session!.teamA, ..._session!.teamB]) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// The fixed End Turn button, always in the same spot to the right of the
  /// description panel.
  Widget _endTurnButton() {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        fixedSize: const Size(134, 48),
        padding: EdgeInsets.zero,
        shape: _openBtnStyleShape,
        side: const BorderSide(color: Palette.accent, width: 1.5),
        foregroundColor: Colors.white,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          fontSize: 14,
        ),
      ),
      onPressed: _endTurn,
      child: const Text('END TURN'),
    );
  }

  String _actionButtonLabel(
    ActiveTrigger t,
    Map<String, String> names,
    String verb,
  ) {
    if (t.targetAffiliation == TargetAffiliation.self) return '$verb (SELF)';
    if (_selectedTargets.length > 1) {
      return '$verb (${_selectedTargets.length} TARGETS)';
    }
    final only = _selectedTargets.firstOrNull;
    return only == null
        ? verb
        : '$verb ON ${(names[only] ?? only).toUpperCase()}';
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

  /// Tapping a top-bar portrait previews that side's info in the description
  /// panel (player account / opponent AI profile). Null while resolving.
  final VoidCallback? onPlayerTap;
  final VoidCallback? onOpponentTap;

  const _BattleTopBar({
    required this.isOver,
    required this.roundNumber,
    required this.teamATrion,
    required this.opponentName,
    required this.opponentSkillLabel,
    this.onPlayerTap,
    this.onOpponentTap,
  });

  /// A name/subtitle block with its portrait, matching the Naruto-Arena
  /// reference: the portrait sits toward the center of the bar (between
  /// the name block and the round/Trion readout) on both sides. The name
  /// text is justified off the portrait: the player's name hugs the left
  /// of its portrait and extends leftward; the opponent's hugs the right
  /// of its portrait and extends rightward.
  Widget _identity(
    String name,
    String? subtitle,
    Color color, {
    required bool portraitFirst,
    VoidCallback? onPortraitTap,
  }) {
    // portraitFirst == true is the opponent side (portrait then name,
    // text extends right); false is the player side (name then portrait,
    // text extends left).
    final textAlign = portraitFirst ? TextAlign.left : TextAlign.right;
    final crossAxis = portraitFirst
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.end;
    final nameBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxis,
      children: [
        Text(
          name,
          textAlign: textAlign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle,
            textAlign: textAlign,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 10.5),
          ),
      ],
    );
    final portrait = _TopBarPortrait(color: color, onTap: onPortraitTap);
    // The portrait sits at the inner edge (a fixed 12px from the divider,
    // so both portraits are equidistant from the center round/Trion box);
    // the name block hugs the portrait and its text grows outward.
    final huggedName = Expanded(
      child: Align(
        alignment: portraitFirst ? Alignment.centerLeft : Alignment.centerRight,
        child: nameBlock,
      ),
    );
    return Row(
      children: portraitFirst
          ? [portrait, const SizedBox(width: 12), huggedName]
          : [huggedName, const SizedBox(width: 12), portrait],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
      decoration: ShapeDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        shape: OpenNotchBorder(
          side: BorderSide(color: isOver ? Colors.white24 : Palette.accent),
          notch: 14,
        ),
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
              children: [
                Expanded(
                  child: _identity(
                    playerDisplayName,
                    null,
                    Palette.gold,
                    portraitFirst: false,
                    onPortraitTap: onPlayerTap,
                  ),
                ),
                const SizedBox(width: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  decoration: ShapeDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    shape: OpenNotchBorder(
                      side: BorderSide(
                        color: Palette.accent.withValues(alpha: 0.7),
                      ),
                      notch: 10,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ROUND $roundNumber',
                        style: const TextStyle(
                          color: Palette.accent,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '⟡ Trion Available: $teamATrion',
                        style: const TextStyle(
                          color: Palette.gold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _identity(
                    opponentName,
                    opponentSkillLabel,
                    Palette.teamB,
                    portraitFirst: true,
                    onPortraitTap: onOpponentTap,
                  ),
                ),
              ],
            ),
    );
  }
}

/// A small generic profile portrait for the top bar - neither the player
/// nor an AI opponent profile has real avatar art, so this borrows the
/// same bordered-icon treatment used elsewhere (e.g. [PlayerPanel]'s own
/// portrait) recolored per side.
class _TopBarPortrait extends StatelessWidget {
  final Color color;

  /// Makes the portrait tappable (the player side uses this to preview the
  /// account info). Null leaves it non-interactive (the opponent side).
  final VoidCallback? onTap;

  const _TopBarPortrait({required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    const size = 84.0; // three times the original 28px top-bar portrait
    final tile = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Icon(Icons.person, color: color, size: size * 0.6),
    );
    if (onTap == null) return tile;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, child: tile),
    );
  }
}

/// A diamond (square rotated 45 degrees) slider thumb, so the volume
/// control's handle matches the app's square-cornered styling instead of
/// the default circular thumb.
class _DiamondSliderThumbShape extends SliderComponentShape {
  static const double halfSize = 8;
  const _DiamondSliderThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(halfSize);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final paint = Paint()
      ..color = sliderTheme.thumbColor ?? Colors.white
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(center.dx, center.dy - halfSize)
      ..lineTo(center.dx + halfSize, center.dy)
      ..lineTo(center.dx, center.dy + halfSize)
      ..lineTo(center.dx - halfSize, center.dy)
      ..close();
    canvas.drawPath(path, paint);
  }
}

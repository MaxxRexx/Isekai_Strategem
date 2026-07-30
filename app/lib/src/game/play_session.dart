import 'dart:math';

import 'package:battle_engine/battle_engine.dart';

import 'battle_models.dart';
import 'draft.dart';

/// A legal ability use for one of the player's characters right now:
/// the trigger itself plus everything the target picker needs.
class LegalAction {
  final ActiveTrigger trigger;
  final List<String> legalTargetIds;
  final int maxTargets;
  final int actualTrionCost;
  final bool affordable;

  const LegalAction({
    required this.trigger,
    required this.legalTargetIds,
    required this.maxTargets,
    required this.actualTrionCost,
    required this.affordable,
  });
}

/// One of a character's equipped Active Triggers, shown in the battle UI
/// regardless of whether it's usable right now - unlike [LegalAction],
/// which only lists what's currently legal, this also covers abilities on
/// cooldown (or otherwise blocked) so the UI can show them grayed out
/// with a cooldown-turns overlay instead of omitting them entirely.
class AbilityDisplay {
  final ActiveTrigger trigger;

  /// Non-null iff this ability could legally be used right now (subject
  /// to [LegalAction.affordable] on top of that).
  final LegalAction? legalAction;

  /// Turns remaining before this ability comes off cooldown (0 if it
  /// isn't on cooldown - it may still be unusable for another reason,
  /// e.g. insufficient Trion or an action-preventing status effect).
  final int cooldownRemaining;

  const AbilityDisplay({
    required this.trigger,
    required this.legalAction,
    required this.cooldownRemaining,
  });

  bool get usable => legalAction != null && legalAction!.affordable;
}

class UseAbilityOutcome {
  final bool success;
  final String? error;
  final LogAction? action;

  const UseAbilityOutcome.failure(this.error) : success = false, action = null;
  const UseAbilityOutcome.done(LogAction this.action)
    : success = true,
      error = null;
}

/// A player action committed to the turn queue but not yet resolved. Its
/// Trion cost is already spent (refunded on [PlaySession.unqueue]); no
/// effects are applied and no cooldown is set until the queue resolves at
/// end of turn via [PlaySession.resolveQueue].
class QueuedAction {
  final String characterId;
  final String triggerId;
  final List<String> targetIds;

  /// Trion actually spent when this action was queued, tracked so that
  /// un-queueing refunds the exact amount.
  final int trionSpent;

  QueuedAction({
    required this.characterId,
    required this.triggerId,
    required this.targetIds,
    required this.trionSpent,
  });
}

/// Result of trying to [PlaySession.queue] an action.
class QueueOutcome {
  final bool success;
  final String? error;

  const QueueOutcome.ok() : success = true, error = null;
  const QueueOutcome.failure(this.error) : success = false;
}

/// A live player-vs-AI battle: the player drives team A turn by turn,
/// the AI plays team B automatically between the player's turns. Native
/// port of the web demo bridge's session API.
class PlaySession {
  final Battle battle;
  final Map<String, List<ActiveTrigger>> equippedA;
  final Map<String, List<ActiveTrigger>> equippedB;
  final Map<String, Loadout> loadoutsA;
  final Map<String, Loadout> loadoutsB;
  final ProfileDrivenAi aiB;

  /// Set when team B randomly won the opening move: its entire opening
  /// turn, resolved before the session surfaces (the player's session
  /// always begins on their own turn).
  LogRound? openingAiRound;

  /// Player actions committed this turn but not yet resolved (see [queue]/
  /// [resolveQueue]). Trion is spent as actions are queued and refunded on
  /// [unqueue]; effects and cooldowns are applied only when the queue
  /// resolves at end of turn.
  final List<QueuedAction> _queue = [];

  PlaySession._({
    required this.battle,
    required this.equippedA,
    required this.equippedB,
    required this.loadoutsA,
    required this.loadoutsB,
    required this.aiB,
  });

  /// [firstTurn] is 'teamA', 'teamB', or 'random' (the default, matching
  /// the real rules - the Guided Tutorial passes 'teamA' so its scripted
  /// walkthrough stays predictable). Player Loadouts must already be
  /// valid; this throws [ArgumentError] otherwise.
  factory PlaySession.start({
    required List<String> playerCharacterIds,
    required Map<String, Loadout> playerLoadouts,
    required List<String> opponentCharacterIds,
    required String opponentProfileId,
    String firstTurn = 'random',
  }) {
    for (final id in playerCharacterIds) {
      final validation = playerLoadouts[id]!.validateFor(roster[id]);
      if (!validation.isValid) {
        throw ArgumentError(
          'Invalid Loadout for $id: ${validation.errors.join('; ')}',
        );
      }
    }

    final teamADraft = DraftedTeam.fromLoadouts(
      teamId: 'player',
      characterIds: playerCharacterIds,
      loadouts: playerLoadouts,
    );
    final teamBDraft = DraftedTeam.draftWithProfile(
      teamId: 'ai',
      characterIds: opponentCharacterIds,
      profile: profileById(opponentProfileId),
    );

    final teamAGoesFirst = switch (firstTurn) {
      'teamA' => true,
      'teamB' => false,
      _ => Random().nextBool(),
    };

    final battle = Battle(
      teamA: teamADraft.team,
      teamB: teamBDraft.team,
      states: {...teamADraft.states, ...teamBDraft.states},
      teamAGoesFirst: teamAGoesFirst,
    );

    final session = PlaySession._(
      battle: battle,
      equippedA: teamADraft.equippedActiveTriggers,
      equippedB: teamBDraft.equippedActiveTriggers,
      loadoutsA: teamADraft.loadouts,
      loadoutsB: teamBDraft.loadouts,
      aiB: ProfileDrivenAi(profileById(opponentProfileId)),
    );

    if (teamAGoesFirst) {
      battle.startTurn(equippedActiveTriggers: session.equippedA);
    } else {
      // Resolve team B's entire opening turn immediately rather than
      // surfacing a session that starts on the opponent's turn with
      // nothing for the player to do yet.
      session.openingAiRound = session._playAiTurns();
      if (!battle.isOver) {
        battle.startTurn(equippedActiveTriggers: session.equippedA);
      }
    }
    return session;
  }

  /// Immediately ends the battle as a loss for the player: zeroes every
  /// one of team A's characters' health so `outcome`/`isOver` resolve to
  /// `teamBWins` through the same defeat-detection every other loss uses,
  /// rather than needing a separate "surrendered" outcome variant.
  void surrender() {
    for (final c in battle.teamA.characters) {
      battle.states[c.id]!.currentHealth = 0;
    }
  }

  bool get isOver => battle.isOver;
  BattleOutcome get outcome => battle.outcome;
  int get roundNumber => battle.roundNumber;
  bool get isPlayerTurn => battle.isTeamATurn;
  int get teamATrion => battle.teamA.trionPool.current;
  int get teamBTrion => battle.teamB.trionPool.current;

  List<FighterSnapshot> get teamA => [
    for (final c in battle.teamA.characters)
      fighterSnapshot(battle.states[c.id]!),
  ];
  List<FighterSnapshot> get teamB => [
    for (final c in battle.teamB.characters)
      fighterSnapshot(battle.states[c.id]!),
  ];

  /// Only meaningful during the player's own turn, for one of their own
  /// living characters; returns an empty list otherwise.
  List<LegalAction> legalActionsFor(String characterId) {
    final state = battle.states[characterId]!;
    final engine = battle.turnEngine;
    if (!battle.isTeamATurn || !state.isAlive) return const [];

    final actions = <LegalAction>[];
    for (final trigger in equippedA[characterId] ?? const <ActiveTrigger>[]) {
      if (!engine.canUseAbility(state, trigger)) continue;

      List<String> legalTargetIds;
      int maxTargets;
      if (trigger.targetAffiliation == TargetAffiliation.self) {
        legalTargetIds = [characterId];
        maxTargets = 1;
      } else {
        final pool = trigger.targetAffiliation == TargetAffiliation.opponent
            ? battle.teamB.characters.map((c) => battle.states[c.id]!)
            : battle.teamA.characters.map((c) => battle.states[c.id]!);
        legalTargetIds = pool
            .where(
              (t) =>
                  t.isAlive &&
                  (trigger.targetAffiliation != TargetAffiliation.opponent ||
                      engine.canTarget(state, t)),
            )
            .map((t) => t.character.id)
            .toList();
        maxTargets = trigger.rangeTag == RangeTag.ranged
            ? engine.maxRangedTargets(state, trigger)
            : trigger.targetCount;
      }

      final actualTrionCost = (trigger.trionCost * state.trionCostMultiplier())
          .round();
      actions.add(
        LegalAction(
          trigger: trigger,
          legalTargetIds: legalTargetIds,
          maxTargets: maxTargets,
          actualTrionCost: actualTrionCost,
          affordable: actualTrionCost <= battle.teamA.trionPool.current,
        ),
      );
    }
    return actions;
  }

  /// Every equipped Active Trigger for [characterId], each paired with its
  /// current legality (if any) and cooldown - unlike [legalActionsFor],
  /// this never omits an ability just because it's on cooldown or
  /// otherwise blocked right now, so the battle UI can render it grayed
  /// out (with a cooldown overlay) instead of making it disappear.
  List<AbilityDisplay> abilityDisplaysFor(String characterId) {
    final state = battle.states[characterId]!;
    final legalById = {
      for (final action in legalActionsFor(characterId))
        action.trigger.id: action,
    };
    return [
      for (final trigger in equippedA[characterId] ?? const <ActiveTrigger>[])
        AbilityDisplay(
          trigger: trigger,
          legalAction: legalById[trigger.id],
          cooldownRemaining: state.cooldowns[trigger.id] ?? 0,
        ),
    ];
  }

  UseAbilityOutcome useAbility(
    String characterId,
    String triggerId,
    List<String> targetIds,
  ) {
    final engine = battle.turnEngine;
    final state = battle.states[characterId]!;
    final trigger = equippedA[characterId]!.firstWhere(
      (t) => t.id == triggerId,
    );

    if (!engine.canUseAbility(state, trigger)) {
      return const UseAbilityOutcome.failure(
        'That ability is not usable right now.',
      );
    }
    if (!engine.useAbility(state, trigger, battle.teamA.trionPool)) {
      return const UseAbilityOutcome.failure('Not enough Trion.');
    }

    final useResult = engine.resolveAbilityUse(
      attacker: state,
      trigger: trigger,
      targets: [for (final id in targetIds) battle.states[id]!],
    );

    return UseAbilityOutcome.done(
      LogAction(
        characterId: characterId,
        characterName: state.character.name,
        triggerId: trigger.id,
        triggerName: trigger.name,
        fatTriggered: state.fatTriggeredThisTurn,
        targets: logTargets(battle, useResult),
      ),
    );
  }

  /// The player's currently queued actions, in the order they were added.
  List<QueuedAction> get queuedActions => List.unmodifiable(_queue);

  /// How many actions [characterId] currently has queued, counted against
  /// its per-turn ability limit.
  int queuedCountFor(String characterId) =>
      _queue.where((q) => q.characterId == characterId).length;

  /// Commits one of the player's abilities to the turn queue: validates
  /// legality, spends its Trion cost now (refunded by [unqueue]), and
  /// records it for resolution at end of turn. Does not apply any effect
  /// or set a cooldown yet - that happens in [resolveQueue].
  QueueOutcome queue(
    String characterId,
    String triggerId,
    List<String> targetIds,
  ) {
    if (!battle.isTeamATurn) {
      return const QueueOutcome.failure('It is not your turn.');
    }
    final state = battle.states[characterId];
    if (state == null || !state.isAlive) {
      return const QueueOutcome.failure('That character cannot act.');
    }
    ActiveTrigger? trigger;
    for (final t in equippedA[characterId] ?? const <ActiveTrigger>[]) {
      if (t.id == triggerId) {
        trigger = t;
        break;
      }
    }
    if (trigger == null) {
      return const QueueOutcome.failure('That ability is not equipped.');
    }
    final engine = battle.turnEngine;
    if (!engine.canUseAbility(state, trigger)) {
      return const QueueOutcome.failure(
        'That ability is not usable right now.',
      );
    }
    if (_queue.any(
      (q) => q.characterId == characterId && q.triggerId == triggerId,
    )) {
      return const QueueOutcome.failure('That ability is already queued.');
    }
    // The engine only records ability uses (and so enforces the per-turn
    // FAT limit) at resolution, so enforce that limit here against what is
    // already queued plus anything already resolved this turn.
    final maxUses = engine.fatEngine.maxAbilitiesThisTurn(state);
    if (state.abilitiesUsedThisTurnCount + queuedCountFor(characterId) >=
        maxUses) {
      return const QueueOutcome.failure('No ability uses left this turn.');
    }
    final cost = (trigger.trionCost * state.trionCostMultiplier()).round();
    if (!battle.teamA.trionPool.trySpend(cost)) {
      return const QueueOutcome.failure('Not enough Trion.');
    }
    _queue.add(
      QueuedAction(
        characterId: characterId,
        triggerId: triggerId,
        targetIds: List.of(targetIds),
        trionSpent: cost,
      ),
    );
    return const QueueOutcome.ok();
  }

  /// Removes the queued action at [index] and refunds its Trion. Returns
  /// false if [index] is out of range.
  bool unqueue(int index) {
    if (index < 0 || index >= _queue.length) return false;
    final action = _queue.removeAt(index);
    battle.teamA.trionPool.gain(action.trionSpent);
    return true;
  }

  /// Clears the whole queue, refunding all Trion spent on queued actions.
  void clearQueue() {
    for (final action in _queue) {
      battle.teamA.trionPool.gain(action.trionSpent);
    }
    _queue.clear();
  }

  /// Resolves every queued player action - applying its effects and
  /// recording the use so end-of-turn cooldowns are set - and returns them
  /// as a single [LogRound]. Trion was already spent at queue time.
  ///
  /// A1: actions resolve in the order they were queued; the phase-priority
  /// ordering lands in A2. Call this before [endTurn].
  LogRound resolveQueue() {
    final engine = battle.turnEngine;
    final actions = <LogAction>[];
    for (final q in _queue) {
      final state = battle.states[q.characterId]!;
      final trigger = equippedA[q.characterId]!.firstWhere(
        (t) => t.id == q.triggerId,
      );
      // Trion was spent when queued; record the use here (without
      // re-spending) so the FAT count and end-of-turn cooldowns are set.
      state.recordAbilityUse(trigger);
      final useResult = engine.resolveAbilityUse(
        attacker: state,
        trigger: trigger,
        targets: [for (final id in q.targetIds) battle.states[id]!],
      );
      actions.add(
        LogAction(
          characterId: q.characterId,
          characterName: state.character.name,
          triggerId: trigger.id,
          triggerName: trigger.name,
          fatTriggered: state.fatTriggeredThisTurn,
          targets: logTargets(battle, useResult),
        ),
      );
    }
    final round = LogRound(
      roundNumber: battle.roundNumber,
      team: 'A',
      actions: actions,
    );
    _queue.clear();
    return round;
  }

  /// Ends the player's turn, plays out the AI's turn, and starts the
  /// player's next turn (unless the battle ends first). Returns the AI's
  /// turn as a log round.
  LogRound endTurn() {
    battle.endTurn();
    final aiRound = _playAiTurns();
    if (!battle.isOver) {
      battle.startTurn(equippedActiveTriggers: equippedA);
    }
    return aiRound;
  }

  /// Forces Full Arms Trigger active for the rest of this character's
  /// current turn, bypassing the normal FAT Chance roll. Not part of the
  /// real rules; exists solely so the Guided Tutorial can demonstrate the
  /// FAT mechanic deterministically.
  void forceFat(String characterId) {
    battle.states[characterId]!.fatTriggeredThisTurn = true;
  }

  /// Resolves consecutive AI (team B) turns - normally just one -
  /// stopping once control returns to team A or the battle ends.
  LogRound _playAiTurns() {
    final actions = <LogAction>[];
    var aiRoundNumber = battle.roundNumber;
    while (!battle.isTeamATurn && !battle.isOver) {
      battle.startTurn(equippedActiveTriggers: equippedB);
      aiRoundNumber = battle.roundNumber;
      if (battle.isOver) break;

      final actionResults = aiB.takeTurn(
        battle,
        equippedActiveTriggers: equippedB,
      );
      for (final result in actionResults) {
        actions.add(
          logActionFor(
            battle,
            equippedB[result.characterId]!.firstWhere(
              (t) => t.id == result.triggerId,
            ),
            result,
          ),
        );
      }

      if (battle.isOver) break;
      battle.endTurn();
    }
    return LogRound(roundNumber: aiRoundNumber, team: 'B', actions: actions);
  }
}

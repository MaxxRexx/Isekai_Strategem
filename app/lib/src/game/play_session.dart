import 'package:battle_engine/battle_engine.dart';

import 'account.dart';
import 'battle_models.dart';
import 'draft.dart';
import 'team_efficiency.dart';
import 'xp_ledger.dart';

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

  /// Whether anything is standing inside this ability's range band right
  /// now. False means the ability is off cooldown and paid for but has
  /// nobody to point at, which is a positioning problem, not a resource one.
  bool get hasTargets => legalTargetIds.isNotEmpty;
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

  /// Short player-facing phrase explaining why this ability cannot be used
  /// right now, or null when it can. The battle screen shows this under a
  /// grayed-out ability so "why not?" never needs guessing - out of range in
  /// particular is a fixable problem, and the player can only fix it if the
  /// UI says so.
  final String? blockedReason;

  const AbilityDisplay({
    required this.trigger,
    required this.legalAction,
    required this.cooldownRemaining,
    this.blockedReason,
  });

  bool get usable =>
      legalAction != null &&
      legalAction!.affordable &&
      legalAction!.hasTargets;

  /// True when the only thing stopping this ability is where its owner is
  /// standing: it is off cooldown, affordable, and simply has nothing inside
  /// its band. That is the cue to offer a Reposition.
  bool get blockedByRange =>
      legalAction != null && legalAction!.affordable && !legalAction!.hasTargets;
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

  /// Set only on a queued Reposition ([triggerId] is [repositionActionId]):
  /// the square this step moves to. Null for every ability.
  final BattlePosition? destination;

  QueuedAction({
    required this.characterId,
    required this.triggerId,
    required this.targetIds,
    required this.trionSpent,
    this.destination,
  });

  /// Whether this queued entry is a move rather than an ability use.
  bool get isReposition => triggerId == repositionActionId;
}

/// Result of trying to [PlaySession.queue] an action.
class QueueOutcome {
  final bool success;
  final String? error;

  const QueueOutcome.ok() : success = true, error = null;
  const QueueOutcome.failure(this.error) : success = false;
}

/// The phase a queued action resolves in. Lower phases resolve first, so a
/// setup/buff lands before the attack that benefits from it, controls land
/// before attacks, and heals land after damage. Within a phase, ties break
/// by Team Spirit deviation then queue order (see [PlaySession.resolveQueue]).
// arm carries the turn's Repositions, resolved before any ability so that
// move-then-strike works and range can be planned against where a character
// will be standing. cleanup carries no content yet (reactive/trap abilities
// arrive in a later phase); keeping it fixes the phase ordinals so that
// content slots in without renumbering.
// ignore: unused_field
enum _ResolutionPhase { arm, buffs, control, attacks, heals, cleanup }

/// Classifies an [ActiveTrigger] into its [_ResolutionPhase]. A
/// damage-dealing ability (including a damage-plus-status rider or a drain)
/// is an attack; a no-damage opponent-targeted ability is control; a
/// no-damage ally/self heal is a heal; anything else ally/self is a buff.
/// The arm and cleanup phases are reserved for the reactive/trap content
/// added in a later phase.
_ResolutionPhase _phaseFor(ActiveTrigger trigger) {
  final dealsDamage = trigger.damageType != null && trigger.damage != null;
  if (dealsDamage) return _ResolutionPhase.attacks;
  if (trigger.targetAffiliation == TargetAffiliation.opponent) {
    return _ResolutionPhase.control;
  }
  if (trigger.healAmount != null) return _ResolutionPhase.heals;
  return _ResolutionPhase.buffs;
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

  /// Each squad's Team Efficiency Grade, computed once at battle start. The
  /// higher grade is favoured for the opening turn (see
  /// `openingTurnChanceFor`) and drives the in-battle dice effects.
  final TeamEfficiency teamAEfficiency;
  final TeamEfficiency teamBEfficiency;

  /// Set when team B won the opening move: its entire opening turn,
  /// resolved before the session surfaces (the player's session always
  /// begins on their own turn).
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
    required this.teamAEfficiency,
    required this.teamBEfficiency,
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

    final teamAEfficiency = computeTeamEfficiency(
      characterIds: playerCharacterIds,
      loadouts: teamADraft.loadouts,
    );
    final teamBEfficiency = computeTeamEfficiency(
      characterIds: opponentCharacterIds,
      loadouts: teamBDraft.loadouts,
    );

    // Who moves first is weighted by the Team Efficiency Grade rather than
    // decided by a fair coin: an evenly graded pair is still 50/50, and each
    // tier of separation moves the odds 5 points up to 65/35. See
    // `openingTurnChanceFor`.
    final teamAGoesFirst = switch (firstTurn) {
      'teamA' => true,
      'teamB' => false,
      _ => rollsOpeningTurn(teamAEfficiency.tier, teamBEfficiency.tier),
    };

    final battle = Battle(
      teamA: teamADraft.team,
      teamB: teamBDraft.team,
      states: {...teamADraft.states, ...teamBDraft.states},
      teamAGoesFirst: teamAGoesFirst,
    );

    // TEG Effects 1/2/5 (section 5.2): inject each team's grade-derived roll
    // profile so the engine can grant coordination/defensive advantage and
    // (at SSS) widen crits. The app computes the grade; the engine only sees
    // the resulting numbers.
    final profileA = tegRollProfileFor(teamAEfficiency.tier);
    final profileB = tegRollProfileFor(teamBEfficiency.tier);
    battle.turnEngine.tegProfiles = {
      for (final id in playerCharacterIds) id: profileA,
      for (final id in opponentCharacterIds) id: profileB,
    };

    // Draegor's 2-tier TEG boost: inject each team's 2-tiers-higher profile
    // (null for SS/SSS teams, which get Draegor's fallback instead).
    final boostedA = tegBoostedProfileFor(teamAEfficiency.tier);
    final boostedB = tegBoostedProfileFor(teamBEfficiency.tier);
    battle.turnEngine.tegBoostedProfiles = {
      if (boostedA != null)
        for (final id in playerCharacterIds) id: boostedA,
      if (boostedB != null)
        for (final id in opponentCharacterIds) id: boostedB,
    };

    // TEG Effect 4 (combo advantage): enable the combo recognizer over the
    // live action ledger. The ledger is populated during resolution and
    // cleared each turn by the engine.
    battle.turnEngine.comboRecognizer = ComboCatalog.defaultRecognizer;

    final session = PlaySession._(
      battle: battle,
      equippedA: teamADraft.equippedActiveTriggers,
      equippedB: teamBDraft.equippedActiveTriggers,
      loadoutsA: teamADraft.loadouts,
      loadoutsB: teamBDraft.loadouts,
      aiB: ProfileDrivenAi(profileById(opponentProfileId)),
      teamAEfficiency: teamAEfficiency,
      teamBEfficiency: teamBEfficiency,
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

  /// Awards battle XP for the finished battle to [account]'s player through
  /// [ledger] (the player controls team A, so its Team Efficiency Grade drives
  /// the inverse-TEG multiplier). Returns the award, or null if the battle
  /// isn't over or nobody is signed in (including as a guest). Scaffold: the
  /// stub ledger computes locally; a real ledger re-validates server-side.
  Future<XpAward?> awardBattleXpTo(
    XpLedger ledger,
    AccountService account, {
    int baseXp = 100,
  }) async {
    if (!isOver) return null;
    final player = account.current;
    if (player == null) return null;
    return ledger.recordBattleResult(BattleResultReport.fromOutcome(
      playerId: player.id,
      baseXp: baseXp,
      tier: teamAEfficiency.tier,
      outcome: outcome,
      playerIsTeamA: true,
    ));
  }
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

  /// Where [characterId] will be standing once this turn's queue resolves:
  /// their current position, stepped by every Reposition they have queued.
  ///
  /// Repositions resolve in the arm phase, ahead of every ability, so this -
  /// not the live position - is what the player is planning from. Judging
  /// range against the live position instead would make move-then-strike
  /// impossible, and closing the gap to swing in the same turn is the whole
  /// point of the positional pillar.
  ///
  /// Enemies never have queued entries, so for them this is just where they
  /// are standing, which is what makes it safe to call on any character.
  BattlePosition projectedPositionOf(String characterId) {
    var position =
        battle.states[characterId]?.position ?? BattlePosition.middle;
    for (final queued in _queue) {
      if (queued.characterId == characterId && queued.destination != null) {
        position = queued.destination!;
      }
    }
    return position;
  }

  /// The squares [characterId] could still step to this turn, given what they
  /// have already queued. Empty when they are pinned, action-locked, or out
  /// of ability uses.
  List<BattlePosition> legalRepositionsFor(String characterId) {
    if (!battle.isTeamATurn) return const [];
    final state = battle.states[characterId];
    if (state == null) return const [];
    final engine = battle.turnEngine;
    if (!engine.canRepositionAtAll(state)) return const [];
    if (!_hasUsesLeft(state)) return const [];
    return projectedPositionOf(characterId).adjacent;
  }

  /// Whether [state] has an ability use left this turn once everything
  /// already queued is counted. The engine only records uses at resolution,
  /// so the queue has to do this accounting itself.
  bool _hasUsesLeft(CharacterBattleState state) {
    final maxUses = battle.turnEngine.fatEngine.maxAbilitiesThisTurn(state);
    return state.abilitiesUsedThisTurnCount +
            queuedCountFor(state.character.id) <
        maxUses;
  }

  /// Every character on the given ability's target side that it can legally
  /// be pointed at, measured from the projected positions on both ends.
  List<String> _legalTargetIdsFor(
    CharacterBattleState state,
    ActiveTrigger trigger,
  ) {
    final engine = battle.turnEngine;
    final from = projectedPositionOf(state.character.id);
    final pool = trigger.targetAffiliation == TargetAffiliation.opponent
        ? battle.teamB.characters.map((c) => battle.states[c.id]!)
        : battle.teamA.characters.map((c) => battle.states[c.id]!);
    return [
      for (final t in pool)
        if (t.isAlive &&
            engine.canTarget(
              state,
              t,
              trigger: trigger,
              fromPosition: from,
              targetPosition: projectedPositionOf(t.character.id),
            ))
          t.character.id,
    ];
  }

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
        legalTargetIds = _legalTargetIdsFor(state, trigger);
        maxTargets = trigger.rangeTag.isAtRange
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
        () {
          final legal = legalById[trigger.id];
          final cooldown = state.cooldowns[trigger.id] ?? 0;
          return AbilityDisplay(
            trigger: trigger,
            legalAction: legal,
            cooldownRemaining: cooldown,
            blockedReason: _blockedReasonFor(state, trigger, legal, cooldown),
          );
        }(),
    ];
  }

  /// The one reason worth showing the player for an unusable ability, most
  /// specific first. Null when the ability is usable.
  String? _blockedReasonFor(
    CharacterBattleState state,
    ActiveTrigger trigger,
    LegalAction? legal,
    int cooldown,
  ) {
    if (legal == null) {
      if (cooldown > 0) {
        return 'On cooldown ($cooldown ${cooldown == 1 ? 'turn' : 'turns'})';
      }
      if (state.isActionPrevented()) return 'Cannot act';
      return 'Unavailable';
    }
    if (!legal.hasTargets) {
      // Say the band and the window, so the fix (step forward or back) is
      // readable off the message rather than needing the rules in front of
      // you.
      return 'Nothing in ${trigger.rangeTag.label} '
          '(distance ${trigger.rangeTag.windowLabel})';
    }
    if (!legal.affordable) {
      return 'Needs ${legal.actualTrionCost} Trion';
    }
    if (!_hasUsesLeft(state)) return 'No uses left this turn';
    return null;
  }

  /// Enemy (team B) character ids whose loadout the player's team has
  /// revealed via Mind's Eye. The reveal is stored per-wielder on the
  /// revealing character's battle state, so the union across team A is the
  /// set the battle UI may show the opponent's abilities for.
  Set<String> get revealedEnemyIds {
    final out = <String>{};
    for (final c in battle.teamA.characters) {
      final state = battle.states[c.id];
      if (state != null) out.addAll(state.revealedEnemyIds);
    }
    return out;
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

    final targets = [for (final id in targetIds) battle.states[id]!];
    if (trigger.targetAffiliation == TargetAffiliation.opponent &&
        targets.isNotEmpty) {
      engine.checkSanctionedStrike(state, trigger, targets.first);
    }
    final useResult = engine.resolveAbilityUse(
      attacker: state,
      trigger: trigger,
      targets: targets,
    );
    // TEG Effect 3: credit any setup->payoff Trion refund (player = team A).
    if (useResult.trionRefund > 0) {
      battle.teamA.trionPool.gain(useResult.trionRefund);
    }
    _feedPassiveCounters(state, trigger, useResult);

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
    if (!_hasUsesLeft(state)) {
      return const QueueOutcome.failure('No ability uses left this turn.');
    }
    // Range is judged against projected positions (see
    // [projectedPositionOf]), so a Reposition queued earlier this turn
    // already counts. Without this the engine would accept the action and
    // then silently drop the target at resolution.
    if (trigger.targetAffiliation != TargetAffiliation.self) {
      final reachable = _legalTargetIdsFor(state, trigger).toSet();
      if (targetIds.any((id) => !reachable.contains(id))) {
        return QueueOutcome.failure(
          'Out of ${trigger.rangeTag.label} '
          '(distance ${trigger.rangeTag.windowLabel}).',
        );
      }
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

  /// Whether [triggerId] on [characterId] could be queued right now: it is
  /// usable, not already queued, within this character's per-turn ability
  /// limit given what is already queued, and affordable. Mirrors [queue]'s
  /// checks (minus the target list) so the UI can gray out abilities that
  /// would just be rejected.
  bool canQueueAbility(String characterId, String triggerId) {
    if (!battle.isTeamATurn) return false;
    final state = battle.states[characterId];
    if (state == null || !state.isAlive) return false;
    ActiveTrigger? trigger;
    for (final t in equippedA[characterId] ?? const <ActiveTrigger>[]) {
      if (t.id == triggerId) {
        trigger = t;
        break;
      }
    }
    if (trigger == null) return false;
    final engine = battle.turnEngine;
    if (!engine.canUseAbility(state, trigger)) return false;
    if (_queue.any(
      (q) => q.characterId == characterId && q.triggerId == triggerId,
    )) {
      return false;
    }
    if (!_hasUsesLeft(state)) return false;
    if (trigger.targetAffiliation != TargetAffiliation.self &&
        _legalTargetIdsFor(state, trigger).isEmpty) {
      return false;
    }
    final cost = (trigger.trionCost * state.trionCostMultiplier()).round();
    return cost <= battle.teamA.trionPool.current;
  }

  /// Commits one step of movement to the turn queue. Movement is free in
  /// Trion but costs the character one of their ability uses for the turn,
  /// so closing the gap competes with attacking rather than being a bonus.
  ///
  /// Queued Repositions resolve first (the arm phase), which is what lets a
  /// character move and then strike in the same turn: everything queued
  /// afterwards is validated against the projected position.
  QueueOutcome queueReposition(String characterId, BattlePosition destination) {
    if (!battle.isTeamATurn) {
      return const QueueOutcome.failure('It is not your turn.');
    }
    final state = battle.states[characterId];
    if (state == null || !state.isAlive) {
      return const QueueOutcome.failure('That character cannot act.');
    }
    final engine = battle.turnEngine;
    if (!engine.canRepositionAtAll(state)) {
      return const QueueOutcome.failure('That character cannot move.');
    }
    if (!_hasUsesLeft(state)) {
      return const QueueOutcome.failure('No ability uses left this turn.');
    }
    if (!projectedPositionOf(characterId).adjacent.contains(destination)) {
      return const QueueOutcome.failure('That is not one step away.');
    }
    _queue.add(
      QueuedAction(
        characterId: characterId,
        triggerId: repositionActionId,
        targetIds: const [],
        trionSpent: 0,
        destination: destination,
      ),
    );
    return const QueueOutcome.ok();
  }

  /// Mirrors [queueReposition]'s checks so the UI can gray out a square that
  /// would just be rejected.
  bool canQueueReposition(String characterId, BattlePosition destination) =>
      legalRepositionsFor(characterId).contains(destination);

  /// The step [characterId] should take to bring more of their Loadout into
  /// range, or null when standing still is at least as good. Measured from
  /// the projected position, so moves already queued this turn count.
  ///
  /// This is the hint behind the battle screen's move prompt, and the same
  /// judgement the AI uses for its own squad. It answers "am I in range to do
  /// anything?" without the player counting squares.
  BattlePosition? suggestRepositionFor(String characterId) {
    if (!battle.isTeamATurn) return null;
    final state = battle.states[characterId];
    if (state == null || !state.isAlive) return null;
    if (!_hasUsesLeft(state)) return null;
    return battle.turnEngine.suggestReposition(
      state,
      equippedA[characterId] ?? const [],
      [for (final c in battle.teamB.characters) battle.states[c.id]!],
      from: projectedPositionOf(characterId),
    );
  }

  /// Removes the queued action at [index] and refunds its Trion. Returns
  /// false if [index] is out of range.
  ///
  /// Removing a Reposition also drops (and refunds) any ability that
  /// character queued afterwards which no longer reaches its targets from
  /// the position they will now end up in. Leaving those queued would let
  /// the player commit Trion to an attack that quietly fizzles at
  /// resolution, which is the worst of the options available.
  bool unqueue(int index) {
    if (index < 0 || index >= _queue.length) return false;
    final action = _queue.removeAt(index);
    battle.teamA.trionPool.gain(action.trionSpent);
    if (action.isReposition) _dropUnreachableQueued(action.characterId);
    return true;
  }

  /// Refunds and removes every queued ability of [characterId] whose targets
  /// are no longer inside its band from the current projected position.
  void _dropUnreachableQueued(String characterId) {
    final state = battle.states[characterId];
    if (state == null) return;
    final equipped = equippedA[characterId] ?? const <ActiveTrigger>[];
    _queue.removeWhere((queued) {
      if (queued.characterId != characterId || queued.isReposition) {
        return false;
      }
      ActiveTrigger? trigger;
      for (final t in equipped) {
        if (t.id == queued.triggerId) {
          trigger = t;
          break;
        }
      }
      if (trigger == null) return false;
      if (trigger.targetAffiliation == TargetAffiliation.self) return false;
      final reachable = _legalTargetIdsFor(state, trigger).toSet();
      if (queued.targetIds.every(reachable.contains)) return false;
      battle.teamA.trionPool.gain(queued.trionSpent);
      return true;
    });
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
  /// Actions do not resolve in click order. Each is sorted into a
  /// [_ResolutionPhase] (arm, buffs, control, attacks, heals, cleanup),
  /// phases resolve low to high, and within a phase ties break by the
  /// acting character's Team Spirit deviation from the neutral midpoint (a
  /// more committed pole resolves first) then by queue order. Sort keys are
  /// snapshotted before any action resolves, so ordering does not depend on
  /// mid-resolution state changes. Cross-team Initiative (via the Team
  /// Efficiency Grade) arrives in A5; this is the within-team ordering.
  ///
  /// Call this before [endTurn].
  LogRound resolveQueue() {
    // Arm phase: every queued Reposition, in queue order, before any
    // ability. Range was validated against the resulting positions when each
    // action was queued, so this ordering is what makes move-then-strike land.
    final moves = <LogAction>[];
    for (final queued in _queue) {
      if (!queued.isReposition) continue;
      final state = battle.states[queued.characterId]!;
      if (!battle.turnEngine.reposition(state, queued.destination!)) continue;
      moves.add(
        LogAction(
          characterId: queued.characterId,
          characterName: state.character.name,
          triggerId: repositionActionId,
          triggerName: 'Reposition to the '
              '${queued.destination!.label.toLowerCase()} line',
          fatTriggered: state.fatTriggeredThisTurn,
          targets: const [],
        ),
      );
    }

    final round = _resolvePlan(
      [
        for (final q in _queue)
          if (!q.isReposition)
            (
              characterId: q.characterId,
              triggerId: q.triggerId,
              targetIds: q.targetIds,
            ),
      ],
      equipped: equippedA,
      team: 'A',
    );
    _queue.clear();
    return LogRound(
      roundNumber: round.roundNumber,
      team: round.team,
      actions: [...moves, ...round.actions],
    );
  }

  /// Safety net for any AI character the plan left doing nothing at all.
  ///
  /// Planning already decides its own moves (see `ProfileDrivenAi.planTurn`),
  /// so this normally finds nobody. It still earns its place: a character can
  /// end up with no planned action for reasons planning does not treat as a
  /// positional problem (an exhausted Trion budget, everything on cooldown),
  /// and a squad that plans nothing and stands still would drag the battle out
  /// forever.
  void _repositionIdleAi(List<AiPlannedAction> plan) {
    final acted = plan.map((a) => a.characterId).toSet();
    for (final character in battle.teamB.characters) {
      if (acted.contains(character.id)) continue;
      final state = battle.states[character.id]!;
      if (!state.isAlive) continue;
      final destination = battle.turnEngine.suggestReposition(
        state,
        equippedB[character.id] ?? const [],
        battle.teamA.characters.map((c) => battle.states[c.id]!).toList(),
      );
      if (destination != null) {
        battle.turnEngine.reposition(state, destination);
      }
    }
  }

  /// Resolves the AI's committed plan (see [ProfileDrivenAi.planTurn]) for
  /// team B through the same phase-priority resolver the player's queue
  /// uses. Trion was budgeted during planning but not spent, so it is spent
  /// here as the plan is committed.
  LogRound resolveAiPlan(List<AiPlannedAction> plan) {
    // Arm phase, exactly as for the player's queue: planned moves resolve
    // ahead of every ability, which is what the AI's target choices assume.
    final moves = <LogAction>[];
    for (final a in plan) {
      if (!a.isReposition) continue;
      final state = battle.states[a.characterId]!;
      if (!battle.turnEngine.reposition(state, a.destination!)) continue;
      moves.add(
        LogAction(
          characterId: a.characterId,
          characterName: state.character.name,
          triggerId: repositionActionId,
          triggerName: 'Reposition to the '
              '${a.destination!.label.toLowerCase()} line',
          fatTriggered: state.fatTriggeredThisTurn,
          targets: const [],
        ),
      );
    }

    final pool = battle.teamB.trionPool;
    for (final a in plan) {
      if (a.isReposition) continue; // moves are free in Trion
      final state = battle.states[a.characterId]!;
      final trigger = equippedB[a.characterId]!.firstWhere(
        (t) => t.id == a.triggerId,
      );
      pool.trySpend((trigger.trionCost * state.trionCostMultiplier()).round());
    }
    final round = _resolvePlan(
      [
        for (final a in plan)
          if (!a.isReposition)
            (
              characterId: a.characterId,
              triggerId: a.triggerId,
              targetIds: a.targetIds,
            ),
      ],
      equipped: equippedB,
      team: 'B',
    );
    return LogRound(
      roundNumber: round.roundNumber,
      team: round.team,
      actions: [...moves, ...round.actions],
    );
  }

  /// Shared phase-priority resolver for a committed set of actions from one
  /// team - the player's queue or the AI's plan. Orders by resolution phase,
  /// then Team Spirit deviation from the midpoint, then original order (see
  /// [resolveQueue] for the rationale), then resolves each and returns a
  /// [LogRound]. Trion is the caller's responsibility.
  LogRound _resolvePlan(
    List<({String characterId, String triggerId, List<String> targetIds})>
    items, {
    required Map<String, List<ActiveTrigger>> equipped,
    required String team,
  }) {
    final engine = battle.turnEngine;
    const midpoint = 50; // TeamSpiritCurveConfig.defaults.midpoint.

    final ordered = List.of(items);
    ActiveTrigger triggerAt(int i) => equipped[ordered[i].characterId]!
        .firstWhere((t) => t.id == ordered[i].triggerId);
    // Keyed by original index (records are value types, so two identical
    // actions would collide as map keys).
    final phase = <int, int>{};
    final deviation = <int, num>{};
    for (var i = 0; i < ordered.length; i++) {
      final state = battle.states[ordered[i].characterId]!;
      phase[i] = _phaseFor(triggerAt(i)).index;
      deviation[i] =
          (state.effectiveStats(fatConfig: engine.fatConfig).teamSpirit -
                  midpoint)
              .abs();
    }
    final order = List<int>.generate(ordered.length, (i) => i)
      ..sort((a, b) {
        if (phase[a] != phase[b]) return phase[a]!.compareTo(phase[b]!);
        if (deviation[a] != deviation[b]) {
          return deviation[b]!.compareTo(deviation[a]!);
        }
        return a.compareTo(b);
      });

    final actions = [
      for (final i in order)
        _resolveAction(
          ordered[i].characterId,
          triggerAt(i),
          ordered[i].targetIds,
        ),
    ];
    // Death Ledger: apply any AoE-swap the engine just signalled, then decay
    // the acting team's existing swaps (reverting expired ones).
    _applyPendingDeathLedgerSwaps();
    _tickDeathLedgerSwaps(team);
    return LogRound(
      roundNumber: battle.roundNumber,
      team: team,
      actions: actions,
    );
  }

  // --- Death Ledger loadout swap (2-turn borrow of a nullified AoE) --------

  /// Active Death Ledger swaps by wielder id: the borrowed AoE trigger id, the
  /// trigger it displaced, the team's equipped map, and turns left before it
  /// reverts.
  final Map<String, ({
    String swappedInId,
    ActiveTrigger swappedOut,
    Map<String, List<ActiveTrigger>> equipped,
    int turnsRemaining,
  })> _deathLedgerSwaps = {};

  static const int _deathLedgerSwapTurns = 2;

  /// Applies any pending Death Ledger swaps the engine parked on a wielder:
  /// swap the borrowed AoE Trigger in for the wielder's nearest-Trion-cost
  /// equipped Trigger.
  void _applyPendingDeathLedgerSwaps() {
    for (final state in battle.states.values) {
      final aoe = state.deathLedgerSwapPending;
      if (aoe == null) continue;
      state.deathLedgerSwapPending = null;
      final wielderId = state.character.id;
      if (_deathLedgerSwaps.containsKey(wielderId)) continue; // one at a time
      final onTeamA = battle.teamA.characters.any((c) => c.id == wielderId);
      final equipped = onTeamA ? equippedA : equippedB;
      final loadout = equipped[wielderId];
      if (loadout == null || loadout.isEmpty) continue;
      if (loadout.any((t) => t.id == aoe.id)) continue; // already owns it
      // Nearest-Trion-cost Trigger (closest cost to the borrowed AoE).
      loadout.sort((a, b) => (a.trionCost - aoe.trionCost)
          .abs()
          .compareTo((b.trionCost - aoe.trionCost).abs()));
      final swappedOut = loadout.removeAt(0);
      loadout.add(aoe);
      _deathLedgerSwaps[wielderId] = (
        swappedInId: aoe.id,
        swappedOut: swappedOut,
        equipped: equipped,
        turnsRemaining: _deathLedgerSwapTurns,
      );
    }
  }

  /// Decays swaps whose wielder is on [team]; reverts any that expire.
  void _tickDeathLedgerSwaps(String team) {
    for (final wielderId in _deathLedgerSwaps.keys.toList()) {
      final onTeamA = battle.teamA.characters.any((c) => c.id == wielderId);
      if ((onTeamA ? 'A' : 'B') != team) continue;
      final swap = _deathLedgerSwaps[wielderId]!;
      final remaining = swap.turnsRemaining - 1;
      if (remaining > 0) {
        _deathLedgerSwaps[wielderId] = (
          swappedInId: swap.swappedInId,
          swappedOut: swap.swappedOut,
          equipped: swap.equipped,
          turnsRemaining: remaining,
        );
        continue;
      }
      // Revert: drop the borrowed AoE, restore the displaced Trigger.
      final loadout = swap.equipped[wielderId];
      if (loadout != null) {
        loadout.removeWhere((t) => t.id == swap.swappedInId);
        if (!loadout.any((t) => t.id == swap.swappedOut.id)) {
          loadout.add(swap.swappedOut);
        }
      }
      _deathLedgerSwaps.remove(wielderId);
    }
  }

  /// Records the use and resolves one committed action, returning its log
  /// entry. This is the seam where Phase B reactive counters (reflect /
  /// dodge / negate / redirect / trap) will intercept an attack before it
  /// resolves; today the only reactive rule is the engine's own Guardian
  /// redirect inside `resolveAbilityUse`.
  LogAction _resolveAction(
    String characterId,
    ActiveTrigger trigger,
    List<String> targetIds,
  ) {
    final engine = battle.turnEngine;
    final state = battle.states[characterId]!;
    final targets = [for (final id in targetIds) battle.states[id]!];
    // Trion was already spent (at queue time for the player, at plan commit
    // for the AI); record the use here so the FAT count and end-of-turn
    // cooldowns are set.
    state.recordAbilityUse(trigger);
    // Ironvow: an attack of the sanctioned type consumes a Sanctioned Strike
    // (strip a buff, brand Interdict, expose allies) before it resolves.
    if (trigger.targetAffiliation == TargetAffiliation.opponent &&
        targets.isNotEmpty) {
      engine.checkSanctionedStrike(state, trigger, targets.first);
    }
    final useResult = engine.resolveAbilityUse(
      attacker: state,
      trigger: trigger,
      targets: targets,
    );
    // TEG Effect 3: credit any setup->payoff Trion refund to the acting team.
    if (useResult.trionRefund > 0) {
      final actingOnTeamA =
          battle.teamA.characters.any((c) => c.id == characterId);
      (actingOnTeamA ? battle.teamA : battle.teamB)
          .trionPool
          .gain(useResult.trionRefund);
    }
    _feedPassiveCounters(state, trigger, useResult);
    return LogAction(
      characterId: characterId,
      characterName: state.character.name,
      triggerId: trigger.id,
      triggerName: trigger.name,
      fatTriggered: state.fatTriggeredThisTurn,
      targets: logTargets(battle, useResult),
    );
  }

  /// Feeds the passive-counter state machines after an ability resolves.
  /// Without these calls the six passive counters never advance (design
  /// 13.1): Draegor Enmity, Reckoning Debt, Nullhymn Discord, Coldread's
  /// read tracking, and Ironvow's last-attack-type all accumulate through
  /// [TurnEngine.notifyAbilityResolved]; Nullhymn also gains Discord from
  /// statuses inflicted on a holder; Gravehour's stall detection needs to
  /// know the active team dealt damage this turn.
  void _feedPassiveCounters(
    CharacterBattleState state,
    ActiveTrigger trigger,
    AbilityUseResult useResult,
  ) {
    final engine = battle.turnEngine;
    final onTeamA =
        battle.teamA.characters.any((c) => c.id == state.character.id);
    final defenderTeam = onTeamA ? battle.teamB : battle.teamA;
    final defenderStates =
        defenderTeam.characters.map((c) => battle.states[c.id]!).toList();
    final isBt = state.character.blackTrigger?.activeAbilities
            .any((t) => t.id == trigger.id) ??
        false;

    engine.notifyAbilityResolved(
      attacker: state,
      trigger: trigger,
      result: useResult,
      defenderTeamStates: defenderStates,
      isBlackTriggerAbility: isBt,
    );

    for (final tr in useResult.targetResults) {
      if (tr.statusEffectsApplied.isEmpty) continue;
      final target = battle.states[tr.targetCharacterId];
      if (target == null) continue;
      for (final statusId in tr.statusEffectsApplied) {
        engine.notifyStatusInflicted(target, statusId);
      }
    }

    if (useResult.targetResults.any((r) => r.totalDamageDealt > 0)) {
      battle.recordDamageDealt();
    }
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

  /// Like [endTurn] but waits [thinkingDelay] before the AI acts, so the UI
  /// can let the player's resolution settle before the opponent responds
  /// (the simulated "thinking" beat). Behaves identically to [endTurn] with
  /// a zero delay.
  Future<LogRound> endTurnWithDelay(Duration thinkingDelay) async {
    battle.endTurn();
    if (thinkingDelay > Duration.zero) {
      await Future<void>.delayed(thinkingDelay);
    }
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

  /// Resolves consecutive AI (team B) turns - normally just one - stopping
  /// once control returns to team A or the battle ends. The AI commits its
  /// whole turn up front as a blind plan and resolves it through the same
  /// phase-priority path the player's queue uses ([resolveAiPlan]).
  LogRound _playAiTurns() {
    final actions = <LogAction>[];
    var aiRoundNumber = battle.roundNumber;
    while (!battle.isTeamATurn && !battle.isOver) {
      battle.startTurn(equippedActiveTriggers: equippedB);
      aiRoundNumber = battle.roundNumber;
      if (battle.isOver) break;

      final plan = aiB.planTurn(battle, equippedActiveTriggers: equippedB);
      actions.addAll(resolveAiPlan(plan).actions);
      _repositionIdleAi(plan);

      if (battle.isOver) break;
      battle.endTurn();
    }
    return LogRound(roundNumber: aiRoundNumber, team: 'B', actions: actions);
  }
}

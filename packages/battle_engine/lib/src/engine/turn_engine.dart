import '../constants.dart';
import '../models/team.dart';
import '../models/trigger.dart';
import '../models/trion.dart';
import 'character_battle_state.dart';
import 'combat_engine.dart';
import 'fat_engine.dart';
import 'status_effect_engine.dart';
import 'team_spirit_curve.dart';
import 'trion_gain_engine.dart';

/// Orchestrates a single turn: team Trion gain, per-character status
/// ticking, Full Arms Trigger rolling, ability-use bookkeeping, and
/// end-of-turn cleanup. AI decision-making (which ability to use, who to
/// target) is deliberately left to the caller (e.g. a future rule-based
/// AI module or story-triggered scripted battle) - this engine only
/// answers "is this legal / what does this cost / what's the result",
/// not "what should happen".
class TurnEngine {
  final TrionGainEngine trionGainEngine;
  final FatEngine fatEngine;
  final CombatEngine combatEngine;
  final StatusEffectEngine statusEffectEngine;
  final TeamSpiritCurve teamSpiritCurve;
  final FatConfig fatConfig;

  TurnEngine({
    TrionGainEngine? trionGainEngine,
    FatEngine? fatEngine,
    CombatEngine? combatEngine,
    StatusEffectEngine? statusEffectEngine,
    TeamSpiritCurve? teamSpiritCurve,
    this.fatConfig = FatConfig.defaults,
  })  : trionGainEngine = trionGainEngine ?? TrionGainEngine(),
        fatEngine = fatEngine ?? FatEngine(),
        combatEngine = combatEngine ?? CombatEngine(),
        statusEffectEngine = statusEffectEngine ?? StatusEffectEngine(),
        teamSpiritCurve = teamSpiritCurve ?? const TeamSpiritCurve();

  /// Rolls this turn's Trion gain for [team] (using the sum of living
  /// members' effective Trion Affinity, so the FAT halving penalty is
  /// reflected) and adds it to the team's pool.
  TrionGainResult resolveTeamTrionGain(
    Team team,
    Map<String, CharacterBattleState> states, {
    double modifier = 0,
  }) {
    final sum = team.characters
        .map((c) => states[c.id]!)
        .where((s) => s.isAlive)
        .fold<int>(
            0,
            (total, s) =>
                total + s.effectiveStats(fatConfig: fatConfig).trionAffinity);

    final result = trionGainEngine.rollTier(
        sumLivingTrionAffinity: sum, modifier: modifier);
    team.trionPool.gain(result.amount);
    return result;
  }

  /// Applies start-of-turn status effect ticking (damage, Trion drain) to
  /// [state]. Trion drained by an effect like Sapped is credited to the
  /// causer's pool via [causerTrionPools] (character id -> their team's
  /// pool), if supplied.
  StatusTickResult tickStatusEffects(
    CharacterBattleState state, {
    Map<String, TrionPool>? causerTrionPools,
  }) {
    final result = statusEffectEngine.tickStartOfTurn(state);

    for (final event in result.damageEvents) {
      final damage = combatEngine.resolveDamage(
        baseDamage: event.amount,
        damageType: event.damageType,
        isCriticalHit: false,
        target: state,
      );
      final maxHealth = state.effectiveStats(fatConfig: fatConfig).maxHealth;
      state.currentHealth = (state.currentHealth - damage).clamp(0, maxHealth);
    }

    for (final drain in result.trionDrainEvents) {
      causerTrionPools?[drain.causerCharacterId]?.gain(drain.amount);
    }

    return result;
  }

  /// Rolls whether Full Arms Trigger activates for [state] this turn,
  /// using its effective FAT Chance (base stat + Team Spirit bonus).
  bool rollFatTrigger(CharacterBattleState state) {
    final stats = state.effectiveStats(fatConfig: fatConfig);
    final bonus = teamSpiritCurve.bonusesFor(stats.teamSpirit).fatChanceBonus;
    return fatEngine.rollTrigger(state, stats.fatChance + bonus);
  }

  /// Whether [state] may use [trigger] right now: not on cooldown, not
  /// action-prevented (Stunned/Frozen), not locked by Prone, and within
  /// this turn's ability-use limit (1, or up to 3 if FAT triggered).
  bool canUseAbility(CharacterBattleState state, Trigger trigger) {
    if (state.isActionPrevented()) return false;
    if ((state.cooldowns[trigger.id] ?? 0) > 0) return false;
    if (!fatEngine.canUseAnotherAbility(state)) return false;
    for (final instance in state.statusEffects) {
      if (instance.data['lockedAbilityId'] == trigger.id) return false;
    }
    return true;
  }

  /// Spends [trigger]'s Trion cost from [teamPool] and records the use
  /// against [state]'s per-turn ability count / pending cooldown. Returns
  /// false (no state change) if the team pool can't afford it.
  bool useAbility(
      CharacterBattleState state, Trigger trigger, TrionPool teamPool) {
    if (!teamPool.trySpend(trigger.trionCost)) return false;
    state.recordAbilityUse(trigger);
    return true;
  }

  /// Finalizes [state] for the turn: applies cooldowns (doubled if FAT
  /// was used for 2+ abilities), the resulting Trion Affinity halving
  /// penalty for next turn, and ticks down existing cooldowns/penalties.
  void endCharacterTurn(CharacterBattleState state) =>
      state.endTurn(fatConfig: fatConfig);
}

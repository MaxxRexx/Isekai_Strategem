import '../constants.dart';
import '../util/dice.dart';
import 'character_battle_state.dart';

/// Resolves Full Arms Trigger (FAT): the roll to trigger it, how many
/// abilities it unlocks for the turn, and its cooldown/cooldown-clearing
/// side effects. The end-of-turn cooldown-doubling / Trion Affinity
/// halving penalty (for actually using 2+ abilities via FAT) is applied
/// by `CharacterBattleState.endTurn`, since it needs to run after every
/// ability use for the turn has been recorded.
class FatEngine {
  final FatConfig config;
  final DiceRoller diceRoller;

  FatEngine({
    this.config = FatConfig.defaults,
    DiceRoller? diceRoller,
  }) : diceRoller = diceRoller ?? DiceRoller();

  /// Rolls whether FAT triggers this turn.
  ///
  /// [fatChancePercent] is the character's effective FAT Chance as a
  /// percentage in [0, 100] (base stat + Team Spirit curve bonus).
  /// Returns false without rolling if FAT is still on cooldown from a
  /// previous trigger.
  ///
  /// FAT is a "may" ability, not forced: rolling true only makes up to
  /// [FatConfig.maxAbilitiesOnFatTrigger] abilities *available* for the
  /// turn; the character can still choose to use just one (or none).
  ///
  /// ## Design note (flagged ambiguity)
  /// The brief doesn't specify FAT's roll mechanic (d20 contest vs. flat
  /// percentage). Since FAT Chance reads as a percentage-shaped stat (raised
  /// by Team Spirit "per point"), this rolls a flat d100 against it rather
  /// than reusing the d20 opposed-roll contest used for attacks/defense.
  bool rollTrigger(CharacterBattleState state, double fatChancePercent) {
    if (!state.canTriggerFat) return false;
    final roll = diceRoller.rollPercent();
    final triggered = roll <= fatChancePercent;
    if (triggered) {
      state.fatTriggeredThisTurn = true;
      // Triggering FAT clears cooldowns on all of that character's abilities.
      state.cooldowns.clear();
      state.fatCooldownRemaining = config.baseFatCooldownTurns;
    }
    return triggered;
  }

  /// Max abilities usable this turn, given whether FAT triggered.
  int maxAbilitiesThisTurn(CharacterBattleState state) =>
      state.fatTriggeredThisTurn
          ? config.maxAbilitiesOnFatTrigger
          : config.normalAbilitiesPerTurn;

  bool canUseAnotherAbility(CharacterBattleState state) =>
      state.abilitiesUsedThisTurnCount < maxAbilitiesThisTurn(state);
}

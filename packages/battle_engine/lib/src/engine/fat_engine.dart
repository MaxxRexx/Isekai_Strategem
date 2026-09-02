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
    if (!rollsTrigger(state, fatChancePercent)) return false;
    grantTrigger(state);
    return true;
  }

  /// Whether [state]'s roll came up, deciding nothing else.
  ///
  /// Split from [grantTrigger] for item #4's cap: a squad gets Full Arms
  /// Trigger on **one** character a turn, so every member rolls and one of
  /// the winners is then drawn. Granting on the roll would have cleared the
  /// cooldowns of characters who go on to lose the draw, and cleared
  /// cooldowns cannot be put back.
  bool rollsTrigger(CharacterBattleState state, double fatChancePercent) {
    if (!state.canTriggerFat) return false;
    return diceRoller.rollPercent() <= fatChancePercent;
  }

  /// Gives [state] Full Arms Trigger for this turn: up to
  /// [FatConfig.maxAbilitiesOnFatTrigger] abilities instead of one, every
  /// cooldown cleared, and FAT locked out for the next few turns.
  void grantTrigger(CharacterBattleState state) {
    state.fatTriggeredThisTurn = true;
    // Triggering FAT clears cooldowns on all of that character's abilities.
    state.cooldowns.clear();
    state.fatCooldownRemaining = config.baseFatCooldownTurns;
  }

  /// Draws the one member of a squad who gets FAT this turn, from everyone
  /// whose roll came up. Returns null when nobody's did.
  ///
  /// Item #4: FAT still rolls for each character, and several may come up;
  /// what changed is that only one of them cashes in, picked at random rather
  /// than by turn order, so the squad cannot count on it being the same one.
  CharacterBattleState? drawWinner(List<CharacterBattleState> rolledTrue) {
    if (rolledTrue.isEmpty) return null;
    if (rolledTrue.length == 1) return rolledTrue.single;
    return rolledTrue[diceRoller.random.nextInt(rolledTrue.length)];
  }

  /// Max abilities usable this turn, given whether FAT triggered.
  int maxAbilitiesThisTurn(CharacterBattleState state) =>
      state.fatTriggeredThisTurn
          ? config.maxAbilitiesOnFatTrigger
          : config.normalAbilitiesPerTurn;

  bool canUseAnotherAbility(CharacterBattleState state) =>
      state.abilitiesUsedThisTurnCount < maxAbilitiesThisTurn(state);
}
